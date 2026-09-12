# Systems Code Review Report #008 (Lens: resilience)

- **Date**: 2026-09-12
- **Auditor**: Gemini 3.8 Flash (Tier 0 Workhorse) via `tools/audit`
- **Focus Lens**: `resilience`
- **Model Tier**: `TIER0`
- **Backend**: `gemini`
- **Scope**: `lib latex_it`
- **Status**: Action Required

---

Auditing via Gemini Flash (bws run) [Profile: resilience]...
[SEVERITY]: Critical  
[LOCATION]: [`lib/latex_it/builder.rb:552-569`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L552-L569) in [`LatexBuilder#capture_pass_output`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L547-L574)  
[ROOT CAUSE]: In [`LatexBuilder#capture_pass_output`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L547-L574), compiler engines are spawned inside a new process group via `Open3.popen2e(..., pgroup: true)`. If compilation is interrupted by `SIGINT` (Ctrl+C), the terminal driver signals only the foreground process group (the Ruby process), not the detached child process group. Ruby raises `Interrupt` inside the `popen2e` block, bypassing `wait_thr.join(timeout)` and unwinding to `Open3.popen_run`'s internal `ensure` block, which calls `wait_thr.join` without a signal ever having been delivered to the child. Because the compiler is never terminated, `wait_thr.join` blocks indefinitely. Furthermore, once `wait_thr` exits, line 567 invokes [`reader.join`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L567) without a timeout; if the compiler spawned any background filter or process (`\write18`, asymptote, python) that inherited standard output/error descriptors, `stdout_err.read` blocks waiting for EOF, freezing the tool indefinitely.  
[FAILURE TRACE]:  
1. User compiles a document that triggers an infinite macro loop: `latex_it runaway.tex`.  
2. Engine process is spawned in an isolated process group (`pgroup: true`).  
3. User presses `Ctrl+C` to cancel.  
4. Ruby raises `Interrupt`. The engine receives no signal and continues executing.  
5. `Open3`'s `ensure` clause calls `wait_thr.join`.  
6. Execution hangs permanently on `wait_thr.join` and cannot be interrupted.  
[REMEDIATION]:  
```ruby
    Open3.popen2e(env, *cmd_args, pgroup: true) do |stdin, stdout_err, wait_thr|
      stdin.close rescue nil
      output = +''
      reader = Thread.new { output = stdout_err.read }
      begin
        unless wait_thr.join(timeout)
          pgid = Process.getpgid(wait_thr.pid) rescue nil
          Process.kill('-KILL', pgid) if pgid rescue Process.kill('KILL', wait_thr.pid) rescue nil
          reader.kill rescue nil
          msg = "\n! LaTeX Error: Compilation timed out after #{timeout}s (suspected runaway loop).\n"
          return [msg, ProcessResultStatus.new(124, false, nil, false)]
        end
        reader.join(2.0) || reader.kill
        [output, wait_thr.value]
      ensure
        if wait_thr.alive?
          pgid = Process.getpgid(wait_thr.pid) rescue nil
          Process.kill('-KILL', pgid) if pgid rescue Process.kill('KILL', wait_thr.pid) rescue nil
        end
        reader.kill rescue nil
      end
    end
```

---

[SEVERITY]: Major  
[LOCATION]: [`lib/latex_it/builder.rb:820-833`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L820-L833) in [`LatexBuilder#execute_bibliography`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L815-L826) and [`LatexBuilder#copy_style_files_for_bibtex`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L828-L833)  
[ROOT CAUSE]: [`LatexBuilder#copy_style_files_for_bibtex`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L828-L833) is executed before [`Dir.chdir('junk')`](file:///home/sariel/prog/26/latex_it/lib/latex_it/builder.rb#L823). While running in the document root, it executes `return unless File.directory?('../styles')`. This tests the parent of the project directory rather than the document's local `./styles` directory. As a consequence:
1. Document BST files under `./styles` are never copied to `junk/styles/`, causing BibTeX to fail with `I couldn't open style file ...` and breaking multi-pass convergence.
2. If `../styles` exists in the parent directory, `FileUtils.mkdir_p('styles')` copies external files into `./styles` in the project root, violating `junk/` isolation and polluting the working directory.  
[FAILURE TRACE]:  
1. Document defines `\bibliographystyle{styles/custom}` with file located at `./styles/custom.bst`.  
2. `LatexBuilder` executes bibliography pass.  
3. `copy_style_files_for_bibtex` evaluates `File.directory?('../styles')` which returns `false`.  
4. BibTeX executes in `junk/`, cannot locate `custom.bst`, and exits with an error status.  
[REMEDIATION]:  
```ruby
  def copy_style_files_for_bibtex
    return unless File.directory?('styles')

    FileUtils.mkdir_p('junk/styles')
    Dir['styles/*'].each { |s| FileUtils.cp_r(s, 'junk/styles/') unless File.basename(s) == 'junk' }
  end
```

---

[SEVERITY]: Major  
[LOCATION]: [`lib/latex_it/arxiv.rb:512-518`](file:///home/sariel/prog/26/latex_it/lib/latex_it/arxiv.rb#L512-L518) in [`LatexArxivPackager#count_zip_entries`](file:///home/sariel/prog/26/latex_it/lib/latex_it/arxiv.rb#L512-L518)  
[ROOT CAUSE]: [`LatexArxivPackager#count_zip_entries`](file:///home/sariel/prog/26/latex_it/lib/latex_it/arxiv.rb#L512-L518) calls `Open3.capture2('unzip', '-l', zip_filename)` without checking [`LaTeXUtils.command_available?('unzip')`](file:///home/sariel/prog/26/latex_it/lib/latex_it/utils.rb#L191-L196) and without rescuing `SystemCallError` / `Errno::ENOENT`. When running with verification disabled (`latex_it --arxiv --no-arxiv-verify`) on systems or minimal containers where `zip` is present but `unzip` is missing, `Open3.capture2` raises unhandled `Errno::ENOENT`, crashing `latex_it` with an unhandled exception despite successful archive generation.  
[FAILURE TRACE]:  
1. In an environment without `unzip` installed, invoke `latex_it --arxiv --no-arxiv-verify paper.tex`.  
2. Archive creation succeeds and writes `arxiv_paper.zip`.  
3. Verification is bypassed, and execution reaches `count_zip_entries`.  
4. `Open3.capture2('unzip', ...)` raises `Errno::ENOENT: No such file or directory - unzip`. Process crashes.  
[REMEDIATION]:  
```ruby
  def count_zip_entries(zip_filename)
    return 0 unless LaTeXUtils.command_available?('unzip')

    out, stat = Open3.capture2('unzip', '-l', zip_filename)
    return 0 unless stat.success?

    lines = out.lines[3..-3] || []
    lines.size
  rescue SystemCallError
    0
  end
```

---

[SEVERITY]: Major  
[LOCATION]: [`lib/latex_it/packager.rb:47`](file:///home/sariel/prog/26/latex_it/lib/latex_it/packager.rb#L47) in [`LatexPackager#do_package`](file:///home/sariel/prog/26/latex_it/lib/latex_it/packager.rb#L32-L50)  
[ROOT CAUSE]: In [`LatexPackager#do_package`](file:///home/sariel/prog/26/latex_it/lib/latex_it/packager.rb#L32-L50), `stage_and_create_zip` writes `zip_filename` to disk. If `@options[:verify]` is enabled and [`verify_archive!(zip_filename)`](file:///home/sariel/prog/26/latex_it/lib/latex_it/packager.rb#L266-L284) fails, `do_package` returns `false` and the CLI exits 1. However, the corrupted or non-compiling `zip_filename` is never cleaned up or renamed. It remains in the project directory, masquerading as a valid archive.  
[FAILURE TRACE]:  
1. User runs `latex_it -z --verify paper.tex` on a document with missing dependencies in the archive.  
2. `stage_and_create_zip` writes `paper.zip`.  
3. Sandbox verification compiles the archive and fails.  
4. Process exits with code 1, but leaves invalid `paper.zip` in the project root.  
[REMEDIATION]:  
```ruby
    if @options[:verify] && !verify_archive!(zip_filename)
      FileUtils.rm_f(zip_filename)
      warn Rainbow("[FAIL] Verification failed. Removed unverified #{zip_filename}.").red.bright
      return false
    end
```

---

[SEVERITY]: Moderate  
[LOCATION]: [`lib/latex_it/meta_extractor.rb:355`](file:///home/sariel/prog/26/latex_it/lib/latex_it/meta_extractor.rb#L355) in [`LaTeXMetaExtractor.extract_page_count`](file:///home/sariel/prog/26/latex_it/lib/latex_it/meta_extractor.rb#L354-L366)  
[ROOT CAUSE]: [`LaTeXMetaExtractor.extract_page_count`](file:///home/sariel/prog/26/latex_it/lib/latex_it/meta_extractor.rb#L354-L366) relies on `system('which pdfinfo > /dev/null 2>&1')`. In minimal environments (e.g. Alpine Linux, Debian slim containers) where `which` is not installed, this subshell check fails even when `pdfinfo` is available in `$PATH`, silently bypassing `pdfinfo` extraction. The codebase already provides [`LaTeXUtils.command_available?`](file:///home/sariel/prog/26/latex_it/lib/latex_it/utils.rb#L191-L196) for this purpose.  
[FAILURE TRACE]:  
1. Execute `latex_it --meta paper.tex` in a container where `poppler-utils` is installed but `which` is not.  
2. `system('which pdfinfo ...')` exits non-zero.  
3. Page count extraction falls back to fragile `.log` scraping or returns `nil`.  
[REMEDIATION]:  
```ruby
  def self.extract_page_count(pdf_path, log_path)
    if pdf_path && File.file?(pdf_path) && LaTeXUtils.command_available?('pdfinfo')
      out, _err, status = Open3.capture3('pdfinfo', pdf_path)
      return Regexp.last_match(1).to_i if status.success? && out =~ /^Pages:\s*(\d+)/
    end
```

---

[SEVERITY]: Moderate  
[LOCATION]: [`lib/latex_it/packager.rb:293-295`](file:///home/sariel/prog/26/latex_it/lib/latex_it/packager.rb#L293-L295) in [`LatexPackager#run_sandbox_compile`](file:///home/sariel/prog/26/latex_it/lib/latex_it/packager.rb#L286-L308) and [`lib/latex_it/arxiv.rb:291-292`](file:///home/sariel/prog/26/latex_it/lib/latex_it/arxiv.rb#L291-L292) in [`LatexArxivPackager#run_sandbox_verify`](file:///home/sariel/prog/26/latex_it/lib/latex_it/arxiv.rb#L288-L313)  
[ROOT CAUSE]: When spawning the verification `latex_it` process in an isolated sandbox, the CLI invocation does not forward the user-configured `--timeout` option (`@options[:timeout]`), and [`sandbox_environment`](file:///home/sariel/prog/26/latex_it/lib/latex_it/packager.rb#L333-L352) strips `LATEX_IT_TIMEOUT`. Consequently, the sandbox run falls back to the default 180s per-pass timeout (up to 540s for 3 passes), ignoring explicit timeout constraints requested by the user.  
[FAILURE TRACE]:  
1. User invokes `latex_it --timeout 15 -z --verify paper.tex`.  
2. Verification executes `cmd = [ruby_bin, script_bin, '--no-env', '--engine', ...]`.  
3. A slow or looping document during verification blocks for up to 180s per pass instead of aborting after 15s.  
[REMEDIATION]:  
```ruby
    cmd = [ruby_bin, script_bin, '--no-env', '--engine', @builder.engine_name]
    cmd += ['--timeout', @options[:timeout].to_s] if @options[:timeout]
    cmd << @filename
```
