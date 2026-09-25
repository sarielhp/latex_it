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

CompilerSet makeprg=l\ --compile\ $*

" Universal errorformat matching GNU standard compiler output from latex_it --compile:
"   paper.tex:3:1: error: undefined control sequence \foo
"   paper.tex:42: warning: reference `nonexistent' on page 1 undefined
"   paper.tex:85: warning: [alert] label `foo' multiply defined
"   paper.tex:120: note: overfull \hbox (1.5pt too wide) detected
CompilerSet errorformat=
      \%f:%l:%c:\ %t%*[^:]:\ %m,
      \%f:%l:\ %t%*[^:]:\ %m,
      \%f:%l:\ %m,
      \%-G%.%#
