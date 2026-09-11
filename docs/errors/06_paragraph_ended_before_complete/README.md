# Paragraph ended before \foo was complete / Runaway argument?

## TeX Output
```text
Runaway argument?
{First line. 
./example.tex:5: Paragraph ended before \textbf was complete.
<to be read again> 
                   \par 
l.5 
```

## Explanation
In TeX, macros are by default "short" (not `\long`), meaning their arguments cannot contain paragraph breaks (`\par` or blank lines). This error typically happens when:
1. An opening brace `{` after a macro like `\textbf{`, `\section{`, or `\emph{` was never closed, and the compiler hit a blank line.
2. An intended multi-paragraph block was passed into a single-paragraph formatting macro.

## How to Fix
- Close the unclosed brace `{` on the line where the macro was opened.
- If multiple paragraphs need formatting, format each paragraph separately, or use an environment (e.g. `\begin{quote} ... \end{quote}`) or switch commands (`{\bfseries ... \par ...}`).
