# Ambiguous; you need another { and }

## Description
Multiple `\over` primitives were used in the same math subformula without grouping braces.

## Remediation
Disambiguate grouping: `{% raw %}${{x \over y} \over z}${% endraw %}` or use LaTeX `\frac{x}{y}`.
