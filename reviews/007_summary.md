# Post-Work Remediation Summary: Review #007 (Resilience)

- **Date**: 2026-09-12
- **Audit Target**: `tools/arxiv_test_worker.rb`
- **Scope**: External process management, bounded execution, failure recovery, exception guarantees, report integrity, dependency validation.
- **Review Document**: `reviews/007_resilience.md`
- **Remediation Plan**: `reviews/007_resilience_plan.md`
- **Outcome**: All 8 findings triaged as genuine defects and fully remediated.

---

## Triage & Defect Classification

| # | Severity | Location | Description | Status | Rationale / Mitigation |
|---|---|---|---|---|---|
| **1** | Critical | `tools/arxiv_test_worker.rb` (`#command`, `#wait_bounded`, `#reap`) | Unbounded `Process.wait2` and inherited stdin in `command` | **Remediated** | Spawns external processes with `in: File::NULL`, `pgroup: true`, and bounded monotonic deadline polling (`wait_bounded`). Reaps stuck or signaled process groups via `reap` (`TERM` -> `KILL`). |
| **2** | Major | `tools/arxiv_test_worker.rb` (`#check`, `#run`, `#read_text`) | Incomplete exception handling in `#check` and `#run`, unscrubbed UTF-8 reads | **Remediated** | Rescues `ScriptError` alongside `StandardError` in `check`. Added top-level `rescue Exception` in `run` recording `status: 'ERROR'` with completed report and backtrace. Added `read_text` with `.scrub('?')` for `.fls` and build logs. |
| **3** | Major | `tools/arxiv_test_worker.rb` (`#with_original`, `#restore_one`, `#restore_all`, `#install_signal_traps`) | Mutate/restore window left paper source corrupted upon signals | **Remediated** | Registered global `@restores` table, installed `INT`, `TERM`, `HUP` signal traps calling `restore_all`, guaranteed restoration in `with_original`, and added marked probe comments (`% %%latex_it-probe`). |
| **4** | Major | `tools/arxiv_test_worker.rb` (`#prepare`) | Broken engine dependency assertion when `@engine` is `nil` | **Remediated** | When `@engine` is omitted, auto-detects first available candidate among `xelatex`, `lualatex`, `pdflatex`. Raises informative `CheckError` if none are found on `PATH` instead of raw `TypeError`. |
| **5** | Major | `tools/arxiv_test_worker.rb` (`#prepare`) | Exit status ignored for engine and `latex_it` `--version` probes | **Remediated** | Checks `status.success?` for `capture2e` version probes. Aborts with clear `CheckError` containing exit status and output if `--version` fails. |
| **6** | Moderate | `tools/arxiv_test_worker.rb` (`#failure_recovery`) | Negative test success predicate accepted crash/signal deaths | **Remediated** | Requires clean compiler failure status (`result[:exit_status].positive? && result[:exit_status] < 128`) and verifies deliberate probe substring exists in the compiler log. |
| **7** | Moderate | `tools/arxiv_test_worker.rb` (`#initialize`, driver block) | Unhandled initialization errors and missing CLI driver error recovery | **Remediated** | Validates existence of `test-config.json`, `'main'` entry, and `latex_it` executable in `Runner#initialize`. Driver catches `StandardError` and `ScriptError`, persisting fallback `test-worker-report.json` with status `'ERROR'` and exiting 2. |
| **8** | Moderate | `tools/arxiv_test_worker.rb` (`ALL_CHECKS`, `#run`, `#save`) | Incomplete check roster on early build failure and vulnerable `#save` | **Remediated** | Introduced `ALL_CHECKS` constant containing all 16 checks. When `prepare` or `fresh_build` fails, all non-executed checks are recorded as `SKIP`. `#save` catches `SystemCallError` (e.g. `ENOSPC`), cleans `.tmp`, and warns rather than crashing. |

---

## Remediation Details

### 1. Bounded Process Execution, Stdin Disconnection, and Process Reaping
- **Severity**: Critical
- **Location**: `tools/arxiv_test_worker.rb` (`#command`, `#wait_bounded`, `#reap`)
- **Issue**: Subprocesses spawned by `command` inherited the worker's stdin. If TeX encountered an error and paused at an interactive prompt (`? ` or `Enter file name:`), it blocked reading stdin forever. Furthermore, `Process.wait2` lacked any per-operation deadline, causing wedged engines or infinite loops to stall indefinitely and orphan child processes.
- **Status / Mitigation**: Fixed.
  - Added `COMMAND_TIMEOUT = 900` default per-command timeout.
  - Updated `Process.spawn` invocation with `in: File::NULL`, `pgroup: true`, `out: log`, `err: %i[child out]`.
  - Implemented `wait_bounded(pid, timeout, log)` with monotonic clock deadline polling via `Process.waitpid2(pid, Process::WNOHANG)`.
  - Implemented `reap(pid)` to send `SIGTERM` to the process group `-pid`, poll for up to 2.0s, and escalate to `SIGKILL` if needed.
- **Verification**:
  - `test/test_arxiv_worker.rb` (`test_command_uses_null_stdin_and_pgroup`): verified spawn options include `in: File::NULL` and `pgroup: true`.
  - `test/test_arxiv_worker.rb` (`test_wait_bounded_times_out_and_reaps`): verified timeout triggers `CheckError` and calls `reap`.

### 2. Robust Exception Handling and UTF-8 Scrubbing
- **Severity**: Major
- **Location**: `tools/arxiv_test_worker.rb` (`#check`, `#run`, `#read_text`, `#dependency`, `#package`)
- **Issue**: `#check` rescued only `StandardError`, allowing `ScriptError` (`LoadError`, `SyntaxError`) to bypass check reporting. `#run` had no top-level exception handler, causing any error outside a check block to crash the worker leaving `test-worker-report.json` in an uncompleted `RUNNING` status. In addition, unscrubbed file reads on `.fls` or build logs containing non-UTF-8 bytes caused `ArgumentError: invalid byte sequence in UTF-8`.
- **Status / Mitigation**: Fixed.
  - Updated `#check` rescue clause to `rescue StandardError, ScriptError => e`.
  - Wrapped `#run` body in `rescue Exception => e` setting `@report[:status] = 'ERROR'`, `@report[:completed] = true`, saving report, and exiting with status 2.
  - Implemented `read_text(path)` performing binary read followed by UTF-8 scrubbing (`.force_encoding(Encoding::UTF_8).scrub('?')`). Applied to `#dependency` and `#package`.
- **Verification**:
  - `test/test_arxiv_worker.rb` (`test_check_catches_script_error`): verified `LoadError` inside check block is captured as `status: 'FAIL'` without aborting.
  - `test/test_arxiv_worker.rb` (`test_run_recovers_from_unhandled_exception`): verified unhandled exception outside check sets `status: 'ERROR'`, `completed: true`, and returns 2.
  - `test/test_arxiv_worker.rb` (`test_read_text_scrubs_invalid_utf8`): verified non-UTF-8 bytes are cleanly scrubbed without `ArgumentError`.

### 3. Signal-Safe File Restoration and Marked Probes
- **Severity**: Major
- **Location**: `tools/arxiv_test_worker.rb` (`#initialize`, `#install_signal_traps`, `#with_original`, `#restore_one`, `#restore_all`, `#change_dependency`, `#failure_recovery`)
- **Issue**: Mutated source files in `#failure_recovery` and `#change_dependency` were restored only in language-level `ensure` blocks. If the worker was killed by a signal (`SIGTERM`, `SIGINT`, `SIGHUP`), `ensure` was bypassed, permanently corrupting the paper files with probe content.
- **Status / Mitigation**: Fixed.
  - Implemented `@restores` map tracking pending file restorations with original contents and file timestamps (`atime`, `mtime`).
  - Added `install_signal_traps` hooking `INT`, `TERM`, `HUP` to invoke `restore_all` and `exit!(130)`.
  - Added `with_original(path)` block helper guaranteeing restoration in `ensure`.
  - Marked probe strings with explicit comment tags (`% %%latex_it-probe`).
- **Verification**:
  - `test/test_arxiv_worker.rb` (`test_with_original_restores_file_on_exception`): verified file is restored upon exception.
  - `test/test_arxiv_worker.rb` (`test_restore_all_restores_multiple_tracked_files`): verified all tracked files are restored by `restore_all`.
  - `test/test_arxiv_worker.rb` (`test_failure_probe_restores_source_and_rejects_false_success`): validated probe restoration and error rejection.
  - `test/test_arxiv_worker.rb` (`test_dependency_probe_keeps_mtime_and_restores_source`): validated dependency probe behavior and timestamp restoration.

### 4. Resilient Engine Detection and Diagnostic Assertions
- **Severity**: Major
- **Location**: `tools/arxiv_test_worker.rb` (`#prepare`)
- **Issue**: When `@engine` was `nil` (automatic mode), `[*@engine]` was empty, so no engine was included in the `missing` dependency check. Then `executable('xelatex')` evaluated to `nil` on systems with only `pdflatex`/`lualatex`, causing `Open3.capture2e(nil, '--version')` to raise `TypeError: no implicit conversion of nil into String`.
- **Status / Mitigation**: Fixed.
  - Set `candidates = @engine ? [@engine] : %w[xelatex lualatex pdflatex]`.
  - Selected `real_engine = candidates.lazy.map { |e| executable(e) }.find(&:itself)`.
  - Asserted `real_engine` with informative error naming candidate engines and configuration instructions.
- **Verification**:
  - `test/test_arxiv_worker.rb` (`test_prepare_raises_actionable_error_when_no_latex_engine_found`): verified `CheckError` naming all candidates when no engine is installed.

### 5. Exit Status Verification for Engine and `latex_it` `--version` Probes
- **Severity**: Major
- **Location**: `tools/arxiv_test_worker.rb` (`#prepare`)
- **Issue**: `Open3.capture2e(...).first` discarded exit statuses. If an engine or `latex_it` failed during `--version` (e.g. missing gem or broken configuration), stderr error text/backtraces were saved as version strings while `prepare` recorded `PASS`.
- **Status / Mitigation**: Fixed.
  - Captured `[output, status]` for both `real_engine` and `@latex` version checks.
  - Added assertions requiring `status.success?`, including the exit status and output lines upon failure.
- **Verification**:
  - `test/test_arxiv_worker.rb` (`test_prepare_fails_when_engine_or_latex_it_version_probe_fails`): verified failure status on `--version` raises `CheckError`.

### 6. Precise Negative Test Validation in `invalid_tex`
- **Severity**: Moderate
- **Location**: `tools/arxiv_test_worker.rb` (`#failure_recovery`)
- **Issue**: Assertion `result[:exit_status] != 0` accepted signal deaths (`>= 128`, e.g. OOM killer status `137`) and unrelated pre-compiler wrapper failures as positive test passes.
- **Status / Mitigation**: Fixed.
  - Asserted `result[:exit_status].positive? && result[:exit_status] < 128` to require a clean compiler error exit.
  - If a log file was produced, verified `read_text(result[:log]).include?('latexItDeliberatelyUndefinedProbe')` to ensure the failure was specifically caused by the injected invalid control sequence.
- **Verification**:
  - `test/test_arxiv_worker.rb` (`test_invalid_tex_rejects_signal_death`): verified exit status `137` records `FAIL`.
  - `test/test_arxiv_worker.rb` (`test_invalid_tex_verifies_probe_in_log`): verified log missing probe name records `FAIL`.

### 7. Self-Describing Staging Validation and CLI Driver Safeguards
- **Severity**: Moderate
- **Location**: `tools/arxiv_test_worker.rb` (`#initialize`, driver block)
- **Issue**: Missing `test-config.json`, missing `'main'` key, or missing `latex_it` raised uncaught exceptions in constructor before `@report` was written, causing silent termination without a report.
- **Status / Mitigation**: Fixed.
  - In `initialize`, added explicit presence checks raising `CheckError` for missing config file, missing `'main'` key, and missing `latex_it` binary.
  - Saved initial `@report` with `status: 'RUNNING'` immediately in constructor.
  - In driver block (`if __FILE__ == $PROGRAM_NAME`), wrapped runner in `begin ... rescue StandardError, ScriptError => e` writing fallback `test-worker-report.json` with status `'ERROR'` and exiting 2.
- **Verification**:
  - `test/test_arxiv_worker.rb` (`test_initialize_validates_config_and_staged_latex_it`): verified missing config, missing `main`, and missing `latex_it` raise actionable `CheckError`.

### 8. Full Check Roster Guarantee (`ALL_CHECKS`) and Resilient Persistence
- **Severity**: Moderate
- **Location**: `tools/arxiv_test_worker.rb` (`ALL_CHECKS`, `#run`, `#save`)
- **Issue**: When `fresh_build` was skipped, the hardcoded skip list omitted `fresh_build` and `settle_before_dependency`, resulting in 14 checks instead of 16 in the report. In addition, `#save` failed ungracefully on `SystemCallError` (e.g. `ENOSPC`).
- **Status / Mitigation**: Fixed.
  - Defined `ALL_CHECKS` covering all 16 check names in canonical order.
  - Recorded all unexecuted checks as `SKIP` when the build fails.
  - Wrapped `#save` in `rescue SystemCallError => e`, cleaning up `.tmp` and warning rather than raising.
- **Verification**:
  - `test/test_arxiv_worker.rb` (`test_all_checks_recorded_as_skip_when_environment_fails`): verified all 16 checks in `ALL_CHECKS` appear in the report (1 `FAIL`, 15 `SKIP`).
  - `test/test_arxiv_worker.rb` (`test_save_handles_system_call_error_gracefully`): verified `save` catches `Errno::ENOSPC` and emits warning without raising.

---

## Quality Gate & Code Metrics Verification

1. **Fast Quality Gate (`./tools/gate`)**:
   - Syntax validation (`ruby -cw`): 100% clean across all 19 test files, libraries, and tools.
   - All 19 test suites passed cleanly with 0 failures, 0 errors.
2. **Code Metrics Audit (`./tools/gate_audit_code`)**:
   - Nesting Depth: $\le 4$ across all methods.
   - Cognitive Complexity: $\le 15$ across all methods.
   - Method Length: $\le 80$ lines (or $\le 120$ lines if cognitive complexity $\le 5$).
   - Repository-wide audit: 793 methods audited, 793 compliant, 0 violations.
3. **Footprint & Scope Containment**:
   - Modified files: `tools/arxiv_test_worker.rb`, `test/test_arxiv_worker.rb`.
   - Documentation added: `reviews/007_resilience_plan.md`, `reviews/007_summary.md`.
   - Zero refactoring of unaffected modules or external CLI behavior.

---

## Conclusion

All 8 defects identified in Systems Code Review Report #007 have been remediated with minimal, robust, and idiomatic fixes. Comprehensive regression tests validate bounded execution, exception safety, signal-safe file restoration, dependency validation, precise failure assertion, complete check reporting, and resilient atomic report persistence.
