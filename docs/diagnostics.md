# Diagnostics & Error Handling

`latex_it` parses raw compiler logs from `xelatex`, `lualatex`, and `pdflatex` to present clean, categorized diagnostic messages. Instead of wading through hundreds of lines of TeX console output, errors and warnings are categorized into clear tiers with actionable remediation hints.

<p align="center">
  <a href="gallery.md"><img src="images/error_comparison.svg" alt="Error Diagnostics Comparison: latexmk vs latex_it" width="100%"></a><br>
  <em>See the <a href="gallery.md">Diagnostic Showcase Gallery</a> for more side-by-side comparisons on real errors.</em>
</p>

---

## 1. The 4-Tier Diagnostic Hierarchy

Diagnostics are organized into four severity levels:

```
┌────────────────────────────────────────────────────────┐
│  Errors     Compilation failures (syntax, missing file)│
│  Alerts     Structural flaws & large overfull hboxes   │
│  Warnings   Standard typesetting & citation warnings   │
│  Whatevers  Harmless noise (suppressed by default)     │
└────────────────────────────────────────────────────────┘
```

| Tier | Description | Examples | Default Behavior |
| :--- | :--- | :--- | :--- |
| **Errors** | Hard compilation failures that prevent PDF generation. | Syntax errors, undefined commands, runaway arguments, missing packages. | Highlighted in red; suppresses lower tiers so the root failure is immediately visible. |
| **Alerts** | Serious structural issues or major layout defects. | Multiply-defined labels, overfull `\hbox` $\ge 24\text{pt}$, inverted labels before captions. | Highlighted in yellow/bold; always displayed. |
| **Warnings** | Actionable layout and reference issues. | Overfull `\hbox` ($2.5\text{pt} < \text{pt} < 24\text{pt}$), underfull `\vbox`, undefined references, missing citations. | Displayed in normal output. Deduplicated per line. |
| **Whatevers** | Minor cosmetic noise with negligible visual impact. | Micro overfull `\hbox` ($\le 2.5\text{pt}$), hyperref bookmark token removals, font substitution notices. | Suppressed from output; total count reported in the summary line (`Whatevers: N (suppressed)`). |

---

## 2. Explanation Mode (`-e` / `--explain`)

Pass `-e` or `--explain` to print a boxed, plain-English explanation on the first occurrence of each diagnostic type:

```bash
l -e paper.tex
```

Example explanation box:

```text
┌─── [Why: Overfull \hbox] ──────────────────────────────────────────┐
│ Text on this line extends beyond the printable margin boundary.    │
│ Fix: Rephrase the line, add hyphenation hints (\-), or wrap in     │
│ \sloppy / \begin{sloppypar} if necessary.                          │
└────────────────────────────────────────────────────────────────────┘
```

Explanations appear at most once per error type to keep terminal output compact.

---

## 3. Threshold Configuration

You can customize the threshold boundaries between Whatevers, Warnings, and Alerts via CLI flags or `.l.jsonc`:

```bash
# Set overfull hbox alert threshold to 30pt
l --alert-hbox 30.0

# Set micro-overflow whatever threshold to 1.0pt
l --whatever-pt 1.0
```

In `.l.jsonc`:

```jsonc
{
  "alert_overfull_pt": 30.0,
  "whatever_pt": 1.0
}
```

To see all diagnostics without any filtering, use `-a` / `--all`:

```bash
l -a paper.tex
```

---

## 4. Proactive Semantic Checks

`latex_it` includes proactive checks that catch subtle bugs before or during compilation:

### Inverted `\label` Before `\caption`
In LaTeX floats (`figure`, `table`), placing `\label{...}` before `\caption{...}` causes the label to bind to the outer section counter instead of the figure number. `latex_it` flags inverted labels with an Alert.

### Type 3 (Bitmap) Font Detection
Journals and indexing services (ACM TAPS, IEEE PDF eXpress, arXiv) often reject PDFs containing Type 3 raster fonts. When `pdffonts` is available, `latex_it` checks the compiled PDF and reports the specific pages where Type 3 fonts appear.

### Pre-Flight Brace Auditing
The built-in brace checker (`LaTeXBraceChecker`) runs before LaTeX starts, catching unmatched `{`, `}`, and mismatched brackets like `{]` across environments without waiting for a full compiler run.

---

## 5. AUCTeX & Editor Integration

For Emacs / AUCTeX or editors parsing `-file-line-error` output directly:

```bash
# Emit AUCTeX-compatible error output
l --emacs paper.tex

# Output error/warning counts only (exit status reflects build success)
l -s paper.tex
```

---

## 6. Error Reference Catalog

For an in-depth catalog of 55 common LaTeX compilation errors, their root causes, and minimal reproducer examples:

- **[Master Error Index](errors/README.md)**: Catalog of 55 errors categorized by layer (TeX Primitive, LaTeX Kernel, Package).
- **Corpus Test Suite**: Run `tools/test_error_corpus` to verify all 55 reproducers against real LaTeX engines.
