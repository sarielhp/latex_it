# Systems Post-Work Summary #006 (Lens: cli)

- **Date**: 2026-09-12
- **Auditor**: Claude / Codex (Tier 1 Standard) via `tools/audit`
- **Focus Lens**: `cli`
- **Scope**: `.`
- **Status**: Resolved & Verified

---

## Executive Summary

Audit #006 focused on Command-Line Interface ergonomics, help system brevity, single-canonical-interface conformance, and stdout/stderr stream separation across `latex_it`, `lib/latex_it/diagnostics.rb`, and `lib/latex_it/utils.rb`. All 4 findings reported in `reviews/006_cli.md` were triaged as genuine defects violating the core CLI lens mandate.

All 4 defects were remediated with minimal, targeted fixes:
1. Engine shortcuts (`--lua`, `--xe`, `--pdflatex`) were eliminated from documented option registrations and routed through hidden argument normalization (`LatexCLI.normalize_argv!`) into canonical `--engine=<engine>` forms.
2. Short help (`-h` / `--help`) was condensed into a high-density 19-line curated overview (strictly $\le 20$ lines, summaries $\le 45$ characters), with full option listings accessible via `--help-all`.
3. Fatal compilation error reporting in `report_errors` was migrated from stdout to stderr (`io: $stderr`), guaranteeing standard Unix stream separation for CI pipelines and logging scripts.
4. Redundant no-op flags were remediated: `--pdf` (a phantom option) was eliminated completely, and `--fast` (an obsolete rebuild no-op) was demoted to a silently accepted, hidden legacy alias.

Regression tests were updated and added in `test/test_latex_it.rb` and `test/test_deep_diagnostics.rb`. All 19 test suites in `tools/gate` pass cleanly in ~2.7s, and `tools/gate_audit_code` verifies 100% compliance across all 785 methods in the repository with zero violations.

---

## Triage Summary

| # | Severity | Location | Defect Description | Triage Decision | Rationale |
|---|---|---|---|---|---|
| **#1** | Major | `latex_it:215-228,259-264` | Shortcut flags `--lua`, `--xe`, `--pdflatex` advertised alongside `--engine ENGINE` | **Genuine Defect** | Violates CLI Mandate 1 ("One Canonical Interface") and Mandate 2 ("retain the legacy form as a hidden alias"). Folding into `normalize_argv!` retains backward compatibility while eliminating alias proliferation. |
| **#2** | Moderate | `latex_it:230-346` | Option short help (`-h` / `--help`) output was 50 lines, exceeding 20-line ceiling | **Genuine Defect** | Violates CLI Mandate 3 ("Subcommand short help (-h) must be dense and concise (strictly <= 20 lines), keeping field and command summaries <= 45 characters"). Bifurcated into condensed help for `-h` / `--help` and full options for `--help-all`. |
| **#3** | Major | `lib/latex_it/diagnostics.rb:818-852` | Fatal compilation error report emitted exclusively to stdout before `exit 1` | **Genuine Defect** | Violates CLI Mandate 4 ("Clean stdout/stderr stream separation"). Primary error report correlated with non-zero exit was invisible to stderr-capturing CI loggers. Routed through stderr. |
| **#4** | Moderate | `latex_it:247,261-262` | Documented no-op flags `--pdf` and `--fast` inflate help text | **Genuine Defect** | `--pdf` documented a non-choice (only PDF mode exists) and `--fast` was an obsolete compatibility no-op. Removed `--pdf` and demoted `--fast` to hidden legacy no-op in `normalize_argv!`. |

---

## Remediation Details

### 1. Engine Selection Canonicalization via Hidden Normalization
- **Severity**: Major
- **Location**: `latex_it` (`LatexCLI.normalize_argv!`, `LatexCLI.add_compilation_options_primary`), `lib/latex_it/utils.rb` (`LaTeXUtils.detailed_examples`)
- **Issue**: Engine selection already possesses a canonical form (`--engine ENGINE`), but `--lua`, `--xe`, and `--pdflatex` were registered as separate documented options in `opts.on` stating "Shortcut for --engine=...". This advertised multiple redundant ways to pick compiler engines in help text.
- **Status / Mitigation**: Fixed. Deleted the three `opts.on` registrations from `add_compilation_options_primary` so that only `--engine ENGINE` is documented. In `LatexCLI.normalize_argv!`, mapped `--lua` and legacy `-lualatex` to `--engine=lualatex`, `--xe` and `-xelatex` to `--engine=xelatex`, and `--pdflatex` and `-pdflatex` to `--engine=pdflatex`. Updated `detailed_examples` in `lib/latex_it/utils.rb` to display canonical `--engine=...` syntax.
- **Verification**:
  - `test/test_latex_it.rb` (`test_help_flag` and `test_help_all_flag`): confirmed `--lua`, `--xe`, and `--pdflatex` are omitted from both condensed `-h` and `--help-all`.
  - `test/test_latex_it.rb` (`test_canonical_cli_flags_and_anti_alias`): validated canonical `--engine=<engine>` flags and verified that hidden aliases `--lua`, `--xe`, and `--pdflatex` continue to function without error.

### 2. Condensed Short Help ($\le 20$ Lines) and `--help-all` Dispatch
- **Severity**: Moderate
- **Location**: `latex_it` (`LatexCLI.condensed_help`, `LatexCLI.build_default_options`, `LatexCLI.add_general_options`, `LatexCLI.print_help_or_examples`, `LatexCLI.parse_options!`)
- **Issue**: Running `l -h` printed 50 lines of options and section headers, more than double the mandated 20-line ceiling for short help.
- **Status / Mitigation**: Fixed. Added `LatexCLI.condensed_help(prog_name = 'l')` generating a 19-line curated overview of the most critical options (`-u`, `-1`, `-c`, `-C`, `-m`, `-d`, `-a`, `-e`, `-z`, `-t`, `-W`, `--engine`, `--arxiv`, `-E`, `--help-all`, `-h`), where all summaries are $\le 45$ characters. Registered `--help-all` in `add_general_options` to print the full `OptionParser` specification. Updated `parse_options!` parse error guidance to reference both `-h` and `--help-all`.
- **Verification**:
  - `test/test_latex_it.rb` (`test_help_flag`): verified `stdout.lines.count <= 20` (exactly 19 lines), confirmed presence of all common options, and refuted uncurated/alias flags.
  - `test/test_latex_it.rb` (`test_help_all_flag`): verified `--help-all` successfully outputs sectioned `OptionParser` help containing advanced flags (`--deps`, `--no-env`, `--alert-hbox`, etc.).
  - `test/test_latex_it.rb` (`test_examples_flag`): verified combined `-h -E` and `--help-all -E` output formats.

### 3. Clean Stream Separation for Fatal Compilation Diagnostics
- **Severity**: Major
- **Location**: `lib/latex_it/diagnostics.rb` (`LaTeXDiagnostics#report_errors`, `#report_error_summary`, `#print_summary_line`, `#print_diagnostics_body`, `#render_diagnostic_entry`, `#render_diagnostic_fallback`, `#render_fallback_lines`, `#explain_diagnostic_item`)
- **Issue**: When LaTeX compilation fails, `report_errors` emits the error banner, per-file diagnostics, "See ... for full error details" notice, and final summary count to `$stdout` before terminating with `exit 1`. Stderr remained empty, breaking standard Unix conventions and CI failure capture.
- **Status / Mitigation**: Fixed. Parameterized `report_errors(loga, io: $stderr)` to direct fatal diagnostics to `$stderr`. Threaded `io:` target through `print_diagnostics_body`, `render_diagnostic_entry`, `render_diagnostic_fallback`, `render_fallback_lines`, `explain_diagnostic_item`, `report_error_summary`, and `print_summary_line`. Non-fatal analysis (`analyze_output`) and normal execution continue to write build diagnostics to `$stdout` by default.
- **Verification**:
  - `test/test_latex_it.rb` (`test_report_errors_suppresses_warnings`): updated to capture both `out` and `err`, asserting `out` is empty and `err` contains the compilation failure banner, error text, and summary line.
  - `test/test_deep_diagnostics.rb` (`test_report_errors_routes_to_stderr_stream`, `test_report_errors_accepts_custom_io`): added regression tests verifying that `report_errors` routes to stderr by default and supports arbitrary `io` streams.

### 4. Elimination of No-Op Flags `--pdf` and Hidden Demotion of `--fast`
- **Severity**: Moderate
- **Location**: `latex_it` (`LatexCLI.normalize_argv!`, `LatexCLI.add_compilation_options_primary`)
- **Issue**: `--pdf` was registered with "Generate PDF output (default behavior)" but its action block was an empty `# No-op` (since only PDF generation is supported). `--fast` similarly advertised an obsolete compatibility no-op ("incremental rebuilds are automatic"). Both cluttered help text.
- **Status / Mitigation**: Fixed. Removed `opts.on('--pdf'...)` and `opts.on('--fast'...)` from `add_compilation_options_primary`. In `LatexCLI.normalize_argv!`, added `argv.delete('--fast')` so existing scripts passing `--fast` continue to run cleanly as hidden no-ops. Invocations of `--pdf` are rejected as invalid options.
- **Verification**:
  - `test/test_latex_it.rb` (`test_help_flag` and `test_help_all_flag`): verified `--fast` and `--pdf` are not present in any help text.
  - `test/test_latex_it.rb` (`test_canonical_cli_flags_and_anti_alias`): verified `--fast` is accepted without error and `--pdf` is rejected as an invalid option.

---

## Quality Gate & Code Metrics Verification

1. **Fast Quality Gate (`./tools/gate`)**:
   - `ruby -cw`: 100% clean across all libraries, tools, and test suites.
   - 19 fast quality gate test suites: All 19 passed cleanly in ~2.7s.
2. **Code Metrics Audit (`./tools/gate_audit_code`)**:
   - Nesting Depth: $\le 4$ across all methods.
   - Cognitive Complexity: $\le 15$ across all methods.
   - Method Length: $\le 80$ lines (or $\le 120$ lines if cognitive complexity $\le 5$).
   - Repository-wide audit: 785 methods compliant, 0 violations.
3. **Footprint**:
   - Modified files: `latex_it`, `lib/latex_it/diagnostics.rb`, `lib/latex_it/utils.rb`, `test/test_latex_it.rb`, `test/test_deep_diagnostics.rb`.
   - Documentation added: `reviews/006_cli_plan.md`, `reviews/006_summary.md`.

---

## Conclusion

All genuine defects identified in Systems Code Review Report #006 have been remediated cleanly and validated with comprehensive regression tests. The CLI interface now features single canonical flags, condensed short help adhering to the $\le 20$-line ceiling, full option access via `--help-all`, clean stderr error streaming, and strict adherence to all repository quality and code metric invariants.
