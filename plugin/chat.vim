" chat.vim - An asynchronous AI Chat interface for Vim
" Maintainer:  BlakeJC94 <https://github.com/BlakeJC94>
" Version:     0.1.0

if exists('g:loaded_chat')
    finish
endif
let g:loaded_chat = 1

command! -bar Chat execute '<mods> split ' . fnameescape(chat#NewChatFilepath())

augroup vim_chat
    autocmd!
    autocmd BufNewFile,BufReadPost,FileReadPost *.chat.vim.json call chat#InitializeChatBuffer()
augroup END
