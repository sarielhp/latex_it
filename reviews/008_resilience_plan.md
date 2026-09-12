# Architectural Plan: Review 008 Resilience Remediation

- **Review Target**: `reviews/008_resilience.md`
- **Scope**: `lib/latex_it/builder.rb`, `lib/latex_it/arxiv.rb`, `lib/latex_it/packager.rb`, `lib/latex_it/meta_extractor.rb`, `latex_it`, `test/test_repair_failures.rb`
- **Author**: Antigravity Assistant
- **Date**: 2026-09-12

---

## 1. Executive Summary & Triage

A comprehensive resilience audit in `reviews/008_resilience.md` reported 6 findings across process lifecycle management, filesystem isolation, external tool dependency resilience, artifact integrity, and option propagation.

Every finding was triaged and evaluated against project invariants and codebase architecture:

| ID | Finding Location | Severity | Triage Classification | Rationale |
|---|---|---|---|---|
| **F1** | `lib/latex_it/builder.rb:552-569` | **Critical** | **Genuine Defect** | Engine spawned in detached pgroup (`pgroup: true`) is not terminated on Interrupt/Ctrl+C or block exception, causing indefinite hang in `wait_thr.join`. Unbounded `reader.join` hangs on leaked file descriptors. |
| **F2** | `lib/latex_it/builder.rb:820-833` | **Major** | **Genuine Defect** | `copy_style_files_for_bibtex` checks `../styles` outside `junk/` chdir, probing parent directory instead of document root `styles/` and failing to copy styles into `junk/styles/`. |
| **F3** | `lib/latex_it/arxiv.rb:512-518` | **Major** | **Genuine Defect** | `count_zip_entries` runs `Open3.capture2('unzip', ...)` without checking `LaTeXUtils.command_available?('unzip')` or rescuing `SystemCallError`, crashing unverified runs on systems lacking `unzip`. |
| **F4** | `lib/latex_it/packager.rb:47` | **Major** | **Genuine Defect** | `LatexPackager#do_package` leaves unverified, corrupt, or incomplete zip archives on disk when sandbox verification fails. |
| **F5** | `lib/latex_it/meta_extractor.rb:355` | **Moderate** | **Genuine Defect** | `LaTeXMetaExtractor.extract_page_count` uses `system('which pdfinfo ...')`, failing in minimal environments without `which` despite `pdfinfo` availability and existing `command_available?` helper. |
| **F6** | `lib/latex_it/packager.rb:293`, `arxiv.rb:291`, `latex_it` | **Moderate** | **Genuine Defect** | Sandbox verification runs strip `LATEX_IT_TIMEOUT` and omit forwarding `@options[:timeout]`. CLI lacks `--timeout SECONDS` option flag. |

All 6 findings represent genuine defects. Zero findings were classified as false positives.

---

## 2. Detailed Technical Design & Implementation

### Finding 1: Engine Process Group Cleanup & Bounded Stream Reader
- **File**: `lib/latex_it/builder.rb`
- **Methods**: `kill_process_group(pid)`, `capture_pass_output(cmd_args)`
- **Architectural Design**:
  1. Introduce private helper `kill_process_group(pid)` in `LatexBuilder` to cleanly terminate child process groups and fall back to single-process SIGKILL.
  2. In `capture_pass_output`:
     - Initialize `output = +''` (mutable string).
     - Wrap process waiting and thread joining in an explicit `begin ... ensure` block inside the `Open3.popen2e` block.
     - On timeout: terminate process group via `kill_process_group(wait_thr.pid)`, kill reader thread, and return timeout status struct.
     - On normal completion: join `reader` thread with a 2.0 second bounded timeout (`reader.join(2.0) || reader.kill rescue nil`) to guard against hung subprocesses leaking open stdout/stderr pipes.
     - In `ensure`: if `wait_thr&.alive?`, execute `kill_process_group(wait_thr.pid)` to ensure that any unwinding exception (such as `Interrupt` / `SIGINT`) guarantees process group termination before `Open3.popen_run`'s internal `wait_thr.join` executes. Kill `reader` thread if still alive.

### Finding 2: Accurate Style Directory Resolution for BibTeX
- **File**: `lib/latex_it/builder.rb`
- **Method**: `copy_style_files_for_bibtex`
- **Architectural Design**:
  1. `execute_bibliography` executes in the document directory before `Dir.chdir('junk')`.
  2. `copy_style_files_for_bibtex` will test `File.directory?('styles')` directly in the document directory.
  3. Pre-create target directory `junk/styles` via `FileUtils.mkdir_p('junk/styles')`.
  4. Enumerate files in `styles/*` and copy recursively into `junk/styles/`, skipping any nested `junk` directory.

### Finding 3: Resilient Zip Entry Enumeration
- **File**: `lib/latex_it/arxiv.rb`
- **Method**: `count_zip_entries(zip_filename)`
- **Architectural Design**:
  1. Check `LaTeXUtils.command_available?('unzip')`. Return 0 immediately if `unzip` is missing.
  2. Wrap execution in `rescue SystemCallError => 0`.
  3. Inspect `stat.success?`. Return 0 if `unzip -l` fails.
  4. Parse entry lines safely and return count.

### Finding 4: Cleanup of Unverified Portable Zip Archives
- **File**: `lib/latex_it/packager.rb`
- **Method**: `do_package`
- **Architectural Design**:
  1. When `@options[:verify]` is truthy and `verify_archive!(zip_filename)` returns `false`:
  2. Delete `zip_filename` immediately via `FileUtils.rm_f(zip_filename)`.
  3. Emit a warning to stderr informing the user that the unverified archive was removed.
  4. Return `false` to abort packaging.

### Finding 5: Direct PATH Lookup for `pdfinfo` Page Extraction
- **File**: `lib/latex_it/meta_extractor.rb`
- **Method**: `self.extract_page_count(pdf_path, log_path)`
- **Architectural Design**:
  1. Replace `system('which pdfinfo > /dev/null 2>&1')` with `LaTeXUtils.command_available?('pdfinfo')`.
  2. Avoid subshell execution and shell fork overhead while ensuring compatibility in minimal container environments lacking `which`.

### Finding 6: Forwarding `--timeout` Option & CLI Support
- **Files**: `latex_it`, `lib/latex_it/packager.rb`, `lib/latex_it/arxiv.rb`
- **Architectural Design**:
  1. In `latex_it`:
     - Add `timeout: cfg['timeout']` to `build_default_options`.
     - Add `--timeout SECONDS` option in `add_compilation_options_secondary` (parsing Integer and assigning `options[:timeout] = v`).
  2. In `lib/latex_it/packager.rb` (`run_sandbox_compile`):
     - Append `['--timeout', @options[:timeout].to_s]` to `cmd` when `@options[:timeout]` is present.
  3. In `lib/latex_it/arxiv.rb` (`run_sandbox_verify`):
     - Append `['--timeout', @options[:timeout].to_s]` to `cmd` when `@options[:timeout]` is present.

---

## 3. Code Metrics & Architectural Invariants

All modified and newly added methods must strictly satisfy the project quality gates:
- Method length $\le 80$ lines (or $\le 120$ lines if cognitive complexity $\le 5$)
- Cognitive complexity $\le 15$
- Nesting depth $\le 4$

### Method Budget Projections
- `LatexBuilder#kill_process_group`: ~6 lines, depth 1, complexity 1
- `LatexBuilder#capture_pass_output`: ~26 lines, depth 3, complexity 3
- `LatexBuilder#copy_style_files_for_bibtex`: ~6 lines, depth 1, complexity 2
- `LatexArxivPackager#count_zip_entries`: ~10 lines, depth 1, complexity 2
- `LatexPackager#do_package`: ~23 lines, depth 2, complexity 3
- `LaTeXMetaExtractor.extract_page_count`: ~13 lines, depth 2, complexity 5
- `LatexPackager#run_sandbox_compile`: ~23 lines, depth 2, complexity 3
- `LatexArxivPackager#run_sandbox_verify`: ~25 lines, depth 3, complexity 5
- `LatexCLI.build_default_options`: ~60 lines, depth 2, complexity 1
- `LatexCLI.add_compilation_options_secondary`: ~32 lines, depth 1, complexity 1

---

## 4. Test Strategy & Verification Plan

Regression unit tests will be added to `test/test_repair_failures.rb` (a core test suite in `FAST_TESTS`):
1. **Finding 1 Regression**:
   - `test_capture_pass_output_kills_process_group_on_interrupt`: Verify that when an exception unwinds `capture_pass_output`, `kill_process_group` is invoked to terminate the child process group.
   - `test_capture_pass_output_reader_timeout_prevents_hang`: Verify `reader.join(2.0)` terminates without hanging when child stream holds pipe open.
2. **Finding 2 Regression**:
   - `test_copy_style_files_for_bibtex_copies_from_styles_to_junk_styles`: Verify files under `./styles/` are copied to `junk/styles/` before BibTeX runs.
3. **Finding 3 Regression**:
   - `test_count_zip_entries_resilient_when_unzip_command_missing`: Verify `count_zip_entries` returns 0 without raising exception when `unzip` is not installed or when `capture2` fails.
4. **Finding 4 Regression**:
   - `test_packager_removes_zip_on_failed_verification`: Verify `LatexPackager#do_package` deletes `zip_filename` when `verify_archive!` returns `false`.
5. **Finding 5 Regression**:
   - `test_meta_extractor_page_count_uses_command_available_pdfinfo`: Verify `extract_page_count` uses `LaTeXUtils.command_available?` without executing `which`.
6. **Finding 6 Regression**:
   - `test_sandbox_compile_and_verify_forwards_timeout_option`: Verify that `run_sandbox_compile` and `run_sandbox_verify` include `--timeout` in the spawned command arguments when `@options[:timeout]` is set.
   - `test_cli_parses_timeout_flag`: Verify `latex_it --timeout 45` correctly parses and populates `options[:timeout]`.

### Quality Verification Steps
1. Run `tools/gate_audit_code` to ensure zero code metric violations.
2. Run `tools/gate` to verify all syntax and fast tier unit tests pass cleanly.
3. Run `ruby tools/bundle --check` to verify the standalone bundle syntax and integrity.
