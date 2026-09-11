# Use of \foo doesn't match its definition

## Description
A delimited macro was defined with specific argument syntax (e.g. `(arg)`) but invoked with standard braces.

## Remediation
Call the macro with the expected argument delimiters (e.g. `\delimcmd(arg)`).
