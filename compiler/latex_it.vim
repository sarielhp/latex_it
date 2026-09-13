" Vim compiler file
" Compiler: latex_it
" Maintainer: Sariel Har-Peled

if exists("current_compiler")
  finish
endif
let current_compiler = "latex_it"

if exists(":CompilerSet") != 2
  command -nargs=* CompilerSet setlocal <args>
endif

CompilerSet makeprg=l\ --vim\ $*

" Universal errorformat matching latex_it --vim output:
"   paper.tex:3:1: error: Undefined control sequence
"   paper.tex:42: warning: LaTeX Warning: ...
"   paper.tex:85: alert: LaTeX Warning: ...
"   paper.tex:120: note: Overfull \hbox ...
CompilerSet errorformat=
      \%f:%l:%c:\ %t%*[^:]:\ %m,
      \%f:%l:\ %t%*[^:]:\ %m,
      \%f:%l:\ %m,
      \%-G%.%#
