# Systems Code Review Report #003 (Lens: correctness)

- **Date**: 2026-09-12
- **Auditor**: Claude / Codex (Tier 1 Standard) via `tools/audit`
- **Focus Lens**: `correctness`
- **Model Tier**: `STANDARD`
- **Backend**: `auto`
- **Scope**: `.`
- **Status**: Action Required

---

Auditing via Claude CLI (sonnet, tier: standard) [Profile: correctness]...
[SEVERITY]: Major
[LOCATION]: `lib/latex_it/flattener.rb`, `LaTeXFlattener.inline_line` (called from `inline_file`'s `chunk.lines.map { |line| inline_line(...) }` loop)
[ROOT CAUSE]: `inline_line` uses a single `line.match(/^\s*\\(?:input|include)\{([^}]+)\}(.*)$/)` per physical line and only inlines the **first** `\input`/`\include` it finds. Everything captured in the trailing `(.*)$` group (`rest`) is appended to the output verbatim — it is never re-scanned for additional `\input`/`\include` directives. Since the flattener is the sole mechanism that determines what gets bundled for `--arxiv`/`--zip` (a single self-contained `.tex` file, per the comment in `config.rb`: "Inlining of \input and \include is not optional: the staging and verification pipeline assumes a single self-contained .tex file"), any second directive on the same line silently survives as dead, unresolved LaTeX source in the flattened output, while the file it names is never staged into the submission bundle.
[FAILURE TRACE]: A source file containing a single line such as:
```latex
\input{macros}\input{content}
```
(a common pattern in generator-produced or minified `.tex` files, or simply a compact human-authored header) is flattened by `arxiv.rb#stage_arxiv_files`. `macros.tex` gets inlined correctly, but the literal text `\input{content}` remains in the flattened `.tex` written into the arXiv staging directory. `content.tex` is never read, never inlined, and never copied into the zip. The packaged arXiv submission then either fails to compile (missing file) or — worse — compiles against whatever file with that name happens to exist in the sandbox/arXiv's own tree, silently producing wrong output. This directly violates the "single self-contained .tex file" invariant the rest of the pipeline (`verify_arxiv_pdf_match`, `verify_arxiv_authors_match`) depends on.
[REMEDIATION]: Loop over all `\input`/`\include` occurrences on the line instead of only the first:
```ruby
def self.inline_line(line, base_expanded, real_base, file_dir, stack)
  line.gsub(/\\(?:input|include)\{([^}]+)\}/) do
    target = Regexp.last_match(1).strip
    target += '.tex' unless target.end_with?('.tex')
    candidate = File.expand_path(target, file_dir)
    if File.file?(candidate) && within_tree?(candidate, base_expanded, real_base)
      inline_file(candidate, base_expanded, stack)
    else
      Regexp.last_match(0)
    end
  end
end
```

[SEVERITY]: Major
[LOCATION]: `lib/latex_it/brace_checker.rb`, `LaTeXBraceChecker.scan_inverted_labels` / `scan_line_for_labels` (class-level methods used by `diagnostics.rb#collect_source_label_alerts`)
[ROOT CAUSE]: The instance-level brace scanner (`LaTeXBraceChecker#scan`) correctly tracks `@in_verbatim`/`VERBATIM_ENVS` and skips content inside `verbatim`, `lstlisting`, `minted`, etc. The separate class-level label/caption scanner (`scan_inverted_labels`, added for the Alert-tier "inverted label" / "unnumbered label" checks) has no such tracking at all — it simply strips trailing `%` comments per line and runs `LABEL_TOKEN_PATTERN` over every line of the file, including lines that are literal example code inside a verbatim-like environment.
[FAILURE TRACE]: Any document containing a LaTeX-syntax example such as:
```latex
\begin{lstlisting}
\begin{figure}[h]
  \label{fig:example}
  \caption{An example figure.}
\end{figure}
\end{lstlisting}
```
(entirely plausible for tutorial papers, this project's own generated docs, or any CS paper discussing LaTeX/figure conventions) causes `scan_inverted_labels` to push a fake `figure` float, see `\label` before `\caption`, and emit a spurious `Alert: Inverted \label Before \caption` (`alert_type: :inverted_label`, `base_color: :red`) for source text that is not a real document structure at all. Because `diagnostics.rb#fail_on_diagnostics` treats non-zero `alerts` as fatal whenever `@options[:werror]` is set, running `l -W` on such a document — which compiles perfectly correctly — aborts with exit code 1 due entirely to text inside a code listing.
[REMEDIATION]: Share the verbatim-tracking logic between both scanners, e.g. reuse the instance scanner's line classification or add equivalent tracking to the class-level pass:
```ruby
def self.scan_inverted_labels(path, content)
  alerts = []
  float_stack = []
  in_verbatim = false
  verbatim_end = nil

  content.each_line.with_index(1) do |raw_line, line_no|
    if in_verbatim
      in_verbatim = false if raw_line =~ /\\end\{#{Regexp.escape(verbatim_end)}\}/
      next
    end
    if raw_line =~ /\\begin\{(#{VERBATIM_ENVS.join('|')})\}/
      in_verbatim = true
      verbatim_end = Regexp.last_match(1)
      next
    end
    line = raw_line.sub(/(?<!\\)%.*\z/, '')
    next if line.strip.empty?

    scan_line_for_labels(line, line_no, path, float_stack, alerts)
  end
  alerts
end
```

[SEVERITY]: Moderate
[LOCATION]: `lib/latex_it/diagnostics.rb`, `LaTeXDiagnostics#count_reference_messages`
[ROOT CAUSE]: Unlike the anchored, comment-noise-filtered regexes used elsewhere in this file (per its own header comment warning that "TeX echoes the offending paragraph... verbatim"), `count_reference_messages` scans `new_content` (raw, un-anchored, not passed through `filter_subcommand_noise`) with bare `line =~ /citation/i && line =~ /undefined/i` etc. Any log line containing these words in any position — including prose from the document itself echoed back by TeX (e.g. inside an Overfull \hbox report of a paragraph discussing "the citation is undefined without a reference" or similar) — is counted as a real diagnostic.
[FAILURE TRACE]: A paper whose body text discusses bibliographic tooling (e.g. "when a citation key is undefined, LaTeX reports it") triggers an Overfull \hbox on that paragraph, and TeX echoes the paragraph text into the log. `count_reference_messages` then increments `undef_cite`, and `collect_diagnostic_counts`/`print_diagnostic_banner` reports a phantom "Undef cite" count in the diagnostic banner even though no citation is actually undefined, misleading the user during an otherwise clean build.
[REMEDIATION]: Anchor to TeX's actual message formats and filter subcommand noise first, consistent with the rest of the file:
```ruby
def count_reference_messages(new_content)
  content = LaTeXUtils.filter_subcommand_noise(new_content)
  undef_cite = content.scan(/^LaTeX Warning: Citation `.*?' .*undefined/i).size
  undef_ref  = content.scan(/^LaTeX Warning: Reference `.*?' .*undefined/i).size
  mult_def   = content.scan(/^LaTeX Warning: Label `.*?' multiply defined/i).size
  [undef_cite, undef_ref, mult_def]
end
```
