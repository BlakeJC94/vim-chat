" TODO search hist
" TODO Delete empty chat files
let s:vim_chat_config_default = {
\  "model": "llama3.2:latest",
\  "endpoint_url": "http://localhost:11434/api/chat"
\}
let s:vim_chat_path_default = expand("$HOME") . "/.chat.vim"

" Globals
let s:chat_states = {}


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
    let l:filepath = fnameescape(chat#NewChatFilepath())

    let config_name = get(a:000, 0, "default")
    let config = chat#GetChatConfig(config_name)

    if has_key(config, "system_prompt")
        let content = config['system_prompt']
        if type(content) == v:t_list
            let content = join(content, "\n")
        endif
        let sys_msg = {"role": "system", "content": content}

        let json_str = "[\n" . json_encode(sys_msg) . "\n]"
        silent! call writefile(split(json_str, "\n"), l:filepath)
    endif

    if a:mods != ''
        execute a:mods . 'silent split ' . l:filepath
    else
        execute 'silent split ' . l:filepath
    endif

    let bufnr = bufnr('%')
    let s:chat_states[bufnr]["config_name"] = config_name

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

    " Return all lines after the last '>>> user'
    return trim(join(l:user_text, "\n"))
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
        \ "config_name": "",
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
    let filename = strftime('%Y-%m-%d_%H-%M_') . printf("%08x", rand()) . ".chat.vim.json"
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
    " TODO Add nvim support
    let state['job_id'] = job_start(cmd + header + body, {
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
        call setbufline(a:bufnr, '$', "")
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

    call s:RenderBuffer(bufnr)

    if len(getbufline(bufnr, 1, '$')) == 1
        call setbufline(bufnr, '$', [">>> user", ""])
    else
        call appendbufline(bufnr, '$', [">>> user", ""])
    endif
endfunction


function! s:RenderBuffer(bufnr) abort
    let bufnr = a:bufnr
    let state = s:chat_states[bufnr]
    " Clear buffer before inserting history
    silent call deletebufline(bufnr, 1, '$')

    " Append messages in the correct format
    for msg_idx in range(len(state['messages']))
        let msg = state['messages'][msg_idx]
        let role = msg['role']
        let content = msg['content']
        if len(getbufline(bufnr, 1, '$')) == 1
            call setbufline(bufnr, '$', ">>> " . role)
        else
            call appendbufline(bufnr, '$', ">>> " . role)
        endif
        call appendbufline(bufnr, '$', split(content, "\n") + [""])
        call appendbufline(bufnr, '$', "<<< " . role)
    endfor
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


function! s:WrapText(text, width)
    " Split the input text into lines based on newlines
    let lines = split(a:text, "\n")
    let result = []

    for line in lines
        while len(line) > a:width
            " Find the last whitespace character within the width limit
            let index = match(line[:a:width-1], '\s\+$')

            if index == -1
                " If no whitespace is found, forcefully break at width
                let index = a:width
            endif

            " Add the portion of the line up to the index to result
            call add(result, line[:index-1])
            " Remove the processed part from the original line
            let line = line[index:]
        endwhile

        " Add any remaining text that fits within the width limit
        if len(line) > 0
            call add(result, line)
        endif
    endfor

    return result
endfunction


function! chat#GrepChats(query, ...) abort
    " Ensure there's a query provided
    if empty(a:query)
        echo "Please provide a search query."
        return
    endif

    let query = a:query
    let search = get(a:000, 0, v:false)
    if search
        let query = '\<' . query . '\>'
    endif

    " Build the vimgrep command for *.chat.vim.json files in g:vim_chat_path
    let grep_command = printf('vimgrep /%s/j %s/*.chat.vim.json', escape(query, '/'), chat#GetChatPath())

    " Execute the vimgrep command to populate the quickfix list with initial matches
    execute 'silent! ' . grep_command

    " Get all current entries in the quickfix list
    let matches = getqflist()

    " Define a new empty list for filtered results
    let filtered_results = []

    " Iterate over each match to apply your custom filtering logic
    let width = max([20, winwidth(0) - 20])
    for match in matches
        let line_text = match.text
        let wrapped_text = s:WrapText(line_text, width)

        for line in wrapped_text
            if match(line, query) > -1
                let foo = copy(match)
                let foo['text'] = line
                call add(filtered_results, foo)
                break
            endif
        endfor
    endfor

    " Clear the current quickfix list and set with filtered results
    call setqflist(filtered_results)

    " Open the quickfix window to show results
    copen
endfunction
