" Settings for A source files
if exists("b:did_ftplugin") | finish | endif
let b:did_ftplugin = 1
setlocal commentstring=//\ %s
setlocal comments=sO:*\ -,mO:*\ \ ,exO:*/,s1:/*,mb:*,ex:*/,://
setlocal formatoptions-=t formatoptions+=croql
setlocal cindent cinoptions=l1,j1,(0,Ws
setlocal expandtab shiftwidth=4 softtabstop=4 tabstop=4
setlocal iskeyword+=_
let b:undo_ftplugin = "setl cms< com< fo< cin< cino< et< sw< sts< ts< isk<"
