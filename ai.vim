let s:chat_bufnr = -1  " Store the chat buffer number

function! OpenChatBuffer()
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

    " Store buffer number globally
    let s:chat_bufnr = bufnr

    normal ggdG
    normal G
endfunction

command Chat :if bufname('%') == '[Chat]' | call AIChatRequest() | else | call OpenChatBuffer() | call setbufline(s:chat_bufnr, 1, [">>> user", ""]) | endif

function! GetChatHistory()
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


function! AIChatRequest()
    let s:chat_bufnr = bufnr('%')  " Store the current buffer number

    call appendbufline(s:chat_bufnr, '$', ["", "<<< user", ">>> assistant"])

    let messages = GetChatHistory()

    " API endpoint
    let url = "http://localhost:11434/api/chat"

    " JSON payload
    let payload = json_encode({"model": "phi4:latest", "messages": messages})

    " Run curl asynchronously
    let cmd = ['curl', '-s', url, '--no-buffer', '-d', payload]
    let job_id = job_start(cmd, {'out_cb': function('OnAIResponse')})
endfunction


function! SaveChatHistory()
    " if s:chat_bufnr == -1 || !bufexists(s:chat_bufnr)
    "     echo "Error: Chat buffer no longer exists"
    "     return
    " endif
    let chat_history = GetChatHistory()
    " Convert to JSON
    let json_string = json_encode(chat_history)

    let temp_file = tempname()
    call writefile([json_string], temp_file, "b")
    let json_string = system('python -m json.tool ' . shellescape(temp_file))
    call delete(temp_file)

    " Create history folder if it doesn't exist
    let history_dir = expand('~/.vim_chat_history')
    if !isdirectory(history_dir)
        call mkdir(history_dir, "p")
    endif

    " Generate timestamped filename
    let timestamp = strftime('%Y-%m-%d_%H-%M-%S')
    let filename = history_dir . '/chat_' . timestamp . '.json'

    " Save to file
    call writefile(split(json_string, '\n'), filename, 'b')

    echo "Chat history saved to " . filename
endfunction

command SaveChat :call SaveChatHistory()

function! LoadChatHistory(filename)
    if !filereadable(a:filename)
        echo "Error: File does not exist"
        return
    endif

    let json_string = join(readfile(a:filename, 'b'), "\n")
    let chat_history = json_decode(json_string)

    " Ensure the chat buffer is created
    call OpenChatBuffer()
    call setbufline(s:chat_bufnr, 1, []) " Clear buffer before inserting history

    " Append messages in the correct format
    for msg in chat_history
        if msg.role == "user"
            call appendbufline(s:chat_bufnr, '$', ">>> user")
        elseif msg.role == "assistant"
            call appendbufline(s:chat_bufnr, '$', "<<< user")
        endif
        call appendbufline(s:chat_bufnr, '$', split(msg.content, "\n"))
    endfor

    echo "Chat history loaded from " . a:filename
endfunction

command! -nargs=1 -complete=file LoadChat call LoadChatHistory(<q-args>)

let s:response_text = ""

function! OnAIResponse(channel, msg)
    if s:chat_bufnr == -1 || !bufexists(s:chat_bufnr)
        echo "Error: Chat buffer no longer exists"
        return
    endif

    if empty(a:msg)
        " Response complete: reset for the next interaction
        let s:response_text = ""
        let s:chat_bufnr = -1
        return
   endif

    let chunk = json_decode(a:msg)
    if !has_key(chunk, 'message')
        return
    endif

    " Append new chunk to the response text
    let s:response_text .= chunk.message.content

    " Find the last occurrence of ">>> assistant" in the correct buffer
    let lines = getbufline(s:chat_bufnr, 1, '$')
    let response_start = -1
    let response_lnum = -1
    let lnum = len(lines)

    while lnum > 0
        if lines[lnum - 1] =~ '>>> assistant'
            let response_start = lnum
            break
        endif
        let lnum -= 1
    endwhile

    if response_start == -1
        echo "Error: Could not find '>>> assistant' marker"
        return
    endif

    " Find the line where the response should go (right after '<<< user')
    let response_lnum = response_start + 1

    " If there's already a response line, replace it, otherwise create it
    if response_lnum <= len(lines)
        call setbufline(s:chat_bufnr, response_lnum, split(s:response_text, "\n"))
    else
        call appendbufline(s:chat_bufnr, response_start, split(s:response_text, "\n"))
    endif

    " Scroll to bottom
    let winid = bufwinid(s:chat_bufnr)
    if winid != -1
        call win_execute(winid, "normal! G")
    endif

    if has_key(chunk, "done_reason")
        call appendbufline(s:chat_bufnr, len(lines), ["", "<<< assistant", ">>> user", ""])
        let s:response_text = ""
        let s:chat_bufnr = -1
    endif
endfunction



nnoremap <Leader>. :call AIChatRequest()<CR>

