# Option clash for package

## Description
A package was loaded multiple times with mutually conflicting options.

## Remediation
Pass all options in the first `\usepackage[opts]{...}` call or use `\PassOptionsToPackage`.
