" TODO Better parsing
" TODO search hist
" TODO model options
" TODO print model name?
" TODO system message/initial prompt
let s:vim_chat_config_default = {
\  "model": "llama3.2:latest",
\  "endpoint_url": "http://localhost:11434/api/chat"
\}
let s:vim_chat_path_default = expand("$HOME") . "/.chat.vim"

" Globals
let s:chat_states = {}


function! chat#GetChatConfig() abort
    return extend(s:vim_chat_config_default, get(g:, 'vim_chat_config', {}))
endfunction


function! chat#GetChatPath() abort
    let chat_path = get(g:, 'vim_chat_path', s:vim_chat_path_default)
    if !isdirectory(chat_path)
        call mkdir(chat_path, "p")
    endif
    return chat_path
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
    let l:lines = getbufline("%", 1, '$')
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


function! s:UpdateHistory(bufnr) abort
    let state = get(s:chat_states, a:bufnr, v:null)
    if state is v:null
        return
    endif
    let json_list = map(copy(state['messages']), 'printf("  %s", json_encode(v:val))')
    let json_str = "[\n" . join(json_list, ",\n") . "\n]"
    silent! call writefile(split(json_str, "\n"), state['messages_filepath'])
endfunction


function! s:InitialiseChatBufferState(bufnr) abort
    let s:chat_states[a:bufnr] = {
        \ "response_text": "",
        \ "response_lnum": -1,
        \ "job_id": v:null,
        \ "awaiting_response": v:false,
        \ "progress_timer": v:null,
        \ "messages": [],
        \ "messages_filepath": expand('%'),
        \ }
    return s:chat_states[a:bufnr]
endfunction


function! chat#NewChatFilepath() abort
    let filename = strftime('%Y-%m-%d_%H-%m_') . printf("%08x", rand()) . ".chat.vim.json"
    return chat#GetChatPath() . '/' . filename
endfunction



function! s:PrintProgressMessage(bufnr, timer_id) abort
    let state = s:chat_states[a:bufnr]
    if !state['awaiting_response']
        return
    endif
    echo "In progress..."
    let state['progress_timer'] = timer_start(1000, function('s:PrintProgressMessage', [a:bufnr]))
endfunction


function! chat#StartChatRequest() abort
    let bufnr = bufnr('%')
    if !has_key(s:chat_states, bufnr)
        echo "Error: No chat buffer state for current buffer"
        return
    endif

    let state = s:chat_states[bufnr]

    if state['job_id'] isnot v:null
        echo "Error: Chat request already in progress"
        return
    endif

    call appendbufline(bufnr, '$', ["", "<<< user", ">>> assistant", ""])

    " Track the line where assistant's response should be written
    let state['response_lnum'] = line('$')

    let config = chat#GetChatConfig()

    let msg = {"role": "user", "content": s:GetLastUserQueryContent()}
    let state['messages'] += [msg]
    call s:UpdateHistory(bufnr)
    let payload = json_encode({"model": config["model"], "messages": state['messages']})

    " Start progress message loop
    let state['awaiting_response'] = v:true
    let state['progress_timer'] = timer_start(0, function('s:PrintProgressMessage', [bufnr]))

    " Run curl asynchronously
    let cmd = ['curl', '-s', config['endpoint_url'], '--no-buffer', '-d', payload]
    let state['job_id'] = job_start(cmd, {
        \ 'out_cb': function('s:OnAIResponse', [bufnr]),
        \ 'exit_cb': function('s:OnAIResponseEnd', [bufnr])
        \ })
endfunction


function! s:StopProgressMessage(bufnr)
    let state = get(s:chat_states, a:bufnr, v:null)
    if state is v:null
        return
    endif
    if state['awaiting_response']
        " Stop progress timer
        if state['progress_timer'] isnot v:null
            call timer_stop(state['progress_timer'])
            let state['progress_timer'] = v:null
        endif
        let state['awaiting_response'] = v:false
        echo ""
    endif
endfunction


function! s:OnAIResponse(bufnr, channel, msg) abort
    let state = get(s:chat_states, a:bufnr, v:null)

    if state is v:null || !bufexists(a:bufnr)
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

    call s:StopProgressMessage(a:bufnr)

    if state['messages'][-1]["role"] != "assistant"
        let state['messages'] += [{"role": "assistant", "content": ""}]
    endif

    " Append new chunk to the response text
    let state['response_text'] .= chunk.message.content
    let state['messages'][-1]["content"] = state['response_text']

    " Split response into lines for correct formatting
    let response_lines = split(state['response_text'], "\n")

    " Update buffer with multi-line response
    call setbufline(a:bufnr, state['response_lnum'], response_lines)

    if has_key(chunk, "done_reason")
        call appendbufline(a:bufnr, '$', ["", "<<< assistant", ">>> user", ""])
        call s:UpdateHistory(a:bufnr)
        let state['response_text'] = ""
        let state['response_lnum'] = line('$')  " Update response line tracking
    endif

    " Scroll to bottom
    let winid = bufwinid(a:bufnr)
    if winid != -1
        call win_execute(winid, "normal! G")
    endif
endfunction


function! s:OnAIResponseEnd(bufnr, job, status) abort
    let state = get(s:chat_states, a:bufnr, v:null)
    let state['response_text'] = ""
    let state['job_id'] = v:null
    call s:StopProgressMessage(a:bufnr)
endfunction


function! chat#StopChatRequest() abort
    let bufnr = bufnr('%')
    let state = get(s:chat_states, bufnr, v:null)
    if state['job_id'] is v:null
        echo "Error: No chat chat request in progress"
        return
    endif
    echo "Stopping chat request"
    call job_stop(state['job_id'])
endfunction


function! chat#InitializeChatBuffer()
    let bufnr = bufnr('%')
    if has_key(s:chat_states, bufnr)
        echo "Chat buffer already initialized"
        return
    endif

    let state = s:InitialiseChatBufferState(bufnr)

    let json_str = trim(join(getbufline(bufnr, 1, '$'), ""))
    if empty(json_str)
        let state['messages'] = []
    else
        try
            let state['messages'] = json_decode(json_str)
        catch /JSON/
            echohl ErrorMsg | echom "Invalid JSON format" | echohl None
            return
        endtry
    endif

    execute 'silent! file [Chat]'

    " Clear buffer before inserting history
    normal ggdG

    " Append messages in the correct format
    for msg_idx in range(len(state['messages']))
        let msg = state['messages'][msg_idx]
        if msg.role == "user"
            if msg_idx == 0
                call setbufline(bufnr, '$', ">>> user")
            else
                call appendbufline(bufnr, '$', "<<< assistant")
                call appendbufline(bufnr, '$', ">>> user")
            endif
        elseif msg.role == "assistant"
            call appendbufline(bufnr, '$', "<<< user")
            call appendbufline(bufnr, '$', ">>> assistant")
        endif
        call appendbufline(bufnr, '$', split(msg.content, "\n") + [""])
    endfor

    call appendbufline(bufnr, '$', [">>> user", ""])

    let lnum = 1
    while lnum <= line('$') && getline(lnum) =~ '^\s*$'
        execute lnum . 'delete'
    endwhile

    normal! G
endfunction
