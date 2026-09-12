# Systems Architecture Plan #006 (Lens: cli)

- **Date**: 2026-09-12
- **Audit Target**: Systems Code Review Report #006 (`reviews/006_cli.md`)
- **Focus Area**: Command-Line Interface, Ergonomics & Help System
- **Status**: Ready for Implementation

---

## 1. Finding Triage & Defect Analysis

| # | Severity | Location | Description | Triage Decision | Rationale |
|---|---|---|---|---|---|
| **#1** | Major | `latex_it:215-228,259-264` | Shortcut flags `--lua`, `--xe`, `--pdflatex` advertised in help text alongside `--engine ENGINE` | **Genuine Defect** | Violates CLI Mandate 1 ("One Canonical Interface: Every command and option must have exactly one obvious, canonical primary form. Help text must never advertise aliases") and Mandate 2 ("retain the legacy form as a hidden alias"). Folding into `normalize_argv!` retains backward compatibility while eliminating alias bloat. |
| **#2** | Moderate | `latex_it:230-346` | Option short help (`-h` / `--help`) exceeds brevity ceiling (50 lines vs mandated $\le 20$ lines) | **Genuine Defect** | Violates CLI Mandate 3 ("Subcommand short help (-h) must be dense and concise (strictly <= 20 lines), keeping field and command summaries <= 45 characters"). Needs bifurcation into a dense, curated condensed help for `-h` / `--help` ($\le 20$ lines) and comprehensive option listing via `--help-all`. |
| **#3** | Major | `lib/latex_it/diagnostics.rb:818-852` | Fatal compilation error report emitted to stdout instead of stderr | **Genuine Defect** | Violates CLI Mandate 4 ("Clean stdout/stderr stream separation"). `report_errors` terminates with `exit 1` but writes the failure banner, diagnostics body, and error counts exclusively to `$stdout`, leaving `$stderr` empty for Unix pipelines and CI failure loggers. |
| **#4** | Moderate | `latex_it:247,261-262` | Documented no-op flags `--pdf` and `--fast` inflate help text | **Genuine Defect** | `--pdf` advertises a non-choice (PDF is the sole output format), while `--fast` is an obsolete compatibility no-op ("incremental rebuilds are automatic"). Violates Mandate 1. `--pdf` must be eliminated, and `--fast` must be demoted to a silently accepted, hidden no-op in `normalize_argv!`. |

---

## 2. Technical Remediation Specifications

### Finding 1: Single Canonical Engine Interface via Hidden Normalization
- **File**: `latex_it`
- **Methods**: `LatexCLI.normalize_argv!`, `LatexCLI.add_compilation_options_primary`
- **Design**:
  1. In `normalize_argv!(argv)`:
     Map shortcut and legacy engine flags directly to the canonical `--engine=<engine>` syntax:
     ```ruby
     when '--lua', '-lualatex' then '--engine=lualatex'
     when '--xe', '-xelatex' then '--engine=xelatex'
     when '--pdflatex', '-pdflatex' then '--engine=pdflatex'
     ```
  2. In `add_compilation_options_primary(opts, options)`:
     Remove `opts.on('--lua'...)`, `opts.on('--xe'...)`, and `opts.on('--pdflatex'...)`. Only `--engine ENGINE` is registered with `OptionParser`.
  3. In `lib/latex_it/utils.rb` (`LaTeXUtils.detailed_examples`):
     Update example commands to showcase canonical `--engine=...` syntax instead of shortcut aliases.

### Finding 2: Condensed Short Help ($\le 20$ Lines) and `--help-all` Dispatch
- **File**: `latex_it`
- **Methods**: `LatexCLI.condensed_help`, `LatexCLI.build_default_options`, `LatexCLI.add_general_options`, `LatexCLI.print_help_or_examples`, `LatexCLI.parse_options!`
- **Design**:
  1. Add `LatexCLI.condensed_help(prog_name)` returning a carefully curated 19-line output conforming strictly to:
     - Line count strictly $\le 20$ lines (19 lines total).
     - Field and command summaries strictly $\le 45$ characters.
     - Curated selection of high-frequency flags (`-u`, `-1`, `-c`, `-C`, `-m`, `-d`, `-a`, `-e`, `-z`, `-t`, `-W`, `--engine`, `--arxiv`, `-E`, `--help-all`, `-h`).
  2. In `add_general_options(opts, options)`:
     Register `--help-all` to set `options[:show_help_all] = true`.
     Update `-h, --help` description to indicate condensed help (`Show condensed help (see --help-all for full list)`).
  3. In `print_help_or_examples`:
     - If `options[:show_help_all]`: output full `parser` (and `detailed_examples` if `-E`).
     - If `options[:show_help]`: output `condensed_help(prog_name)` (and `detailed_examples` if `-E`).
  4. In `parse_options!`:
     Update error hint: `Try '#{prog_name} -h' for condensed help, or '#{prog_name} --help-all' for all options.`

### Finding 3: Stream Separation for Fatal Compilation Errors
- **File**: `lib/latex_it/diagnostics.rb`
- **Methods**: `LaTeXDiagnostics#report_errors`, `#report_error_summary`, `#print_summary_line`, `#print_diagnostics_body`, `#render_diagnostic_entry`, `#explain_diagnostic_item`, `#render_diagnostic_fallback`, `#render_fallback_lines`
- **Design**:
  1. In `report_errors(loga, io: $stderr)`:
     Default destination to `$stderr`. Thread `io` parameter through:
     - Error header banners -> `io.puts`
     - `print_diagnostics_body(..., io: io)`
     - Footer banner and log path note -> `io.puts`
     - `report_error_summary(..., io: io)`
  2. In `report_error_summary(..., io: $stdout)`:
     Pass `io: io` into `print_summary_line(..., io: io)`.
  3. In `print_summary_line(..., io: nil)`:
     Use `target_io = io || ((@options && @options[:score]) ? (@orig_stdout || $stdout) : $stdout)`.
  4. In `print_diagnostics_body(..., io: $stdout)`:
     Pass `io: io` to `render_diagnostic_entry` and `render_diagnostic_fallback`.
  5. In `render_diagnostic_entry(..., io: $stdout)`:
     Output file separators, rendered lines, and AUCTeX delimiters to `io`.
  6. In `render_diagnostic_fallback(..., io: $stdout)` and `render_fallback_lines(..., io: $stdout)`:
     Direct fallback lines to `io`.
  7. In `explain_diagnostic_item(item, io: $stdout)`:
     Direct boxed explanation to `io`.

### Finding 4: Elimination of No-Op Flags `--pdf` and Hidden Demotion of `--fast`
- **File**: `latex_it`
- **Methods**: `LatexCLI.normalize_argv!`, `LatexCLI.add_compilation_options_primary`
- **Design**:
  1. In `add_compilation_options_primary`:
     Remove `opts.on('--fast'...)` and `opts.on('--pdf'...)`.
  2. In `normalize_argv!(argv)`:
     Add `argv.delete('--fast')` so legacy invocations continue to succeed silently without altering behavior or advertising the flag.
  3. Reject `--pdf` as an invalid option if passed (removes the phantom choice).

---

## 3. Code Metrics & Architectural Invariants

All modified and new methods must satisfy the constraints checked by `tools/gate_audit_code`:
- **Method Length**: $\le 80$ lines (or $\le 120$ lines if cognitive complexity $\le 5$)
- **Cognitive Complexity**: $\le 15$
- **Nesting Depth**: $\le 4$

### Target Method Projections
- `LatexCLI.condensed_help`: ~22 lines, depth 0, CC 0 ($\le 15$)
- `LatexCLI.normalize_argv!`: ~15 lines, depth 2, CC 1 ($\le 15$)
- `LatexCLI.add_compilation_options_primary`: ~16 lines, depth 1, CC 1 ($\le 15$)
- `LatexCLI.add_general_options`: ~12 lines, depth 1, CC 1 ($\le 15$)
- `LatexCLI.print_help_or_examples`: ~18 lines, depth 2, CC 5 ($\le 15$)
- `LaTeXDiagnostics#report_errors`: ~18 lines, depth 1, CC 1 ($\le 15$)
- `LaTeXDiagnostics#report_error_summary`: ~16 lines, depth 1, CC 1 ($\le 15$)
- `LaTeXDiagnostics#print_summary_line`: ~11 lines, depth 1, CC 4 ($\le 15$)
- `LaTeXDiagnostics#print_diagnostics_body`: ~13 lines, depth 2, CC 2 ($\le 15$)
- `LaTeXDiagnostics#render_diagnostic_entry`: ~22 lines, depth 3, CC 6 ($\le 15$)

---

## 4. Test Strategy & Verification Plan

1. **Regression & Unit Tests**:
   - `test/test_latex_it.rb`:
     - Update `test_help_flag` to verify line count is strictly $\le 20$ lines (`assert stdout.lines.count <= 20`).
     - Verify `test_help_flag` confirms presence of curated flags and refutes removed aliases (`--lua`, `--xe`, `--pdflatex`, `--fast`, `--pdf`).
     - Add `test_help_all_flag` validating `--help-all` outputs full option parser with section headers and non-condensed options (`--deps`, `--no-env`, etc.) while excluding removed aliases.
     - Update `test_canonical_cli_flags_and_anti_alias` to verify canonical `--engine` forms and hidden aliases `--lua`, `--xe`, `--pdflatex`, `--fast`.
     - Update `test_report_errors_suppresses_warnings` to assert `report_errors` outputs exclusively to `err` (`assert_empty out`, `assert_includes err, ...`).
   - `test/test_deep_diagnostics.rb`:
     - Add `test_report_errors_writes_to_stderr_stream` testing direct invocation with custom IO streams to ensure clean stream separation.

2. **Quality Gate Verification**:
   - `tools/gate_audit_code`: Verify 100% compliance across all methods.
   - `tools/gate`: Verify fast tier tests pass cleanly with zero failures.
