# LaTeX Error: Not in outer par mode

## Description
A floating environment (`figure` or `table`) was placed inside a restricted box (`\mbox`) or table cell.

## Remediation
Move floating environments to the main vertical page flow, or use a `minipage` with `\captionof`.
