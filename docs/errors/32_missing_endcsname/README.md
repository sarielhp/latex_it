# Missing \endcsname inserted

## Description
A `\csname` primitive was started without a terminating `\endcsname`.

## Remediation
Close the macro name construction with `\endcsname`.
