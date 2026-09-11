# Package amsmath Error: \begin{split} won't work here

## Description
`\begin{split}` can only be used inside an existing display math environment (`equation`, `align`).

## Remediation
Wrap `\begin{split}` inside an enclosing `\begin{equation}` or `\begin{gather}`.
