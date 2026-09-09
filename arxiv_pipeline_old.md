# Analysis of Legacy arXiv Preparation Pipeline (`kitit arxiv`)

This document summarizes the architecture, workflow stages, external dependencies, and underlying concepts in `~/bin/private/tex/kitit arxiv` (and its predecessor `kitit_suffix_bash`).

---

## 1. Executive Summary & Purpose

The `kitit arxiv` command prepares a LaTeX project for submission to [arXiv.org](https://arxiv.org). Its primary goals are:
1. **Isolate only true dependencies**: Prevent leaking private drafts, scratch files, git history, or unused 100MB images.
2. **Comment & Style Sanitization**: Strip private comments (`% ...`) from LaTeX sources and local style files.
3. **Document Flattening**: Consolidate multiple sub-files (`\input`, `\include`) into a single standalone `.tex` file using `flatex`.
4. **BibLaTeX / Biber Compatibility**: Circumvent arXiv's version mismatch error (`wrong format version`) by bundling the local system's `biblatex` package files (`.sty`, `.bbx`, `.cbx`, `.lbx`) directly into the submission.

---

## 2. Tools Inventory & System Availability

All tools required by `kitit arxiv` were checked on the local machine. **All tools are installed and operational in `PATH`:**

| Tool | Resolved Path | Purpose in Pipeline | Status |
| :--- | :--- | :--- | :--- |
| **`pdflatex`** | `/usr/bin/pdflatex` | Initial dry-run pass with `max_print_line=10000` to discover loaded `.sty` files from `.log`. | Installed |
| **`latexpand`** | `/usr/bin/latexpand` | Strips comments from discovered local style files (`--empty-comments`). | Installed |
| **`latexmk`** | `/usr/bin/latexmk` | Builds the paper in a sanitized environment to generate fresh `.bbl` and `.deps`. | Installed |
| **`arxiv-collector`** | `/home/sariel/.local/bin/arxiv-collector` | Extracts runtime dependencies from `latexmk -deps`, strips comments, and bundles `biblatex` system files. | Installed |
| **`flatex`** | `/home/sariel/bin/flatex` (source in `/home/sariel/prog/misc/flatex/flatex.C`) | Inlines all `\input` and `\include` statements into a single flattened `.tex` file. | Installed |
| **`tar`** | `/usr/bin/tar` | Extracts the intermediate `arxiv.tar.gz` bundle produced by `arxiv-collector`. | Installed |
| **`zip` / `unzip`** | `/usr/bin/zip`, `/usr/bin/unzip` | Archives intermediate workspaces and packages the final submission `.zip`. | Installed |

*(Other utilities used by `kitit` for ancillary tasks — `gh`, `rsync`, `ssh`, `uuencode`, `ipescript`, `ipetoipe` — are also fully installed).*

---

## 3. Pipeline Architecture: Step-by-Step Flow

The pipeline operates across two temporary staging directories in `/tmp/sariel/kitit_arxiv/`:
- **Stage 1 (`sdir` = `latex/`)**: Dependency discovery, clean compile, and collection.
- **Stage 2 (`sdir_b` = `latex_2/`)**: Flattening, macro sanitization, and packaging.

```
Project Root
    │
    ├─► [Stage 0: Style Discovery]
    │     Run pdflatex (max_print_line=10000)
    │     Scan .log for papers/styles/*.sty
    │     latexpand --empty-comments -> styles/*.sty
    │
    ├─► [Stage 1: Clean Compilation & Collection]
    │     cmd_zip -> Unpack in /tmp/sariel/kitit_arxiv/latex/
    │     latexmk -f (cleared TEXINPUTS, BIBINPUTS)
    │     arxiv-collector main.tex -> arxiv.tar.gz
    │       • Tracks used figures/files
    │       • Strips comments from .tex files
    │       • Copies system biblatex package (.sty, .bbx, .cbx, .lbx)
    │       • Captures main.bbl
    │
    ├─► [Stage 2: Flattening & Sanitizing]
    │     Unpack arxiv.tar.gz in /tmp/sariel/kitit_arxiv/latex_2/
    │     flatex -b main.tex -> inlines \input into single .tex
    │     Strip flatex markers, empty comments, sariel_computer.sty
    │     Clean intermediate artifacts
    │
    └─► [Stage 3: Final Packaging]
          zip -r arxiv_<basename>_<date>_<host>.zip *
          Copy to ~/keep/ and ~/ftp/
```

### Stage 0: Style Discovery & Sanitization
1. Creates a local `styles/` folder.
2. Invokes `pdflatex` on the document with `max_print_line=10000` to prevent line-wrapping in the `.log` file.
3. Parses the log file using regex for style files originating from `sariel/papers/styles` or `./styles` (filtering out `sariel_colors.sty`).
4. For each detected `.sty` file, invokes `latexpand --empty-comments <file>` to sanitize comments and writes the clean version into `styles/`.

### Stage 1: Clean Compilation & `arxiv-collector`
1. Creates a full project zip using `kitit cmd_zip` and unpacks it into clean sandbox `sdir`.
2. Clears environment variables (`BIBINPUTS=''`, `BSTINPUTS=''`, `TEXINPUTS=''`) and executes `latexmk -f main.tex`.
3. Runs `arxiv-collector main.tex`:
   - `arxiv-collector` runs `latexmk -deps`.
   - Captures all input files used by LaTeX and strips inline `%` comments.
   - **The BibLaTeX Solution**: By default, `arxiv-collector` has `--include-package biblatex`. It locates every system BibLaTeX file loaded by the document (`biblatex.sty`, `biblatex.cfg`, style files like `standard.bbx`, `numeric.cbx`, language files `english.lbx`) and bundles them directly into the root of `arxiv.tar.gz`.
   - When arXiv compiles the uploaded package, TeX finds `biblatex.sty` in the submission root and uses it instead of arXiv's system version. This guarantees that `biblatex.sty` and your uploaded `.bbl` file have identical format versions.

### Stage 2: Flattening with `flatex`
1. Unpacks `arxiv.tar.gz` into second sandbox `sdir_b`.
2. Runs `clean_all_curr_dir` to strip `.bak`, `.ipe`, `.svg`, `.ps`, and stale build artifacts.
3. Invokes `flatex -b main.tex`:
   - `flatex` (authored by Sariel Har-Peled) recursively parses `\input{...}` and `\include{...}` statements and inlines them into a single monolithic `.flt` file.
   - The `-b` flag instructs `flatex` **not** to inline the bibliography, allowing the `.bbl` file to remain standalone.
4. Renames `<main>.flt` back to `<main>.tex`.
5. Filters out:
   - Empty comment lines (`^%$`).
   - Injected flatex header comments (`^% flatex`).
   - Mentions of internal machine-specific styles (`sariel_computer.sty`).
   - Trailing whitespace.

### Stage 3: Packaging & Archiving
1. Cleans leftover auxiliary files.
2. Zips the contents into `arxiv_<basename>_<date>_<host>.zip`.
3. Stores backups in `~/keep/<destp>/` and exports to `~/ftp/<destp>/`.

---

## 4. Critical Bug Discovered in the Ruby Rewrite

A comparison between the original bash script (`kitit_suffix_bash`) and the Ruby version (`kitit`) revealed a critical regression:

- **Original Bash (`kitit_suffix_bash:880-883`)**:
  ```bash
  rm *.pdf >& /dev/null
  rm *.bib >& /dev/null
  rm prefix.tex prelim.tex >& /dev/null
  rm *.ps >& /dev/null
  ```
  *(Notice: `*.bbl` was **NOT** deleted; the `.bbl` produced by `arxiv-collector` was preserved in the final zip).*

- **Ruby Rewrite (`kitit:828`)**:
  ```ruby
  Dir.glob('*.{pdf,bib,bbl,ps}').each { |f| FileUtils.rm_f(f) }
  ```
  *(Notice: `*.bbl` **IS** explicitly deleted!)*

Because `*.bbl` is deleted and `flatex -b` did not inline the bibliography, any submission produced by the current Ruby script will arrive on arXiv **completely missing its `.bbl` file**, causing arXiv compilation to fail on the bibliography pass!

---

## 5. Key Architectural Insights for `latex_it`

The legacy pipeline solved real problems through a chain of 5 different tools (`pdflatex` $\rightarrow$ `latexpand` $\rightarrow$ `latexmk` $\rightarrow$ `arxiv-collector` $\rightarrow$ `flatex`).

`latex_it` already possesses the foundational mechanics to absorb these steps natively:
1. **Dynamic Recorder (`-recorder` / `.fls`)**: `latex_it` already captures the exact list of opened files. It does not need `latexmk -deps`.
2. **BibLaTeX Package Bundling**: When preparing an arXiv bundle, `latex_it` can identify that BibLaTeX was loaded and automatically copy the local `biblatex.sty`, `.bbx`, `.cbx`, and `.lbx` files into the bundle root.
3. **Sanitized Inlining**: Instead of juggling multiple temporary tarballs, `latex_it` can run `flatex` or an in-memory expander directly inside `junk/arxiv/`.
4. **Preserve `.bbl` & Exclude Targets**: Guarantee that `<basename>.bbl` is preserved while omitting `*.pdf` and `*.bib`.
