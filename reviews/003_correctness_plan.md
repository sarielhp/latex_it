# Remediation Plan: Correctness Audit Report #003

**Target Report**: `reviews/003_correctness.md`  
**Date**: 2026-09-12  
**Focus Area**: Correctness Audit  
**Author**: Antigravity  

---

## 1. Executive Summary & Defect Triage

Each finding from `reviews/003_correctness.md` has been evaluated. All three reported findings represent genuine correctness defects that lead to missing dependencies in arXiv bundles, false-positive alerts halting builds under `-W`, or phantom diagnostic counts in build summaries.

| Finding | Severity | Component | Classification | Planned Action |
| :--- | :--- | :--- | :--- | :--- |
| 1. Multiple `\input`/`\include` on a single line drops subsequent files | Major | `lib/latex_it/flattener.rb` | Genuine Defect | In `inline_line`, separate comments and scan/expand all `\input`/`\include` directives on the line, preserving newline semantics. |
| 2. `scan_inverted_labels` lacks verbatim tracking, causing false-positive alerts in listings | Major | `lib/latex_it/brace_checker.rb` | Genuine Defect | In `scan_inverted_labels`, add verbatim environment tracking (`VERBATIM_ENVS`) to skip verbatim blocks and avoid spurious alerts. |
| 3. `count_reference_messages` uses unanchored regexes that match echoed body prose | Moderate | `lib/latex_it/diagnostics.rb` | Genuine Defect | In `count_reference_messages`, filter subcommand noise and anchor matches to TeX warning headers (`LaTeX Warning:` and package warnings). |

---

## 2. Technical Remediation Plan

### Finding 1: Flattener Drops Multiple Directives on a Single Line
- **Location**: `lib/latex_it/flattener.rb` (`LaTeXFlattener.inline_line`)
- **Root Cause**: `inline_line` matched `^\s*\\(?:input|include)\{([^}]+)\}(.*)$` once per line. The first directive was inlined, but everything matched by `(.*)$` (`rest`) was appended verbatim without scanning for additional `\input` or `\include` commands. If a line contained `\input{macros}\input{content}`, `content.tex` was neither inlined nor staged for arXiv, breaking the self-contained document bundle.
- **Fix**:
  - Use `inline_comment_index(line)` to isolate active LaTeX code from trailing `%` comments.
  - Return early if the code portion contains no `\input` or `\include` directives.
  - Replace each in-tree directive via `gsub(/\\(?:input|include)\{([^}]+)\}/)`, recursively expanding targets via `inline_file(candidate, base_expanded, stack)` while keeping out-of-tree or non-existent directives verbatim.
  - Preserve newline formatting: when a line contains only directives and trailing newline, normalize double newlines so document layout remains identical to single-directive lines.
  - Re-attach any trailing comment portion untouched.
- **Verification**:
  - Add regression unit test `test_multiple_inputs_on_single_line_are_all_inlined` in `test/test_flattener.rb`.
  - Validate that commented-out `\input` directives (`% \input{...}`) remain un-inlined.

### Finding 2: `scan_inverted_labels` Lacks Verbatim Tracking
- **Location**: `lib/latex_it/brace_checker.rb` (`LaTeXBraceChecker.scan_inverted_labels`)
- **Root Cause**: `LaTeXBraceChecker.scan_inverted_labels` scanned lines for `LABEL_TOKEN_PATTERN` without tracking verbatim environments (`VERBATIM_ENVS`). If LaTeX documentation, papers, or examples included `figure`, `\label`, or `\caption` inside a `lstlisting`, `verbatim`, or `minted` environment, false-positive `:inverted_label` alerts were triggered. Under `-W` (`werror`), this caused clean builds to exit with code 1.
- **Fix**:
  - Add verbatim state tracking (`in_verbatim` and `verbatim_end`) to `scan_inverted_labels` using `VERBATIM_ENVS`.
  - Strip comments (`(?<!\\)%.*\z`) before checking for environment boundaries.
  - When encountering `\begin{<verbatim_env>}`, skip scanning until matching `\end{<verbatim_env>}`.
  - Handle single-line verbatim environments (`\begin{...}...\end{...}`) on the same line cleanly without toggling multi-line verbatim state.
- **Verification**:
  - Add regression unit test `test_inverted_label_ignored_inside_verbatim_or_lstlisting` in `test/test_deep_diagnostics.rb`.
  - Verify that genuine inverted labels outside verbatim blocks continue to be detected.

### Finding 3: Unanchored Diagnostic Patterns Match Echoed Prose
- **Location**: `lib/latex_it/diagnostics.rb` (`LaTeXDiagnostics#count_reference_messages`)
- **Root Cause**: `count_reference_messages` checked `line =~ /citation/i && line =~ /undefined/i`, `line =~ /reference/i && line =~ /undefined/i && line =~ /page/i`, and `line =~ /multiply defined/i && line =~ /label/i` on un-anchored, raw `new_content`. When TeX echoed paragraph prose following an Overfull `\hbox` (e.g., body text discussing citations or references), these unanchored patterns triggered phantom counts in the diagnostic summary banner.
- **Fix**:
  - Run `LaTeXUtils.filter_subcommand_noise(new_content)` before scanning.
  - Anchor patterns to TeX warning prefixes: `^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+`.
  - Match specific warning structures for:
    - Undefined citation: `^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Citation\s+[`'"].*?['"`].*?undefined/i`
    - Undefined reference: `^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Reference\s+[`'"].*?['"`].*?undefined/i`
    - Multiply defined label: `^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Label\s+[`'"].*?['"`]\s+multiply defined/i`
- **Verification**:
  - Add regression unit test `test_document_text_containing_citation_words_not_counted_as_reference_warnings` in `test/test_log_recognisers.rb`.
  - Verify that authentic LaTeX warnings (both LaTeX core and packages like `natbib`) increment counts properly.

---

## 3. Invariants & Code Metrics Compliance

- **Method Length**: <= 80 lines (or <= 120 lines if cognitive complexity <= 5).
- **Cognitive Complexity**: <= 15.
- **Nesting Depth**: <= 4.
- **Quality Gate**: `tools/gate` must pass cleanly (all 19 fast quality gate test files).
- **Code Audit**: `tools/gate_audit_code` must report 0 violations across the repository.
- **Scope Containment**: Changes limited strictly to `lib/latex_it/flattener.rb`, `lib/latex_it/brace_checker.rb`, `lib/latex_it/diagnostics.rb`, and their corresponding test files.

---

## 4. Implementation Steps & Sequencing

1. **Plan Authoring**: Save detailed plan to `reviews/003_correctness_plan.md`.
2. **Phase 1 (Finding 1)**:
   - Implement multi-directive scanning in `lib/latex_it/flattener.rb`.
   - Add unit tests in `test/test_flattener.rb`.
   - Run `tools/gate` and `tools/gate_audit_code`.
3. **Phase 2 (Finding 2)**:
   - Implement verbatim tracking in `lib/latex_it/brace_checker.rb`.
   - Add unit tests in `test/test_deep_diagnostics.rb`.
   - Run `tools/gate` and `tools/gate_audit_code`.
4. **Phase 3 (Finding 3)**:
   - Implement anchored regexes and subcommand noise filtering in `lib/latex_it/diagnostics.rb`.
   - Add unit tests in `test/test_log_recognisers.rb`.
   - Run `tools/gate` and `tools/gate_audit_code`.
5. **Phase 4 (Final Verification & Summary)**:
   - Run full fast gate and code metrics audit.
   - Author post-work summary to `reviews/003_summary.md`.
   - Commit all changes to the git repository.
