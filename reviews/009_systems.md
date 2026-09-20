# Systems Code Review Report #009 (Lens: systems)

- **Date**: 2026-09-19
- **Auditor**: Gemini 3.8 Flash (Tier 0 Workhorse) via `tools/audit`
- **Focus Lens**: `systems`
- **Model Tier**: `TIER0`
- **Backend**: `gemini`
- **Scope**: `lib latex_it`
- **Status**: Action Required

---

Auditing via Gemini Flash (bws run) [Profile: systems]...
[SEVERITY]: Critical
[LOCATION]: lib/latex_it/builder.rb:702-715 (`LatexBuilder#build_latex_pass_cmd`)
[ROOT CAUSE]: Subprocess argument corruption leading to immediate compiler process crash. In `build_latex_pass_cmd`, `latexopts` and `latexoptions` from `ENV['LATEXOPTS']` or `ENV['LATEXOPTIONS']` (typically used to specify CLI options like `-shell-escape`) are string-interpolated directly into `cfilename` (`"#{latexoptions} #{RUNTIME_HOOK}\\input{#{@filename}}"`). The resulting string is passed as the final element of the `cmd_args` array: `[@engine_name] + @latex_flags + [cfilename]`. Because `capture_pass_output` executes `Open3.popen2e` / `Process.spawn` without a shell, TeX engines (`pdflatex`, `xelatex`, `lualatex`) receive `"-shell-escape \makeatletter..."` as a single `argv` string. The engines reject this option with `unrecognized option` or fail to open the file and terminate immediately with exit code 1.
[FAILURE TRACE]:
1. User exports `LATEXOPTIONS="-shell-escape"` to compile documents using minted, tikz externalize, or pstricks.
2. User executes `latex_it paper.tex`.
3. `build_latex_pass_cmd` sets `cfilename = "-shell-escape \\makeatletter...\\input{paper.tex}"`.
4. `capture_pass_output` spawns `["xelatex", "-interaction=nonstopmode", ..., "-shell-escape \\makeatletter...\\input{paper.tex}"]`.
5. Engine aborts on pass 1: `xelatex: unrecognized option '-shell-escape \makeatletter...' (Status: 1)`. Standard compilation fails completely.
[REMEDIATION]:
```ruby
require 'shellwords'

def build_latex_pass_cmd
  latexopts = ENV['LATEXOPTS'] || ''
  latexoptions = ENV['LATEXOPTIONS'] || ''
  combined = "#{latexopts} #{latexoptions}".strip
  tokens = combined.empty? ? [] : Shellwords.split(combined)

  extra_flags = tokens.reject { |tok| tok.start_with?('\\') }
  tex_prefixes = tokens.select { |tok| tok.start_with?('\\') }.join(' ')

  cfilename = "#{tex_prefixes}#{RUNTIME_HOOK}\\input{#{@filename}}"
  [@engine_name] + extra_flags + @latex_flags + [cfilename]
end
```

---

[SEVERITY]: Major
[LOCATION]: lib/latex_it/builder.rb:110-113, lib/latex_it/builder.rb:334-335, and lib/latex_it/builder.rb:967-982 (`LatexBuilder#execute_compile_pipeline`, `snapshot_build_inputs!`, `needs_bib_pass?`)
[ROOT CAUSE]: Premature cache file deletion causing broken multi-pass convergence and skipped bibliography regeneration.
In `execute_compile_pipeline`, line 110 executes `FileUtils.rm_f('junk/.build_state.json')`. Line 113 then calls `snapshot_build_inputs!`, which attempts to read `junk/.build_state.json` (line 334) to restore `@last_bib_citations ||= state['citations']`. Because the file was just unlinked, `state` is always `nil`, leaving `@last_bib_citations` permanently `nil` on every build run.
Consequently, in `needs_bib_pass?` (line 979), `return true if @last_bib_citations && current_cites != @last_bib_citations` cannot evaluate to true. Furthermore, `needs_bib_pass?` ignores its `loga` parameter and never inspects the LaTeX run log for undefined citation warnings (`LaTeX Warning: Citation ... undefined`). Since `sync_bbl_before_compile` preserves an existing `paper.bbl` into `junk/paper.bbl`, `File.exist?(fnbbl)` is true. If `.bib` files were not modified after `paper.bbl`, `needs_bib_pass?` returns `false`, skipping BibTeX/Biber entirely.
[FAILURE TRACE]:
1. Build `paper.tex` with citation `\cite{knuth1984}`. Compilation succeeds, generating `paper.bbl` and `junk/.build_state.json`.
2. Add a second citation `\cite{lamport1994}` to `paper.tex`, where `lamport1994` is already present in `refs.bib` (so `refs.bib` mtime is unchanged).
3. Run `latex_it paper.tex`.
4. `execute_compile_pipeline` unlinks `junk/.build_state.json` at line 110. `snapshot_build_inputs!` at line 113 finds no file; `@last_bib_citations` is `nil`.
5. Pass 1 runs. LaTeX logs `LaTeX Warning: Citation 'lamport1994' on page 1 undefined`.
6. `needs_bib_pass?` checks `fnbbl` (exists), `.bib` mtimes (not newer than `.bbl`), and `@last_bib_citations` (`nil`). It returns `false`.
7. Neither BibTeX nor Biber runs. Passes 2 and 3 finalize without resolving `lamport1994`, producing a final PDF containing unresolved `[?]` references.
[REMEDIATION]:
```ruby
# In lib/latex_it/builder.rb: execute_compile_pipeline
def execute_compile_pipeline
  setup_environment
  deep_clean if @options[:clean]
  paper_cleanup

  if targets_up_to_date?
    puts "      #{Rainbow("All targets (#{@bfilename}.pdf) are up-to-date.").green} (Use 'l -f' to force rebuild)"
    analyze_output if diagnostics_requested?
    return true
  end

  snapshot_build_inputs!
  FileUtils.rm_f('junk/.build_state.json')
  clean_pass_logs
  junk_dir_create
  total_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @options[:time]
  # ...
end

# In lib/latex_it/builder.rb: needs_bib_pass?
def needs_bib_pass?(tool, loga, aux_contents = nil)
  return false if @options[:bib] == false
  return true if @options[:bib] == true

  fnbbl = "junk/#{@bfilename}.bbl"
  return true unless File.exist?(fnbbl)

  log_content = LaTeXUtils.safe_read(loga)
  return true if log_content =~ /LaTeX Warning: Citation\s+[`'"].*?['"]\s+.*undefined/i ||
                 log_content =~ /Package biblatex Warning: Please \(re\)run Biber/i

  bbl_mtime = File.mtime(fnbbl)
  bib_files = discover_bib_files(aux_contents)
  return true if bib_files.any? { |b| File.mtime(b) > bbl_mtime }

  current_cites = current_citation_keys(aux_contents)
  return true if @last_bib_citations && current_cites != @last_bib_citations

  false
end
```

---

[SEVERITY]: Major
[LOCATION]: lib/latex_it/builder.rb:945 (`LatexBuilder#execute_bibliography`) & lib/latex_it/compatibility.rb:13-23 (`LaTeXCompatibility.source_needs_revtex4?`)
[ROOT CAUSE]: Process-global working directory mutation before dynamic environment resolution, causing missing vendor environment variables.
In `execute_bibliography`:
```ruby
Dir.chdir('junk') { capture_pass_output(cmd) }
```
`Dir.chdir` modifies the working directory of the Ruby process to `junk/`. Inside `capture_pass_output`, `pass_environment` is evaluated dynamically, invoking `LaTeXCompatibility.compiler_environment(@options, ENV.to_h, @filename)`. In `LaTeXCompatibility.source_needs_revtex4?(@filename)`, line 16 performs `File.file?(path_or_content.to_s)`. Because the current directory is `junk/`, `File.file?("paper.tex")` checks `junk/paper.tex`, which does not exist (the file is in `.`).
Consequently, `source_needs_revtex4?` returns `false`, and `compiler_environment` fails to inject the vendor `revtex4` directory into `TEXINPUTS`. When `bibtex` runs inside `junk/`, it cannot locate REVTeX 4 bibliography style files (e.g. `apsrev.bst`, `apsrmp.bst`), causing BibTeX to fail fatally.
[FAILURE TRACE]:
1. A manuscript uses `\documentclass{revtex4}` and `\bibliographystyle{apsrev}`.
2. Run `latex_it paper.tex`.
3. Pass 1 completes. `execute_bibliography(:bibtex)` changes working directory to `junk/`.
4. `capture_pass_output` evaluates `pass_environment`. `source_needs_revtex4?("paper.tex")` checks `junk/paper.tex`, returns `false`.
5. `TEXINPUTS` is not set with the vendor REVTeX 4 path.
6. `bibtex paper` runs and crashes: `I couldn't open style file apsrev.bst` (`err_bib`).
[REMEDIATION]:
```ruby
def execute_bibliography(tool)
  discover_bib_files.each do |b|
    target = File.join('junk', File.basename(b))
    FileUtils.cp(b, target) unless File.expand_path(b) == File.expand_path(target)
  end
  cmd = if tool == :biber
          ['biber', '--output_safechars', '--input-directory', '.', '--output-directory', '.', @bfilename]
        else
          copy_style_files_for_bibtex
          ['bibtex', @bfilename]
        end
  env = pass_environment
  Dir.chdir('junk') do
    timeout = (@options[:timeout] || ENV['LATEX_IT_TIMEOUT'] || DEFAULT_PASS_TIMEOUT).to_i
    timeout <= 0 ? Open3.capture2e(env, *cmd) : capture_with_timeout(env, cmd, timeout)
  end
end
```

---

[SEVERITY]: Major
[LOCATION]: lib/latex_it/builder.rb:883-889 (`LatexBuilder#preserve_bibliography_backup`)
[ROOT CAUSE]: Build artifact pollution leaking outside `junk/` isolation into the project working tree.
In `preserve_bibliography_backup`:
```ruby
def preserve_bibliography_backup(previous, root_bbl)
  return unless previous

  backup = "#{root_bbl}.bak"
  FileUtils.cp(previous, backup)
  FileUtils.cp(previous, "junk/#{File.basename(backup)}")
end
```
Whenever a previous `.bbl` exists and a bibliography pass is executed, the method creates `#{@bfilename}.bbl.bak` directly in the project root directory. If compilation succeeds, this file is never removed or cleaned up, permanently leaving intermediate backup junk in the user's workspace and violating intermediate file isolation.
[FAILURE TRACE]:
1. User compiles a manuscript containing citations.
2. On any subsequent compile where `run_bib_pass` executes, `preserve_bibliography_backup` copies the existing `.bbl` to `paper.bbl.bak` in the document root.
3. Build completes cleanly. `git status` shows an untracked, dirty file `paper.bbl.bak` outside `junk/`.
[REMEDIATION]:
```ruby
def preserve_bibliography_backup(previous, root_bbl)
  return unless previous

  backup = "junk/#{File.basename(root_bbl)}.bak"
  FileUtils.cp(previous, backup)
end

def restore_bibliography(junk_bbl, previous)
  return FileUtils.rm_f(junk_bbl) unless previous

  backup = "junk/#{@bfilename}.bbl.bak"
  source = File.file?(backup) ? backup : previous
  FileUtils.cp(source, junk_bbl) unless source == junk_bbl
end
```

---

[SEVERITY]: Major
[LOCATION]: lib/latex_it/builder.rb:269-272 (`LatexBuilder#run_index_pass`)
[ROOT CAUSE]: Destructive overwrite and corruption of the native compiler index log file (`.ilg`).
In `run_index_pass`:
```ruby
cmd = ['makeindex', '-q', "#{@bfilename}.idx"]
out, status = Dir.chdir('junk') { capture_pass_output(cmd) }
File.write("junk/#{@bfilename}.ilg", out) unless out.empty?
```
When `makeindex` runs inside `junk/`, it automatically creates `<bfilename>.ind` and `<bfilename>.ilg` (the index transcript log containing entry stats, line references, and rejected key warnings). `capture_pass_output` captures makeindex's process stdout/stderr. If makeindex emits any banner, summary, or warnings to stderr/stdout, line 271 executes `File.write("junk/#{@bfilename}.ilg", out)`, which completely truncates and overwrites the real transcript log generated by `makeindex`, replacing diagnostic line details with process stream output.
[FAILURE TRACE]:
1. Manuscript index contains invalid formatting or duplicate entries generating makeindex warnings.
2. `makeindex` writes diagnostic line errors (e.g. `## Warning (input = paper.idx, line = 12): -- Extra '|' ...`) into `junk/paper.ilg`.
3. `capture_pass_output` captures makeindex stderr summary into `out`.
4. Line 271 executes `File.write("junk/#{@bfilename}.ilg", out)`, truncating the `.ilg` file and discarding the exact line diagnostics.
[REMEDIATION]:
```ruby
cmd = ['makeindex', '-q', "#{@bfilename}.idx"]
out, status = Dir.chdir('junk') { capture_pass_output(cmd) }
File.open("junk/#{@bfilename}.ilg", 'a') { |f| f.write("\n#{out}") } if !out.empty? && File.file?("junk/#{@bfilename}.ilg")
File.write("junk/#{@bfilename}.ilg", out) if !out.empty? && !File.file?("junk/#{@bfilename}.ilg")
```

---

[SEVERITY]: Major
[LOCATION]: lib/latex_it/builder.rb:523-541 (`LatexBuilder#resolve_engine`)
[ROOT CAUSE]: In-file compiler engine directives overridden by heuristics due to missing explicit flag tracking.
In `resolve_engine`:
`file_engine` accurately parses in-file magic comments such as `% !TEX program = lualatex`. However, the compatibility guard at line 532 only checks `@options[:engine_explicit]`, which is only set when `-e` / `--engine` is passed on the CLI. If a user sets `% !TEX program = lualatex` (or `xelatex`) in their document, and the file contains EPS graphics or `inputenc`, `resolve_engine` treats the engine choice as non-explicit and forcibly overrides it to `pdflatex` via `compatible_engine`.
[FAILURE TRACE]:
1. A user writes `paper.tex` with `% !TEX program = lualatex`, uses `\usepackage{fontspec}`, and includes `\includegraphics{figure.eps}`.
2. User runs `latex_it paper.tex`.
3. `resolve_engine` detects `file_engine = 'lualatex'`, but `@options[:engine_explicit]` is `false`.
4. `source_pdflatex_reasons` detects EPS graphics.
5. Line 536 triggers: `resolve_engine` selects `pdflatex` automatically.
6. `pdflatex` compiles `paper.tex` and aborts immediately: `! Fatal fontspec error: "cannot-use-pdftex"`.
[REMEDIATION]:
```ruby
def resolve_engine
  raw_source = LaTeXUtils.safe_read(@filename)
  magic_engine = LaTeXUtils.detect_engine_from_magic_comments(raw_source)
  file_engine = magic_engine || LaTeXUtils.detect_engine_from_auctex(raw_source) ||
                (LaTeXUtils.active_source_needs_lualatex?(raw_source) ? 'lualatex' : nil) ||
                (LaTeXUtils.active_source_needs_pdflatex?(raw_source) ? 'pdflatex' : nil)

  candidate_engine = @options[:engine] || ENV['PDFBINONLY'] || file_engine ||
                     @options[:config_engine] || ENV['PDFBIN'] || ENV['LATEX_ENGINE'] || 'xelatex'
  requested_engine = LaTeXUtils.normalize_engine(candidate_engine)
  pdflatex_reasons = LaTeXUtils.source_pdflatex_reasons(@filename)
  incompatible = %w[xelatex lualatex].include?(requested_engine) && !pdflatex_reasons.empty?
  reason = pdflatex_reasons.join(' and ')

  explicit = @options[:engine_explicit] || !magic_engine.nil?
  if incompatible && explicit
    puts Rainbow(" -- Source uses #{reason}; #{requested_engine} may fail. Recommended: -e pdflatex").yellow
    requested_engine
  elsif incompatible
    puts Rainbow(" -- Source uses #{reason}; selecting pdflatex automatically.").cyan
    LaTeXUtils.compatible_engine(requested_engine, @filename)
  else
    requested_engine
  end
end
```

---

[SEVERITY]: Moderate
[LOCATION]: lib/latex_it/config.rb:287-304 (`LaTeXConfig.save_settings!`)
[ROOT CAUSE]: Non-atomic configuration file overwrite risking permanent config file corruption.
In `save_settings!`:
```ruby
File.write(target_file, content)
```
The method writes updated JSONC settings directly to `target_file` (`~/.config/latex_it/config.jsonc` or `.l.jsonc`) using `File.write`. `File.write` truncates the file upon open (`O_TRUNC`). If execution is interrupted by a signal (`SIGINT`, `SIGTERM`) or abnormal termination during the write, the configuration file is left empty or corrupted.
[FAILURE TRACE]:
1. User invokes `latex_it --config-save ...`.
2. `save_settings!` opens `~/.config/latex_it/config.jsonc`, truncating it to 0 bytes.
3. User presses `Ctrl-C` or the process receives `SIGTERM`.
4. `~/.config/latex_it/config.jsonc` is left corrupted or empty, breaking all subsequent `latex_it` runs.
[REMEDIATION]:
```ruby
require 'tempfile'

def self.save_settings!(settings, target_file)
  dir = File.dirname(target_file)
  FileUtils.mkdir_p(dir)
  content = File.exist?(target_file) ? File.read(target_file) : DEFAULT_CONFIG_TEMPLATE.dup

  settings.each do |k, v|
    if k == 'zip' && v.is_a?(Hash)
      v.each { |zk, zv| content = update_jsonc_key(content, zk, zv) }
    else
      content = update_jsonc_key(content, k, v)
    end
  end

  Tempfile.create(['.config_', '.jsonc'], dir) do |tmp|
    tmp.write(content)
    tmp.flush
    FileUtils.mv(tmp.path, target_file)
  end
  true
rescue StandardError => e
  warn " -- Warning: Could not persist settings to #{target_file}: #{e.message}"
  false
end
```

---

[SEVERITY]: Moderate
[LOCATION]: lib/latex_it/builder.rb:644-653 (`LatexBuilder#capture_with_timeout`)
[ROOT CAUSE]: Total loss of compiler stream buffer on process timeout.
In `capture_with_timeout`:
```ruby
output = +''
reader = Thread.new { output = stdout_err.read }
begin
  unless wait_thr.join(timeout)
    kill_process_group(wait_thr.pid)
    reader.kill rescue nil
    msg = "\n! LaTeX Error: Compilation timed out after #{timeout}s (suspected runaway loop).\n"
    return [msg, ProcessResultStatus.new(124, false, nil, false)]
  end
```
The reader thread issues a single blocking `stdout_err.read`. If the compilation process times out, `reader.kill` is called before `stdout_err.read` returns EOF. Because `output` was never assigned, the entire stdout/stderr produced by the compiler up to the timeout is dropped. The timeout error message is returned with zero log context, preventing users or diagnostic analyzers from inspecting where the compilation stalled.
[FAILURE TRACE]:
1. A document contains an infinite loop macro or runaway counter. The compiler outputs 2,000 lines of trace diagnostics before stalling.
2. The pass hits `DEFAULT_PASS_TIMEOUT` (180s).
3. `capture_with_timeout` kills the process group and calls `reader.kill`.
4. `output` remains `""`. All 2,000 diagnostic lines are discarded. `junk/err_<engine>_1` receives only the timeout message without any compiler trace.
[REMEDIATION]:
```ruby
output = +''
reader = Thread.new do
  until stdout_err.eof?
    chunk = stdout_err.read(4096)
    output << chunk if chunk
  end
rescue StandardError
  nil
end
```
