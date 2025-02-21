" chat.vim - An asynchronous AI Chat interface for Vim
" Maintainer:  BlakeJC94 <https://github.com/BlakeJC94>
" Version:     0.2.0

if exists('g:loaded_chat')
    finish
endif
let g:loaded_chat = 1

command! -complete=customlist,chat#ConfigCompletion -nargs=* Chat call chat#OpenChatSplit(<q-mods>, <f-args>)
command! -nargs=* ChatDebug call chat#DebugChatState(<f-args>)

command! ChatSend call chat#StartChatRequest()
command! ChatStop call chat#StopChatRequest()

nmap <silent> <plug>(chat-start) <cmd>call chat#StartChatRequest()<CR>
nmap <silent> <plug>(chat-stop) <cmd>call chat#StopChatRequest()<CR>

augroup vim_chat
    autocmd!
    autocmd BufNewFile,BufReadPost,FileReadPost *.chat.vim.json call chat#InitializeChatBuffer()
augroup END
