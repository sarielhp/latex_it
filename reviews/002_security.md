# Systems Code Review Report #002 (Lens: security)

- **Date**: 2026-09-12
- **Auditor**: Gemini 3.8 Flash (Tier 0 Workhorse) via `tools/audit`
- **Focus Lens**: `security`
- **Model Tier**: `TIER0`
- **Backend**: `gemini`
- **Scope**: `.`
- **Status**: Action Required

---

Auditing via Gemini Flash (bws run) [Profile: security]...
[SEVERITY]: Critical
[LOCATION]: [tools/review_cycle](file:///home/sariel/prog/26/latex_it/tools/review_cycle#L958-L972)
[ROOT CAUSE]: Insecure manual shell serialization passed to `PTY.spawn(command_str)`. `PTY.spawn` takes either a single shell command string (which delegates to `/bin/sh -c`) or an argument list (`command, *args`). `run_with_auto_triage` receives an already-split command array (`cmd_args`), but collapses it into a single string by joining with spaces and quoting only arguments that contain spaces (`%("#{a.gsub('"', '\"')}")`). Inside double quotes in POSIX shells, backticks (`` `...` ``), command substitutions (`$(...)`), and parameter expansions (`$VAR`) are actively evaluated. Furthermore, arguments without spaces containing metacharacters (`;`, `&`, `|`) are left completely unquoted.
[FAILURE TRACE]:
1. `tools/review_cycle` invokes Phase 2 remediation: `remediate_in_sandbox` calls `remediate_prompt`.
2. `remediate_prompt` embeds literal backticks: `Run `tools/gate`#{gate_note} frequently and ensure all tests pass.`.
3. `remediate_in_sandbox` builds `cmd = ['bws', 'gw', ..., '-p', prompt]` and passes it to `run_with_auto_triage(cmd)`.
4. `run_with_auto_triage` wraps the prompt argument in double quotes: `"Run `tools/gate` frequently..."`.
5. `PTY.spawn(command_str)` spawns `/bin/sh -c command_str`.
6. `/bin/sh` executes `` `tools/gate` `` as a shell command substitution directly on the host system prior to launching the sandbox agent. Any backticks or `$()` in user guidelines, audit reports, or prompt annotations execute arbitrary commands on the host machine.
[REMEDIATION]:
Pass array arguments directly to `PTY.spawn(*cmd_args)` without shell serialization:
```ruby
  def run_with_auto_triage(cmd_args)
    status = nil
    log_write("--> Spawning PTY: #{cmd_args.join(' ')}\n")

    PTY.spawn(*cmd_args) do |stdout, stdin, pid|
      begin
        stream_pty_output(stdout, stdin)
      rescue Interrupt, SignalException => e
        kill_pty_process(pid)
        raise e
      ensure
        _, status = Process.wait2(pid) rescue [nil, nil]
      end
    end

    exit_code = status&.exitstatus || (status&.success? ? 0 : 1)
    log_write("--> Sandbox PTY exited with status: #{exit_code}\n")
    exit_code.zero?
  end
```

---

[SEVERITY]: Major
[LOCATION]: [lib/latex_it/flattener.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/flattener.rb#L38-L71)
[ROOT CAUSE]: Missing filesystem containment verification on recursive file inlining. In `LaTeXFlattener.inline_line`, target arguments inside `\input{...}` or `\include{...}` are resolved via `candidate = File.expand_path(target, file_dir)`. The method neither verifies that `candidate` resides within the project root (`base_dir`), nor guards against symlink traversal across filesystem boundaries.
[FAILURE TRACE]:
1. A manuscript includes an out-of-tree path or directory traversal directive: `\input{../../secrets.tex}` or `\input{/etc/issue.tex}`.
2. The user prepares an archive using `latex_it --arxiv`, which executes `LaTeXFlattener.flatten(@filename, '.', ...)`.
3. `inline_line` computes `candidate = File.expand_path(target, file_dir)`. Because `candidate` is valid and exists on disk, `File.file?(candidate)` succeeds.
4. `inline_file` reads the sensitive out-of-tree file content and inlines it directly into the resulting flattened `.tex` document.
5. `stage_flattened_tex` writes the inlined sensitive content into the staging area and bundles it into the public arXiv submission archive.
[REMEDIATION]:
Enforce boundary containment against `base_dir` before inlining targets:
```ruby
  def self.inline_file(filepath, base_dir, stack)
    base_expanded = File.expand_path(base_dir)
    real_path = File.expand_path(filepath, base_dir)
    return '' unless real_path.start_with?(base_expanded + File::SEPARATOR) || real_path == base_expanded

    if stack.include?(real_path)
      chain = (stack + [real_path]).map { |path| File.basename(path) }.join(' -> ')
      raise "Cyclic LaTeX input detected: #{chain}"
    end

    return '' unless File.file?(real_path)

    stack << real_path
    entered = true
    content = LaTeXUtils.safe_read(real_path)
    file_dir = File.dirname(real_path)

    transform_tex(content) do |chunk|
      chunk.lines.map { |line| inline_line(line, base_expanded, file_dir, stack) }.join
    end
  ensure
    stack.pop if entered
  end

  def self.inline_line(line, base_expanded, file_dir, stack)
    match = line.match(/^\s*\\(?:input|include)\{([^}]+)\}(.*)$/)
    return line unless match

    target, rest = match.captures
    target = target.strip
    target += '.tex' unless target.end_with?('.tex')
    candidate = File.expand_path(target, file_dir)
    return line unless candidate.start_with?(base_expanded + File::SEPARATOR) && File.file?(candidate)

    inlined = inline_file(candidate, base_expanded, stack)
    return inlined if rest.strip.empty?

    "#{inlined}\n#{rest}"
  end
```

---

[SEVERITY]: Major
[LOCATION]: [lib/latex_it/arxiv.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/arxiv.rb#L199-L213) and [lib/latex_it/packager.rb](file:///home/sariel/prog/26/latex_it/lib/latex_it/packager.rb#L241-L255)
[ROOT CAUSE]: Insecure fallback for out-of-boundary asset paths. `copy_preserving_path` tests whether `expanded.start_with?(cwd + '/')`. When an asset path resolves outside `cwd` (e.g. an absolute path or relative parent path `../`), instead of rejecting the path, it falls back to `rel_path = File.basename(src)` and copies the file into the staging root `File.join(dest_root, rel_path)`.
[FAILURE TRACE]:
1. A user references an external asset in their document: `\includegraphics{/home/user/private/architecture.pdf}` or `\includegraphics{../confidential.png}`.
2. During LaTeX compilation, `junk/<name>.fls` records: `INPUT /home/user/private/architecture.pdf`.
3. The user runs `latex_it --arxiv` (or `latex_it -z`).
4. `stage_active_figures` extracts the path and calls `copy_preserving_path('/home/user/private/architecture.pdf', stage_dir)`.
5. Because the file is outside `cwd`, `rel_path` defaults to `architecture.pdf`, and the external private file is copied into `stage_dir/architecture.pdf`.
6. `build_arxiv_zip` packages the entire `stage_dir` into the `.zip` archive, silently leaking private filesystem files into the distribution archive.
[REMEDIATION]:
Refuse to copy files located outside the project root and disallow symlinks traversing outside `cwd`:
```ruby
  def copy_preserving_path(src, dest_root)
    return unless File.exist?(src)

    cwd = Dir.pwd
    real_cwd = File.realpath(cwd)
    real_src = File.realpath(src) rescue nil
    return unless real_src && (real_src.start_with?(real_cwd + File::SEPARATOR) || real_src == real_cwd)

    expanded = File.expand_path(src)
    return unless expanded.start_with?(cwd + '/')

    rel_path = expanded.sub(cwd + '/', '')
    dest = File.join(dest_root, rel_path)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(src, dest)
  end
```

---

[SEVERITY]: Moderate
[LOCATION]: [tools/generate_gallery](file:///home/sariel/prog/26/latex_it/tools/generate_gallery#L327-L330) and [tools/generate_error_comparison](file:///home/sariel/prog/26/latex_it/tools/generate_error_comparison#L146-L175)
[ROOT CAUSE]: Unescaped shell string interpolation into `Kernel#system`. Command paths are wrapped in single quotes (`system("convert -density 150 '#{svg_path}' '#{png_path}'")`) instead of using multi-argument array invocations. Any path containing single quotes or shell control sequences leads to shell syntax breaks and command injection.
[FAILURE TRACE]:
1. A path or scenario filename containing a single quote (e.g., `image's_card`) is processed by `tools/generate_gallery` or `tools/generate_error_comparison`.
2. The single quote breaks out of `'#{svg_path}'`, allowing subsequent shell commands to execute under `/bin/sh`.
[REMEDIATION]:
Replace string-interpolated `system()` calls with multi-argument array syntax:
```ruby
  if system('which', 'convert', out: File::NULL, err: File::NULL)
    system('convert', '-density', '150', svg_path, png_path)
    puts "      Wrote #{png_path}" if File.exist?(png_path)
  end
```
