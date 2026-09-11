# Misplaced alignment tab character &

## TeX Output
```text
./example.tex:5: Misplaced alignment tab character &.
l.5   x = 1 &
              y = 2
```

## Explanation
The ampersand symbol (`&`) is a reserved TeX alignment delimiter. This error occurs when:
1. `&` is used inside an unaligned math environment (like `equation`, `equation*`, or inline `$ ... $`).
2. `&` is used in normal prose without escaping it (e.g. `Barnes & Noble`).
3. Alignment environments like `matrix` or `align` are used without loading `\usepackage{amsmath}`.

## How to Fix
- In math mode, replace `equation*` with `align*` or wrap the expressions inside `\begin{aligned} ... \end{aligned}`:
  ```latex
  \begin{align*}
    x = 1 & y = 2
  \end{align*}
  ```
- In regular text, escape the ampersand with a backslash: `\&`.
