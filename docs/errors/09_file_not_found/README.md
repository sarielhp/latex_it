# LaTeX Error: File '...' not found

## TeX Output
```text
./example.tex:2: LaTeX Error: File `nonexistent_file_xyz.tex' not found.
l.2 \input{nonexistent_file_xyz.tex}
```

## Explanation
An `\input{...}`, `\include{...}`, or `\usepackage{...}` command requested a file that could not be located on the TeX search path (`TEXINPUTS` or local directory).

## How to Fix
1. Verify the exact spelling and file extension of the target file.
2. Check relative paths (e.g. `\input{chapters/intro}` instead of `\input{intro}`).
3. If referencing a package (`.sty` file), ensure the package is installed via TeX Live (`tlmgr install <pkg>`) or place the `.sty` in the project root or styles directory.
