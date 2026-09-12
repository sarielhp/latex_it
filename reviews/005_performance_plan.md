# Architecture & Performance Remediation Plan: Review #005

**Review Document**: `reviews/005_performance.md`  
**Date**: 2026-09-12  
**Target Subsystems**: `LatexBuilder` (`lib/latex_it/builder.rb`), `LaTeXBraceChecker` (`lib/latex_it/brace_checker.rb`), `LaTeXMetaExtractor` (`lib/latex_it/meta_extractor.rb`), `LaTeXFlattener` (`lib/latex_it/flattener.rb`)

---

## 1. Executive Summary & Triage Overview

A comprehensive architectural and performance audit of Systems Code Review Report #005 (`reviews/005_performance.md`) was conducted across all 4 reported findings. Each finding was evaluated against repository invariants, architectural documentation (`docs/AGENTS.md`), existing regression test suites, and strict AST code metrics.

### Triage Matrix

| Finding | Severity | Component | Finding Description | Triage Decision | Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **#1** | Major | `lib/latex_it/builder.rb:148-174` | Premature cache invalidation in `targets_up_to_date?` when `update_on_diff` is active or source mtime changes without content diff | **Genuine Defect** | Comparing `root_files` mtime against `target_pdf` mtime causes perpetual rebuild loops when `update_on_diff` suppresses updating `target_pdf` due to invariant layout. It also invalidates caching when source files are touched without content modifications. |
| **#2** | Moderate | `lib/latex_it/builder.rb:198-226, 637-648, 780-788, 851-861` | Redundant aux globbing and reading across passes and checks in convergence loop | **Genuine Defect** | `compute_aux_hash`, `needs_latex_rerun?`, `detect_bib_tool`, and `extract_aux_bib_files` repeatedly perform `Dir.glob('junk/**/*.aux')` and read all auxiliary files from disk 10–12 times per 3-pass build, generating unnecessary filesystem I/O in the hot compilation loop. |
| **#3** | Moderate | `lib/latex_it/brace_checker.rb:64-70, 167-172` & `lib/latex_it/meta_extractor.rb:171-188` | Dynamic regex compilation in inner verbatim loops and 82 sequential regex passes in `clean_latex_math` | **Genuine Defect** | Interpolating `@verbatim_end` in regexes inside verbatim line loops compiles regexes on every verbatim line. In `clean_latex_math`, looping through `GREEK_SYMBOLS`, `MATH_SYMBOLS`, and `MATH_FUNCTIONS` performs 82 `gsub!` passes and dynamic regex compilations per invocation. |
| **#4** | Moderate | `lib/latex_it/flattener.rb:228-244` | Heap string slice allocation on every character index in `inline_comment_index` | **Genuine Defect** | `line[i..]` allocates an unbounded heap string on every character iteration of `inline_comment_index`, generating millions of short-lived string allocations across file flattening and comment stripping. |

---

## 2. Technical Remediation Specifications

### Finding 1: Content-Addressable & Diff-Aware Build Cache Invalidation
- **File**: `lib/latex_it/builder.rb`
- **Method**: `targets_up_to_date?`
- **Design**:
  1. Base freshness comparison on the recorded build timestamp `build_time = state['saved_at'] || (File.exist?(state_file) ? File.mtime(state_file).to_i : 0)` instead of `File.mtime(target_pdf)`.
  2. For `root_files` (`Dir['*.tex'] + bib_files_on_disk`), only invalidate if a file was modified after `build_time` AND (it is untracked in `sources` OR its SHA256 actually differs from `sources[f]['sha']`).
  3. This ensures that:
     - `update_on_diff` preserving an older `target_pdf` does not cause false invalidations on subsequent builds.
     - Touching files (e.g. `touch` or `git checkout`) without altering content does not defeat the build cache.
     - Any real content changes or newly added root `.tex`/`.bib` files still trigger an immediate rebuild.
  4. Ensure all AST metric constraints are strictly maintained ($\le 80$ lines, complexity $\le 15$, depth $\le 4$).

### Finding 2: Auxiliary State Threading & In-Memory Memoization in Convergence Loop
- **File**: `lib/latex_it/builder.rb`
- **Methods**: `run_pass_iterations(max_passes, bib_ran, bib_tool)`, `needs_latex_rerun?(loga, prev_aux_hash = nil, curr_aux_hash = nil)`, `detect_bib_tool(aux_contents = nil)`, `needs_bib_pass?(tool, loga, aux_contents = nil)`, `discover_bib_files(aux_contents = nil)`, `extract_aux_bib_files(aux_contents = nil)`
- **Design**:
  1. In `run_pass_iterations`:
     - Compute `aux_before = compute_aux_hash` once before starting the pass iteration loop.
     - After `run_latex_pass("_#{pass}")`, compute `curr_aux_hash = compute_aux_hash` once.
     - Pass `curr_aux_hash` into `needs_latex_rerun?`, eliminating the second `compute_aux_hash` call in `needs_latex_rerun?`.
     - Thread `aux_before = curr_aux_hash` for the subsequent pass, eliminating re-reading of `.aux` files at the top of pass $N+1$.
     - Pass `curr_aux_hash` into `detect_bib_tool` and `needs_bib_pass?`.
  2. In `detect_bib_tool(aux_contents = nil)`:
     - Accept optional `aux_contents`. When provided, skip `Dir.glob('junk/**/*.aux')` and file reads, inspecting `aux_contents` directly.
  3. In `extract_aux_bib_files(aux_contents = nil)`:
     - Accept optional `aux_contents`. When provided, scan `aux_contents` for `\bibdata{...}` without filesystem traversal.
  4. Preserve full backward compatibility when optional parameters are omitted.

### Finding 3: Inner Loop Regex Elimination & Precompiled Dictionary Matching
- **Files**: `lib/latex_it/brace_checker.rb`, `lib/latex_it/meta_extractor.rb`
- **Methods**: `LaTeXBraceChecker.scan_inverted_labels`, `LaTeXBraceChecker#scan_line`, `LaTeXMetaExtractor.clean_latex_math`
- **Design**:
  1. In `LaTeXBraceChecker`:
     - Replace dynamic regex `/\\end\{#{Regexp.escape(@verbatim_end)}\}/` with fast substring search `raw_line.include?("\\end{#{@verbatim_end}}")`.
     - Replace matching in `scan_inverted_labels` with `raw_line.include?("\\end{#{verbatim_end}}")` and `unless line.include?("\\end{#{name}}")`.
     - Completely eliminates regex compilation inside verbatim environment line processing.
  2. In `LaTeXMetaExtractor`:
     - Construct a unified replacement dictionary at module load time:
       ```ruby
       MATH_REPLACEMENTS = GREEK_SYMBOLS.merge(MATH_SYMBOLS).merge(MATH_FUNCTIONS.to_h { |f| [f, f] }).freeze
       ```
     - Precompile a single dictionary token regex sorted by length descending:
       ```ruby
       MATH_TOKEN_PATTERN = /\\(#{Regexp.union(MATH_REPLACEMENTS.keys.sort_by { |k| -k.length }).source})\b/.freeze
       MATH_FONT_PATTERN = /\\(?:mathbb|mathcal|mathfrak)\{([A-Za-z])\}/.freeze
       MATH_SQRT_PATTERN = /\\sqrt\{([^}]+)\}/.freeze
       MATH_INLINE_PATTERN = /\$([^\$]+)\$/.freeze
       ```
     - In `clean_latex_math`, replace the 82 sequential loops with a single regex substitution block:
       ```ruby
       str.gsub!(MATH_TOKEN_PATTERN) { MATH_REPLACEMENTS[Regexp.last_match(1)] }
       str.gsub!(MATH_FONT_PATTERN, '\1')
       str.gsub!(MATH_SQRT_PATTERN, '√(\1)')
       str.gsub!(MATH_INLINE_PATTERN, '\1')
       str.delete('$')
       ```

### Finding 4: Zero-Allocation Guarded Scanning in `inline_comment_index`
- **File**: `lib/latex_it/flattener.rb`
- **Method**: `self.inline_comment_index(line)`
- **Design**:
  1. Guard URL command inspection with `c == '\\'`:
     ```ruby
     if c == '\\' && (line[i, 5] == '\\url{' || line[i, 6] == '\\href{')
       in_url = true
     ```
  2. For the vast majority of characters ($c \ne \text{'\\'}$) in LaTeX source, avoid allocating `line[i..]` or substring slices altogether.
  3. Maintain exact semantics for percent characters inside `\url{...}` and `\href{...}` as validated by existing tests.

---

## 3. Code Metrics & Architectural Invariants

All modified methods must adhere to `tools/gate_audit_code`:
- **Method Length**: $\le 80$ lines (or $\le 120$ lines if cognitive complexity $\le 5$)
- **Cognitive Complexity**: $\le 15$
- **Nesting Depth**: $\le 4$

Audit projection for modified methods:
- `LaTeXBuilder#targets_up_to_date?`: ~28 lines, depth 2, CC ~ 8 ($\le 15$)
- `LaTeXBuilder#run_pass_iterations`: ~29 lines, depth 3, CC ~ 11 ($\le 15$)
- `LaTeXBuilder#needs_latex_rerun?`: ~11 lines, depth 2, CC ~ 8 ($\le 15$)
- `LaTeXBuilder#detect_bib_tool`: ~14 lines, depth 2, CC ~ 6 ($\le 15$)
- `LaTeXBuilder#extract_aux_bib_files`: ~14 lines, depth 2, CC ~ 4 ($\le 15$)
- `LaTeXBraceChecker.scan_inverted_labels`: ~30 lines, depth 2, CC ~ 10 ($\le 15$)
- `LaTeXBraceChecker#scan_line`: ~35 lines, depth 2, CC ~ 12 ($\le 15$)
- `LaTeXMetaExtractor.clean_latex_math`: ~10 lines, depth 1, CC ~ 2 ($\le 15$)
- `LaTeXFlattener.inline_comment_index`: ~17 lines, depth 2, CC ~ 13 ($\le 15$)

---

## 4. Test Strategy & Verification Plan

1. **Regression Unit Tests**:
   - `test/test_build_cache.rb`:
     * Add `test_targets_up_to_date_with_update_on_diff_when_pdf_timestamp_is_older`: verifies that when `update_on_diff` preserves an older PDF mtime, caching is preserved.
     * Add `test_targets_up_to_date_when_file_touched_without_content_change`: verifies content-addressable cache is not invalidated by `touch`.
     * Add `test_targets_up_to_date_invalidates_when_content_changes`: verifies actual content modifications correctly invalidate cache.
     * Add `test_targets_up_to_date_invalidates_when_new_root_file_added`: verifies adding a new root `.tex` or `.bib` invalidates cache.
   - `test/test_latex_it.rb`:
     * Add `test_aux_hash_threading_and_memoized_aux_reads`: verifies `needs_latex_rerun?` with supplied `curr_aux_hash` and `extract_aux_bib_files(aux_contents)` avoid disk I/O while producing accurate results.
   - `test/test_brace_checker.rb`:
     * Add `test_verbatim_detection_with_substring_matching`: verifies `\begin{verbatim} ... \end{verbatim}` and `\begin{lstlisting} ... \end{lstlisting}` are accurately handled without regex recompilation.
   - `test/test_arxiv.rb`:
     * Add `test_clean_latex_math_comprehensive`: verifies all greek letters, math symbols, math functions, blackboard bold/calligraphic/fraktur fonts, and square roots are accurately transformed.
   - `test/test_flattener.rb`:
     * Add `test_inline_comment_index_handles_urls_and_comments`: verifies unescaped percents, escaped `\%`, URLs, and hrefs across edge cases.

2. **Quality Gate Verification**:
   - `tools/gate_audit_code`: Zero metric violations across all modified and repository methods.
   - `tools/gate`: All fast quality gate tests passing cleanly.
