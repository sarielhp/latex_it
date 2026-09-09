# Agent Instructions for Maintaining `latex_it`

This document provides architectural guidelines, core invariants, development workflows, and acceleration instructions for AI agents and maintainers working in the [latex_it](file:///home/sariel/prog/26/latex_it/latex_it) repository.

---

## 1. Core Architecture & Repository Layout

- **Primary Executable**: [latex_it](file:///home/sariel/prog/26/latex_it/latex_it)
  - Standalone, high-performance Ruby executable (`#!/usr/bin/env ruby`).
  - Supports symlink personalities (`l`, `lw`, `ll`, `llua`, `latex_clean`, `latex_file_in_dir`, `latex_env_free`).
- **Core Modules & Classes**:
  - [`LaTeXUtils`](file:///home/sariel/prog/26/latex_it/latex_it#L56-L306): Engine detection & validation, main file discovery heuristics, TeX environment sanitization, noise filtering, and directory cleanup.
  - [`LatexBuilder`](file:///home/sariel/prog/26/latex_it/latex_it#L308-L1166): Compilation lifecycle manager, pass scheduler, `junk/` directory isolation, bibliography handling, lockfile protection, and diagnostic log analysis.
  - **CLI Dispatcher** ([lines 1172–1345](file:///home/sariel/prog/26/latex_it/latex_it#L1172-L1345)): Symlink personality detection and option parsing with `OptionParser`.
- **Workflow & Quality Tooling** (`tools/` / `tool/`):
  - [`tools/gate`](file:///home/sariel/prog/26/latex_it/tools/gate): Sub-second (< 1s) quality gate verifying syntax and test suites.
  - [`tools/setup_ruby_dev`](file:///home/sariel/prog/26/latex_it/tools/setup_ruby_dev): Automated environment auditor and installer for Ruby gems, LSPs, and CLI tools.
  - [`tools/install`](file:///home/sariel/prog/26/latex_it/tools/install) (aliased as `tool/install`): Installs `latex_it` to `~/bin/latex_it` and configures `~/bin/l` symlink.
  - [`tools/bump`](file:///home/sariel/prog/26/latex_it/tools/bump) (aliased as `tool/bump`): Validates 100% clean git working tree, runs `tools/gate`, increments version by +0.1.0 in [`VERSION`](file:///home/sariel/prog/26/latex_it/VERSION) and `latex_it`, commits, tags, and pushes to remote.
- **Automated Test Suite** (`test/`):
  - `test/test_*.rb`: Fast regression and end-to-end tests using `minitest`.
- **Documentation & Configuration**:
  - [`VERSION`](file:///home/sariel/prog/26/latex_it/VERSION): Plaintext file tracking the canonical project version.
  - [README.md](file:///home/sariel/prog/26/latex_it/README.md): User-facing feature reference, options, and architecture guide.
  - [AGENTS.md](file:///home/sariel/prog/26/latex_it/AGENTS.md): Machine-readable contract and developer guidelines for AI agents.

---

## 2. Invariants & Strict Rules

- **Method Length — Hard Limit 80 Lines**:
  No Ruby method may exceed **80 lines**. Function length is a correctness metric. Decompose long methods in-place into private helpers before moving modules.
- **File Sizing Guidelines**:
  Keep methods concise and maintain modular files in the **300–700 line** range (soft warning at 800 lines, hard limit 1100 lines). Never split a file across a method body.
- **Language Policy**:
  All scripts, tooling, and test runners must be written in idiomatic **Ruby** (`#!/usr/bin/env ruby`). Do not introduce Python, Bash, Sed, or Awk scripts.
- **Canonical Interface & Anti-Alias Bloat**:
  Maintain a minimal, well-documented CLI hierarchy. Do not add undocumented switches or unadvertised legacy aliases without updating [README.md](file:///home/sariel/prog/26/latex_it/README.md).
- **Isolated Build Output (`junk/`)**:
  All intermediate build artifacts must remain confined to `junk/`. Only final targets (`<file>.pdf`, `<file>.bbl`, `<file>.synctex.gz`) are exported to the project root. Cache preservation happens exclusively via `junk/old/`.
- **Modern Engine Guard**:
  Modern UTF-8 engines (`xelatex` as default, `lualatex` as supported alternative). `pdflatex` must be rejected with an explicit deprecation message.
- **Dependency Minimalism**:
  Rely on Ruby standard library modules (`fileutils`, `open3`, `optparse`, `tmpdir`, `shellwords`) and minimal mature gems (`rainbow`, `minitest`).

---

## 3. The `latex_it` Execution Contract

Any modifications to compilation logic must honor the following invariants:

1. **Intelligent Convergence Pass Model**:
   - **Default**: Tracks source dependencies via `-recorder` (`.fls`) and SHA256 build state. Exits in 0 passes if targets are up to date; runs 1 pass if citations/labels are stable; runs pre-primary BibTeX/Biber if `.bib` changed; and only executes extra passes (up to `-n`, default 3) when `.aux` changes or rerun is requested in logs.
   - **Fast Incremental (`--fast` / `lw`)**: Aliased to reuse build state cache and avoid redundant recompilations.
   - **Single Pass (`-u` / `--single-pass`)**: Executes exactly 1 LaTeX pass with bibliography passes disabled (forces rebuild when targets are up to date).
2. **Bibliography Safety**:
   - Detect tool automatically: Biber (via `.bcf` / `.run.xml`) or BibTeX (via `\bibdata` and `\citation` in `.aux`).
   - Root `.bbl` is only overwritten if the generated `junk/*.bbl` contains valid bibliography entries (`\bibitem` or `\entry`).
   - `.bbl.bak` is preserved during updates.
3. **PDF Text Diffing (`-d` / `--diff`)**:
   - When `--diff` is active and `pdftotext` is available, skip replacing the target PDF if the extracted text layout matches the existing PDF.

---

## 4. Development Workflow & Automated Tooling

Always execute quality workflows through the provided scripts:

### 1. `tools/gate` (Fast Quality Gate)
- Sub-second check (< 1s) validating:
  1. Ruby syntax (`ruby -cw`) across `latex_it`, `tools/`, and `test/`.
  2. Automated Minitest regression test suite (`test/test_*.rb`).
- **Trigger**: Run continuously after every edit or refactoring step.
  ```bash
  rtk ./tools/gate
  ```

### 2. `tools/setup_ruby_dev` (Environment & Tooling Auditor)
- Audits and provisions local gems and system binaries.
- **Audit mode**:
  ```bash
  ./tools/setup_ruby_dev --check-only
  ```
- **Auto-install mode**:
  ```bash
  ./tools/setup_ruby_dev
  ```

### 3. Static Analysis & Linting
- Verify code style and syntax offenses:
  ```bash
  rtk rubocop latex_it tools/ test/
  ```
- Automatically correct safe offenses:
  ```bash
  rtk rubocop -A latex_it tools/ test/
  ```

### 4. `tools/install` (Local Binary Installation)
- Copies `latex_it` to `~/bin/latex_it` (setting permissions to `0755`).
- Creates symbolic link `~/bin/l -> latex_it`.
- **Trigger**:
  ```bash
  ./tools/install
  # Or via symlink:
  ./tool/install
  ```

### 5. `tools/bump` (Version Bump, Tag & Push Workflow)
- Ensures working tree is completely clean (aborts if uncommitted changes exist).
- Runs [`tools/gate`](file:///home/sariel/prog/26/latex_it/tools/gate).
- Increments version by +0.1.0 in [`VERSION`](file:///home/sariel/prog/26/latex_it/VERSION) and `latex_it`.
- Commits changes, creates a release git tag, and pushes to remote with `--follow-tags`.
- **Trigger**:
  ```bash
  ./tools/bump
  # Or via symlink:
  ./tool/bump
  ```

---

## 5. Pre-Installed Tooling & Acceleration

The following developer tools are pre-configured in the environment:

| Tool | Location / Command | Purpose for AI Agents |
| :--- | :--- | :--- |
| **`rtk`** | `/home/sariel/.cargo/bin/rtk` | **CLI output token compression proxy.** Prefix all shell commands with `rtk` (e.g. `rtk rubocop`, `rtk git status`) to compress terminal output by 60–90%. |
| **`ast-grep` (`sg`)** | `/home/sariel/.local/bin/sg` | **Structural AST search & rewrite.** Use `rtk sg -p '<pattern>' -l ruby` instead of fragile regex searches. |
| **`rubocop`** | `~/.local/share/gem/ruby/3.3.0/bin/rubocop` | **Static analysis & formatting.** Lint and auto-correct Ruby code. |
| **`ruby-lsp`** | `~/.local/share/gem/ruby/3.3.0/bin/ruby-lsp` | **Shopify Language Server.** Fast symbol navigation, definitions, and code intelligence. |
| **`repomix`** | `/home/sariel/.local/bin/repomix` | **Repository context packer.** Generates token-optimized codebase snapshots for LLM prompts. |
| **`pdftotext`** | `/usr/bin/pdftotext` | **Poppler PDF text extractor.** Enables text diff verification in `latex_it -d`. |
| **`minitest`** | Ruby gem | **Unit test runner.** Powers `tools/gate` and `test/test_*.rb`. |
| **`rainbow`** | Ruby gem | **Colorized diagnostics.** ANSI color rendering in terminal output. |

---

## 6. Adversarial Audit Lenses

When reviewing, refactoring, or evaluating changes to `latex_it`, evaluate across these 5 domain lenses:

1. **Systems & Concurrency**:
   - File locking (`--lock` with `flock`) must prevent race conditions without deadlocking.
   - Child process execution via `Open3.capture2e` must handle process exit statuses and signal termination gracefully.
2. **Correctness & Heuristics**:
   - Main file heuristic detection must accurately resolve `.mainfile`, directory name matching, and candidate filtering without false positives.
   - Auxiliary file hashing (`compute_aux_hash`) must accurately reflect all `.aux` changes across subdirectories.
3. **Resilience & Fault Tolerance**:
   - Missing compilers (`xelatex`, `biber`, `bibtex`) or system tools must fail fast with actionable error messages.
   - Subprocess noise (METAFONT, `mktextfm`) must be filtered cleanly without suppressing underlying TeX errors.
4. **Performance & Incremental Efficiency**:
   - Fast mode (`--fast`) must avoid redundant LaTeX and bibliography passes whenever cache is valid.
   - Text diff checking (`-d`) must avoid disk writes and unnecessary PDF viewer reloads when content is identical.
5. **CLI Consistency & User Experience**:
   - Clean, readable `-h` help text.
   - Colorized diagnostic outputs with fallback to plain text if `rainbow` is absent or `--emacs` is supplied.

---

## 7. Agent Batching & Efficiency Guidelines

- **Autonomous Batching**:
  Combine code edits, test updates, and quality gate verification (`tools/gate`) within a single agent turn instead of requesting piecemeal confirmations.
- **Fast Feedback**:
  Execute `rtk ./tools/gate` for sub-second verification after making modifications.
- **Token Efficiency**:
  Always prefix shell commands with `rtk` (e.g. `rtk ./tools/gate`, `rtk rubocop`, `rtk ls`).
- **AST Pattern Refactoring**:
  Use `ast-grep` (`sg`) to inspect or transform method signatures and patterns:
  ```bash
  rtk sg -p 'def $NAME($$$ARGS) $$$BODY end' -l ruby latex_it
  ```
