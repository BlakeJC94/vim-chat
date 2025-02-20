setlocal buftype=nofile    " Unlisted, scratch buffer
setlocal bufhidden=hide    " Hide buffer when switching
setlocal wrap              " Text wrapping
setlocal foldmethod=manual " Disable automatic folds
setlocal noswapfile        " Prevent swap file creation
setlocal foldlevel=99
setlocal formatoptions-=t


" TODO Make mappings customizable
nmap <silent> <buffer> <CR> <plug>(chat-start)
nmap <silent> <buffer> <BS> <plug>(chat-stop)

execute 'silent! file [Chat]'
