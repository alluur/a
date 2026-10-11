" Vim color scheme "a-dark" - made for the A language, works for other files too
" Install: copy to ~/.vim/colors/ and run  :colorscheme a-dark
set background=dark
hi clear
if exists("syntax_on") | syntax reset | endif
let g:colors_name = "a-dark"
set termguicolors

function! s:h(group, fg, bg, attr)
  exec "hi " . a:group . " guifg=" . a:fg . " guibg=" . a:bg . " gui=" . a:attr . " cterm=" . a:attr
endfunction

"           group           fg         bg         attr
call s:h("Normal",       "#d6deeb", "#0f1720", "NONE")
call s:h("Cursor",       "#0f1720", "#7fdbca", "NONE")
call s:h("CursorLine",   "NONE",    "#16212d", "NONE")
call s:h("CursorLineNr", "#ffcb6b", "#16212d", "bold")
call s:h("LineNr",       "#4b5d70", "NONE",    "NONE")
call s:h("Visual",       "NONE",    "#2a3f5a", "NONE")
call s:h("Search",       "#0f1720", "#ffcb6b", "NONE")
call s:h("IncSearch",    "#0f1720", "#f78c6c", "NONE")
call s:h("MatchParen",   "#ffcb6b", "#3a4d63", "bold")
call s:h("StatusLine",   "#d6deeb", "#1f3047", "bold")
call s:h("StatusLineNC", "#7a8ca0", "#16212d", "NONE")
call s:h("VertSplit",    "#16212d", "#16212d", "NONE")
call s:h("Pmenu",        "#d6deeb", "#1f3047", "NONE")
call s:h("PmenuSel",     "#0f1720", "#7fdbca", "NONE")
call s:h("ColorColumn",  "NONE",    "#16212d", "NONE")
call s:h("NonText",      "#33475b", "NONE",    "NONE")
call s:h("Error",        "#ff5874", "NONE",    "bold,underline")
call s:h("Todo",         "#0f1720", "#ffcb6b", "bold")

call s:h("Comment",      "#637a91", "NONE",    "italic")
call s:h("Constant",     "#f78c6c", "NONE",    "NONE")
call s:h("String",       "#c3e88d", "NONE",    "NONE")
call s:h("Character",    "#c3e88d", "NONE",    "NONE")
call s:h("Number",       "#f78c6c", "NONE",    "NONE")
call s:h("Boolean",      "#ff9cac", "NONE",    "bold")
call s:h("SpecialChar",  "#7fdbca", "NONE",    "bold")
call s:h("Identifier",   "#82aaff", "NONE",    "NONE")
call s:h("Function",     "#addb67", "NONE",    "NONE")
call s:h("Namespace",    "#7fdbca", "NONE",    "NONE")
call s:h("Statement",    "#c792ea", "NONE",    "NONE")
call s:h("Conditional",  "#c792ea", "NONE",    "NONE")
call s:h("Repeat",       "#c792ea", "NONE",    "NONE")
call s:h("Keyword",      "#ff5874", "NONE",    "bold")
call s:h("Operator",     "#89ddff", "NONE",    "NONE")
call s:h("Delimiter",    "#7a8ca0", "NONE",    "NONE")
call s:h("PreProc",      "#ffcb6b", "NONE",    "NONE")
call s:h("Include",      "#ff9cac", "NONE",    "NONE")
call s:h("Type",         "#ffcb6b", "NONE",    "NONE")
call s:h("StorageClass", "#c792ea", "NONE",    "italic")
call s:h("Structure",    "#c792ea", "NONE",    "bold")
call s:h("Typedef",      "#ffcb6b", "NONE",    "bold")
call s:h("Special",      "#7fdbca", "NONE",    "italic")
