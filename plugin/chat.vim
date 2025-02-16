if exists('g:autoloaded_chat')
    finish
endif
let g:autoloaded_chat = 1

" TODO Default config

command! Chat call chat#OpenChatBuffer()

" TODO
" command SaveChat :call chat#SaveChatHistory()
" command! -nargs=1 -complete=file LoadChat call chat#LoadChatHistory(<q-args>)

augroup vim_chat
    autocmd!
    autocmd BufReadPost,FileReadPost *.chat.vim.json call chat#RenderBuffer()
augroup END
