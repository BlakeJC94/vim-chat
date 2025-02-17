" chat.vim - An asynchronous AI Chat interface for Vim
" Maintainer:  BlakeJC94 <https://github.com/BlakeJC94>
" Version:     0.0.1


" TODO Default config

command Chat :call chat#OpenChatBuffer()

" TODO
" command SaveChat :call chat#SaveChatHistory()
" command! -nargs=1 -complete=file LoadChat call chat#LoadChatHistory(<q-args>)
