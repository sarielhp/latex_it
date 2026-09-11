# LaTeX Error: \caption outside float

## Description
`\caption` was used outside a floating environment (`figure` or `table`).

## Remediation
Wrap in `\begin{figure}` / `\begin{table}`, or use `\captionof{figure}{...}` from `caption` package.
