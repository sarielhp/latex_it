# Misplaced \noalign / Misplaced \omit

## Description
`\hline` or `\cline` was placed after table cell content instead of immediately after `\\`.

## Remediation
Ensure `\hline` is placed immediately after `\\` at the end of the previous row.
