# LaTeX Command Datasets

This directory provides public reference datasets of standard and frequent LaTeX commands for use in linter dictionaries, typo-correction engines, editor completion, and corpus analysis.

## Datasets

### 1. Standard LaTeX Commands (`standard_latex_commands.txt`)

- **File**: [`standard_latex_commands.txt`](./standard_latex_commands.txt)
- **Total Commands**: 461
- **Description**: Consolidated, deduplicated list of standard and core LaTeX command identifiers.
- **Credits & Sources**:
  - [LaTeX Workshop](https://github.com/James-Yu/LaTeX-Workshop) by James Yu and contributors:
    - `data/packages/latex-document.json` (268 core document macros)
    - `data/commands.json` (300 primary formatting and structural commands)
  - [The LaTeX Project](https://www.latex-project.org/) LaTeX2e kernel specifications.

### 2. Top 500 Commands by Corpus Frequency (`corpus_top500_commands.txt`)

- **File**: [`corpus_top500_commands.txt`](./corpus_top500_commands.txt)
- **Total Commands**: 500
- **Corpus Size**: 29368 `.tex` research papers
- **Description**: Ranked frequency distribution of LaTeX commands extracted from an extensive real-world corpus of research papers in theoretical computer science, computational geometry, and discrete mathematics.
- **Privacy & Cleaning**:
  - Comments (`% ...`) stripped before parsing.
  - Filtered to remove all author name tokens matching `sariel` or `har-peled` (case-insensitive).

#### Top 25 Preview from Corpus

| Rank | Command | Occurrences | Note |
| :---: | :--- | :---: | :--- |
| 1 | `\item` | 1,602,464 | Layout & structure |
| 2 | `\end` | 870,684 | Layout & structure |
| 3 | `\begin` | 870,336 | Layout & structure |
| 4 | `\vspace` | 516,110 | Layout & structure |
| 5 | `\noindent` | 423,937 | Layout & structure |
| 6 | `\log` | 330,504 | Core math / logic |
| 7 | `\newcommand` | 291,873 | Layout & structure |
| 8 | `\hrule` | 282,130 | Layout & structure |
| 9 | `\in` | 255,427 | Core math / logic |
| 10 | `\bf` | 210,684 | Font emphasis |
| 11 | `\Graph` | 205,455 | Math symbol / macro |
| 12 | `\T` | 199,931 | Math symbol / macro |
| 13 | `\ldots` | 175,931 | Ellipsis |
| 14 | `\eps` | 169,720 | Math symbol / macro |
| 15 | `\leq` | 166,646 | Core math / logic |
| 16 | `\newpage` | 160,067 | Layout & structure |
| 17 | `\textwidth` | 159,639 | Layout & structure |
| 18 | `\G` | 113,885 | Math symbol / macro |
| 19 | `\bigstar` | 113,320 | Math symbol / macro |
| 20 | `\geq` | 110,352 | Core math / logic |
| 21 | `\pth` | 109,950 | Math symbol / macro |
| 22 | `\alpha` | 107,757 | Math symbol / macro |
| 23 | `\frac` | 107,028 | Core math / logic |
| 24 | `\vfil` | 88,195 | Math symbol / macro |
| 25 | `\penalty` | 87,568 | Math symbol / macro |
