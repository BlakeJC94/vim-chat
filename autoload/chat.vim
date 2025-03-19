let s:vim_chat_config_default = {
\  "model": "llama3.2:latest",
\  "endpoint_url": "http://localhost:11434/api/chat"
\}
let s:vim_chat_path_default = expand("$HOME") . "/.chat.vim"

" Globals
let s:chat_states = {}
let g:chat_states = s:chat_states


function! chat#GetChatConfig(...) abort
    let config_name = get(a:000, 0, "default")
    let configs = get(g:, 'vim_chat_config', {})
    let config = has_key(configs, "endpoint") ? configs : get(configs, config_name, {})
    return extend(s:vim_chat_config_default, config)
endfunction


function! chat#GetChatPath() abort
    let chat_path = get(g:, 'vim_chat_path', s:vim_chat_path_default)
    if !isdirectory(chat_path)
        call mkdir(chat_path, "p")
    endif
    return chat_path
endfunction


function! chat#OpenChatSplit(mods, ...) abort
    let filepath = fnameescape(chat#NewChatFilepath())

    let config_name = get(a:000, 0, "default")
    let config = chat#GetChatConfig(config_name)

    if a:mods != ''
        execute 'silent ' . a:mods . ' split ' . filepath
    else
        execute 'silent split ' . filepath
    endif

    let bufnr = bufnr('%')
    let s:chat_states[bufnr]["config_name"] = config_name

    if has_key(config, "system_prompt") && len(s:chat_states[bufnr]['messages']) == 0
        let content = config['system_prompt']
        if type(content) == v:t_list
            let content = join(content, "\n")
        endif
        call appendbufline(bufnr, 0, [">>> system", content, "", "<<< system"])
    endif

    execute 'silent! file [Chat (' . config_name . ')]'
    normal! G
endfunction


function! chat#DebugChatState(...) abort
    let bufnr = bufnr('%')
    if !has_key(s:chat_states, bufnr)
        echo "Error: No chat buffer state for current buffer"
        return
    endif
    let chat_state = s:chat_states[bufnr]
    let key = get(a:000, 0, '')
    if key == ''
        echo chat_state
        return
    endif
    if !has_key(chat_state, key)
        echo "Error: Invalid key '" . key . "', select one of " . join(keys(state), ", ")
        return
    endif
    echo chat_state[key]
endfunction


function! s:GetChatHistory(bufnr) abort
    " Get buffer content
    let lines = getbufline(a:bufnr, 1, '$')

    let messages = []
    let current_role = ''
    let current_message = ''

    " Loop through buffer to extract user/assistant pairs
    for line in lines
        if line =~ trim('^<<< ' . current_role)
            call add(messages, {'role': current_role, 'content': current_message})
            let current_role = ''
            let current_message = ''
        elseif line =~ '^>>>'
            let current_role = substitute(line, '^>>>\s\(.*\)', '\1', '')
        else
            let current_message .= "\n" . line
        endif
    endfor
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

    " Return all lines after the last '>>> user'
    return trim(join(l:user_text, "\n"))
endfunction


function! s:UpdateHistory(bufnr) abort
    let state = get(s:chat_states, a:bufnr, v:null)
    if state is v:null
        return
    endif
    silent! call writefile(getbufline(a:bufnr, 1,'$'), state['messages_filepath'])
endfunction


function! chat#InitializeChatBufferState(bufnr) abort
    if has_key(s:chat_states, a:bufnr)
        return
    endif
    let s:chat_states[a:bufnr] = {
        \ "config_name": "",
        \ "response_text": "",
        \ "response_lnum": -1,
        \ "job_id": v:null,
        \ "awaiting_response": v:false,
        \ "progress_timer": v:null,
        \ "messages": s:GetChatHistory(a:bufnr),
        \ "messages_filepath": bufname(a:bufnr),
        \ }
    " call chat#WritePrompt(a:bufnr)
    call timer_start(50, {-> chat#WritePrompt(a:bufnr)})
endfunction


function! chat#NewChatFilepath() abort
    let filename = strftime('%Y-%m-%d_%H-%M_') . printf("%08x", rand()) . ".chat"
    return chat#GetChatPath() . '/' . filename
endfunction


function! s:PrintProgressMessage(bufnr, timer_id) abort
    let state = s:chat_states[a:bufnr]
    if !state['awaiting_response']
        return
    endif
    call setbufline(a:bufnr, "$", "In progress..")
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

    " prompt config selection if not set
    if empty(state['config_name'])
        let configs = get(g:, 'vim_chat_config', {})
        if has_key(configs, "endpoint")
            let config_name = "default"
        elseif len(keys(configs)) == 1
            let config_name = keys(configs)[0]
        else
            let menu = "Choose config type\n"
            let opts = keys(configs)
            for idx in range(len(opts))
                let opt = opts[idx]
                let menu .= printf("%d. %s\n", idx+1, opt)
            endfor
            let full_prompt = menu . "Type number and <Enter> (empty cancels): "
            let choice = input(full_prompt)
            let config_name = opts[choice - 1]
        endif
        let state['config_name'] = config_name
        execute 'silent! file [Chat (' . config_name . ')]'
    endif

    let config = chat#GetChatConfig(state['config_name'])

    let header = [
        \ '-H',
        \ 'Content-Type: application/json',
        \ ]
    if has_key(config, 'token_var')
        if getenv(config['token_var']) == ''
            echo "Error: Key not found in environment variable '".config["token_var"]."'"
            return
        endif
        let header = header + [
            \ '-H',
            \ 'Authorization: Bearer '. getenv(config['token_var']),
            \ ]
    endif


    let msg = {"role": "user", "content": s:GetLastUserQueryContent()}
    let state['messages'] += [msg]
    call s:RenderBuffer(bufnr)
    call s:UpdateHistory(bufnr)

    let payload = {"model": config["model"], "messages": state['messages']}
    if has_key(config, "options")
        payload["options"] = config['options']
    endif
    let body = [
        \ '-d',
        \ json_encode(payload),
        \ ]
    let cmd = [
        \ 'curl',
        \ '--no-buffer',
        \ config['endpoint_url']
        \ ]

    call appendbufline(bufnr, '$', [">>> assistant", ""])

    " Track the line where assistant's response should be written
    let state['response_lnum'] = line('$')

    let winid = bufwinid(bufnr)
    if winid != -1
        call win_execute(winid, "normal! G")
    endif

    " Start progress message loop
    let state['awaiting_response'] = v:true
    let state['progress_timer'] = timer_start(0, function('s:PrintProgressMessage', [bufnr]))

    " Launch curl asynchronously
    if has('nvim')
        let state['job_id'] = jobstart(cmd + header + body, {
            \ 'on_stdout': function('s:OnAIResponseNvim', [bufnr]),
            \ 'on_exit': function('s:OnAIResponseEndNvim', [bufnr])
            \ })
    else
        let state['job_id'] = job_start(cmd + header + body, {
            \ 'out_cb': function('s:OnAIResponse', [bufnr]),
            \ 'exit_cb': function('s:OnAIResponseEnd', [bufnr])
            \ })
    endif
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
        call setbufline(a:bufnr, '$', "")
    endif
endfunction


function! s:OnAIResponseNvim(bufnr, _job_id, data, _event) abort
    call s:OnAIResponse(a:bufnr, v:null, join(a:data))
endfunction
function! s:OnAIResponse(bufnr, _channel, msg) abort
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
        call appendbufline(a:bufnr, '$', ["", "<<< assistant"])
        call s:UpdateHistory(a:bufnr)
        call chat#WritePrompt(a:bufnr)
        let state['response_text'] = ""
        let state['response_lnum'] = line('$')  " Update response line tracking
    endif

    " Scroll to bottom only if the cursor is already on the last line
    let winid = bufwinid(a:bufnr)
    if winid != -1
        let cursor_lnum = win_execute(winid, 'echo line(".")')->split("\n")[-1]
        let last_lnum = win_execute(winid, 'echo line("$")')->split("\n")[-1]

        if has_key(chunk, "done_reason") || cursor_lnum + 1 == last_lnum
            call win_execute(winid, "normal! G")
        endif
    endif
endfunction


" TODO Print errors that occur
function! s:OnAIResponseEndNvim(bufnr, _job_id, _data, _event) abort
    call s:OnAIResponseEnd(a:bufnr, v:null, v:null)
endfunction
function! s:OnAIResponseEnd(bufnr, _job, _status) abort
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


function! chat#WritePrompt(bufnr) abort
    let bufnr = a:bufnr
    if len(getbufline(bufnr, 1, '$')) == 1
        call setbufline(bufnr, '$', [">>> user", ""])
    else
        call appendbufline(bufnr, '$', [">>> user", ""])
    endif
endfunction


function! s:GetRenderedLines(messages)
    let messages = a:messages
    let lines = []

    for msg_idx in range(len(messages))
        let msg = messages[msg_idx]
        let role = msg['role']
        let content = msg['content']

        call add(lines, ">>> " . role)
        let lines += split(content, "\n") + [""]
        call add(lines, "<<< " . role)
    endfor

    return lines
endfunction


function! s:RenderBuffer(bufnr) abort
    let bufnr = a:bufnr
    let state = s:chat_states[bufnr]
    let lines = s:GetRenderedLines(state['messages'])
    silent call setbufline(bufnr, 1, lines)
endfunction


function! chat#ConfigCompletion(ArgLead, CmdLine, CursorPos)
    echo a:ArgLead
    let configs = get(g:, 'vim_chat_config', {})
    let results = []
    if len(configs) == 0 || has_key(configs, 'endpoint')
        return results
    endif
    let keys = keys(configs)

    for key in keys
        if key =~ '^' . a:ArgLead
            call add(results, key)
        endif
    endfor
    return results
endfunction


function! chat#GrepChats(query, ...) abort
    let query = a:query
    let search = get(a:000, 0, v:false)

    if empty(query)
        echo "Please provide a search query."
        return
    endif

    if search
        let query = '\<' . query . '\>'
    endif

    let grep_command = printf('vimgrep /%s/j %s/*.chat', escape(query, '/'), chat#GetChatPath())
    execute 'silent! ' . grep_command
    copen
endfunction
