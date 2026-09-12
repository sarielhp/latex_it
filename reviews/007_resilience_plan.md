# Architectural Plan: Review #007 Remediation (Resilience Audit)

- **Date**: 2026-09-12
- **Audit Target**: `tools/arxiv_test_worker.rb`
- **Scope**: External process management, bounded execution, failure recovery, exception guarantees, report integrity, dependency validation.
- **Auditor Report**: `reviews/007_resilience.md`

---

## 1. Triage Summary & Defect Classification

| # | Severity | Location | Description | Classification | Rationale |
|---|---|---|---|---|---|
| **1** | Critical | `tools/arxiv_test_worker.rb:232-245` | Unbounded `Process.wait2` and inherited stdin in `command` | **Genuine Defect** | TeX prompts for interactive input upon errors to stdout and halts on inherited stdin. Without `in: File::NULL` and timeout enforcement (`wait_bounded`), worker hangs indefinitely. Without `pgroup: true` and process tree reaping (`reap`), child processes are orphaned. |
| **2** | Major | `tools/arxiv_test_worker.rb:119-138, 264-267` | Incomplete exception handling in `#check` and `#run`, unscrubbed UTF-8 reads | **Genuine Defect** | `#check` rescues only `StandardError`, allowing `ScriptError` (`LoadError`, `SyntaxError`) to escape. `#run` lacks top-level exception handling, leaving on-disk report frozen in `RUNNING`. Non-UTF-8 bytes in `.fls` or build logs cause unhandled `ArgumentError` crashes. |
| **3** | Major | `tools/arxiv_test_worker.rb:144-186` | Unsafe mutate/restore window in `#failure_recovery` and `#change_dependency` | **Genuine Defect** | `ensure` blocks do not execute when worker receives signals (`SIGTERM`, `SIGINT`, `SIGHUP`). Subprocess kills leave paper source permanently corrupted with probes. Needs signal traps, global restore registry (`@restores`), and marked probe comments. |
| **4** | Major | `tools/arxiv_test_worker.rb:62-68` | Broken engine dependency assertion when `@engine` is `nil` | **Genuine Defect** | When `@engine` is omitted (automatic mode), `[*@engine]` evaluates to `[]`, skipping engine presence in `missing`. Subsequent `executable(@engine || 'xelatex')` evaluates to `nil` on pdflatex/lualatex-only hosts, raising raw `TypeError` on `capture2e(nil, ...)` instead of an actionable error. |
| **5** | Major | `tools/arxiv_test_worker.rb:67-68` | Exit status ignored for engine and `latex_it` `--version` probes | **Genuine Defect** | `Open3.capture2e(...).first` discards exit status. Engine or `latex_it` staging crashes/backtraces on stderr are silently captured into version report fields, falsely passing `environment` check and confusing downstream diagnosis. |
| **6** | Moderate | `tools/arxiv_test_worker.rb:166-172` | Flawed negative test success predicate in `invalid_tex` | **Genuine Defect** | `result[:exit_status] != 0` treats signal deaths (`>= 128`, such as OOM `137`) and pre-compile wrapper failures as success. Fails to verify that the nonzero exit was a clean compiler rejection and that the failure was caused by the deliberate probe. |
| **7** | Moderate | `tools/arxiv_test_worker.rb:16-31, 286` | Unhandled initialization errors and missing top-level CLI error handler | **Genuine Defect** | Missing/malformed `test-config.json`, missing `'main'` key, or missing `latex_it` raise unhandled exceptions in `Runner#initialize` before any report file is created. CLI driver lacks exception handling, causing silent failures without `test-worker-report.json`. |
| **8** | Moderate | `tools/arxiv_test_worker.rb:50-55, 277-282` | Incomplete check list on skipped builds and non-atomic/vulnerable `#save` | **Genuine Defect** | When `fresh_build` is skipped, hardcoded list in `else` branch omits `fresh_build` and `settle_before_dependency`, causing report to report 14 checks instead of 16. `#save` fails ungracefully on `SystemCallError` (e.g., `ENOSPC`) leaving `.tmp` files and propagating exceptions. |

---

## 2. Technical Remediation Specifications

### Finding 1: Bounded Process Execution, Stdin Disconnection, and Process Group Reaping
- **File**: `tools/arxiv_test_worker.rb`
- **Constant**: `COMMAND_TIMEOUT = 900`
- **Methods**: `command(argv, timeout: COMMAND_TIMEOUT)`, `wait_bounded(pid, timeout, log)`, `reap(pid)`
- **Design**:
  1. In `command`: Spawn subprocess with `in: File::NULL`, `pgroup: true`, `out: log`, `err: %i[child out]`.
  2. In `wait_bounded`: Monotonic clock deadline polling via `Process.waitpid2(pid, Process::WNOHANG)`. If deadline exceeded, call `reap(pid)` and raise `CheckError`. If interrupted/signaled (`rescue Exception`), ensure `reap(pid)` runs and re-raise.
  3. In `reap`: Send `SIGTERM` to process group `-pid`. Allow up to 2.0s for graceful termination. If still running, send `SIGKILL` to `-pid` and reap zombie with `Process.waitpid(pid)`. Gracefully swallow `Errno::ESRCH`, `Errno::ECHILD`, `Errno::EPERM`.

### Finding 2: Robust Exception Handling and UTF-8 Scrubbing
- **File**: `tools/arxiv_test_worker.rb`
- **Methods**: `check(name)`, `run`, `read_text(path)`
- **Design**:
  1. In `check`: Expand rescue clause to `rescue StandardError, ScriptError => e` so `LoadError` and `SyntaxError` from dynamic tools (`check_arxiv_metadata`) are recorded as check failures rather than unhandled aborts.
  2. In `run`: Enclose entire method execution in `rescue Exception => e`. Set `@report[:status] = 'ERROR'`, `@report[:completed] = true`, `@report[:error] = "#{e.class}: #{e.message}"`, `@report[:backtrace] = e.backtrace&.first(15)`. Save report, emit warning to stderr, re-raise if `SignalException`, otherwise return 2.
  3. In `read_text(path)`: Safe binary read followed by UTF-8 conversion with `.scrub('?')`. Use across `#dependency`, `#package`, `#failure_recovery`.

### Finding 3: Signal-Safe File Restoration and Marked Probes
- **File**: `tools/arxiv_test_worker.rb`
- **Methods**: `initialize`, `install_signal_traps`, `with_original(path)`, `restore_one(path)`, `restore_all`, `failure_recovery`, `change_dependency`
- **Design**:
  1. Initialize `@restores = {}` in constructor.
  2. In `install_signal_traps`: When running on `Thread.main`, install handlers for `INT`, `TERM`, `HUP` that invoke `restore_all` and `exit!(130)`.
  3. In `with_original(path)`: Record `[File.binread(path), File.stat(path)]` in `@restores`. Guarantee `restore_one(path)` executes in `ensure`.
  4. In `restore_one(path)`: Safely restore file content and utime (`stat.atime`, `stat.mtime`).
  5. In `failure_recovery`: Mark probe with `\latexItDeliberatelyUndefinedProbe\n% %%latex_it-probe\n`. Explicitly restore before `recovery` check.
  6. In `change_dependency`: Wrap entire change and rerun cycle inside `with_original(path)` with marked probe comment `% %%latex_it-probe: dependency change`.

### Finding 4: Resilient Engine Detection and Diagnostic Assertions
- **File**: `tools/arxiv_test_worker.rb`
- **Method**: `prepare`
- **Design**:
  1. Candidate engines: `@engine ? [@engine] : %w[xelatex lualatex pdflatex]`.
  2. Select first executable engine from candidates via `candidates.lazy.map { |e| executable(e) }.find(&:itself)`.
  3. Assert engine existence: if `real_engine.nil?`, raise `CheckError` with descriptive message naming candidates and remediation advice.
  4. Verify secondary tools (`pdftotext`, `pdftoppm`, `zip`, `unzip`).

### Finding 5: Exit Status Verification for Engine and `latex_it` `--version`
- **File**: `tools/arxiv_test_worker.rb`
- **Method**: `prepare`
- **Design**:
  1. Capture `Open3.capture2e(real_engine, '--version')` into output and status.
  2. Assert `status.success?` with clear error including exit status and first line of output if failed.
  3. Capture `Open3.capture2e(RbConfig.ruby, @latex, '--version')` into output and status.
  4. Assert `status.success?` before assigning `@report[:latex_it_version]`.

### Finding 6: Precise Negative Test Validation in `invalid_tex`
- **File**: `tools/arxiv_test_worker.rb`
- **Method**: `failure_recovery`
- **Design**:
  1. Validate that the process exited cleanly with a compiler failure code: `assert(result[:exit_status].positive? && result[:exit_status] < 128, ...)`.
  2. If log file exists, verify that compiler failure was specifically triggered by probe: `assert(read_text(result[:log]).include?('latexItDeliberatelyUndefinedProbe'), ...)`.

### Finding 7: Self-Describing Staging Validation and CLI Entrypoint Safeguards
- **File**: `tools/arxiv_test_worker.rb`
- **Methods**: `initialize`, bottom-of-file driver block
- **Design**:
  1. In `initialize`:
     - Validate existence of `test-config.json`, raising `CheckError` with clear message if missing.
     - Validate `'main'` key existence in config, raising `CheckError` if missing.
     - Validate `@latex` file existence, raising `CheckError` if `latex_it` was not staged.
     - Initialize and immediately save baseline `@report` to guarantee report presence from start.
  2. In CLI driver (`if __FILE__ == $PROGRAM_NAME`):
     - Wrap invocation in `begin ... rescue StandardError, ScriptError => e`.
     - Generate and write fallback `test-worker-report.json` with status `'ERROR'`, completed `true`, and error message/backtrace.
     - Emit warning and exit 2.

### Finding 8: Full Check Roster Guarantee (`ALL_CHECKS`) and Resilient Persistence
- **File**: `tools/arxiv_test_worker.rb`
- **Constant**: `ALL_CHECKS = %w[environment fresh_build unchanged_rerun fast_rerun single_pass settle_after_single_pass pdf_diff settle_before_dependency dependency_change dependency_rerun invalid_tex recovery metadata portable_archive arxiv_archive].freeze`
- **Methods**: `run`, `save`
- **Design**:
  1. In `run`: When `built` is false, compute `(ALL_CHECKS - @report[:checks].map { |c| c[:name] })` and record each as `SKIP`, guaranteeing all 16 checks appear in final report.
  2. In `save`: Write `.tmp` and rename. Enclose in `rescue SystemCallError => e`, remove orphaned `.tmp`, and warn without aborting worker execution.

---

## 3. Code Metrics & Architectural Invariants

All new and modified methods must strictly satisfy `tools/gate_audit_code`:
- Method length $\le 80$ lines (or $\le 120$ lines if cognitive complexity $\le 5$)
- Cognitive complexity $\le 15$
- Nesting depth $\le 4$

### Target Method Projections
- `Runner#initialize`: ~35 lines, depth 1, complexity 3 ($\le 15$)
- `Runner#install_signal_traps`: ~12 lines, depth 2, complexity 2 ($\le 15$)
- `Runner#run`: ~35 lines, depth 2, complexity 6 ($\le 15$)
- `Runner#prepare`: ~30 lines, depth 2, complexity 3 ($\le 15$)
- `Runner#command`: ~20 lines, depth 1, complexity 1 ($\le 15$)
- `Runner#wait_bounded`: ~18 lines, depth 2, complexity 4 ($\le 15$)
- `Runner#reap`: ~12 lines, depth 2, complexity 2 ($\le 15$)
- `Runner#read_text`: ~5 lines, depth 1, complexity 0 ($\le 15$)
- `Runner#with_original`: ~8 lines, depth 1, complexity 0 ($\le 15$)
- `Runner#restore_one`: ~8 lines, depth 1, complexity 1 ($\le 15$)
- `Runner#restore_all`: ~8 lines, depth 2, complexity 1 ($\le 15$)
- `Runner#failure_recovery`: ~25 lines, depth 2, complexity 3 ($\le 15$)
- `Runner#change_dependency`: ~22 lines, depth 2, complexity 2 ($\le 15$)
- `Runner#save`: ~12 lines, depth 1, complexity 1 ($\le 15$)

---

## 4. Test Strategy & Verification Plan

1. **Unit & Regression Tests (`test/test_arxiv_worker.rb`)**:
   - `test_command_spawns_with_null_stdin_and_pgroup`: Verify spawn options `in: File::NULL` and `pgroup: true`.
   - `test_wait_bounded_times_out_and_reaps`: Verify bounded execution raises `CheckError` on timeout and invokes `reap`.
   - `test_check_catches_script_error`: Verify `LoadError` / `SyntaxError` are handled cleanly as `FAIL`.
   - `test_run_recovers_from_unhandled_exception_and_marks_error`: Verify top-level exceptions outside check produce `ERROR` report with `completed: true`.
   - `test_read_text_scrubs_invalid_utf8`: Verify non-UTF-8 bytes are scrubbed without raising `ArgumentError`.
   - `test_with_original_restores_file_on_exception`: Verify mutated files are restored even if block throws unexpected exception.
   - `test_prepare_detects_candidate_engine_when_unspecified`: Verify auto-detection of `xelatex`/`lualatex`/`pdflatex` when `@engine` is nil.
   - `test_prepare_raises_actionable_error_when_no_engine_available`: Verify clear `CheckError` when no LaTeX engine is found.
   - `test_prepare_verifies_version_probe_exit_status`: Verify failed `--version` exits raise `CheckError`.
   - `test_invalid_tex_rejects_signal_death_and_unrelated_failures`: Verify exit code $\ge 128$ (signal death) is rejected.
   - `test_initialize_validates_required_config_and_staged_files`: Verify missing config, missing `main`, or missing `latex_it` raise `CheckError`.
   - `test_all_checks_recorded_as_skip_when_build_fails`: Verify all 16 checks exist in report when `environment` fails.
   - `test_save_handles_system_call_error_gracefully`: Verify ENOSPC/IO errors do not crash `save`.

2. **Quality Gate Verification**:
   - `tools/gate_audit_code`: Zero violations across all methods in `latex_it`, `lib/`, `tools/`, and `test/`.
   - `tools/gate`: Fast tier quality gate (all 19 unit test files) passing cleanly.
