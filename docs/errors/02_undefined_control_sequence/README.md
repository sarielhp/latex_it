# Undefined control sequence

## TeX Output
```text
./example.tex:3: Undefined control sequence.
l.3 This has an \undefinedcommand
                                 {here}.
```

## Explanation
TeX encountered a command (macro starting with `\`) that has not been defined in the LaTeX kernel, the document class, or any loaded package.

## How to Fix
1. Check for typos in the command name (e.g. `\textbld` instead of `\textbf`, or `\cal` instead of `\mathcal`).
2. If the command comes from an external package (such as `\mathbb` from `amssymb` or `\href` from `hyperref`), add `\usepackage{...}` to your document preamble.
3. If writing custom macros, define it using `\newcommand{\mycmd}{...}` before invoking it.
