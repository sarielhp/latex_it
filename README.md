# latex_it (Unified LaTeX Builder)

`latex_it` (commonly symlinked as `l` or `lw`) is a high-performance, robust Ruby-based wrapper and build manager for LaTeX workflows (`xelatex`, `lualatex`, and `pdflatex`). It simplifies LaTeX document compilation by providing clean directory management, automatic main file detection, intelligent multi-pass scheduling, smart bibliography tooling (Biber/BibTeX), PDF diffing, and structured diagnostic error/warning analysis.

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

### 3. Multiple LaTeX Engines (XeLaTeX, LuaLaTeX & pdfLaTeX)
- Default engine is **`xelatex`**.
- Full support for **`lualatex`** via CLI flag or automatic detection.
- Full support for **`pdflatex`** via CLI flag, configuration, or symlink personality.
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
  - **Zero Passes**: If all source files are unchanged and targets are up to date, exits immediately in milliseconds (`All targets are up-to-date. (Use 'l -1' to force rebuild)`).
  - **1 Pass**: For simple documents or edits that do not alter cross-references or citations.
  - **Pre-primary Bibliography**: Runs BibTeX/Biber before LaTeX if only `.bib` changed, updating the document in a single LaTeX pass.
  - **2–3 Passes**: Only executed when `.aux` changes, new citations are introduced, or rerun requests appear in compiler logs.
- **Force Mode (`-1` / `--force`)**:
  Bypasses the initial up-to-date check and forces the first LaTeX pass, continuing with subsequent passes and BibTeX only if needed for convergence.
- **Single-Pass Mode (`-u` / `--single-pass`)**:
  Executes exactly one LaTeX pass without bibliography or extra iterations (forces a single rebuild pass and exits immediately).
- **Fast Incremental Mode (`--fast` / `lw`)**:
  Explicit alias ensuring incremental caching behavior.

### 6. PDF Text Diff Protection (`-d` / `--diff`)
- When enabled, runs `pdftotext -layout` to compare newly compiled PDF text against the existing target PDF.
- Skips overwriting the target PDF if text content is unchanged, preventing unnecessary PDF viewer redraws and timestamp changes.

### 7. Diagnostics, Error & Warning Parsing
- Strips low-level TeX font-generation noise (such as `mktextfm`, `mktexpk`, METAFONT errors).
- **4-Tier Diagnostic Hierarchy (`Errors -> Alerts -> Warnings -> Whatevers`)**:
  - **Errors**: Fatal compilation failures (syntax errors, runaway arguments, process failure). Suppresses lower tiers on crash so only actionable errors are displayed.
  - **Alerts**: Document integrity flaws (multiply-defined labels) and wild overfull `\hbox` lines exceeding the alert threshold (default $\ge 24\text{pt}$, configurable via `--alert-hbox <pt>` or `"alert_overfull_pt"` in `.l.jsonc`).
  - **Warnings**: Actionable typesetting and layout issues ($2.5\text{pt} < \text{hbox} < 24\text{pt}$, underfull `\vbox`, undefined references/citations). Displayed by default alongside Alerts.
  - **Whatevers**: Harmless background noise (micro overfull `\hbox \le 2.5\text{pt}`, hyperref PDF bookmark token removals, float specifier changes, redundant summaries, font substitutions). Suppressed by default in terminal output, with count reported in the summary line (`Whatevers: W (suppressed)`).
- **First-Occurrence In-line Explanations (`-e` / `--explain`)**:
  - Displays a clean boxed callout with colored borders explaining **Why** LaTeX emitted the diagnostic and **Fix** recommendations.
  - Appears only on the first occurrence of each diagnostic category to keep terminal output readable.
- **Unsuppressed Mode (`-a` / `--all`)**:
  - Displays all diagnostics across all tiers (including Whatevers and any configured suppressed warnings).
- Groups and deduplicates `Overfull \hbox` and `Underfull \vbox` warnings per line, reporting the worst-case badness/pt dimension.
- **Proactive Semantic Alerts**:
  - **Inverted `\label` Before `\caption`**: Detects when `\label{...}` appears before `\caption` inside float environments (`figure`, `table`, etc.) or inside unnumbered math (`equation*`, `align*`), preventing silent cross-reference binding to the section counter instead of the float.
  - **Type 3 (Raster Bitmap) Font Detection**: Inspects the generated PDF via `pdffonts` for Type 3 fonts and identifies offending page numbers, preventing last-minute rejections by IEEE PDF eXpress, ACM TAPS, and arXiv.
- Provides `--emacs` flag for AUCTeX-compatible log format.
- Provides `-s` / `--score` mode for quiet status reporting (`Errors: X, Alerts: Y, Warnings: Z, Whatevers: W`).

### 8. Environment & Configuration Controls
- **Unified JSONC Configuration**:
  - Global configuration at `~/.config/latex_it/config.jsonc` (auto-generated on first run with fully documented defaults).
  - Per-project overrides at `.l.jsonc` (or `.latex_it.jsonc`). Initialize a local template via `l --init-config`.
  - Strict precedence: `CLI Flags > Local (.l.jsonc) > Global (~/.config/latex_it/config.jsonc) > Defaults`.
  - Legacy `.config_latex` supported as fallback.
- Supports custom macro injections via `LATEXOPTS` or `LATEXOPTIONS`.
- Provides `--no-env` to sanitize TeX-related environment variables (`TEXINPUTS`, `BIBINPUTS`, etc.) to prevent environment pollution.
- Automatic concurrency control with path-hashed lockfile protection (`--[no-]lock`, default: enabled).

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
  - Runs `latex_it --no-env` with an isolated HOME and TeX configuration tree.
  - Compares the test build against the bundled PDF using `pdftotext -layout` when available; otherwise reports that comparison was skipped.
  - Archive creation, extraction, compilation, and PDF comparison failures produce a nonzero exit status.

### 10. Complete arXiv Submission Preparation (`--arxiv` and `--meta`)
- **Submission Packaging (`--arxiv`)**:
  - Automatically compiles and bundles a sanitized, self-contained `arxiv_<document>.zip` package ready for immediate upload to [arXiv.org](https://arxiv.org).
  - **Monolithic Flattening**: Inlines all subfiles referenced via `\input{...}` and `\include{...}` into a single unified `<document>.tex`.
  - **Sanitization**: Strips private `%` draft comments (preserving `\%`, TeX magic directives, and URLs) and removes private/machine-specific style imports.
    Empty `%` markers retain TeX whitespace semantics. Repeated inputs remain repeated, input cycles are reported, and standard verbatim/listing environments and `\verb` examples are preserved literally.
  - **Active Figures Only**: Consults compiler recorder (`.fls`) to bundle only active `.pdf`/`.png` graphic files, strictly excluding raw figure sources (`.fig`, `.ipe`, `.svg`, etc.) and target PDF.
  - **BibLaTeX Version Shielding**: Detects `biblatex` and automatically bundles local distribution files (`biblatex.sty`, `biblatex.cfg`, `*.bbx`, `*.cbx`, `*.lbx`) to shield against arXiv's `wrong format version` compilation mismatch.
  - **Verification Sandbox**: Automatically extracts the archive to `/tmp`, compiles with the selected engine and `latex_it --no-env`, and requires exact `pdftotext -layout` equality with the fresh local build plus exact equality of every corresponding page rendered by `pdftoppm` at 150 DPI. Missing `pdftotext`/`pdftoppm`, failed extraction or rendering, missing PDFs, changed text layout, or changed rendered pages fail verification. Use `--no-arxiv-verify` to bypass all checks, or `--no-arxiv-visual-verify` to keep text-only verification. Visual verification requires the `pdftoppm` command from Poppler.
  - **Author Verification**: Extracts all author names from the original source and requires every name to appear on the rebuilt PDF's first page. Missing, malformed, or placeholder (`Unknown`/`Anonymous`) authors fail verification before visual comparison.
    Matching tolerates case, whitespace, punctuation, and normalized accents/umlauts. Small spelling differences produce edit-distance suggestions but still fail verification. This check also runs with `--no-arxiv-visual-verify`; only `--no-arxiv-verify` bypasses it.
- **Metadata Extraction (`--meta`)**:
  - Extracts `Title`, `Authors`, and `Abstract` from source TeX. The abstract is emitted in arXiv web-form format: ASCII-only, comment-free, with supported inline MathJax TeX preserved and paragraph breaks represented by arXiv's required indentation rule.
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
| `lp`, `pdflatex_l`, `pdflatex` | Sets engine to `pdflatex`. |
| `latex_file_in_dir` | Prints detected main `.tex` file in directory and exits. |
| `latex_clean`, `clean_latex`, `latex-clean` | Cleans auxiliary and junk files in directory and exits. |
| `latex_env_free`, `bibtex_env_free`, `pdflatex_env_free` | Enables `--no-env` to reset TeX environment variables. |

---

## Command-Line Options

```text
Usage: l [options] [document.tex] [-- extra_files...]

Compilation Options:
    -m, --main                       Print the detected main LaTeX file and exit
    -C, --clean-only                 Clean auxiliary and junk files in directory and exit without building
        --fast                       Fast incremental mode: reuse aux files and only run subsequent passes/biber/bibtex if needed
    -a, --all                        Show all diagnostics across all tiers (including Whatevers and Warnings)
    -e, --explain                    Display boxed plain-English explanations for diagnostics on first occurrence
        --engine ENGINE              LaTeX compiler: xelatex (default), lualatex, or pdflatex
        --lua                        Shortcut for --engine=lualatex
        --xe                         Shortcut for --engine=xelatex (default)
        --pdf                        Generate PDF output (default behavior)
        --pdflatex                   Shortcut for --engine=pdflatex
    -u, --single-pass                Perform a single LaTeX run only (no BibTeX/Biber, no extra passes)
    -1, --force                      Force initial LaTeX run, continuing with subsequent passes only if needed
    -d, --diff                       Only replace target PDF if text content changed
    -c, --clean                      Clean temporary build files (junk/, .bbl, .aux) before building
    -b, --[no-]bib                   Force or skip BibTeX pass (default: auto-detect)
    -n, --passes NUM                 Number of compilation passes (1-3, default: 3)
    -T, --time                       Show execution time diagnostics per pass
    -t, --verify                     Verify self-contained portability of generated zip in /tmp sandbox
    -z, --zip                        Create self-contained portable zip archive of paper
        --zip-name NAME              Specify custom output name for zip archive
        --[no-]inject-styles         Enable/disable isolating styles into styles/ and injecting \input@path
        --init-config                Create a local .l.jsonc configuration template in the current directory
        --[no-]color                 Enable or disable colored terminal output (default: auto)
        --[no-]lock                  Enable or disable lockfile concurrency protection (default: enabled)
    -s, --score                      Suppress stdout and output error/warning count from the last LaTeX run
        --no-env                     Reset environment variables used by LaTeX/BibTeX/Biber
        --emacs                      Format warnings/errors for Emacs AUCTeX integration (suppress line/W: prefixes)
    -v, --verbose                    Verbose output (e.g. show box text snippets)
    -W, --werror                     Treat compilation warnings as fatal errors and exit with non-zero code
    -M, --deps                       Print Makefile dependency rule for the document and exit
        --alert-hbox PT              Overfull hbox threshold in pt to classify as Alert (default: 24.0)
        --whatever-pt PT             Overfull hbox threshold in pt to classify as Whatever (default: 2.5)

arXiv Preparation Options:
        --arxiv                      Prepare sanitized, flattened, submission-ready arXiv zip package
        --arxiv-name NAME            Specify custom output name for arXiv zip archive
        --meta                       Extract and display sanitized paper metadata and write arxiv_<file>_meta.txt
        --[no-]arxiv-verify          Enable/disable sandbox compile plus exact PDF text verification
        --[no-]arxiv-visual-verify   Enable/disable rendered PDF page verification (requires pdftoppm)
        --[no-]biblatex-shield       Enable/disable bundling local biblatex distribution files

    -V, --version                    Show version
    -E, --examples                   Show detailed usage examples and common workflows
    -h, --help                       Show this help message
```

---

## Code Architecture

The script [`latex_it`](https://github.com/sarielhp/latex_it/blob/master/latex_it) is organized into modular classes:

- [`LaTeXConfig`](https://github.com/sarielhp/latex_it/blob/master/latex_it):
  Unified JSONC configuration loader (`.l.jsonc`, `~/.config/latex_it/config.jsonc`), auto-template creator, and quote-aware parser.

- [`LaTeXUtils`](https://github.com/sarielhp/latex_it/blob/master/latex_it):
  Utility module containing helper methods for:
  - Engine normalization (`normalize_engine`)
  - File inspection & magic comment parsing (`detect_engine_from_file`)
  - Safe binary-safe file reading (`safe_read`)
  - Output noise reduction (`filter_subcommand_noise`)
  - Bibliography content verification (`bbl_has_entries?`)
  - Binary executable checks in `$PATH` (`command_available?`, `check_program`)
  - Local configuration loading (`load_config_latex`)
  - Main file heuristic detection (`find_main_latex_file`)
  - Directory cleaning (`clean_directory`)
  - Environment sanitization (`reset_latex_environment!`)

- [`LaTeXBraceChecker`](https://github.com/sarielhp/latex_it/blob/master/latex_it):
  Lexical brace validator enforcing environment-scoped matching, `{]` mistype alert detection, and AUCTeX error message formatting.

- [`LatexBuilder`](https://github.com/sarielhp/latex_it/blob/master/latex_it):
  Main orchestrator class managing target builds:
  - Entry point and working directory context (`run!`, `compile_target`)
  - Concurrency locking via `flock` (`with_lock`)
  - Build environment & compiler flag setup (`setup_environment`)
  - Isolated `junk/` directory layout and cache management (`junk_dir_create`)
  - Compilation execution via `Open3.capture2e` (`run_latex_pass`)
  - Bibliography engine selection and execution (`detect_bib_tool`, `run_bib_pass`)
  - Change detection heuristics (`needs_bib_pass?`, `needs_latex_rerun?`, `compute_aux_hash`)
  - PDF diff comparison and target artifact updating (`update_target_file`)
  - Diagnostics, warnings, and errors extraction (`extract_warnings`, `extract_errors`, `report_errors`, `analyze_output`)

- [`LatexPackager`](https://github.com/sarielhp/latex_it/blob/master/latex_it):
  Portable paper archive generator (`-z`) and `/tmp` sandbox verifier (`-t`).

- [`LaTeXMetaExtractor`](https://github.com/sarielhp/latex_it/blob/master/latex_it):
  Metadata parser for Title, Authors, and Abstract, converting TeX math and formatting into clean Unicode plaintext.

- [`LaTeXFlattener`](https://github.com/sarielhp/latex_it/blob/master/latex_it):
  Recursive subfile inliner and comment sanitizer producing monolithic `<file>.tex`.

- [`LatexArxivPackager`](https://github.com/sarielhp/latex_it/blob/master/latex_it):
  arXiv packaging manager (`--arxiv`), biblatex version shield collector, and isolated sandbox verifier.

- **CLI Dispatcher**:
  Executable name inspection, option parsing using `OptionParser`, color setup via Rainbow, and target dispatching.

---

## Requirements & Dependencies

- **Ruby**: 2.7+ (tested with Ruby 3.x).
- **TeX System**: TeX Live, MacTeX, or compatible distribution with `xelatex`, `lualatex`, or `pdflatex`, plus `bibtex` or `biber` as needed.
- **Optional Tools**:
  - `pdftotext` (from `poppler-utils`) for diff-based updates (`-d`).
  - `pdftotext` and `pdftoppm` (from `poppler-utils`) are required by default for arXiv verification; use `--no-arxiv-visual-verify` for arXiv text-only verification when `pdftoppm` is unavailable.
  - `rainbow` gem for colored terminal diagnostic output (automatic plain-text fallback included).

---

## Sampling External Papers

To sample a random arXiv paper and retain its source archive (when available):

```bash
tools/sample_arxiv --output examples/arxiv --attempts 10
```

The sampler chooses a completed calendar month uniformly from April 2007 onward,
then a random paper in that month. This favors papers in quieter months; it is
not a uniform sample of all arXiv papers. Months exceeding 30,000 results are
skipped because of the API paging limit.

Each download goes into `examples/arxiv/<versioned-paper-id>/` by default, with
`source.tar.gz`, `source.tex.gz`, `source.tar`, or `source.tex` and `metadata.json`.
Metadata records the title, API abstract/summary, authors, categories, source URL, checksum, and sampled
month/offset. Existing samples are preserved, and the entire `examples/`
directory is ignored by Git. Use `--output DIR` to choose another location, `--attempts N` to bound
candidate attempts (default 10), or `--seed N` to repeat random choices while the
date range and API results remain unchanged. Monthly result counts are cached in
`~/.cache/latex_it/arxiv` by default; use `--cache-dir DIR` to choose another
location. Invalid cache entries are ignored and refreshed from arXiv. `--help`
lists these options.

Review a retained sample's arXiv metadata against the current TeX extractor:

```bash
tools/check_arxiv_metadata examples/arxiv/1510.00949v1
tools/check_arxiv_metadata examples/arxiv/1510.00949v1 --main paper.tex --pdf paper.pdf
```

The command reads the retained source in memory, verifies `metadata.json`'s
SHA256 checksum, detects a single main TeX member, and writes
`metadata-report.json`. Use `--main MEMBER.tex` for ambiguous archives.
`--pdf FILE` optionally checks expected arXiv author names on PDF page one with
`pdftotext`. Metadata mismatches are review findings and exit successfully;
malformed input, checksum errors, and extraction failures exit nonzero.
Raw values and normalized comparisons are retained, including missing/extra
authors, author order differences, and near-match suggestions. Near matches
remain mismatches. Only the selected main file is passed to the existing
extractor; included files and custom macros are not expanded. The report does
not compile or execute downloaded TeX. Its optional PDF check uses an existing
PDF and the independent arXiv author list.
The report also extracts the abstract and records a loose API-versus-TeX
comparison for review. Abstract differences are expected for some papers and
never fail the metadata check; an isolated generated abstract-page comparison
is not performed. The original Atom `<entry>` XML is retained in
`arxiv_entry_xml` so additional API fields remain available for later review.

The sampler retains source bytes without extracting or compiling them. It skips
missing or unrecognized TeX sources, limits downloads and decompressed data to
100 MiB each, and stops on HTTP service errors. Requests are sequential and spaced
at least three seconds apart; run only one sampler at a time. The download check
recognizes TeX files but does not establish whether a project compiles.

## Legacy REVTeX 4.0 support

`tools/install` installs a small LPPL-licensed REVTeX 4.0 compatibility tree in
`~/.local/share/latex_it/texmf`. It lets old papers using
`\documentclass{revtex4}` compile without changing their source tree. The files
are added only to compiler subprocesses and are copied into an arXiv archive when
they were used, keeping that archive self-contained. `bws_run` stages the same
tree inside its disposable workspace.

Compatibility is enabled by default. Configure it in `.l.jsonc` or the global
config file:

```jsonc
"revtex4": {
  "enabled": true,
  "texmf_dirs": ["~/.local/share/latex_it/texmf"]
}
```

Set `enabled` to `false` for a strict modern-only build. `texmf_dirs` can add
other local trees containing the same REVTeX 4.0 layout.

## Offline LaTeX builds with bws

`tools/bws_run` stages a source tree into a retained disposable workspace and
launches a command through the local `bws` executable. The generated local
profile ([profiles/bws-latex-write.json](profiles/bws-latex-write.json)) composes
`latex`, `offline`, and `no-ssh`. Existing TeX caches, the fontconfig cache, and
`~/.local/share/fonts` are writable, matching the installed LaTeX profile.
The original paper directory and repository are not mounted. `bws` reads an
empty global configuration from a temporary home; programs receive an empty
`XDG_CONFIG_HOME`, and your real `~/.config` and SSH files are not mounted.
Network, SSH forwarding, X11, D-Bus, and proxy access are disabled.

The copy excludes `.git` directories and worktree `.git` files at every depth,
`junk/`, and source-provided `.bws` configuration. Symlinks and special files
are rejected. Other source files, including local `latex_it` configuration
and supplied bibliography files, are preserved. Use an already extracted paper
directory; this runner does not unpack source archives.

Prepare and inspect the staged configuration without launching a sandbox:

```bash
tools/bws_run /path/to/paper --prepare-only
```

The command prints the retained workspace path. To build, pass a command and
its arguments after `--`:

```bash
tools/bws_run /path/to/paper -- latex_it paper.tex
tools/bws_run /path/to/paper --timeout 60 -- ruby -e 'puts Dir.pwd'
```

Use `--output DIR` to choose a new retained workspace outside the source tree
(default: a unique directory under `/tmp`). Existing output directories are
never overwritten. The runner stages this repository's `latex_it` on the
sandbox's `PATH`; other commands must be available inside the sandbox.
`--bws PATH` (or `BWS_BIN`) selects the host launcher, and `--latex-it PATH`
selects the executable to stage. With no command, the staged `latex_it` runs.

`--timeout SECONDS` defaults to 300 seconds and must be positive. On expiry,
the runner terminates the sandbox, escalates to killing remaining processes
after a two-second grace period, and exits with status 124. Otherwise it
returns the command's exit status. Command output is printed and saved in
`bws-run.log`; build files and logs remain available after success or failure.
The timeout covers sandbox execution, not copying the source tree.

## Installation

To install `latex_it` directly to `~/bin/latex_it` and create the `~/bin/l` symlink:

```bash
./tools/install
# Or via symlink:
./tool/install
```

---

For a complete disposable build audit of a retained sample, run:

```bash
tools/test_arxiv examples/arxiv/1510.00949v1
```

`tools/test_arxiv SAMPLE_DIR` preserves the downloaded snapshot and runs one
selected engine (default `xelatex`) through `bws_run`. It writes
`test-report.json`, `test-report.md`, and exactly one `PASS` or `FAIL` marker in
the original sample directory. The report covers fresh, no-op and `--fast` builds,
single-pass, PDF diff hash/mtime preservation, same-mtime source mutation, negative TeX and
recovery, metadata, portable zip verification, and strict arXiv text/visual/
author checks. Use `--main` for ambiguous archives, or `--engine`, `--bws`,
`--latex-it`, and `--timeout` (default 600 seconds). Partial timeout results,
environment or metadata failures, and retained `/tmp` artifacts are recorded.
The exit status is zero only for `PASS`; failures require review and do not
necessarily mean a `latex_it` bug. The worker uses a UTF-8 locale. The timeout
covers sandbox execution, not bounded source extraction and staging. Source
archives with links, unsafe paths, conflicting members or more than 100 MiB
compressed/expanded data are rejected. Plain and gzip-compressed TeX are also
accepted. No published arXiv PDF comparison or multi-engine matrix is performed.
`tools/arxiv_test_worker.rb` is an internal worker, not a public command.

To download a fresh random sample and test it in one step, run:

```bash
tools/arxiv_test_cycle --output examples/arxiv
```

The cycle records the directories present before downloading, runs
`tools/sample_arxiv`, identifies the one newly created paper directory, and
runs `tools/test_arxiv` on it. It exits zero only when the paper passes every
test, and reports failed checks and the retained test report otherwise. The
`--engine`, `--bws`, `--latex-it`, `--main`, and `--timeout` options are passed
to the tester; `--attempts` and `--seed` are passed to the downloader.

## Development Environment Setup

To verify or install all development and AI agent tooling (linter, LSP, AST search, token compression):

```bash
# Check existing tool status without installing
./tools/setup_ruby_dev --check-only

# Check and install any missing tools
./tools/setup_ruby_dev
```
