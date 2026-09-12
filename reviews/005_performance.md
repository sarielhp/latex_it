# Systems Code Review Report #005 (Lens: performance)

- **Date**: 2026-09-12
- **Auditor**: Gemini 3.8 Flash (Tier 0 Workhorse) via `tools/audit`
- **Focus Lens**: `performance`
- **Model Tier**: `TIER0`
- **Backend**: `gemini`
- **Scope**: `.`
- **Status**: Action Required

---

Auditing via Gemini Flash (bws run) [Profile: performance]...
[SEVERITY]: Major
[LOCATION]: [lib/latex_it/builder.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L1470-L1496) (`targets_up_to_date?`) and [lib/latex_it/builder.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L2231-L2240) (`update_target_file`)
[ROOT CAUSE]:
`targets_up_to_date?` performs an early invalidation check comparing `pdf_mtime = File.mtime(target_pdf)` against the mtime of all root `.tex` and `.bib` files:
```ruby
pdf_mtime = File.mtime(target_pdf)
root_files = Dir['*.tex'].select { |f| File.file?(f) } + bib_files_on_disk
return false if root_files.any? { |f| File.mtime(f) > pdf_mtime }
```
When `update_on_diff` is enabled (via `-d` or `"update_on_diff": true` in `.l.jsonc`), `update_target_file` checks `pdf_text_unchanged?(src, dst)`. When the rendered text layout is unchanged (such as after editing comments, adjusting spacing, or modifying bibliography metadata), `update_target_file` intentionally preserves the destination PDF without updating its timestamp. `save_build_state!` then records the fresh SHA256 checksums of the sources and sets `saved_at = Time.now.to_i`.

On every subsequent invocation, `targets_up_to_date?` observes that `root_files` still have an mtime newer than `pdf_mtime`. It returns `false` immediately, completely short-circuiting the SHA256 checksum cache verification. Because the subsequent build again finds identical PDF text and skips updating `target_pdf`, the project is permanently trapped in an un-cached state where every run triggers a full multi-pass compilation. Furthermore, comparing against `pdf_mtime` defeats content-addressable caching for any file touched without content modification (e.g., git checkout or `touch`).
[FAILURE TRACE]:
1. Configure `update_on_diff: true` or run with `l -d paper.tex`. Initial compilation completes, creating `paper.pdf` at timestamp $T_1$.
2. At timestamp $T_2 > T_1$, edit a comment inside `paper.tex`. The PDF text layout remains invariant.
3. Run `l -d paper.tex`. Pass 1 runs; `update_target_file` determines PDF text is unchanged and skips touching `paper.pdf` (mtime remains $T_1$). `save_build_state!` writes `junk/.build_state.json` recording `paper.tex`'s new SHA256.
4. Run `l paper.tex` again without changing any file.
5. `targets_up_to_date?` checks `root_files.any? { |f| File.mtime(f) > pdf_mtime }`. Since `paper.tex` mtime ($T_2$) > `paper.pdf` mtime ($T_1$), it returns `false`. A full 3-pass rebuild runs redundantly, and will continue to run on every future invocation.
[REMEDIATION]:
Check `root_files` modification times against `state['saved_at']` (or `File.mtime(state_file)`), and only invalidate if an untracked file was added or an mtime-modified file actually differs in SHA256:
```ruby
build_time = state['saved_at'] || (File.exist?(state_file) ? File.mtime(state_file).to_i : 0)
return false if root_files.any? do |f|
  File.mtime(f).to_i > build_time && (!sources[f] || Digest::SHA256.file(f).hexdigest != sources[f]['sha'])
end
```

---

[SEVERITY]: Moderate
[LOCATION]: [lib/latex_it/builder.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L1520-L1547) (`run_pass_iterations`), [lib/latex_it/builder.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L2142-L2145) (`compute_aux_hash`), and [lib/latex_it/builder.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L2102-L2110) (`extract_aux_bib_files`)
[ROOT CAUSE]:
During the hot compilation convergence loop, `Dir.glob('junk/**/*.aux')` and full reading of all auxiliary files via `LaTeXUtils.safe_read` are executed repeatedly within the same pass and across successive passes without caching:
1. `aux_before = compute_aux_hash` globs and reads all `.aux` files from disk before `run_latex_pass`.
2. `needs_latex_rerun?` immediately invokes `curr_aux_hash = compute_aux_hash`, re-globbing and re-reading all `.aux` files.
3. If a rerun is needed, the next loop iteration (pass $N+1$) calls `aux_before = compute_aux_hash` on line 1527, re-globbing and re-reading all `.aux` files a third time, even though no compiler process ran between the end of pass $N$ and the start of pass $N+1$.
4. `detect_bib_tool` and `extract_aux_bib_files` also perform redundant `Dir.glob('junk/**/*.aux')` traversals and disk reads.
In a 3-pass build, the `junk/` hierarchy is traversed and all `.aux` files are fully read into memory 10–12 times.
[FAILURE TRACE]:
Run `l paper.tex` on any document with multiple chapters or sub-packages (e.g. `junk/chapters/*.aux`). In pass 1, `compute_aux_hash` runs at line 1527; line 1530 calls `needs_latex_rerun?` which runs `compute_aux_hash` again; line 1536 calls `detect_bib_tool` which runs `Dir.glob('junk/**/*.aux')`; line 1537 calls `needs_bib_pass?` -> `extract_aux_bib_files` which runs `Dir.glob('junk/**/*.aux')` again. Pass 2 starts and line 1527 runs `compute_aux_hash` yet again before compiling.
[REMEDIATION]:
Thread the already-computed `curr_aux_hash` from the end of pass $N$ into pass $N+1$ as `aux_before`, and memoize the aux file list within each convergence evaluation step:
```ruby
def run_pass_iterations(max_passes, bib_ran, bib_tool)
  pass = 0
  aux_before = compute_aux_hash
  loop do
    pass += 1
    prefix = (pass == 1 && !bib_ran) ? '      ' : ', '
    print "#{prefix}#{Rainbow(@engine_name).bright} (#{pass})"

    return false unless run_latex_pass("_#{pass}")

    curr_aux_hash = compute_aux_hash
    rerun_needed = aux_before && !aux_before.empty? ? (curr_aux_hash != aux_before) : aux_has_cross_references?(curr_aux_hash)
    rerun_needed ||= latex_rerun_requested?(LaTeXUtils.safe_read("#{@pdferr}_#{pass}"))
    aux_before = curr_aux_hash
...
```

---

[SEVERITY]: Moderate
[LOCATION]: [lib/latex_it/brace_checker.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/brace_checker.rb#L1048-L1054) (`scan_inverted_labels`), [lib/latex_it/brace_checker.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/brace_checker.rb#L1151-L1156) (`scan_line`), and [lib/latex_it/meta_extractor.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/meta_extractor.rb#L5163-L5179) (`clean_latex_math`)
[ROOT CAUSE]:
Dynamic regular expressions are constructed and compiled inside inner loops without memoization or precompilation:
1. In `LaTeXBraceChecker#scan_line` and `LaTeXBraceChecker.scan_inverted_labels`, every line inside a verbatim environment executes:
```ruby
if raw_line =~ /\\end\{#{Regexp.escape(@verbatim_end)}\}/
```
Because the expression contains string interpolation, Ruby recompiles a new `Regexp` instance on every line. For a 2,000-line code listing or verbatim dataset, this compiles 2,000 identical regular expressions.
2. In `LaTeXMetaExtractor.clean_latex_math`, 82 individual symbol replacements are evaluated sequentially:
```ruby
GREEK_SYMBOLS.each { |tex, uni| str.gsub!(/\\#{tex}\b/, uni) }
MATH_SYMBOLS.each { |tex, uni| str.gsub!(/\\#{tex}\b/, uni) }
MATH_FUNCTIONS.each { |fn| str.gsub!(/\\#{fn}\b/, fn) }
```
`clean_latex_math` is invoked for every line in `parse_single_author_line` as well as on titles and abstracts, compiling 82 separate regexes and performing 82 full-string `gsub!` passes per line.
[FAILURE TRACE]:
1. A `.tex` manuscript includes source code in `\begin{lstlisting} ... \end{lstlisting}` spanning 1,500 lines. `LaTeXBraceChecker.scan` calls `scan_line` for each line, compiling `/\\end\{lstlisting\}/` 1,500 times.
2. During metadata extraction, an `\author` block containing 10 co-authors with affiliations calls `parse_single_author_line` 20 times, compiling $20 \times 82 = 1,640$ dynamic regular expressions.
[REMEDIATION]:
In `LaTeXBraceChecker`, precompile the closing regex once upon entering verbatim mode or perform a substring match:
```ruby
# In scan_line / scan_inverted_labels:
if @in_verbatim
  if raw_line.include?("\\end{#{@verbatim_end}}")
    @in_verbatim = false
    @verbatim_end = nil
  end
  return
end
```
In `LaTeXMetaExtractor`, compile a single dictionary regex at module load time:
```ruby
MATH_REPLACEMENTS = GREEK_SYMBOLS.merge(MATH_SYMBOLS).merge(MATH_FUNCTIONS.to_h { |f| [f, f] }).freeze
MATH_TOKEN_PATTERN = /\\(#{Regexp.union(MATH_REPLACEMENTS.keys).source})\b/.freeze

def self.clean_latex_math(text)
  return '' if text.nil?
  str = text.dup
  str.gsub!(MATH_TOKEN_PATTERN) { MATH_REPLACEMENTS[Regexp.last_match(1)] }
  str.gsub!(/\\(?:mathbb|mathcal|mathfrak)\{([A-Za-z])\}/, '\1')
  str.gsub!(/\\sqrt\{([^}]+)\}/, '√(\1)')
  str.delete('$')
end
```

---

[SEVERITY]: Moderate
[LOCATION]: [lib/latex_it/flattener.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/flattener.rb#L4972-L4988) (`inline_comment_index`)
[ROOT CAUSE]:
`inline_comment_index` scans each line character-by-character to locate unescaped `%` comment characters. On every single index `i`:
```ruby
while i < len
  c = line[i]
  if line[i..].start_with?('\\url{', '\\href{')
```
`line[i..]` allocates a brand new String slice representing the remainder of the line on every iteration, even when `c` is not `\`. In a document containing 15,000 lines with an average length of 70 characters, this results in over 1,000,000 heap string allocations per pass of `inline_comment_index`. Because `inline_comment_index` is called by `inline_line` across all files during flattening and again by `strip_comment_chunk` across all lines during comment stripping, this generates millions of short-lived allocations in a hot character loop.
[FAILURE TRACE]:
Run `l --arxiv` on a document with 10,000 lines across nested `\input` files. `LaTeXFlattener.flatten` runs `inline_file` followed by `strip_comments`. `inline_comment_index` executes over 1.4 million string slice allocations, inducing high GC pressure and memory churn.
[REMEDIATION]:
Guard the prefix check so it only executes when `c == '\\'`, and check fixed-length substrings or character lookahead without slicing to the end of the line:
```ruby
def self.inline_comment_index(line)
  in_url = false
  i = 0
  len = line.length
  while i < len
    c = line[i]
    if c == '\\' && (line[i, 5] == '\\url{' || line[i, 6] == '\\href{')
      in_url = true
    elsif in_url && c == '}'
      in_url = false
    elsif c == '%' && !in_url
      return i if preceding_backslash_count(line, i).even?
    end
    i += 1
  end
  nil
end
```
