# Something's wrong--perhaps a missing \item

## TeX Output
```text
./example.tex:4: LaTeX Error: Something's wrong--perhaps a missing \item.
l.4   This
           text is missing an item macro.
```

## Explanation
In LaTeX list environments (`itemize`, `enumerate`, `description`), all content must be preceded by an `\item` command. This error is triggered when:
1. Text is placed immediately after `\begin{itemize}` without an `\item`.
2. A list environment is completely empty with no `\item` entries at all.
3. The list was closed improperly or another environment was opened inside it without an `\item`.

## How to Fix
Precede any list content with `\item`:
```latex
\begin{itemize}
  \item This text is now properly introduced.
\end{itemize}
```
If you do not want bulleted/numbered items, use normal paragraphs or `\begin{quote}` instead.
