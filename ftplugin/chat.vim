setlocal buftype=nofile    " Unlisted, scratch buffer
setlocal bufhidden=hide    " Hide buffer when switching
setlocal wrap              " Text wrapping
setlocal foldmethod=manual " Disable automatic folds
setlocal syntax=markdown   " Enable Markdown highlighting
setlocal noswapfile        " Prevent swap file creation
setlocal foldlevel=99
setlocal formatoptions-=t


" TODO Make mappings customizable
nnoremap <silent> <buffer> <CR> <cmd>call chat#StartChatRequest()<CR>
nnoremap <silent> <buffer> <BS> <cmd>call chat#StopChatRequest()<CR>
