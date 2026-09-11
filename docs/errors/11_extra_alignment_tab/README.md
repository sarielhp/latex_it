# Extra alignment tab has been changed to \cr

## Description
A table or matrix row contains more `&` separators than columns specified in the table preamble (e.g. `{c}`).

## Remediation
Add more columns to the tabular preamble (e.g. `\begin{tabular}{cc}`) or remove the extra `&`.
