# Ambiguous; you need another { and }

## Description
Multiple `\over` primitives were used in the same math subformula without grouping braces.

## Remediation
Disambiguate grouping: `${{x \over y} \over z}$` or use LaTeX `\frac{x}{y}`.
