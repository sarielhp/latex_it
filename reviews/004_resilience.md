# Systems Code Review Report #004 (Lens: resilience)

- **Date**: 2026-09-12
- **Auditor**: Gemini 3.8 Flash (Tier 0 Workhorse) via `tools/audit`
- **Focus Lens**: `resilience`
- **Model Tier**: `TIER0`
- **Backend**: `gemini`
- **Scope**: `.`
- **Status**: Action Required

---

Auditing via Gemini Flash (bws run) [Profile: resilience]...
[SEVERITY]: Major
[LOCATION]: `lib/latex_it/builder.rb:563-570`
[ROOT CAUSE]: Technical explanation of invariant breakdown
In `LatexBuilder#run_latex_pass`, the subprocess exit status is extracted via `status.exitstatus || 0`. When a compiler engine (e.g. `xelatex`, `lualatex`, `pdflatex`) crashes due to a fatal signal (such as `SIGSEGV`, `SIGBUS`, `SIGABRT`, or `SIGKILL` triggered by memory exhaustion, broken C extensions in `xdvipdfmx`, or invalid Lua scripts in LuaTeX), `Process::Status#exitstatus` returns `nil` because `status.signaled?` is true. Defaulting `nil` to `0` assigns `st = 0`, misleading subsequent error checks into treating the fatal crash as a successful zero exit code. `handle_pass_errors(st, lgx)` then passes `st = 0` to `count_errors_in_log(st, lgx)`, which evaluates to `0 + 0 = 0` if the engine died before emitting standard TeX log error lines. Consequently, `handle_pass_errors` returns without printing any error message, and the build loop terminates abruptly with zero diagnostic feedback to the user.
[FAILURE TRACE]: Concrete sequence, input, or conditions required to trigger the bug
1. Run compilation on a document that causes the TeX engine or driver to segfault (e.g., corrupted font file under XeLaTeX or LuaTeX memory limit exceeded).
2. The engine aborts immediately on signal 11 (`SIGSEGV`).
3. `capture_pass_output` returns the process status with `exitstatus: nil`, `termsig: 11`.
4. Line 564 evaluates `st = status.exitstatus || 0` => `st = 0`.
5. Line 567 checks `if st > 0` (false, so no exit status is logged).
6. Line 569 calls `handle_pass_errors(0, lgx)`, which finds 0 TeX error lines and returns silently.
7. Line 576 returns `false`, aborting the build without any crash or error report.
[REMEDIATION]: Minimal, idiomatic code snippet resolving the defect
```ruby
    stdout_stderr, status = capture_pass_output(cmd_args)
    st = status.exitstatus || (status.termsig ? 128 + status.termsig : 1)

    File.open(lgx, 'a') { |f| f.write(stdout_stderr) }
    if status.signaled?
      warn "\nLaTeX engine terminated by signal #{status.termsig} (fatal crash).\n"
    elsif st > 0
      puts "\nLaTeX process exited with status: #{st}\n"
    end

    handle_pass_errors(st, lgx)
```

---

[SEVERITY]: Major
[LOCATION]: `lib/latex_it/builder.rb:88-96` and `lib/latex_it/builder.rb:455`
[ROOT CAUSE]: Technical explanation of invariant breakdown
`LatexBuilder#setup_environment` is invoked unconditionally at the beginning of `execute_compile_pipeline`, prior to evaluating `targets_up_to_date?`. In `setup_environment` (line 455), the method unlinks all previous log and diagnostic files:
```ruby
FileUtils.rm_f([@log, @loga, @biberr, @pdferr, "#{@pdferr}_1", "#{@pdferr}_2", "#{@pdferr}_3"])
```
When `targets_up_to_date?` subsequently evaluates to `true`, the build returns early. If the user requested diagnostics (`l -a`, `l -e`, `l -v`, or `l --emacs`), line 94 invokes `analyze_output if diagnostics_requested?`. However, `find_last_latex_log` attempts to inspect `_3`, `_2`, `_1`, and `@pdferr`, all of which were just deleted by `setup_environment`. `analyze_output` reads an empty string, silently swallowing and erasing all cached warnings, errors, and AUCTeX diagnostics.
[FAILURE TRACE]: Concrete sequence, input, or conditions required to trigger the bug
1. Compile a document containing LaTeX warnings: `l paper.tex`. Build finishes and generates `junk/err_xelatex_1`.
2. Re-run `l -a paper.tex` (or `l -e` / `l --emacs`) to inspect warnings on the up-to-date document.
3. `setup_environment` runs first and deletes `junk/err_xelatex_1`.
4. `targets_up_to_date?` verifies hash matches and returns `true`.
5. `analyze_output` runs, calls `find_last_latex_log`, finds no log files, and reads `""`.
6. Zero warnings are reported, defeating the purpose of the `-a` / `--emacs` flags on cached builds.
[REMEDIATION]: Minimal, idiomatic code snippet resolving the defect
Do not wipe log artifacts in `setup_environment`. Defer log cleanup until after `targets_up_to_date?` has determined that an actual recompilation pass is required:
```ruby
  # In lib/latex_it/builder.rb
  def execute_compile_pipeline
    setup_environment
    deep_clean if @options[:clean]
    paper_cleanup

    if targets_up_to_date?
      puts "      #{Rainbow("All targets (#{@bfilename}.pdf) are up-to-date.").green} (Use 'l -1' to force rebuild)"
      analyze_output if diagnostics_requested?
      return true
    end

    FileUtils.rm_f('junk/.build_state.json')
    FileUtils.rm_f([@log, @loga, @biberr, @pdferr, "#{@pdferr}_1", "#{@pdferr}_2", "#{@pdferr}_3"])
    junk_dir_create
    snapshot_build_inputs!
    # ...
```

---

[SEVERITY]: Major
[LOCATION]: `lib/latex_it/builder.rb:779-794`
[ROOT CAUSE]: Technical explanation of invariant breakdown
While LaTeX engine passes are guarded by `DEFAULT_PASS_TIMEOUT` (180s) inside `capture_pass_output`, bibliography generation in `execute_bibliography` directly delegates to `Open3.capture2e('biber', ...)` and `Open3.capture2e('bibtex', ...)` without any timeout guard. Biber (a Perl application) regularly resolves network URIs (e.g. `@online` data sources) and is susceptible to indefinite hangs on unreachable hosts, DNS hangs, cyclic cross-reference inheritance, or catastrophic backtracking on malformed entries. Without a per-operation timeout guard, a stalled bibliography tool hangs the entire `latex_it` build process indefinitely.
[FAILURE TRACE]: Concrete sequence, input, or conditions required to trigger the bug
1. A bibliography contains an entry with a remote datasource or malformed cross-reference that triggers network wait or a Perl regex spin in `biber`.
2. `LatexBuilder#run_pass_iterations` triggers `run_bib_pass(:biber)`.
3. `execute_bibliography` calls `Open3.capture2e('biber', ...)`.
4. `biber` blocks indefinitely.
5. The build hangs permanently with no timeout trigger, no process termination, and no error message.
[REMEDIATION]: Minimal, idiomatic code snippet resolving the defect
Route bibliography command executions through a timeout-guarded runner (or reuse `capture_pass_output` with directory isolation):
```ruby
  def execute_bibliography(tool)
    discover_bib_files.each { |b| FileUtils.cp(b, 'junk/') }
    cmd = if tool == :biber
            ['biber', '--output_safechars', '--input-directory', '.', '--output-directory', '.', @bfilename]
          else
            if File.directory?('../styles')
              FileUtils.mkdir_p('styles')
              Dir['../styles/*'].each { |s| FileUtils.cp_r(s, 'styles/') unless File.basename(s) == 'junk' }
            end
            ['bibtex', @bfilename]
          end
    Dir.chdir('junk') do
      capture_pass_output(cmd)
    end
  end
```

---

[SEVERITY]: Major
[LOCATION]: `lib/latex_it/builder.rb:535-550`
[ROOT CAUSE]: Technical explanation of invariant breakdown
`capture_pass_output` contains two critical subprocess management defects:
1. `_stdin` pipe is left open: `Open3.popen2e(env, *cmd_args) do |_stdin, stdout_err, wait_thr|` never closes `_stdin`. If TeX encounters an error or package macro requesting interactive input (`\typein`, `\read 16`, or terminal prompt on missing file when nonstopmode fails), it blocks on standard input. Because `_stdin` remains open in the parent Ruby process, EOF is never delivered, causing the engine to hang for the full 180 seconds rather than aborting immediately.
2. Subprocess group leak: `Process.kill('KILL', wait_thr.pid)` kills only the direct PID. TeX engines spawn auxiliary subprocesses (e.g. `xelatex` spawns `xdvipdfmx`, `pdflatex` spawns `kpathsea`/`mktexpk` or `\write18` shell-escaped utilities). Because the child was not spawned in its own process group (`pgroup: true`), killing `wait_thr.pid` leaves orphaned child processes running indefinitely at 100% CPU.
[FAILURE TRACE]: Concrete sequence, input, or conditions required to trigger the bug
1. A document contains `\typein[\answer]{Enter value:}` or includes a package that prompts for missing input on standard input.
2. `capture_pass_output` executes `popen2e`. `_stdin` is kept open.
3. TeX pauses waiting for input from the pipe. EOF is never received.
4. The process stalls for 180 seconds until `wait_thr.join(timeout)` triggers timeout kill.
5. If `xelatex` was executing `xdvipdfmx`, killing only `wait_thr.pid` leaves `xdvipdfmx` orphaned.
[REMEDIATION]: Minimal, idiomatic code snippet resolving the defect
```ruby
    Open3.popen2e(env, *cmd_args, pgroup: true) do |stdin, stdout_err, wait_thr|
      stdin.close rescue nil
      output = ''
      reader = Thread.new { output = stdout_err.read }
      unless wait_thr.join(timeout)
        begin
          pgid = Process.getpgid(wait_thr.pid)
          Process.kill('-KILL', pgid)
        rescue StandardError
          Process.kill('KILL', wait_thr.pid) rescue nil
        end
        reader.kill rescue nil
        msg = "\n! LaTeX Error: Compilation timed out after #{timeout}s (suspected runaway loop).\n"
        return [msg, Struct.new(:exitstatus, :success?).new(124, false)]
      end
      reader.join
      [output, wait_thr.value]
    end
```

---

[SEVERITY]: Major
[LOCATION]: `lib/latex_it/builder.rb:734-740`
[ROOT CAUSE]: Technical explanation of invariant breakdown
In `LatexBuilder#preserve_bibliography_backup`:
```ruby
  def preserve_bibliography_backup(previous, root_bbl)
    return unless previous

    backup = "#{root_bbl}.bak"
    FileUtils.cp(previous, backup)
    FileUtils.cp(previous, "junk/#{File.basename(backup)}")
  end
```
The method writes `backup = "#{root_bbl}.bak"` directly into the user's project root directory (e.g. `paper.bbl.bak`). Neither `paper_cleanup` (lines 514-522) nor `finalize_build_outputs` cleans up `#{root_bbl}.bak`. Consequently, every compilation with a bibliography pass leaks an intermediate backup artifact into the project root, breaking the architectural invariant defined in `lib/latex_it/utils.rb:17` that all scratch and intermediate build files must remain isolated under `junk/`.
[FAILURE TRACE]: Concrete sequence, input, or conditions required to trigger the bug
1. Place a `.tex` document with citations in a clean git repository.
2. Compile with `l paper.tex`.
3. `run_bib_pass` calls `preserve_bibliography_backup`.
4. `paper.bbl.bak` is written to the root directory.
5. Check `git status`: `paper.bbl.bak` is left behind as an untracked, leaked intermediate file.
[REMEDIATION]: Minimal, idiomatic code snippet resolving the defect
Confine the backup file strictly to `junk/`:
```ruby
  def preserve_bibliography_backup(previous, root_bbl)
    return unless previous

    FileUtils.cp(previous, "junk/#{File.basename(root_bbl)}.bak")
  end

  def restore_bibliography(junk_bbl, previous)
    unless previous
      FileUtils.rm_f(junk_bbl)
      return
    end

    backup = "junk/#{@bfilename}.bbl.bak"
    source = File.file?(backup) ? backup : previous
    FileUtils.cp(source, junk_bbl) unless source == junk_bbl
  end
```

---

[SEVERITY]: Moderate
[LOCATION]: `lib/latex_it/arxiv.rb:181-184`
[ROOT CAUSE]: Technical explanation of invariant breakdown
In `LatexArxivPackager#stage_biblatex_shield`, when harvesting core biblatex files, the method executes:
```ruby
path, stat = Open3.capture2('kpsewhich', core)
```
Unlike external dependencies such as `zip`, `unzip`, `pdftotext`, and `pdftoppm`, which are explicitly checked with `LaTeXUtils.command_available?` before invocation, `kpsewhich` is neither validated for availability in `PATH` nor wrapped in an exception handler. If `kpsewhich` is missing or unexecutable, `Open3.capture2` raises an unhandled `Errno::ENOENT`, causing the arXiv packaging process to crash with an unhandled Ruby stack trace.
[FAILURE TRACE]: Concrete sequence, input, or conditions required to trigger the bug
1. Run `latex_it --arxiv paper.tex` on a system where BibLaTeX is used but TeX utilities are in a restricted PATH missing `kpsewhich` (or in a minimal container).
2. `stage_biblatex_shield` is reached.
3. `Open3.capture2('kpsewhich', core)` raises `Errno::ENOENT`.
4. The packaging command crashes immediately with an uncaught exception.
[REMEDIATION]: Minimal, idiomatic code snippet resolving the defect
```ruby
    %w[biblatex.sty biblatex.cfg standard.bbx english.lbx].each do |core|
      if harvested.none? { |h| File.basename(h) == core }
        next unless LaTeXUtils.command_available?('kpsewhich')

        begin
          path, stat = Open3.capture2('kpsewhich', core)
          harvested << path.strip if stat.success? && File.file?(path.strip)
        rescue SystemCallError => e
          warn Rainbow(" -- Warning: kpsewhich execution failed: #{e.message}").yellow
        end
      end
    end
```

---

[SEVERITY]: Moderate
[LOCATION]: `lib/latex_it/arxiv.rb:92-96`
[ROOT CAUSE]: Technical explanation of invariant breakdown
In `LaTeXFlattener.inline_file` (`lib/latex_it/flattener.rb:65`), when a cyclic input reference is detected, it raises a `RuntimeError`:
```ruby
raise "Cyclic LaTeX input detected: #{chain}"
```
`LatexArxivPackager#stage_arxiv_files` calls `LaTeXFlattener.flatten` without rescuing this exception. The uncaught exception bubbles up through `do_package` and crashes `latex_it` with a Ruby backtrace instead of failing cleanly, reporting an actionable diagnostic, and properly cleaning up or preventing the creation of invalid packages.
[FAILURE TRACE]: Concrete sequence, input, or conditions required to trigger the bug
1. Create `main.tex` that includes `chapter1.tex`, which accidentally includes `main.tex` via `\input{main.tex}`.
2. Run `l --arxiv main.tex`.
3. `stage_arxiv_files` invokes `LaTeXFlattener.flatten`.
4. `LaTeXFlattener` raises `RuntimeError: Cyclic LaTeX input detected: ...`.
5. `latex_it` crashes with an unhandled exception trace.
[REMEDIATION]: Minimal, idiomatic code snippet resolving the defect
```ruby
  def stage_arxiv_files(stage_dir)
    flattened_tex = begin
      LaTeXFlattener.flatten(@filename, '.', @options[:strip_host_patterns],
                             strip_comments: @options[:strip_comments] != false)
    rescue StandardError => e
      warn Rainbow("[FAIL] Could not flatten LaTeX source: #{e.message}").red.bright
      return false
    end
    File.write(File.join(stage_dir, @filename), flattened_tex)
    # ...
```
And check the return status in `do_package`:
```ruby
    Dir.mktmpdir('latex_it_arxiv_stage_') do |stage_dir|
      return false unless stage_arxiv_files(stage_dir)
      return false unless build_arxiv_zip(stage_dir, zip_filename)
```
