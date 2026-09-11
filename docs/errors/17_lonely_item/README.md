# Lonely \item--perhaps a missing list environment

## Description
An `\item` macro was used outside of an `itemize`, `enumerate`, or `description` environment.

## Remediation
Enclose items within `\begin{itemize} ... \end{itemize}`.
