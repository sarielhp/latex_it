# Vim & Neovim Integration with latex_it

`latex_it` provides first-class support for Vi, Vim, and Neovim through the `--vim` (or `--qf`) flag and the bundled Vim compiler plugin.

---

## Quick Start (Zero-Plugin)

You can use `latex_it` directly with Vim's built-in `:make` command without installing any plugins.

In your `~/.vim/after/ftplugin/tex.vim` (or `~/.config/nvim/after/ftplugin/tex.lua`):

### Vimscript (`~/.vim/after/ftplugin/tex.vim`):
```vim
setlocal makeprg=l\ --vim
setlocal errorformat=%f:%l:%c:\ %t%*[^:]:\ %m,%f:%l:\ %t%*[^:]:\ %m,%f:%l:\ %m,%-G%.%#
```

### Lua (`~/.config/nvim/after/ftplugin/tex.lua`):
```lua
vim.opt_local.makeprg = "l --vim"
vim.opt_local.errorformat = "%f:%l:%c: %t%*[^:]: %m,%f:%l: %t%*[^:]: %m,%f:%l: %m,%-G%.%#"
```

Whenever you run `:make` inside a `.tex` file:
* All compilation errors, alerts, and warnings automatically populate the **Quickfix list** (`:copen`).
* Navigating with `:cnext` and `:cprev` jumps directly to the file, line, and column.
* Clean builds complete silently with zero noise.

---

## Compiler Plugin (`compiler/latex_it.vim`)

The repository includes a standard Vim compiler script at [`compiler/latex_it.vim`](file:///home/sariel/prog/26/latex_it/compiler/latex_it.vim).

### Installation:
Copy or symlink `compiler/latex_it.vim` into your Vim/Neovim compiler directory:
```bash
# Classic Vim
mkdir -p ~/.vim/compiler
cp compiler/latex_it.vim ~/.vim/compiler/

# Neovim
mkdir -p ~/.config/nvim/compiler
cp compiler/latex_it.vim ~/.config/nvim/compiler/
```

*(If you use a plugin manager like vim-plug, lazy.nvim, or packer pointing to this repo, `compiler/latex_it.vim` is detected automatically).*

### Usage:
In any LaTeX buffer:
```vim
:compiler latex_it
:make
```

---

## Asynchronous Building

### With `tpope/vim-dispatch`:
```vim
:compiler latex_it
:Make
```
Compiles in the background without freezing your editor and loads errors into Quickfix when finished.

### With `skywind3000/asynrun.vim`:
```vim
:AsyncRun -program=make l --vim
```

---

## VimTeX Integration

If you use [VimTeX](https://github.com/lervag/vimtex), configure it to use `l` and recognize `junk/` as the build directory:

```vim
let g:vimtex_compiler_method = 'generic'
let g:vimtex_compiler_generic = {
      \ 'command' : 'l --vim',
      \ }
let g:vimtex_build_dir = 'junk'
```
