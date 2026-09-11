# Package amsmath Error: Invalid use of \intertext

## Description
`\intertext` can only be used inside multi-line alignment environments (`align`, `gather`), not `equation`.

## Remediation
Switch to `\begin{align}` or place text outside the equation block.
