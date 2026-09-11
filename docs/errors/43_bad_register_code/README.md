# Bad register code

## Description
A TeX register index was out of range (registers must be between 0 and 255/65535).

## Remediation
Ensure register numbers are non-negative, or use `\newcount` instead of hardcoded numbers.
