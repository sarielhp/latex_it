# Remediation Plan: Security Audit Report #002

**Target Report**: `reviews/002_security.md`  
**Date**: 2026-09-12  
**Focus Area**: Security Audit  
**Author**: Antigravity  

---

## 1. Executive Summary & Defect Triage

Each finding from `reviews/002_security.md` has been evaluated. All four reported findings represent genuine security defects that violate least-privilege, filesystem boundary isolation, or safe process execution invariants.

| Finding | Severity | Component | Classification | Planned Action |
| :--- | :--- | :--- | :--- | :--- |
| 1. Insecure manual shell serialization in `PTY.spawn` | Critical | `tools/review_cycle` | Genuine Defect | Replace string shell interpolation with multi-arg array invocation `PTY.spawn(*cmd_args)`. |
| 2. Unchecked directory & symlink traversal in recursive file inlining | Major | `lib/latex_it/flattener.rb` | Genuine Defect | Add `within_tree?` containment checks against `base_dir` and verify `realpath` on input targets. |
| 3. Insecure fallback copying out-of-boundary assets into zip | Major | `lib/latex_it/arxiv.rb`<br>`lib/latex_it/packager.rb` | Genuine Defect | Reject asset copying if `expanded` or `realpath` resolves outside `cwd`. Remove out-of-tree basename fallback. |
| 4. Shell string interpolation in ImageMagick conversion commands | Moderate | `tools/generate_gallery`<br>`tools/generate_error_comparison` | Genuine Defect | Replace shell string `system("convert ...")` with safe multi-argument array calls `system('convert', ...)`. |

---

## 2. Technical Remediation Plan

### Finding 1: Process Execution Security in `tools/review_cycle`
- **Location**: `tools/review_cycle` (`MultiProfileReviewCycle#run_with_auto_triage`)
- **Root Cause**: An array of arguments `cmd_args` is serialized into a single string with naive space/double-quote escaping and passed to `PTY.spawn(command_str)`. `PTY.spawn` delegates strings to `/bin/sh -c`, which evaluates backticks (e.g. `Run `tools/gate`...`), command substitutions `$()`, and unquoted metacharacters on the host machine.
- **Fix**:
  - Pass `cmd_args` directly as varargs: `PTY.spawn(*cmd_args)`.
  - Ruby's `PTY.spawn(command, *args)` bypasses the shell and performs direct `execvp`, preventing shell injection.
- **Verification**:
  - Add regression test in `test/test_destructive_paths.rb` confirming arguments containing shell metacharacters (`;&|`) and backticks (`` `echo injected` ``) execute verbatim without shell expansion or syntax errors.

### Finding 2: Filesystem Containment in `lib/latex_it/flattener.rb`
- **Location**: `lib/latex_it/flattener.rb` (`LaTeXFlattener.inline_file`, `LaTeXFlattener.inline_line`)
- **Root Cause**: `inline_line` resolves `\input{target}` and `\include{target}` via `candidate = File.expand_path(target, file_dir)` without validating that `candidate` remains inside `base_dir`. Furthermore, `inline_file` recursively passed `file_dir` instead of the root `base_dir`, allowing directory traversal (`../../etc/passwd`) and symlink escapes to inline arbitrary host files into public arXiv papers.
- **Fix**:
  - Implement helper `within_tree?(candidate, base_expanded, real_base)` checking that both `File.expand_path(candidate)` and `File.realpath(candidate)` are within the project root directory.
  - Guard `inline_file` and `inline_line` to reject targets resolving outside `base_expanded`.
  - Maintain `base_expanded` across recursive `inline_file` calls so nested inputs cannot escape the project root.
- **Verification**:
  - Add regression tests in `test/test_flattener.rb` verifying that `\input{../../secret.tex}` and symlinks pointing outside the project root are not inlined, while normal in-tree nested inputs continue to work correctly.

### Finding 3: Out-of-Boundary Asset Leakage in `arxiv.rb` & `packager.rb`
- **Location**: `lib/latex_it/arxiv.rb` and `lib/latex_it/packager.rb` (`copy_preserving_path`)
- **Root Cause**: When an asset or dependency path in `.fls` (or extra files) is outside `cwd`, `copy_preserving_path` fell back to `rel_path = File.basename(src)` and copied the file into `dest_root`, causing out-of-boundary private files (e.g. `/home/user/private/secrets.pdf` or `../confidential.png`) to be copied into the staging directory and included in the `.zip` archive.
- **Fix**:
  - In both `Arxiv#copy_preserving_path` and `Packager#copy_preserving_path`, verify that:
    1. `src` exists.
    2. `File.realpath(src)` resides within `File.realpath(cwd)`.
    3. `File.expand_path(src)` starts with `cwd + File::SEPARATOR`.
  - Drop the fallback `rel_path = File.basename(src)` for out-of-tree files; instead, silently reject copying any file outside `cwd`.
- **Verification**:
  - Add regression tests in `test/test_destructive_paths.rb` ensuring that out-of-tree files and out-of-tree symlinks referenced as figures/dependencies are ignored by `copy_preserving_path` and never copied into the destination root.

### Finding 4: Shell String Escaping in Media Generation Tools
- **Location**: `tools/generate_gallery` and `tools/generate_error_comparison`
- **Root Cause**: Invocations of `convert` use string interpolation wrapped in single quotes (e.g. `system("convert -density 150 '#{svg_path}' '#{png_path}'")`). Paths containing single quotes or special characters break shell quoting and allow shell injection.
- **Fix**:
  - Replace shell-string `system()` calls with multi-argument array calls:
    `system('which', 'convert', out: File::NULL, err: File::NULL)`
    `system('convert', '-density', '150', svg_path, png_path)`
    `system('convert', '-delay', '120', f1_png, ..., GIF_FILE)`
- **Verification**:
  - Verify script syntax with `ruby -cw tools/generate_gallery` and `ruby -cw tools/generate_error_comparison`.
  - Validate code metrics with `tools/gate_audit_code`.

---

## 3. Invariants & Code Metrics Compliance

- **Method Length**: Hard ceiling <= 80 lines (or <= 120 lines if cognitive complexity <= 5).
- **Cognitive Complexity**: <= 15.
- **Nesting Depth**: <= 4.
- **Quality Gate**: All 19 fast quality gate checks (`./tools/gate`) must pass cleanly.
- **Code Audit**: `./tools/gate_audit_code` must report zero violations across the repository.
- **Scope Containment**: No unrelated refactoring or external CLI changes.

---

## 4. Implementation Steps & Sequencing

1. **Phase 1**: Fix Finding 1 in `tools/review_cycle`.
2. **Phase 2**: Fix Finding 2 in `lib/latex_it/flattener.rb`.
3. **Phase 3**: Fix Finding 3 in `lib/latex_it/arxiv.rb` and `lib/latex_it/packager.rb`.
4. **Phase 4**: Fix Finding 4 in `tools/generate_gallery` and `tools/generate_error_comparison`.
5. **Phase 5**: Author regression unit tests in `test/test_flattener.rb` and `test/test_destructive_paths.rb`.
6. **Phase 6**: Run quality gates (`./tools/gate` and `./tools/gate_audit_code`), audit code metrics, author post-work summary `reviews/002_summary.md`, and commit.
