# latex_it

<p align="center">
  <a href="https://sarielhp.github.io/latex_it/"><strong>Website & Documentation</strong></a> •
  <a href="https://github.com/sarielhp/latex_it"><strong>GitHub Repository</strong></a> •
  <a href="https://sarielhp.github.io/latex_it/docs/gallery.html"><strong>Diagnostic Gallery</strong></a>
</p>

`latex_it` (often invoked as `l`) is a standalone Ruby script and automated build tool for LaTeX documents (`xelatex`, `lualatex`, and `pdflatex`).

Like `latexmk`, it handles multi-pass compilation and bibliography dependencies automatically — but it is designed specifically to eliminate the two biggest headaches of LaTeX workflows:
1. **Cluttered directories**: Intermediate build files (`.aux`, `.log`, `.toc`, etc.) are isolated in a `junk/` directory, keeping your working tree clean.
2. **Cryptic output**: Low-level engine noise is filtered out, separating real errors and layout flaws from harmless background warnings and offering plain-English suggestions for fixes.

<p align="center">
  <a href="docs/gallery.html"><img src="docs/images/error_comparison.svg" alt="Error Diagnostics Comparison: latexmk vs latex_it" width="100%"></a><br>
  <em>Explore more real-world examples in the <a href="docs/gallery.html">Diagnostic Showcase Gallery</a>.</em>
</p>

---

## Installation

### Standalone Executable (Recommended)

Install the latest standalone binary directly into `~/bin/l` (no clone or build required):

```bash
mkdir -p ~/bin && curl -sSL https://github.com/sarielhp/latex_it/releases/latest/download/latex_it -o ~/bin/l && chmod +x ~/bin/l
```

*(Ensure `~/bin` is in your `$PATH`.)*

### From Source

```bash
git clone https://github.com/sarielhp/latex_it.git
cd latex_it
./tools/install
```

*(Installs to `~/bin/latex_it` along with all shortcut symlinks (`l`, `lw`, `ll`, `lp`, etc.). Ensure `~/bin` is in your `$PATH`.)*

### Requirements

- **Operating System**: **Linux** (primary target; macOS is supported/functional via Homebrew/MacTeX; Windows requires WSL).
- **Ruby**: 2.7 or newer.
- **TeX Distribution**: TeX Live, MacTeX, or compatible (`xelatex`, `lualatex`, or `pdflatex`).
- **Optional**: `poppler-utils` (provides `pdftotext` for `-d` / `--diff` text diffing; `brew install poppler` on macOS).

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
l -f        # Force a rebuild even if files haven't changed
l -r        # Print raw compiler output (debug mode)
l -C        # Clean auxiliary and temporary files
l -x        # Show plain-English explanations for errors and warnings
l -B        # Extract cited references into local .bib file
```

---

## Key Features

- **Zero-dependency standalone script**: Written in pure Ruby (`#!/usr/bin/env ruby`) using standard libraries. Distributed as a single self-contained executable with no gem compilation or virtualenv setup required.
- **Clean directories**: All intermediate files (`.aux`, `.log`, `.out`, `.toc`, `.fls`, etc.) are kept in `junk/`. Only your final `.pdf`, `.bbl`, and `.synctex.gz` stay in the working directory.
- **Automatic detection**:
  - Finds your main `.tex` file if omitted (checks `.mainfile`, folder name, and `\begin{document}`).
  - Selects the right engine (`xelatex`, `lualatex`, or `pdflatex`) from magic comments or loaded packages.
  - Automatically runs Biber or BibTeX when citations or `.bib` files change.
- **Fast incremental builds**: Tracks file checksums and exits immediately if nothing changed, avoiding redundant compiler passes.
- **Intelligent 4-tier diagnostics (Alerts & Whatevers)**: Standard LaTeX treats a $0.5\text{mm}$ line overflow with the same gravity as a broken citation, while silently producing a broken PDF when `\label` is placed before `\caption`. `latex_it` introduces two specialized tiers:
  - **Alerts**: Catches critical flaws that compile with exit code 0 but silently ruin published papers (e.g. inverted `\label` binding to the wrong section, or massive $\ge 24\text{pt}$ line spillages).
  - **Whatevers**: Suppresses harmless sub-millimeter cosmetic noise (like $\le 2.5\text{pt}$ micro-overflows and hyperref bookmark stripping) to cure warning fatigue, while counting them in the summary line (`l -a` to inspect).
  [Learn more about Alerts & Whatevers](docs/diagnostics.html#why-alerts-and-whatevers).
- **arXiv packaging**: Run `l --arxiv` to produce a flattened, comment-free zip archive ready for upload to arXiv (see [docs/arxiv.md](docs/arxiv.md)).

---

## Common CLI Options

| Flag | Description |
| :--- | :--- |
| *(none)* | Build the document (auto-detects main file if omitted). |
| `-f`, `--force` | Force initial LaTeX run, continuing only if needed for convergence. |
| `-u`, `--single-pass` | Run exactly one LaTeX pass without BibTeX or extra passes. |
| `-c`, `--clean` | Remove temporary build files before compiling. |
| `-C`, `--clean-only` | Remove temporary build files and exit without compiling. |
| `-x`, `--explain` | Show plain-English explanation boxes for errors and warnings. |
| `-a`, `--all` | Display all diagnostics, including suppressed minor warnings. |
| `--update-if-changed` | Only update the target PDF if the text content actually changed. |
| `-m`, `--main` | Print the detected main LaTeX file and exit. |
| `-e`, `--engine ENGINE` | Choose compiler: `x` (`xelatex`, default), `l` (`lualatex`), or `p` (`pdflatex`). |
| `-z`, `--zip` | Create a self-contained portable zip archive of the paper. |
| `-Z`, `--zip-flat` | Create a self-contained portable zip archive with inlined/flattened `.tex`. |
| `-B`, `--bib-extract` | Extract cited bibliography entries into local `.bib` file (default: `<doc>.bib`). |
| `--config-init` | Generate a local `.l.jsonc` configuration template. |
| `--config-show` | Show active configuration sources and resolved settings. |
| `--vscode-init` | Generate `.vscode/tasks.json` and `settings.json` for VS Code integration. |
| `--theme-list` | List available diagnostic color themes with terminal previews. |
| `-cc`, `--compile` | Format diagnostics in strict GNU standard (`file:line:col: severity: message`). |
| `-llm`, `--agent` | Token-optimized mode for AI agents (zero ANSI, folded warnings, silent on success). |
| `--json` | Output structured compilation and diagnostic results as JSON. |
| `-h`, `--help` | Show condensed help summary of everyday options. |
| `-H`, `--help-all` | Show complete list of command-line options with detailed explanations. |

---

## Symlink Shortcuts

The installer creates several convenient shortcuts based on the executable name:

| Command | Behavior |
| :--- | :--- |
| `l`, `latex_it` | Default build (`xelatex`, up to 3 passes, auto-bib). |
| `lw` | Same as `l`; kept for compatibility with existing symlinks. |
| `ll`, `llua` | Build using LuaLaTeX (`--engine=lualatex`). |
| `lp`, `pdflatex` | Build using pdfLaTeX (`--engine=pdflatex`). |
| `clean_latex`, `latex_clean` | Clean temporary files in current directory. |
| `latex_file_in_dir` | Print the detected main file in current directory. |

---

## Documentation

For technical details, configuration options, and advanced features, see:

- **[docs/llm_reference.md](docs/llm_reference.md)**: Token-optimized complete technical reference for AI agents and LLMs (flags, exit codes, config schema, error remedies).
- **[docs/vim.md](docs/vim.md)**: Vi, Vim, and Neovim Quickfix integration (`:make`), errorformat, and compiler plugin.
- **[docs/emacs.md](docs/emacs.md)**: GNU Emacs and AUCTeX error jumping, compilation buffer, and elisp configuration.
- **[docs/vscode.md](docs/vscode.md)**: Visual Studio Code native tasks (`Ctrl+Shift+B`), problem matcher, and LaTeX Workshop setup.
- **[docs/gallery.md](docs/gallery.md)**: Side-by-side diagnostic gallery comparing standard LaTeX/latexmk against latex_it on real errors.
- **[docs/troubleshooting_bibliography_errors.md](docs/troubleshooting_bibliography_errors.md)**: Diagnosing and solving cryptic `\printbibliography` crashes and pinpointing errors in `.bib` databases.
- **[docs/guides/underfull_boxes/README.md](docs/guides/underfull_boxes/README.md)**: Deep dive into diagnosing and fixing `Underfull \hbox (badness 10000)` and `Underfull \vbox` warnings with verified reproducers.
- **[docs/arxiv.md](docs/arxiv.md)**: arXiv submission packaging, flattening, comment stripping, and verification.
- **[docs/diagnostics.md](docs/diagnostics.html)**: The 4-tier diagnostic hierarchy (**Alerts** & **Whatevers** explained), error explanations (`-e`), and threshold tuning.
- **[docs/errors/README.md](docs/errors/README.md)**: Master catalog of 55 TeX/LaTeX errors with causes, solutions, and reproducers.
- **[docs/configuration.md](docs/configuration.md)**: Project configuration (`.l.jsonc`), global settings, and environment variables.
- **[docs/architecture.md](docs/architecture.md)**: Internal design, build lifecycle, and modular Ruby structure.
- **[docs/sandbox_testing.md](docs/sandbox_testing.md)**: Sandboxed testing (`bws_run`), portable paper bundles (`-z`), and REVTeX 4.0 support.

---

## Frequently Asked Questions (FAQ)

### Why a CLI flag (`l -llm`) instead of an MCP (Model Context Protocol) server?

1. **Token Economy**: Standard GNU compiler plaintext (`file:line: error: message`) takes ~75% fewer tokens than JSON-RPC envelopes or deeply nested structured JSON. LLMs are natively trained on trillions of tokens of compiler outputs and parse them effortlessly.
2. **Zero Configuration**: Autonomous coding agents (Claude Code, Cursor, Antigravity, OpenCode, Aider) already have terminal / shell tools. `l -llm` works immediately with zero configuration files, daemon setup, or background process management.
3. **Sandbox & Git Compatibility**: Agents frequently run inside isolated sandboxes (Bubblewrap `bws`, Docker containers, temporary worktrees). A CLI command runs directly inside the sandbox where files and compiler environments reside, whereas daemon-based MCP servers run outside and struggle with path mapping and permissions.
4. **Programmatic Support via `--json`**: For workflows that strictly require structured payloads, `latex_it --json` emits clean JSON on stdout, making it trivial to build a 20-line standalone MCP bridge without adding daemon bloat to `latex_it`.

### How should AI coding agents invoke `latex_it`?

AI agents should invoke:
```bash
l -llm paper.tex
```
- On clean builds or up-to-date targets, it exits `0` with **zero output**, consuming zero context window tokens.
- Output is pure plaintext: **zero ANSI color escape codes** and **zero OSC 8 terminal hyperlinks**.
- High-repetition warnings (e.g. 50 missing citations) are automatically folded into the first 2 instances plus a summary note, preventing context blowout.
- If unclassified compilation failures occur, the compiler log-tail is extracted automatically.

---

## Credits

Program, documentation and everything else really, were written using AI tools (mainly `antigravity-cli`).
