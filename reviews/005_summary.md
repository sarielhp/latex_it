# Systems Review Remediation Summary #005 (Lens: performance)

- **Date**: 2026-09-12
- **Remediator**: Antigravity Assistant (Tier 1 Standard)
- **Report Reviewed**: `reviews/005_performance.md`
- **Plan Reference**: `reviews/005_performance_plan.md`
- **Status**: Complete & Verified Clean

---

## Executive Summary

All 4 findings from Systems Code Review Report #005 (`reviews/005_performance.md`) were evaluated, triaged, and remediated in accordance with repository invariants and architectural guidelines. All 4 findings represented genuine performance defects:
1. Premature build cache invalidation under `update_on_diff` and file timestamp touches.
2. Redundant aux globbing and reading across passes and checks in the compilation convergence loop.
3. Inner loop dynamic regex recompilation in `LaTeXBraceChecker` and 82 sequential regex passes in `LaTeXMetaExtractor`.
4. Continuous heap string slice allocations per character in `LaTeXFlattener#inline_comment_index`.

Each genuine defect was remediated with minimal, idiomatic code, accompanied by dedicated regression unit tests. Strict AST metrics enforced by `tools/gate_audit_code` (method length $\le 80$ lines, cognitive complexity $\le 15$, nesting depth $\le 4$) were adhered to with 100% compliance across all 784 repository methods, and all fast quality gate tests (`tools/gate`) passed cleanly.

---

## Remediation Details

### 1. Premature Build Cache Invalidation Under `update_on_diff` and Source Touches
- **Severity**: Major
- **Location**: `lib/latex_it/builder.rb` (`LatexBuilder#targets_up_to_date?`)
- **Issue**: `targets_up_to_date?` checked `root_files.any? { |f| File.mtime(f) > pdf_mtime }`. When `update_on_diff` is enabled (via `-d` or configuration) and the rendered PDF layout remains invariant, `update_target_file` intentionally preserves `target_pdf` without updating its timestamp. Meanwhile, `save_build_state!` records the source's fresh SHA256 checksum and sets `saved_at = Time.now.to_i`. On subsequent runs, `targets_up_to_date?` observed `File.mtime(f) > pdf_mtime` and returned `false`, trapping the project in an un-cached state where every run executed redundant multi-pass compilation. Comparing against `pdf_mtime` also broke caching when files were touched without content changes (e.g. `touch` or `git checkout`).
- **Status / Mitigation**: Fixed. Freshness comparison now evaluates root files against `build_time = state['saved_at'] || (File.exist?(state_file) ? File.mtime(state_file).to_i : 0)`. The check only invalidates if `File.mtime(f).to_i > build_time && (!sources[f] || Digest::SHA256.file(f).hexdigest != sources[f]['sha'])`. If a file was touched without content changes, or if `target_pdf` was preserved by `update_on_diff`, the content-addressable cache is preserved and rebuild is avoided. Real modifications and newly added root `.tex`/`.bib` files still immediately invalidate the cache.
- **Verification**: Added regression unit tests in `test/test_build_cache.rb`:
  - `test_targets_up_to_date_when_pdf_timestamp_is_older_than_build_state`: verifies `update_on_diff` preserving an older PDF does not falsely invalidate cache.
  - `test_targets_up_to_date_when_file_touched_without_content_change`: verifies `touch` without content change does not invalidate cache.
  - `test_targets_up_to_date_invalidates_when_content_changes`: verifies source content modifications correctly invalidate cache.
  - `test_targets_up_to_date_invalidates_when_untracked_root_file_added`: verifies adding a new root `.tex` file correctly invalidates cache.

### 2. Redundant Auxiliary File Globbing and Disk Reads in Convergence Loop
- **Severity**: Moderate
- **Location**: `lib/latex_it/builder.rb` (`LatexBuilder#run_pass_iterations`, `needs_latex_rerun?`, `detect_bib_tool`, `discover_bib_files`, `extract_aux_bib_files`)
- **Issue**: In the multi-pass compilation convergence loop, `Dir.glob('junk/**/*.aux')` and full file reads were repeated 10–12 times per build: `compute_aux_hash` ran before pass 1; `needs_latex_rerun?` ran `compute_aux_hash` again immediately after pass 1; pass 2 ran `compute_aux_hash` a third time before compiling despite no changes occurring since the end of pass 1; and `detect_bib_tool` and `extract_aux_bib_files` each repeatedly globbed and read all aux files.
- **Status / Mitigation**: Fixed. `run_pass_iterations` computes `aux_before = compute_aux_hash` once before starting iterations. After each LaTeX pass, `curr_aux_hash = compute_aux_hash` is computed once and passed into `needs_latex_rerun?`, `detect_bib_tool`, and `needs_bib_pass?` / `extract_aux_bib_files`. `aux_before` is updated to `curr_aux_hash` for the subsequent pass, eliminating re-reading of `.aux` files at the top of pass $N+1$. `detect_bib_tool(aux_contents = nil)` and `extract_aux_bib_files(aux_contents = nil)` accept the in-memory aux contents directly, bypassing `Dir.glob` and disk reads.
- **Verification**: Added regression unit tests in `test/test_build_cache.rb`:
  - `test_needs_latex_rerun_uses_passed_curr_aux_hash`: verifies `needs_latex_rerun?` uses the passed in-memory aux hash and detects changes or convergence without extra disk reads.
  - `test_extract_aux_bib_files_with_in_memory_aux_contents`: verifies `extract_aux_bib_files` parses `\bibdata` directly from passed memory buffer.
  - `test_detect_bib_tool_with_in_memory_aux_contents`: verifies `detect_bib_tool` correctly recognizes `:bibtex` and `:biber` from memory buffer without disk traversals.

### 3. Dynamic Regex Compilation in Verbatim Environments and Sequential Math Scans
- **Severity**: Moderate
- **Locations**: `lib/latex_it/brace_checker.rb` (`scan_inverted_labels`, `scan_line`), `lib/latex_it/meta_extractor.rb` (`clean_latex_math`)
- **Issue**:
  1. In `LaTeXBraceChecker`, every line inside a verbatim environment executed `/\\end\{#{Regexp.escape(@verbatim_end)}\}/`, recompiling a new `Regexp` instance on every line of verbatim text or code listings.
  2. In `LaTeXMetaExtractor.clean_latex_math`, 82 symbol and function replacements (`GREEK_SYMBOLS`, `MATH_SYMBOLS`, `MATH_FUNCTIONS`) were iterated sequentially per line, compiling dynamic regexes and running 82 separate `gsub!` passes.
- **Status / Mitigation**: Fixed.
  1. In `LaTeXBraceChecker`, replaced dynamic regex compilation with direct substring searching using `raw_line.include?("\\end{#{@verbatim_end}}")` (and `include?` in `scan_inverted_labels`), entirely eliminating regex compilation inside verbatim loops.
  2. In `LaTeXMetaExtractor`, consolidated greek symbols, math symbols, and math functions into a frozen `MATH_REPLACEMENTS` hash and compiled a single regex pattern `MATH_TOKEN_PATTERN` sorted by length descending at module load time. Replaced the 82 sequential loops with a single regex substitution pass `str.gsub!(MATH_TOKEN_PATTERN) { MATH_REPLACEMENTS[Regexp.last_match(1)] }`.
- **Verification**: Added regression unit tests:
  - `test/test_brace_checker.rb` (`test_verbatim_environments_with_braces_are_ignored`): verifies verbatim blocks across multiple environment types (`verbatim`, `lstlisting`, `minted`, `filecontents`) with unbalanced braces are parsed cleanly.
  - `test/test_arxiv.rb` (`test_clean_latex_math_comprehensive`): verifies single-pass dictionary replacement across greek symbols, math symbols, functions, fonts (`\mathbb`, `\mathcal`, `\mathfrak`), and roots.

### 4. Excessive String Allocations in `LaTeXFlattener#inline_comment_index`
- **Severity**: Moderate
- **Location**: `lib/latex_it/flattener.rb` (`LaTeXFlattener.inline_comment_index`)
- **Issue**: On every single character index `i` in `line`, `line[i..].start_with?('\\url{', '\\href{')` allocated a new heap String slice representing the remainder of the line, even when `line[i]` was not a backslash. In a large document with 15,000 lines, this created millions of short-lived string allocations during flattening and comment stripping.
- **Status / Mitigation**: Fixed. Guarded the URL detection with `if c == '\\' && (line[i, 5] == '\\url{' || line[i, 6] == '\\href{')`. Characters that are not backslashes (the vast majority of document text) bypass substring allocation completely, drastically reducing heap churn and GC pressure.
- **Verification**: Added regression unit test `test_inline_comment_index_handles_urls_and_comments` in `test/test_flattener.rb` validating comment index detection across standard comments, escaped `\%`, `\url{...%...}`, `\href{...}`, double backslashes, and commentless lines.

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
