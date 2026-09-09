# latex_it (Unified LaTeX Builder)

`latex_it` (commonly symlinked as `l` or `lw`) is a high-performance, robust Ruby-based wrapper and build manager for modern LaTeX workflows (`xelatex` and `lualatex`). It simplifies LaTeX document compilation by providing clean directory management, automatic main file detection, intelligent multi-pass scheduling, smart bibliography tooling (Biber/BibTeX), PDF diffing, and structured diagnostic error/warning analysis.

---

## Key Features

### 1. Isolated Build Directory (`junk/`)
- All intermediate build artifacts (`.aux`, `.log`, `.out`, `.toc`, `.fls`, `.bcf`, etc.) are written directly into an isolated `junk/` directory using LaTeX's `-output-directory=junk` option.
- Keeps your working directory clean: only final output targets (`<document>.pdf`, `<document>.bbl`, and `<document>.synctex.gz`) are copied back to the document root upon completion.
- Preserves compilation cache between runs in `junk/old/`, copying previous `.aux`, `.bbl`, and `.out` files forward to ensure references and outlines remain stable across incremental builds.

### 2. Automatic Main File Detection
If no target `.tex` file is explicitly passed, `latex_it` discovers the main document automatically:
1. **`.mainfile`**: Reads the file name specified inside a `.mainfile` file if present.
2. **Directory Filtering**: Scans directory `*.tex` files and excludes preamble/prefix snippets (`*.num.tex`, `prefix*.tex`, `prelim*.tex`, `preamble*.tex`, `pratenddefaultcategory.tex`, `flycheck_*.tex`, editor backups, and hidden files).
3. **Directory Name Match**: Checks if `<directory_name>.tex` exists.
4. **Document Marker Inspection**: Checks candidate files for `\begin{document}` or `\documentclass`.
5. **Existing Output Match**: Checks if a matching `<name>.pdf` or `junk/<name>.pdf` exists.

### 3. Modern Engine First (XeLaTeX & LuaLaTeX)
- Default engine is **`xelatex`**.
- Full support for **`lualatex`** via CLI flag or automatic detection.
- **`pdflatex` is rejected by default**: Rejects compilation with an explanatory notice recommending modern UTF-8 capable engines.
- **Engine Auto-Detection**:
  - TeX magic comments: `% !TEX TS-program = <engine>` or `% !TEX program = <engine>`
  - AUCTeX / Emacs file local variables: `TeX-engine: <engine>`
  - LuaTeX packages: usage of `\usepackage{luacode}`, `\usepackage{luamplib}`, `\usepackage{luatex85}`, or `\directlua` automatically selects `lualatex`.

### 4. Bibliography Automation (BibTeX & Biber)
- Automatically detects whether the project uses **Biber** (via `.bcf` citekeys or `run.xml` declarations) or **BibTeX** (via `\bibdata` and `\citation` in `.aux`).
- Copies local `.bib` files and style dependencies (`styles/`) into `junk/` before invocation.
- Validates `.bbl` output: preserves `.bbl.bak` backups and only updates root `.bbl` if entries (`\bibitem` or `\entry`) were generated.

### 5. Intelligent Convergence & Compilation Modes
- **Intelligent Pass Model (Default)**:
  Dynamically tracks source dependencies (via `-recorder` / `.fls`) and checksums to eliminate redundant compiler passes:
  - **Zero Passes**: If all source files are unchanged and targets are up to date, exits immediately in milliseconds (`All targets are up-to-date. (Use 'l -u' to force rebuild)`).
  - **1 Pass**: For simple documents or edits that do not alter cross-references or citations.
  - **Pre-primary Bibliography**: Runs BibTeX/Biber before LaTeX if only `.bib` changed, updating the document in a single LaTeX pass.
  - **2–3 Passes**: Only executed when `.aux` changes, new citations are introduced, or rerun requests appear in compiler logs.
- **Single-Pass Mode (`-u` / `--single-pass` / `--quick`)**:
  Forces exactly one LaTeX pass without bibliography or extra iterations (also useful to force a rebuild).
- **Fast Incremental Mode (`--fast` / `lw`)**:
  Explicit alias ensuring incremental caching behavior.

### 6. PDF Text Diff Protection (`-d` / `--diff`)
- When enabled, runs `pdftotext -layout` to compare newly compiled PDF text against the existing target PDF.
- Skips overwriting the target PDF if text content is unchanged, preventing unnecessary PDF viewer redraws and timestamp changes.

### 7. Diagnostics, Error & Warning Parsing
- Strips low-level TeX font-generation noise (such as `mktextfm`, `mktexpk`, METAFONT errors).
- Aggregates and colorizes syntax errors, undefined control sequences, missing citations, broken references, and multiply defined labels.
- Groups and deduplicates `Overfull \hbox` and `Underfull \vbox` warnings per line, reporting the worst-case badness/pt dimension.
- Provides `--emacs` flag for AUCTeX-compatible log format.
- Provides `-s` / `--score` mode for quiet status reporting (`Errors: X, Warnings: Y`).

### 8. Environment & Configuration Controls
- **Unified JSONC Configuration**:
  - Global configuration at `~/.config/latex_it/config.jsonc` (auto-generated on first run with fully documented defaults).
  - Per-project overrides at `.l.jsonc` (or `.latex_it.jsonc`). Initialize a local template via `l --init-config`.
  - Strict precedence: `CLI Flags > Local (.l.jsonc) > Global (~/.config/latex_it/config.jsonc) > Defaults`.
  - Legacy `.config_latex` supported as fallback.
- Supports custom macro injections via `LATEXOPTS` or `LATEXOPTIONS`.
- Provides `--no-env` (`--env-free`) to sanitize TeX-related environment variables (`TEXINPUTS`, `BIBINPUTS`, etc.) to prevent environment pollution.
- Supports concurrency control with file locking (`--lock`).

### 9. Portable Paper Archive & Verification (`-z` and `-t`)
- **Portable Zip Bundling (`-z` / `--zip`)**:
  - Generates self-contained `<document>.zip` bundling the paper, compiled target PDF, and compiled `.bbl`.
  - Harvests active style and package dependencies from the compiler recorder (`.fls`), ignoring system TeX Live packages.
  - Automatically discovers original figure sources (`.fig`, `.ipe`, `.svg`, `.asy`, `.gp`, `.gnuplot`, `.py`, `.R`) matching compiled figure stems, stripped view/page suffixes (`diagram_1.pdf` -> `diagram.ipe`), and companion `*.isy` stylesheets. Excludes backup files (`*.bak`, `figs/bak/`, `figs/old/`).
  - **Styles Organization (`inject_styles`)**:
    - Default (`false`): Harvested styles sit in the archive root for 100% universal journal/publisher compatibility without modifying `.tex` source code.
    - Opt-in (`true` via config or `--inject-styles`): Styles routed to `styles/` and `\def\input@path{{styles/}{./}}` is safely injected into the staged `.tex`.
  - **CLI Extra Assets (`-- <files...>)`**:
    - Pass arbitrary supplementary files or globs after `--` to bundle them directly (e.g. `l -z -- notes.txt code/*.py`).
- **Sandbox Portability Verification (`-t` / `--verify`)**:
  - Unpacks the zip in an isolated `/tmp` directory.
  - Runs `latex_it --env-free` with no ambient environment variables.
  - Compares the test build against the bundled PDF using `pdftotext -layout`.

### 10. Complete arXiv Submission Preparation (`--arxiv` and `--meta`)
- **Submission Packaging (`--arxiv`)**:
  - Automatically compiles and bundles a sanitized, self-contained `arxiv_<document>.zip` package ready for immediate upload to [arXiv.org](https://arxiv.org).
  - **Monolithic Flattening**: Inlines all subfiles referenced via `\input{...}` and `\include{...}` into a single unified `<document>.tex`.
  - **Sanitization**: Strips private `%` draft comments (preserving `\%`, TeX magic directives, and URLs) and removes private/machine-specific style imports.
  - **Active Figures Only**: Consults compiler recorder (`.fls`) to bundle only active `.pdf`/`.png` graphic files, strictly excluding raw figure sources (`.fig`, `.ipe`, `.svg`, etc.) and target PDF.
  - **BibLaTeX Version Shielding**: Detects `biblatex` and automatically bundles local distribution files (`biblatex.sty`, `biblatex.cfg`, `*.bbx`, `*.cbx`, `*.lbx`) to shield against arXiv's `wrong format version` compilation mismatch.
  - **Verification Sandbox**: Automatically extracts the archive to `/tmp` and compiles with `latex_it --env-free` to guarantee clean compilation on arXiv servers.
- **Metadata Extraction (`--meta`)**:
  - Extracts `Title`, `Authors`, and `Abstract` from source TeX and converts TeX math/formatting macros into clean, readable Unicode plaintext.
  - Automatically derives page count and figure count for submission comments.
  - Generates `arxiv_<document>_meta.txt` in the root and announces both files upon completion.

---

## Symlink Personalities

The script inspects `$PROGRAM_NAME` and changes default behavior based on the executable name:

| Executable Name | Description / Activated Behavior |
| :--- | :--- |
| `latex_it`, `l` | Default compilation mode (`xelatex`, 3 passes, auto-bib). |
| `lw` | Fast incremental mode (`--fast`). |
| `ll`, `llua`, `lualatex_l` | Sets engine to `lualatex`. |
| `lp`, `pdflatex_l`, `pdflatex` | Triggers pdflatex rejection check. |
| `latex_file_in_dir` | Prints detected main `.tex` file in directory and exits. |
| `latex_clean`, `clean_latex`, `latex-clean` | Cleans auxiliary and junk files in directory and exits. |
| `latex_env_free`, `bibtex_env_free`, `pdflatex_env_free` | Enables `--no-env` to reset TeX environment variables. |

---

## Command-Line Options

```text
Usage: l [options] [document.tex] [-- extra_files...]

Compilation Options:
    -m, --main, --find-main, --file  Print the detected main LaTeX file and exit
    -C, --clean-only                 Clean auxiliary and junk files in directory and exit without building
        --fast                       Fast incremental mode: reuse aux files and only run subsequent passes/biber/bibtex if needed
    -e, --engine ENGINE              LaTeX compiler: xelatex (default), lualatex
        --lua, --lualatex            Shortcut for --engine=lualatex
        --xe, --xelatex              Shortcut for --engine=xelatex (default)
        --pdf                        Generate PDF output (default behavior)
        --pdflatex                   Shortcut for --engine=pdflatex (rejected)
    -u, --single-pass, --quick       Perform a single LaTeX run only (no BibTeX/Biber, no extra passes)
    -d, --diff, --update-on-diff     Only replace target PDF if text content changed
    -c, --clean                      Clean temporary build files (junk/, .bbl, .aux) before building
    -b, --[no-]bib                   Force or skip BibTeX pass (default: auto-detect)
    -n, --passes NUM                 Number of compilation passes (1-3, default: 3)
    -T, --time                       Show execution time diagnostics per pass
    -t, --verify, --test             Verify self-contained portability of generated zip in /tmp sandbox
    -z, --zip                        Create self-contained portable zip archive of paper
        --zip-name NAME              Specify custom output name for zip archive
        --[no-]inject-styles         Enable/disable isolating styles into styles/ and injecting \input@path
        --init-config                Create a local .l.jsonc configuration template in the current directory
        --[no-]color                 Enable or disable colored terminal output (default: auto)
        --lock                       Enable lockfile concurrency protection
    -s, --score                      [-score] Suppress stdout and output error/warning count from the last LaTeX run
        --no-env, --env-free, --envfree
                                     [-no-env, -env-free] Reset environment variables used by LaTeX/BibTeX/Biber
        --emacs                      Format warnings/errors for Emacs AUCTeX integration (suppress line/W: prefixes)
    -v, --verbose                    Verbose output (e.g. show box text snippets)
    -W, --werror                     [-Werror] Treat compilation warnings as fatal errors and exit with non-zero code
    -M, --deps                       Print Makefile dependency rule for the document and exit

arXiv Preparation Options:
        --arxiv                      Prepare sanitized, flattened, submission-ready arXiv zip package
        --arxiv-name NAME            Specify custom output name for arXiv zip archive
        --meta                       Extract and display sanitized paper metadata and write arxiv_<file>_meta.txt
        --[no-]arxiv-verify          Enable/disable isolated /tmp sandbox verification pass for arXiv package
        --[no-]biblatex-shield       Enable/disable bundling local biblatex distribution files

    -V, --version                    Show version
    -h, --help                       Show this help message
```

---

## Code Architecture

The script [latex_it](file:///home/sariel/prog/26/latex_it/latex_it) is organized into three primary sections:

- [`LaTeXUtils`](file:///home/sariel/prog/26/latex_it/latex_it#L56-L306):
  Utility module containing helper methods for:
  - Engine normalization & validation ([`check_engine!`](file:///home/sariel/prog/26/latex_it/latex_it#L68-L75), [`normalize_engine`](file:///home/sariel/prog/26/latex_it/latex_it#L77-L93))
  - File inspection & magic comment parsing ([`detect_engine_from_file`](file:///home/sariel/prog/26/latex_it/latex_it#L95-L128))
  - Safe binary-safe file reading ([`safe_read`](file:///home/sariel/prog/26/latex_it/latex_it#L130-L136))
  - Output noise reduction ([`filter_subcommand_noise`](file:///home/sariel/prog/26/latex_it/latex_it#L138-L143))
  - Bibliography content verification ([`bbl_has_entries?`](file:///home/sariel/prog/26/latex_it/latex_it#L145-L150))
  - Binary executable checks in `$PATH` ([`command_available?`](file:///home/sariel/prog/26/latex_it/latex_it#L152-L157), [`check_program`](file:///home/sariel/prog/26/latex_it/latex_it#L159-L164))
  - Local configuration loading ([`load_config_latex`](file:///home/sariel/prog/26/latex_it/latex_it#L166-L185))
  - Main file heuristic detection ([`find_main_latex_file`](file:///home/sariel/prog/26/latex_it/latex_it#L187-L239))
  - Directory cleaning ([`clean_directory`](file:///home/sariel/prog/26/latex_it/latex_it#L241-L271))
  - Environment sanitization ([`reset_latex_environment!`](file:///home/sariel/prog/26/latex_it/latex_it#L273-L305))

- [`LatexBuilder`](file:///home/sariel/prog/26/latex_it/latex_it#L308-L1166):
  Main orchestrator class managing target builds:
  - Entry point and working directory context ([`run!`](file:///home/sariel/prog/26/latex_it/latex_it#L318-L338), [`compile_target`](file:///home/sariel/prog/26/latex_it/latex_it#L342-L421))
  - Concurrency locking via `flock` ([`with_lock`](file:///home/sariel/prog/26/latex_it/latex_it#L423-L434))
  - Build environment & compiler flag setup ([`setup_environment`](file:///home/sariel/prog/26/latex_it/latex_it#L436-L469))
  - Isolated `junk/` directory layout and cache management ([`junk_dir_create`](file:///home/sariel/prog/26/latex_it/latex_it#L470-L495))
  - Compilation execution via `Open3.capture2e` ([`run_latex_pass`](file:///home/sariel/prog/26/latex_it/latex_it#L517-L568))
  - Bibliography engine selection and execution ([`detect_bib_tool`](file:///home/sariel/prog/26/latex_it/latex_it#L570-L607), [`run_bib_pass`](file:///home/sariel/prog/26/latex_it/latex_it#L609-L651))
  - Change detection heuristics ([`needs_bib_pass?`](file:///home/sariel/prog/26/latex_it/latex_it#L658-L681), [`needs_latex_rerun?`](file:///home/sariel/prog/26/latex_it/latex_it#L683-L699), [`compute_aux_hash`](file:///home/sariel/prog/26/latex_it/latex_it#L653-L656))
  - PDF diff comparison and target artifact updating ([`update_target_file`](file:///home/sariel/prog/26/latex_it/latex_it#L998-L1012))
  - Diagnostics, warnings, and errors extraction ([`extract_warnings`](file:///home/sariel/prog/26/latex_it/latex_it#L745-L874), [`extract_errors`](file:///home/sariel/prog/26/latex_it/latex_it#L876-L930), [`report_errors`](file:///home/sariel/prog/26/latex_it/latex_it#L971-L996), [`analyze_output`](file:///home/sariel/prog/26/latex_it/latex_it#L1014-L1113))

- [`LatexPackager`](file:///home/sariel/prog/26/latex_it/latex_it):
  Portable paper archive generator (`-z`) and `/tmp` sandbox verifier (`-t`).

- [`LaTeXMetaExtractor`](file:///home/sariel/prog/26/latex_it/latex_it):
  Metadata parser for Title, Authors, and Abstract, converting TeX math and formatting into clean Unicode plaintext.

- [`LaTeXFlattener`](file:///home/sariel/prog/26/latex_it/latex_it):
  Recursive subfile inliner and comment sanitizer producing monolithic `<file>.tex`.

- [`LatexArxivPackager`](file:///home/sariel/prog/26/latex_it/latex_it):
  arXiv packaging manager (`--arxiv`), biblatex version shield collector, and isolated sandbox verifier.

- **CLI Dispatcher**:
  Executable name inspection, option parsing using `OptionParser`, color setup via Rainbow, and target dispatching.

---

## Requirements & Dependencies

- **Ruby**: 2.7+ (tested with Ruby 3.x).
- **TeX System**: TeX Live, MacTeX, or compatible distribution with `xelatex`, `lualatex`, `bibtex`, or `biber`.
- **Optional Tools**:
  - `pdftotext` (from `poppler-utils`) for diff-based updates (`-d`).
  - `rainbow` gem for colored terminal diagnostic output (automatic plain-text fallback included).

---

## Installation

To install `latex_it` directly to `~/bin/latex_it` and create the `~/bin/l` symlink:

```bash
./tools/install
# Or via symlink:
./tool/install
```

---

## Development Environment Setup

To verify or install all development and AI agent tooling (linter, LSP, AST search, token compression):

```bash
# Check existing tool status without installing
./tools/setup_ruby_dev --check-only

# Check and install any missing tools
./tools/setup_ruby_dev
```
