# LaTeX Error: There's no line here to end

## TeX Output
```text
./example.tex:3: LaTeX Error: There's no line here to end.
l.3 \\
```

## Explanation
The `\\` and `\newline` macros instruct LaTeX to break the *current horizontal line*. If LaTeX is currently in vertical mode (between paragraphs, at the start of a section, or after an empty line), there is no line in progress to break.

## How to Fix
- Remove `\\` from the beginning of paragraphs, sections, or table cells.
- If vertical spacing is desired, use vertical space commands like `\vspace{1em}`, `\smallskip`, `\medskip`, or `\bigskip`, never `\\`.
- To separate paragraphs, simply leave a blank line between them in the source.
