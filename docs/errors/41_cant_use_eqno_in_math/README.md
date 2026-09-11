# You can't use `\eqno' in math mode

## Description
`\eqno` assigns an equation number and can only be used in display math (`$$`), not inline math (`$`).

## Remediation
Use display math: `\[ x \tag{1} \]` or `\begin{equation}`.
