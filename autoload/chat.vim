if exists('g:autoloaded_chat')
    finish
endif
let g:autoloaded_chat = 1

" TODO model options
" TODO print model name?
" TODO system message/initial prompt
let s:vim_chat_config_default = {
\  "model": "llama3.2:latest",
\  "endpoint_url": "http://localhost:11434/api/chat"
\}

" Globals
let s:response_text = ""
let s:chat_bufnr = -1
let s:response_lnum = -1  " Track the line number of the current assistant response
let s:job_id = v:null

function! chat#GetChatConfig() abort
    return extend(s:vim_chat_config_default, get(g:, 'vim_chat_config', {}))
endfunction

function! s:GetChatHistory() abort
    " Get buffer content
    let lines = getline(1, '$')

    let messages = []
    let current_role = ''
    let current_message = ''
    let collecting_message = 0

    " Loop through buffer to extract user/assistant pairs
    for line in lines
        if line =~ '^>>> user'
            " If we are switching to user, push previous message if exists
            if collecting_message
                " Clean up content: trim and remove '<<< user' and '<<< assistant'
                let current_message = substitute(current_message, '<<< user\|<<< assistant', '', 'g')
                let current_message = trim(current_message)
                call add(messages, {'role': current_role, 'content': current_message})
            endif
            let current_role = 'user'
            let current_message = trim(substitute(line, '>>> user\|>>> assistant', '', 'g'))
            let collecting_message = 1
        elseif line =~ '^>>> assistant'
            " If we are switching to assistant, push previous message if exists
            if collecting_message
                " Clean up content: trim and remove '<<< user' and '<<< assistant'
                let current_message = substitute(current_message, '<<< user\|<<< assistant', '', 'g')
                let current_message = trim(current_message)
                call add(messages, {'role': current_role, 'content': current_message})
            endif
            let current_role = 'assistant'
            let current_message = trim(substitute(line, '>>> user\|>>> assistant', '', 'g'))
            let collecting_message = 1
        elseif collecting_message
            " Append the line to the current message (preserving newlines)
            let current_message .= "\n" . line
        endif
    endfor

    " Append the last collected message, after cleanup
    if collecting_message
        let current_message = trim(current_message)
        let current_message = substitute(current_message, '<<< user\|<<< assistant', '', 'g')
        call add(messages, {'role': current_role, 'content': current_message})
    endif
    return messages
endfunction


function! chat#OpenChatBuffer() abort
    " Define the buffer name
    let bufname = "[Chat]"

    " Check if the buffer exists
    if !bufexists('^'.bufname.'$')
        " Create a new buffer
        execute "silent keepalt botright split " . bufname
    else
        " If buffer exists but not active, switch to it
        execute "silent keepalt botright split buffer " . bufnr('^'.bufname.'$')
    endif
    let bufnr = bufnr('%')

    " Set buffer options
    setlocal buftype=nofile   " Unlisted, scratch buffer
    setlocal bufhidden=hide   " Hide buffer when switching
    setlocal nowrap           " Disable text wrapping
    setlocal foldmethod=manual " Disable automatic folds
    setlocal filetype=markdown " Enable Markdown highlighting
    setlocal noswapfile       " Prevent swap file creation
    setlocal foldlevel=99
    nnoremap <buffer> <CR> :call chat#AIChatRequest()<CR>
    nnoremap <buffer> <C-c> :call chat#StopChatRequest()<CR>

    " Store buffer number globally
    let s:chat_bufnr = bufnr

    normal ggdG
    call setbufline(s:chat_bufnr, 1, [">>> user", ""])
    normal G
endfunction


function! chat#AIChatRequest() abort
    if bufnr('%') != s:chat_bufnr
        echo "Error: Can only send chat requests from [Chat] buffer"
        return
    endif
    if s:job_id isnot v:null
        echo "Error: Chat request already in progress"
        return
    endif

    call appendbufline(s:chat_bufnr, '$', ["", "<<< user", ">>> assistant", ""])

    " Track the line where assistant's response should be written
    let s:response_lnum = line('$')

    let config = chat#GetChatConfig()

    let messages = s:GetChatHistory()
    let payload = json_encode({"model": config["model"], "messages": messages})

    " Run curl asynchronously
    let cmd = ['curl', '-s', config['endpoint_url'], '--no-buffer', '-d', payload]
    let s:job_id = job_start(cmd, {'out_cb': function('s:OnAIResponse'), 'exit_cb': function('s:OnAIResponseEnd')})
endfunction


function! chat#StopChatRequest() abort
    if s:job_id is v:null
        echo "Error: No chat chat request in progress"
        return
    endif
    echo "Stopping chat request"
    call job_stop(s:job_id)
endfunction


function! s:OnAIResponse(channel, msg) abort
    if s:chat_bufnr == -1 || !bufexists(s:chat_bufnr)
        echo "Error: Chat buffer no longer exists"
        return
    endif

    if empty(a:msg)
        return
    endif

    let chunk = json_decode(a:msg)
    if !has_key(chunk, 'message')
        return
    endif

    " Append new chunk to the response text
    let s:response_text .= chunk.message.content

    " Split response into lines for correct formatting
    let response_lines = split(s:response_text, "\n")

    " Update buffer with multi-line response
    call setbufline(s:chat_bufnr, s:response_lnum, response_lines)

    " Scroll to bottom
    let winid = bufwinid(s:chat_bufnr)
    if winid != -1
        call win_execute(winid, "normal! G")
    endif

    if has_key(chunk, "done_reason")
        call appendbufline(s:chat_bufnr, '$', ["", "<<< assistant", ">>> user", ""])
        let s:response_text = ""
        let s:response_lnum = line('$')  " Update response line tracking
    endif
endfunction


function! s:OnAIResponseEnd(job, status) abort
    let s:response_text = ""
    let s:job_id = v:null
endfunction

" TODO
" function! SaveChatHistory() abort
"     " if s:chat_bufnr == -1 || !bufexists(s:chat_bufnr)
"     "     echo "Error: Chat buffer no longer exists"
"     "     return
"     " endif
"     let chat_history = s:GetChatHistory()
"     " Convert to JSON
"     let json_string = json_encode(chat_history)

"     let temp_file = tempname()
"     call writefile([json_string], temp_file, "b")
"     let json_string = system('python -m json.tool ' . shellescape(temp_file))
"     call delete(temp_file)

"     " Create history folder if it doesn't exist
"     let history_dir = expand('~/.vim_chat_history')
"     if !isdirectory(history_dir)
"         call mkdir(history_dir, "p")
"     endif

"     " Generate timestamped filename
"     let timestamp = strftime('%Y-%m-%d_%H-%M-%S')
"     let filename = history_dir . '/chat_' . timestamp . '.json'

"     " Save to file
"     call writefile(split(json_string, '\n'), filename, 'b')

"     echo "Chat history saved to " . filename
" endfunction

" " TODO
" function! LoadChatHistory(filename) abort
"     if !filereadable(a:filename)
"         echo "Error: File does not exist"
"         return
"     endif

"     let json_string = join(readfile(a:filename, 'b'), "\n")
"     let chat_history = json_decode(json_string)

"     " Ensure the chat buffer is created
"     call OpenChatBuffer()
"     call setbufline(s:chat_bufnr, 1, []) " Clear buffer before inserting history

"     " Append messages in the correct format
"     for msg in chat_history
"         if msg.role == "user"
"             call appendbufline(s:chat_bufnr, '$', ">>> user")
"         elseif msg.role == "assistant"
"             call appendbufline(s:chat_bufnr, '$', "<<< user")
"         endif
"         call appendbufline(s:chat_bufnr, '$', split(msg.content, "\n"))
"     endfor

"     echo "Chat history loaded from " . a:filename
" endfunction
