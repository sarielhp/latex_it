# LaTeX Error: Can be used only in preamble

## Description
A preamble declaration (like `\usepackage`) was executed after `\begin{document}`.

## Remediation
Move package and preamble declarations before `\begin{document}`.
