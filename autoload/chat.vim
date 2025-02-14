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
let s:awaiting_response = v:false
let s:progress_timer = v:null
let s:messages = []


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


function! s:GetLastUserQueryContent() abort
    let l:lines = getbufline(s:chat_bufnr, 1, '$')
    let l:last_user_index = -1

    " Find the last occurrence of '>>> user'
    for l:i in reverse(range(len(l:lines)))
        if l:lines[l:i] == '>>> user'
            let l:last_user_index = l:i + 1
            break
        endif
    endfor

    " If no '>>> user' marker is found, return empty
    if l:last_user_index == -1 || l:last_user_index >= len(l:lines)
        return ''
    endif

    " Collect all lines until the next marker (or end of buffer)
    let l:user_text = []
    for l:j in range(l:last_user_index, len(l:lines)-1)
        if l:lines[l:j] =~ '^<<< ' || l:lines[l:j] =~ '^>>> ' " Stop at next marker
            break
        endif
        call add(l:user_text, substitute(l:lines[l:j], '\s\+$', '', ''))
    endfor

    " Process text to join wrapped lines while preserving code blocks
    let l:processed_lines = []
    let l:current_paragraph = []

    for l:line in l:user_text
        if l:line =~ '^\s*$'  " Blank line: end of paragraph
            if !empty(l:current_paragraph)
                call add(l:processed_lines, join(l:current_paragraph, ' '))
                let l:current_paragraph = []
            endif
            call add(l:processed_lines, '')  " Preserve blank line
        elseif l:line =~ '^\s'
            " Likely a code block (indented line), preserve as-is
            if !empty(l:current_paragraph)
                call add(l:processed_lines, join(l:current_paragraph, ' '))
                let l:current_paragraph = []
            endif
            call add(l:processed_lines, l:line)
        else
            " Normal sentence, add to paragraph buffer
            call add(l:current_paragraph, l:line)
        endif
    endfor

    " Add any remaining paragraph
    if !empty(l:current_paragraph)
        call add(l:processed_lines, join(l:current_paragraph, ' '))
    endif

    " Return all lines after the last '>>> user'
    return trim(join(l:processed_lines, "\n"))
endfunction

function! chat#Debug()
    echo s:messages
endfunction


function! chat#OpenChatBuffer() abort
    " Define the buffer name
    let bufname = "[Chat]"

    " Check if the buffer exists
    if !bufexists('^'.bufname.'$')
        " Create a new buffer
        execute "silent keepalt botright split " . bufname
        let s:messages = []
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
    nnoremap <silent> <buffer> <CR> <cmd>call chat#AIChatRequest()<CR>
    nnoremap <silent> <buffer> <BS> <cmd>call chat#StopChatRequest()<CR>

    " Store buffer number globally
    let s:chat_bufnr = bufnr

    normal ggdG
    call setbufline(s:chat_bufnr, 1, [">>> user", ""])
    normal G
endfunction


function! s:PrintProgressMessage(...) abort
    if !s:awaiting_response
        return
    endif
    echo "In progress..."
    let s:progress_timer = timer_start(1000, function('s:PrintProgressMessage'))
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

    " let messages = s:GetChatHistory()
    let message = {"role": "user", "content": s:GetLastUserQueryContent()}
    let s:messages = add(s:messages, message)
    let payload = json_encode({"model": config["model"], "messages": s:messages})

    " Start progress message loop
    let s:awaiting_response = v:true
    let s:progress_timer = timer_start(0, function('s:PrintProgressMessage'))

    " Run curl asynchronously
    let cmd = ['curl', '-s', config['endpoint_url'], '--no-buffer', '-d', payload]
    let s:job_id = job_start(cmd, {'out_cb': function('s:OnAIResponse'), 'exit_cb': function('s:OnAIResponseEnd')})
endfunction


function! s:StopProgressMessage()
    if s:awaiting_response
        " Stop progress timer
        if s:progress_timer isnot v:null
            call timer_stop(s:progress_timer)
            let s:progress_timer = v:null
        endif
        let s:awaiting_response = v:false
        echo ""
    endif
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

    call s:StopProgressMessage()

    if s:messages[-1]["role"] != "assistant"
        let s:messages = add(s:messages, {"role": "assistant", "content": ""})
    endif

    " Append new chunk to the response text
    let s:response_text .= chunk.message.content
    let s:messages[-1]["content"] = s:response_text

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
    call s:StopProgressMessage()
endfunction


function! chat#StopChatRequest() abort
    if s:job_id is v:null
        echo "Error: No chat chat request in progress"
        return
    endif
    echo "Stopping chat request"
    call job_stop(s:job_id)
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
