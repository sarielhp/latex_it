# Resilience Remediation Summary #004

- **Date**: 2026-09-12
- **Focus Area**: Resilience Audit
- **Source Report**: `reviews/004_resilience.md`
- **Plan**: `reviews/004_resilience_plan.md`
- **Branch**: `fix-review-004-resilience-remediation`
- **Status**: Complete & Verified Green

---

## Triage & Mitigation Summary

All 7 findings from `reviews/004_resilience.md` were thoroughly evaluated against the codebase, system requirements, architectural specifications (`docs/AGENTS.md`), and regression test suites. Six findings were identified as genuine resilience defects and remediated with targeted, minimal, and idiomatic fixes. One finding (Finding #5) was triaged as an intentional design behavior / false positive and documented accordingly without code modification.

### 1. Fatal Process Signal Termination Hides Engine Crashes
- **Severity**: Major
- **Location**: `lib/latex_it/builder.rb` (`LatexBuilder#run_latex_pass`)
- **Issue**: When a LaTeX engine crashed on a fatal signal (`SIGSEGV`, `SIGBUS`, `SIGABRT`, `SIGKILL`), `status.exitstatus` returned `nil`. Defaulting `nil` to `0` assigned `st = 0`, misleading subsequent checks into treating the fatal crash as a success. `handle_pass_errors(st, lgx)` received `0`, and if the engine died before emitting standard TeX error log lines, the build aborted silently with zero feedback to the user.
- **Status / Mitigation**: Fixed. Updated `run_latex_pass` to extract the exit status using standard UNIX signal convention `st = status.exitstatus || (status.respond_to?(:termsig) && status.termsig ? 128 + status.termsig : 1)`. Added an explicit warning `\nLaTeX engine terminated by signal #{status.termsig} (fatal crash).\n` when `status.signaled?` is true. `handle_pass_errors(st, lgx)` now reliably receives a non-zero exit status ($> 0$), ensuring crash diagnosis and error reporting are always triggered. Defined `ProcessResultStatus` struct to provide consistent duck-typing for timeout and process statuses.
- **Verification**: Added regression unit test `test_latex_pass_signal_termination_detected_and_handled` in `test/test_repair_failures.rb` confirming that fatal signal termination (`termsig: 11`) emits the crash diagnostic, sets non-zero status, invokes error handling, and returns false.

### 2. Premature Diagnostic Log Erasure on Cached Builds
- **Severity**: Major
- **Location**: `lib/latex_it/builder.rb` (`LatexBuilder#setup_environment`, `execute_compile_pipeline`)
- **Issue**: `setup_environment` unlinked all previous log and diagnostic files (`@log`, `@loga`, `@biberr`, `@pdferr`, `_1`, `_2`, `_3`) prior to running `targets_up_to_date?`. When a document was already up-to-date and the user requested diagnostics (`-a`, `-e`, `-v`, `--emacs`), `analyze_output` inspected `find_last_latex_log`, found that all log artifacts had just been deleted, and silently swallowed all cached warnings and diagnostics.
- **Status / Mitigation**: Fixed. Removed premature `FileUtils.rm_f` from `setup_environment` and introduced `clean_pass_logs`. In `execute_compile_pipeline`, log cleanup is deferred until after `targets_up_to_date?` has confirmed that recompilation is necessary. On cached/up-to-date builds, logs are preserved for analysis by `analyze_output`.
- **Verification**: Added regression unit test `test_cached_build_preserves_diagnostic_logs` in `test/test_build_cache.rb` verifying that when targets are up-to-date, existing log files (`junk/err_xelatex_1`, `junk/log.txt`) remain intact and accessible to diagnostics.

### 3. Bibliography Runner Lacks Timeout Protection
- **Severity**: Major
- **Location**: `lib/latex_it/builder.rb` (`LatexBuilder#execute_bibliography`)
- **Issue**: `execute_bibliography` directly invoked `Open3.capture2e('biber', ...)` and `Open3.capture2e('bibtex', ...)` without any timeout guard. External bibliography tools like Biber (which can fetch remote URIs or backtrack on malformed entries) were susceptible to indefinite hangs, causing `latex_it` to hang permanently without diagnostics.
- **Status / Mitigation**: Fixed. Re-routed bibliography tool execution through `capture_pass_output(cmd)` inside `junk/` directory isolation, inheriting configurable timeout management (`DEFAULT_PASS_TIMEOUT` / `@options[:timeout]`), process group killing on timeout, and error reporting. Extracted style copying into `copy_style_files_for_bibtex` to preserve clean code metrics.
- **Verification**: Added regression unit test `test_bibliography_timeout_aborts_cleanly_and_preserves_previous` in `test/test_repair_failures.rb` verifying that a timed-out bibliography run aborts cleanly, records the timeout diagnostic in `junk/err_bib`, restores previous bibliography files, and returns false.

### 4. Unclosed `stdin` Pipe and Subprocess Group Leak in Subprocess Execution
- **Severity**: Major
- **Location**: `lib/latex_it/builder.rb` (`LatexBuilder#capture_pass_output`)
- **Issue**: In `capture_pass_output`, `Open3.popen2e` left the child process's standard input pipe open. When TeX prompted for input (`\typein`, interactive package queries), it blocked waiting on stdin; because EOF was never delivered, TeX hung for the full timeout duration instead of aborting immediately. Additionally, child processes were not spawned in their own process group, so killing only `wait_thr.pid` on timeout orphaned child processes spawned by TeX engines (e.g. `xdvipdfmx`, `mktexpk`).
- **Status / Mitigation**: Fixed. Spawned processes with `pgroup: true`, immediately closed standard input with `stdin.close rescue nil` so interactive prompts receive instant EOF, and updated timeout cleanup to target the process group via `Process.kill('-KILL', pgid)` before falling back to direct PID kill.
- **Verification**: Added regression unit test `test_capture_pass_output_closes_stdin_prompt_immediately` in `test/test_repair_failures.rb` verifying that subprocesses reading standard input receive EOF immediately and exit cleanly.

### 5. Intermediate Bibliography Backup Artifact (`.bbl.bak`) in Project Root
- **Severity**: Major
- **Location**: `lib/latex_it/builder.rb` (`LatexBuilder#preserve_bibliography_backup`)
- **Issue**: Review report claimed writing `backup = "#{root_bbl}.bak"` directly to the root project directory leaked intermediate build files and violated the `junk/` isolation invariant.
- **Status / Mitigation**: **False Positive / Intentional Design Behavior** (No code changes). Architectural specification in `docs/AGENTS.md` explicitly specifies under *2. Bibliography Safety*: `Root .bbl is only overwritten if the generated junk/*.bbl contains valid bibliography entries (\bibitem or \entry)` and `.bbl.bak is preserved during updates.` Root `.bbl` files are user documents often placed in the project root; backing them up as `.bbl.bak` before overwriting protects user data from destructive compilation passes. This invariant is actively validated by existing unit tests in `test/test_repair_failures.rb` (`assert_equal previous, File.read('paper.bbl.bak')`) and `.bbl.bak` is explicitly classified in `lib/latex_it/utils.rb` under `JUNK_PATTERNS` for manual/deep cleanup (`l -c`).
- **Verification**: Retained existing behavior and verified regression tests in `test/test_repair_failures.rb` pass without modification to the backup logic.

### 6. Unguarded `kpsewhich` Execution in `stage_biblatex_shield`
- **Severity**: Moderate
- **Location**: `lib/latex_it/arxiv.rb` (`LatexArxivPackager#stage_biblatex_shield`)
- **Issue**: `stage_biblatex_shield` invoked `Open3.capture2('kpsewhich', core)` without checking whether `kpsewhich` was installed in `PATH` or rescuing system call errors. On minimal systems or environments where TeX utilities are restricted, this raised an unhandled `Errno::ENOENT`, crashing arXiv packaging with a stack trace.
- **Status / Mitigation**: Fixed. Extracted `harvest_kpsewhich_core_files(harvested)` helper method. Added pre-execution check `LaTeXUtils.command_available?('kpsewhich')` and wrapped `Open3.capture2` in `rescue SystemCallError => e` with an informative warning.
- **Verification**: Added regression unit test `test_arxiv_biblatex_shield_resilient_to_kpsewhich_failure` in `test/test_repair_failures.rb` verifying that both missing `kpsewhich` and execution errors (`SystemCallError`) are handled gracefully without exceptions.

### 7. Unhandled Exceptions in `stage_arxiv_files` During LaTeX Flattening
- **Severity**: Moderate
- **Location**: `lib/latex_it/arxiv.rb` (`LatexArxivPackager#stage_arxiv_files`, `do_package`)
- **Issue**: `stage_arxiv_files` called `LaTeXFlattener.flatten` without exception guards. When `LaTeXFlattener` encountered cyclic input dependencies (raising `RuntimeError`) or file read failures, the uncaught exception crashed the process with a stack trace.
- **Status / Mitigation**: Fixed. Wrapped `LaTeXFlattener.flatten` in `stage_arxiv_files` with `begin ... rescue StandardError => e`, logging a concise, styled diagnostic `[FAIL] Could not flatten LaTeX source: #{e.message}` and returning `false`. In `do_package`, added `return false unless stage_arxiv_files(stage_dir)` to ensure clean abort without generating invalid archives.
- **Verification**: Added regression unit test `test_arxiv_packaging_handles_cyclic_flattener_exception` in `test/test_repair_failures.rb` asserting that cyclic input errors abort packaging cleanly with appropriate diagnostic output and return code.
- **Footprint**: 6 files changed, 376 insertions(+), 35 deletions(-)
- **Differential Audit**: 2 warning(s)

---

## Quality Gate & Code Metrics Verification

1. **Fast Quality Gate (`./tools/gate`)**:
   - `ruby -cw`: 100% clean across all libraries, tools, and test suites.
   - 19 fast quality gate test suites: All 19 passed cleanly in ~2.7s.
2. **Code Metrics Audit (`./tools/gate_audit_code`)**:
   - Nesting Depth: $\le 4$ across all methods.
   - Cognitive Complexity: $\le 15$ across all methods.
   - Method Length: $\le 80$ lines (or $\le 120$ lines if cognitive complexity $\le 5$).
   - Repository-wide audit: 784 methods compliant, 0 violations.
