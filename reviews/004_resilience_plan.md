# Architecture & Resilience Remediation Plan: Review #004

**Review Document**: `reviews/004_resilience.md`  
**Date**: 2026-09-12  
**Target Subsystems**: `LatexBuilder` (`lib/latex_it/builder.rb`), `LatexArxivPackager` (`lib/latex_it/arxiv.rb`)

---

## 1. Executive Summary & Triage Overview

A comprehensive architectural audit of Systems Code Review Report #004 (`reviews/004_resilience.md`) was conducted across all 7 reported findings. Each finding was analyzed against repository invariants, architectural documentation (`docs/AGENTS.md`), and existing regression test suites.

### Triage Matrix

| Finding | Severity | Component | Finding Description | Triage Decision | Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **#1** | Major | `lib/latex_it/builder.rb:563-570` | Unhandled fatal crashes (signals) default exit status to 0 | **Genuine Defect** | When TeX crashes on a fatal signal (`SIGSEGV`, `SIGBUS`, etc.), `status.exitstatus` is `nil`. Defaulting to `0` misleads error handling into treating a fatal crash as success, suppressing error reporting. |
| **#2** | Major | `lib/latex_it/builder.rb:88-96, 455` | `setup_environment` wipes diagnostic logs before up-to-date check | **Genuine Defect** | Log artifacts (`err_<engine>`, `log.txt`, etc.) are unlinked before `targets_up_to_date?` executes. When a build is up-to-date and diagnostics (`-a`, `-e`, `--emacs`) are requested, cached logs have been destroyed, resulting in empty diagnostic reports. |
| **#3** | Major | `lib/latex_it/builder.rb:779-794` | Bibliography execution (`biber`/`bibtex`) lacks timeout protection | **Genuine Defect** | `execute_bibliography` invokes `Open3.capture2e` synchronously without timeout guards. A hanging Biber run (network data source hang, regex backtracking) permanently hangs `latex_it`. |
| **#4** | Major | `lib/latex_it/builder.rb:535-550` | Unclosed `stdin` pipe and missing process group isolation in `capture_pass_output` | **Genuine Defect** | An open `stdin` pipe prevents immediate EOF delivery when TeX halts on input prompts, causing unnecessary 180s hangs. Killing only `wait_thr.pid` fails to terminate auxiliary subprocesses (`xdvipdfmx`, `mktexpk`) spawned in child process groups. |
| **#5** | Major | `lib/latex_it/builder.rb:734-740` | Intermediate bibliography backup artifact (`.bbl.bak`) written to root | **False Positive (Intentional Behavior)** | `docs/AGENTS.md` explicitly specifies under *Bibliography Safety*: "Root `.bbl` is only overwritten if the generated `junk/*.bbl` contains valid bibliography entries... `.bbl.bak` is preserved during updates." Existing regression tests in `test/test_repair_failures.rb` enforce this. `paper.bbl` is a user root artifact; backing it up to `paper.bbl.bak` prevents user data loss. `lib/latex_it/utils.rb` includes `*.bbl.bak` in `JUNK_PATTERNS` for cleanup (`l -c`). |
| **#6** | Moderate | `lib/latex_it/arxiv.rb:181-184` | `stage_biblatex_shield` executes `kpsewhich` without checking availability or catching exceptions | **Genuine Defect** | Invoking `Open3.capture2('kpsewhich', ...)` on systems where `kpsewhich` is missing raises an unhandled `Errno::ENOENT`, crashing arXiv packaging with a stack trace. |
| **#7** | Moderate | `lib/latex_it/arxiv.rb:92-96` | `stage_arxiv_files` does not handle exceptions from `LaTeXFlattener.flatten` | **Genuine Defect** | When `LaTeXFlattener` detects cyclic input or encounters read failures, it raises `RuntimeError`. Unhandled in `stage_arxiv_files`, this crashes the process instead of failing cleanly with actionable user guidance. |

---

## 2. Technical Remediation Specifications

### Finding 1: Signal Termination & Status Detection in `run_latex_pass`
- **File**: `lib/latex_it/builder.rb`
- **Method**: `run_latex_pass(suffix)`
- **Design**:
  1. Define a robust `ProcessResultStatus = Struct.new(:exitstatus, :success?, :termsig, :signaled?)` for fallback and timeout statuses.
  2. In `run_latex_pass`, extract status using standard UNIX convention:
     ```ruby
     st = status.exitstatus || (status.respond_to?(:termsig) && status.termsig ? 128 + status.termsig : 1)
     ```
  3. Emit a explicit warning when killed by signal:
     ```ruby
     if status.respond_to?(:signaled?) && status.signaled?
       warn "\nLaTeX engine terminated by signal #{status.termsig} (fatal crash).\n"
     elsif st > 0
       puts "\nLaTeX process exited with status: #{st}\n"
     end
     ```
  4. Pass the non-zero `st` to `handle_pass_errors(st, lgx)`, ensuring `count_errors_in_log(st, lgx)` triggers error reporting even if the TeX engine emitted zero error lines before crashing.

### Finding 2: Deferred Log Artifact Cleanup
- **File**: `lib/latex_it/builder.rb`
- **Methods**: `setup_environment`, `execute_compile_pipeline`, `clean_pass_logs`
- **Design**:
  1. Remove `FileUtils.rm_f([@log, @loga, @biberr, @pdferr, "#{@pdferr}_1", "#{@pdferr}_2", "#{@pdferr}_3"])` from `setup_environment`.
  2. Introduce `clean_pass_logs` helper method.
  3. In `execute_compile_pipeline`, place `clean_pass_logs` immediately after `targets_up_to_date?` check and before `junk_dir_create`.
  4. This preserves existing logs for inspection by `analyze_output if diagnostics_requested?` on cached builds.

### Finding 3 & 4: Subprocess Process Group Isolation, Immediate Stdin EOF & Bibliography Timeout
- **File**: `lib/latex_it/builder.rb`
- **Methods**: `capture_pass_output(cmd_args)`, `execute_bibliography(tool)`, `copy_style_files_for_bibtex`
- **Design**:
  1. In `capture_pass_output`:
     - Spawn child with `pgroup: true`.
     - Immediately invoke `stdin.close rescue nil` so interactive prompts receive EOF.
     - On timeout, retrieve process group ID via `Process.getpgid(wait_thr.pid)` and issue `Process.kill('-KILL', pgid)`, falling back to direct PID kill.
     - Re-raise `Errno::ENOENT` so tool availability checks / callers can handle missing binaries cleanly.
     - Return `ProcessResultStatus.new(124, false, nil, false)` on timeout.
  2. In `execute_bibliography(tool)`:
     - Route command execution through `capture_pass_output(cmd)` inside `Dir.chdir('junk')`.
     - Extract style file copying into `copy_style_files_for_bibtex` helper to maintain low cognitive complexity and concise method length.

### Finding 5: Rationale for Retaining Root `.bbl.bak`
- **File**: `lib/latex_it/builder.rb`
- **Status**: No code changes. Retain `preserve_bibliography_backup` writing `paper.bbl.bak` to project root and `junk/`.
- **Contract Enforcement**: Protects user root `.bbl` files as specified in `docs/AGENTS.md` and validated by `test/test_repair_failures.rb`.

### Finding 6: Guarded `kpsewhich` Resolution in `stage_biblatex_shield`
- **File**: `lib/latex_it/arxiv.rb`
- **Method**: `stage_biblatex_shield(stage_dir)`, `harvest_kpsewhich_core_files(harvested)`
- **Design**:
  1. Extract core file harvesting into `harvest_kpsewhich_core_files(harvested)`.
  2. Check `LaTeXUtils.command_available?('kpsewhich')` prior to execution.
  3. Wrap `Open3.capture2('kpsewhich', core)` in a `rescue SystemCallError` block to catch unexpected execution or path failures.

### Finding 7: Safe LaTeX Source Flattening in arXiv Packaging
- **File**: `lib/latex_it/arxiv.rb`
- **Methods**: `stage_arxiv_files(stage_dir)`, `do_package`
- **Design**:
  1. Wrap `LaTeXFlattener.flatten` in `stage_arxiv_files` with `begin ... rescue StandardError => e`.
  2. Warn with formatted failure message `[FAIL] Could not flatten LaTeX source: #{e.message}` and return `false`.
  3. In `do_package`, abort packaging cleanly: `return false unless stage_arxiv_files(stage_dir)`.

---

## 3. Code Metrics & Architectural Invariants

All modified and new methods must satisfy the repo's strict AST metrics enforced by `tools/gate_audit_code`:
- **Method Length**: $\le 80$ lines (or $\le 120$ lines if cognitive complexity $\le 5$)
- **Cognitive Complexity**: $\le 15$
- **Nesting Depth**: $\le 4$

Projected metrics for modified methods:
- `execute_compile_pipeline`: ~22 lines, depth 2, CC 5
- `setup_environment`: ~15 lines, depth 1, CC 1
- `clean_pass_logs`: ~3 lines, depth 0, CC 0
- `capture_pass_output`: ~26 lines, depth 2, CC 5
- `run_latex_pass`: ~25 lines, depth 1, CC 4
- `execute_bibliography`: ~15 lines, depth 2, CC 2
- `copy_style_files_for_bibtex`: ~5 lines, depth 2, CC 2
- `stage_arxiv_files`: ~16 lines, depth 1, CC 2
- `harvest_kpsewhich_core_files`: ~12 lines, depth 2, CC 4
- `stage_biblatex_shield`: ~18 lines, depth 2, CC 4

---

## 4. Test Strategy & Verification Plan

1. **Regression Unit Tests**:
   - `test/test_repair_failures.rb`:
     * Update `run_bib_pass` test mocks to stub `capture_pass_output` while validating `test_bibliography_replacement_and_previous_backup_for_both_tools` (Finding 5 invariant).
     * Add test for bibliography process timeout handling (Finding 3).
     * Add test for LaTeX pass termination by signal (Finding 1).
     * Add test for arXiv packaging failure when `LaTeXFlattener` raises cyclic dependency exception (Finding 7).
     * Add test for `stage_biblatex_shield` when `kpsewhich` is unavailable or raises `SystemCallError` (Finding 6).
   - `test/test_build_cache.rb`:
     * Add test verifying log artifacts are preserved and accessible by diagnostics when `targets_up_to_date?` is true (Finding 2).

2. **Quality Gate Verification**:
   - Run `tools/gate_audit_code` to ensure 100% compliance with line length, cognitive complexity, and nesting depth limits.
   - Run `tools/gate` (`--fast`) to verify all 19 test suites pass without regression.
