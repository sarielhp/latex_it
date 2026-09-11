# Illegal parameter number in definition of \foo

## Description
A macro definition referenced `#1` (or `#2`) without declaring arguments in `\newcommand`.

## Remediation
Declare the number of parameters: `\newcommand{\mycmd}[1]{#1}`.
