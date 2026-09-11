# LaTeX Error: Environment \foo undefined

## TeX Output
```text
./example.tex:3: LaTeX Error: Environment unknownenv undefined.
l.3 \begin{unknownenv}
```

## Explanation
LaTeX was asked to enter an environment (`\begin{unknownenv}`) that has not been declared via `\newenvironment` in the document, class, or any imported package.

## How to Fix
1. Check for spelling errors in the environment name (e.g. `align*` vs `align`, `tabular` vs `table`).
2. If the environment belongs to a third-party package (e.g. `tikzpicture` from `tikz`, `algorithm` from `algorithm2e`, or `lstlisting` from `listings`), add `\usepackage{...}` to the preamble.
3. If creating a custom environment, declare it with `\newenvironment{unknownenv}{<before>}{<after>}`.
