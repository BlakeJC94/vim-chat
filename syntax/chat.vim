if exists("b:current_syntax")
   finish
endif

" Source the markdown syntax file
setl syntax=markdown

" Set b:current_syntax to avoid re-loading in future
let b:current_syntax = 'markdown'
