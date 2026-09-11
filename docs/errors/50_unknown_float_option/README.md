# LaTeX Error: Unknown float option 'H'

## Description
The strict placement specifier `[H]` was used without loading the supporting `float` package.

## Remediation
Add `\usepackage{float}` to your preamble, or use standard options `[!htbp]`.
