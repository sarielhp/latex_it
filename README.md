# latex_it

`latex_it` (often invoked via the shortcut `l`) is a command-line build tool for LaTeX documents. It manages compilation with `xelatex`, `lualatex`, or `pdflatex`, keeps your working directory free of temporary files, detects your main document automatically, and reports errors with clear, actionable hints.

---

## Quick Start

Run `l` inside any LaTeX project directory:

```bash
# Finds and compiles the main document automatically
l

# Or specify a file
l paper.tex
```

Common everyday commands:

```bash
lw          # Fast incremental rebuild (reuses cached state)
l -1        # Force a rebuild even if files haven't changed
l -C        # Clean auxiliary and temporary files
l -e        # Show plain-English explanations for errors and warnings
```

---

## Why use `latex_it`?

- **Clean directories**: All intermediate files (`.aux`, `.log`, `.out`, `.toc`, `.fls`, etc.) are kept in an isolated `junk/` directory. Only your final `.pdf`, `.bbl`, and `.synctex.gz` stay in the working directory.
- **Automatic detection**:
  - Finds your main `.tex` file if you don't specify one (checks `.mainfile`, folder name, and `\begin{document}`).
  - Selects the right engine (`xelatex`, `lualatex`, or `pdflatex`) from magic comments or loaded packages.
  - Detects whether your project uses Biber or BibTeX and runs them when citations change.
- **Fast builds**: Checks file modification times and checksums. If nothing changed, it exits immediately without rebuilding.
- **Clear diagnostics**: Categorizes compiler output into Errors, Alerts, and Warnings, filtering out low-level TeX engine noise. Adding `-e` shows plain-English suggestions on how to fix issues.
- **arXiv packaging**: Run `l --arxiv` to produce a flattened, comment-free zip archive ready for upload to arXiv (see [docs/arxiv.md](docs/arxiv.md)).

---

## Common Options

```text
Usage: l [options] [document.tex] [-- extra_files...]
```

| Option | Description |
| :--- | :--- |
| *(none)* | Build the document (auto-detects main file if omitted). |
| `--fast`, `lw` | Fast incremental mode; reuses previous state and skips unchanged passes. |
| `-1`, `--force` | Force initial LaTeX run, continuing only if needed for convergence. |
| `-u`, `--single-pass` | Run exactly one LaTeX pass without BibTeX or extra passes. |
| `-C`, `--clean-only` | Remove temporary build files and exit without compiling. |
| `-c`, `--clean` | Remove temporary build files before compiling. |
| `-e`, `--explain` | Show plain-English explanation boxes for errors and warnings. |
| `-a`, `--all` | Display all diagnostics, including suppressed minor warnings. |
| `-d`, `--diff` | Only update the target PDF if the text content actually changed. |
| `-m`, `--main` | Print the detected main LaTeX file and exit. |
| `--engine ENGINE` | Choose compiler: `xelatex` (default), `lualatex`, or `pdflatex`. |
| `-z`, `--zip` | Create a self-contained portable zip archive of the paper. |
| `--arxiv` | Prepare a sanitized, flattened zip package for arXiv submission. |
| `--init-config` | Generate a local `.l.jsonc` configuration template. |
| `-h`, `--help` | Show complete list of command-line options. |

---

## Symlink Shortcuts

The installer creates several convenient shortcuts based on the executable name:

| Command | Behavior |
| :--- | :--- |
| `l`, `latex_it` | Default build (`xelatex`, up to 3 passes, auto-bib). |
| `lw` | Fast incremental build (`--fast`). |
| `ll`, `llua` | Build using LuaLaTeX (`--engine=lualatex`). |
| `lp`, `pdflatex` | Build using pdfLaTeX (`--engine=pdflatex`). |
| `clean_latex`, `latex_clean` | Clean temporary files in current directory. |
| `latex_file_in_dir` | Print the detected main file in current directory. |

---

## Installation

Run the install script to copy `latex_it` to `~/bin/` and set up the `l` symlink:

```bash
./tools/install
```

Ensure `~/bin` is in your `PATH`.

### Requirements
- **Ruby**: 2.7 or newer.
- **TeX System**: TeX Live, MacTeX, or compatible distribution with `xelatex`, `lualatex`, or `pdflatex`.
- **Optional**: `poppler-utils` (provides `pdftotext` for PDF diffing and `pdftoppm` for visual verification).

---

## Documentation

For technical details, configuration options, and advanced features, see:

- **[docs/arxiv.md](docs/arxiv.md)**: arXiv submission packaging, flattening, comment stripping, and verification.
- **[docs/diagnostics.md](docs/diagnostics.md)**: Diagnostic tiers, error explanations, threshold settings, and semantic checks.
- **[docs/errors/README.md](docs/errors/README.md)**: Master catalog of 55 TeX/LaTeX errors with causes, solutions, and reproducers.
- **[docs/configuration.md](docs/configuration.md)**: Project configuration (`.l.jsonc`), global settings, and environment variables.
- **[docs/architecture.md](docs/architecture.md)**: Internal design, build lifecycle, and modular Ruby structure.
- **[docs/sandbox_testing.md](docs/sandbox_testing.md)**: Sandboxed testing (`bws_run`), portable paper bundles (`-z`), and REVTeX 4.0 support.
