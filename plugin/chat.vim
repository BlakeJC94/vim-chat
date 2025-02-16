if exists('g:loaded_chat')
    finish
endif
let g:loaded_chat = 1

command! -bar Chat execute '<mods> split ' . fnameescape(chat#NewChatFilepath())

augroup vim_chat
    autocmd!
    autocmd BufNewFile,BufReadPost,FileReadPost *.chat.vim.json call chat#InitializeChatBuffer()
augroup END
