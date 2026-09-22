# The Diagnostic Bestiary (`horror.tex`)

A deliberate torture-test document engineered to trigger as many distinct LaTeX, font, box, float, hyperref, and cross-referencing warnings and alerts as possible in a single document while successfully compiling to a finished PDF.

## Warnings & Alerts Triggered

| Category | Diagnostic | Trigger Mechanism |
| :--- | :--- | :--- |
| **Document** | Unused global option | `\documentclass[11pt,unused_horror_option_flag]{article}` |
| **Package** | Extended allocation already in use | `\usepackage{etex}` on modern LaTeX |
| **Hyperref** | Bookmark token stripping | Math `$\sum$` and formatting inside `\section` headings |
| **Hyperref** | Duplicate destination | Identical `\hypertarget{dest}{...}` anchors |
| **Labels** | Duplicate / Multiply-defined label | Two identical `\label{horror:dup_label}` declarations |
| **Labels** | Inverted label | `\label{...}` placed before `\caption{...}` inside a float |
| **Labels** | Label in unnumbered math | `\label{...}` placed inside `equation*` or `align*` |
| **Cross-Refs** | Undefined reference | `\ref{missing}` and `\pageref{missing}` |
| **Citations** | Undefined citation | `\cite{missing_key}` |
| **BibTeX** | Missing required fields | Entries missing `author`, `title`, `year`, `publisher` in `.bib` |
| **BibTeX** | Missing database entries | Citations referring to keys omitted from `.bib` |
| **Fonts** | Undefined font shape / substitution | Requesting Sans-serif Small Caps (`\textsf{\textsc{...}}`) in Computer Modern |
| **Fonts** | Unavailable font combination | Monospace Bold Slanted (`\texttt{\textbf{\textsl{...}}}`) |
| **Boxes** | Severe Overfull `\hbox` (≥24pt) | Massive monolithic `\mbox{...}` exceeding page margin |
| **Boxes** | Moderate Overfull `\hbox` | Paragraph protrusion of ~22pt |
| **Boxes** | Micro Overfull `\hbox` (≤2.5pt) | Sub-2.5pt margin protrusion |
| **Boxes** | Underfull `\hbox` (badness 10000) | Short line forced with trailing `\linebreak` |
| **Boxes** | Underfull `\vbox` (badness 10000) | Rigid `\vbox to 4.5in` with no stretchable vertical glue |
| **Boxes** | Overfull `\vbox` | Rigid `\vbox to 12pt` with multi-line `\Huge` content |
| **Floats** | Float specifier auto-adjusted | Figure requesting strict `[!h]` forced to `[!ht]` |
| **Floats** | Float too large for page | Figure with height `1.2\textheight` exceeding printable area |
| **Layout** | Marginpar moved | Colliding `\marginpar` calls on the same line |

## Testing

```bash
# View all alerts and warnings
l -a examples/horror/horror.tex

# View with 2 lines of surrounding source context (-2)
l -a -2 examples/horror/horror.tex

# View with diagnostic explanations (-x)
l -a -x examples/horror/horror.tex
```
