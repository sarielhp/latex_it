# You can't use `\hrule' here except with leaders

## Description
An `\hrule` horizontal rule was placed inside an `\hbox` (horizontal box) where only `\vrule` is permitted.

## Remediation
Use `\vrule` inside horizontal boxes, or place `\hrule` in vertical mode outside the box.
