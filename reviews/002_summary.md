# Security Remediation Summary #002

- **Date**: 2026-09-12
- **Focus Area**: Security Audit
- **Source Report**: `reviews/002_security.md`
- **Plan**: `reviews/002_security_plan.md`
- **Branch**: `fix-review-002-security-remediation`
- **Status**: Complete & Verified Green

---

## Triage & Mitigation Summary

All 4 findings from `reviews/002_security.md` were evaluated and identified as genuine security defects. Targeted, minimal, idiomatic remediations and regression tests were implemented for all issues.

### 1. Insecure Manual Shell Serialization Passed to `PTY.spawn`
- **Severity**: Critical
- **Location**: `tools/review_cycle` (`MultiProfileReviewCycle#run_with_auto_triage`)
- **Issue**: `run_with_auto_triage` converted argument array `cmd_args` into a single string with naive quoting before calling `PTY.spawn(command_str)`. Single-string `PTY.spawn` delegates to `/bin/sh -c`, allowing backtick command substitutions (e.g. `` `tools/gate` `` in remediation prompts), parameter expansions (`$VAR`), and unquoted metacharacters (`;`, `&`, `|`) to execute arbitrary commands on the host machine.
- **Status / Mitigation**: Fixed. Passed array arguments directly to `PTY.spawn(*cmd_args)`. Ruby invokes `execvp` directly without passing through `/bin/sh`, completely preventing command injection.
- **Verification**: Added regression unit test `test_review_cycle_run_with_auto_triage_prevents_shell_injection` in `test/test_destructive_paths.rb` confirming arguments containing shell metacharacters and backticks execute literally without shell expansion or interpolation.

### 2. Missing Filesystem Containment Verification on Recursive File Inlining
- **Severity**: Major
- **Location**: `lib/latex_it/flattener.rb` (`LaTeXFlattener.inline_file`, `LaTeXFlattener.inline_line`, `LaTeXFlattener.within_tree?`)
- **Issue**: In `LaTeXFlattener.inline_line`, `\input{...}` and `\include{...}` targets were expanded with `File.expand_path(target, file_dir)` without verifying that candidate paths reside within `base_dir`, nor guarding against symlink traversals across project boundaries. Furthermore, `inline_file` recursively forwarded `file_dir` instead of `base_dir`, allowing directory traversals (`../../secrets.tex`) to inline sensitive out-of-tree files into public arXiv papers.
- **Status / Mitigation**: Fixed. Added helper `LaTeXFlattener.within_tree?` checking both `File.expand_path` and `File.realpath` against project root `base_expanded` and `real_base`. Refused inlining of any target resolving outside the project boundary. Maintained `base_expanded` across recursive calls.
- **Verification**: Added regression unit tests `test_out_of_tree_input_is_not_inlined`, `test_symlink_pointing_out_of_tree_is_not_inlined`, and `test_in_tree_nested_subfolder_input_is_inlined` in `test/test_flattener.rb`.

### 3. Insecure Fallback for Out-of-Boundary Asset Paths
- **Severity**: Major
- **Location**: `lib/latex_it/arxiv.rb` (`LatexArxivPackager#copy_preserving_path`) and `lib/latex_it/packager.rb` (`LatexPackager#copy_preserving_path`)
- **Issue**: `copy_preserving_path` checked `expanded.start_with?(cwd + '/')`. When asset paths recorded in `.fls` or extra files were outside `cwd` (e.g., `/home/user/private/architecture.pdf` or `../confidential.png`), it fell back to `rel_path = File.basename(src)` and copied the file into `dest_root`, leaking private filesystem assets into public distribution zip archives.
- **Status / Mitigation**: Fixed. Verified that `File.realpath(src)` and `File.expand_path(src)` strictly reside within `cwd` and `real_cwd`. Removed the insecure out-of-tree basename fallback, refusing to copy any file residing outside the project tree.
- **Verification**: Added regression unit tests `test_arxiv_copy_preserving_path_rejects_out_of_tree_and_symlinks` and `test_packager_copy_preserving_path_rejects_out_of_tree_and_symlinks` in `test/test_destructive_paths.rb`.

### 4. Unescaped Shell String Interpolation into `Kernel#system`
- **Severity**: Moderate
- **Location**: `tools/generate_gallery` and `tools/generate_error_comparison`
- **Issue**: ImageMagick `convert` invocations used single-quote string interpolation `system("convert -density 150 '#{svg_path}' '#{png_path}'")` and `system('which convert >/dev/null 2>&1')`. Filenames with single quotes or shell metacharacters could escape quoting and execute shell commands under `/bin/sh`.
- **Status / Mitigation**: Fixed. Replaced string-interpolated `system()` calls with safe multi-argument array calls (`system('convert', '-density', '150', svg_path, png_path)` and `system('which', 'convert', out: File::NULL, err: File::NULL)`).
- **Verification**: Added regression unit test `test_image_generation_scripts_avoid_shell_string_interpolation` in `test/test_destructive_paths.rb`, verified syntax via `ruby -cw`, and verified code metrics via `tools/gate_audit_code`.

---

## Quality Gate & Code Metrics Verification

1. **Fast Quality Gate (`./tools/gate`)**:
   - `ruby -cw`: Passed on all files.
   - 19 test files (all fast quality gate unit & integration tests): 100% passed cleanly.
2. **Code Metrics Audit (`./tools/gate_audit_code`)**:
   - Nesting Depth: <= 4 across all methods.
   - Cognitive Complexity: <= 15 across all methods.
   - Method Length: <= 80 lines (or <= 120 lines if cognitive complexity <= 5).
   - Repository-wide audit: 779 methods compliant, 0 violations.
