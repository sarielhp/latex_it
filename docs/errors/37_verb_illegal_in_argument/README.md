# LaTeX Error: \verb illegal in command argument

## Description
`\verb` changes catcodes dynamically and cannot be used inside the argument of another command.

## Remediation
Use `\texttt{...}` instead of `\verb`, or use `cprotect` package or a separate verbatim block.
