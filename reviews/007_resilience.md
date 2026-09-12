# Systems Code Review Report #007 (Lens: resilience)

- **Date**: 2026-09-12
- **Auditor**: Flagship Opus / Deep (Tier 2 Deep) via `tools/audit`
- **Focus Lens**: `resilience`
- **Model Tier**: `DEEP`
- **Backend**: `auto`
- **Scope**: `.`
- **Status**: Action Required

---

Auditing via Claude CLI (opus, tier: deep) [Profile: resilience]...
# Resilience Audit — `tools/arxiv_test_worker.rb`

Eight defects found in the error-handling / timeout / recovery surface. Findings are ordered by severity.

---

### FINDING 1

**[SEVERITY]**: Critical

**[LOCATION]**: `ArxivTestWorker::Runner#command`, lines:
```ruby
pid = Process.spawn(*argv, chdir: @project, out: log, err: %i[child out])
_, status = Process.wait2(pid)
```

**[ROOT CAUSE]**: Two invariants are violated simultaneously on every external invocation in the harness:

1. **stdin is inherited.** Only `out:` and `err:` are redirected. The child (`latex_it` → `xelatex`/`lualatex`/`pdflatex`) inherits the worker's stdin. TeX's error recovery prompt (`! Undefined control sequence. ... ? ` / `Enter file name:`) is written to *stdout* — which is redirected into a log file nobody is reading — and then TeX blocks reading stdin. If the worker was started from a terminal (manual `bws_run`, interactive debugging) or from a harness that keeps stdin open, that read never returns.
2. **`Process.wait2` is unbounded.** There is no per-operation deadline anywhere in the file. A wedged engine, a `latex_it` rerun loop that fails to converge, or a network/font-cache stall in `pdftoppm` blocks the worker forever.

**[FAILURE TRACE]**:
1. Worker reaches `failure_recovery`, which *deliberately* creates the exact condition that makes TeX prompt:
   `File.binwrite(@main, "\latexItDeliberatelyUndefinedProbe\n" + original)`.
2. `compile` → `latex_it --emacs …`. If `latex_it` does not force `-interaction=nonstopmode` (or the engine is reached through a path that drops it, e.g. `latexmk`), the engine emits `? ` and reads stdin.
3. stdin is the operator's TTY. `Process.wait2(pid)` blocks forever.
4. `@report` is frozen at `status: "RUNNING"`, `running_check: "invalid_tex"`. **The paper source `@main` remains on disk with `\latexItDeliberatelyUndefinedProbe` prepended** (see Finding 3), because `ensure` cannot run while the parent is blocked in `wait2`.
5. The only backstop is an external harness kill, which — per Finding 3 — leaves the corruption permanent.

Note this is not limited to the deliberate-failure check: any missing `.sty` during `fresh_build` reaches the same prompt.

**[REMEDIATION]**:
```ruby
    COMMAND_TIMEOUT = 900 # seconds; per external command

    def command(argv, timeout: COMMAND_TIMEOUT)
      before = File.file?(@counter) ? File.foreach(@counter).count : 0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @command_index = (@command_index || 0) + 1
      log = File.join(@logs, format('%02d-%s.log', @command_index, @active_check))
      @last_command = { command: argv, log: log }
      pid = Process.spawn(*argv, chdir: @project, in: File::NULL,
                          out: log, err: %i[child out], pgroup: true)
      status = wait_bounded(pid, timeout, log)
      # ... unchanged tail ...
    end

    def wait_bounded(pid, timeout, log)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          reap(pid)
          raise CheckError, "timed out after #{timeout}s; see #{log}"
        end
        sleep 0.05
      end
    rescue Exception # Interrupt/SignalException must not orphan the engine
      reap(pid)
      raise
    end

    def reap(pid)
      Process.kill('TERM', -pid)
      20.times { return if Process.waitpid(pid, Process::WNOHANG); sleep 0.1 }
      Process.kill('KILL', -pid)
      Process.waitpid(pid)
    rescue Errno::ESRCH, Errno::ECHILD, Errno::EPERM
      nil
    end
```
`in: File::NULL` alone converts the hang into a deterministic TeX abort; `pgroup: true` + `reap` guarantees the engine subtree dies with the worker.

---

### FINDING 2

**[SEVERITY]**: Major

**[LOCATION]**: `#check` (`rescue StandardError => e`) and `#run` (no rescue at all); triggered by `#metadata` line 1: `load File.join(@root, 'tools', 'check_arxiv_metadata')`, and by `#dependency`/`#change_dependency`/`#exercise_build` which execute *outside* any `check` block.

**[ROOT CAUSE]**: The report-finalization invariant ("every terminal state of the worker leaves a `test-worker-report.json` with `completed: true` and a terminal `status`") has two holes:

* `check` rescues only `StandardError`. `LoadError` and `SyntaxError` are `ScriptError`, **not** `StandardError`, so they bypass the per-check handler entirely.
* `run` has no `rescue`/`ensure`. Anything escaping a `check` block — including the substantial amount of logic that runs *outside* checks (`dependency`, the `File.binread`/`File.stat` preambles of `change_dependency` and `failure_recovery`, `exercise_build` itself) — kills the process with a raw backtrace on stderr while the on-disk report still reads `"status": "RUNNING", "completed": false`.

**[FAILURE TRACE]**:
1. `bws_run` stages the workspace but `tools/check_arxiv_metadata` is not in the staging manifest (renamed, or newly added and not yet in the file list).
2. `fresh_build` passes; `exercise_build` passes; `check('metadata')` is entered, `@report[:running_check] = 'metadata'` is saved.
3. `load` raises `LoadError: cannot load such file -- /ws/tools/check_arxiv_metadata`.
4. `rescue StandardError` does not match → propagates through `run` → uncaught. Exit status 1 (Ruby's uncaught-exception status), identical to the legitimate "some check FAILed" status.
5. The orchestrator reads `test-worker-report.json`: `status: RUNNING`, no `metadata` entry, no `portable_archive`/`arxiv_archive` entries. It cannot distinguish "worker crashed" from "worker still running" from "checks failed". The actionable message (the missing path) exists only in stderr, which is not part of the report contract.

The same path is reachable non-hypothetically via `#dependency`: `File.readlines(recorder).grep(/^INPUT /)` raises `ArgumentError: invalid byte sequence in UTF-8` on an `.fls` recording a file whose name contains non-UTF-8 bytes (`Encoding.default_external` is forced to UTF-8 in `initialize`). That call site is outside every `check`, so the worker dies identically.

**[REMEDIATION]**:
```ruby
    def check(name)
      # ...
    rescue StandardError, ScriptError => e
      record(name, 'FAIL', **@last_command, detail: "#{e.class}: #{e.message}")
      false
    end

    def run
      # ... existing body ...
    rescue Exception => e
      @report[:status] = 'ERROR'
      @report[:completed] = true
      @report[:error] = "#{e.class}: #{e.message}"
      @report[:backtrace] = e.backtrace&.first(15)
      save
      warn "#{e.class}: #{e.message}"
      raise if e.is_a?(SignalException)
      2
    end
```
and scrub bytes at the boundary:
```ruby
    def read_text(path)
      File.binread(path).force_encoding(Encoding::UTF_8).scrub('?')
    end
    # #dependency:  read_text(recorder).each_line.grep(/^INPUT /)
    # #package:     output = read_text(result[:log])
```
(The `#package` site is a second live instance: `output.match?(/visual|pixel|rendered/i)` raises `ArgumentError` on a TeX log containing Latin‑1 font/filename bytes, turning a passing arXiv archive into a `FAIL: arxiv_archive — ArgumentError: invalid byte sequence in UTF-8`.)

---

### FINDING 3

**[SEVERITY]**: Major

**[LOCATION]**: `#failure_recovery` (and symmetrically `#change_dependency`) — the mutate/restore window:
```ruby
      original = File.binread(@main)
      stat = File.stat(@main)
      check('invalid_tex') do
        File.binwrite(@main, "\\latexItDeliberatelyUndefinedProbe\n" + original)
```
Restoration exists only in a Ruby `ensure` block.

**[ROOT CAUSE]**: `ensure` is a *language-level* guarantee, not a *process-level* one. It does not run on `SIGTERM`, `SIGHUP`, `SIGKILL`, or `exit!`. The worker deliberately puts the paper's main source into a knowingly-broken state and holds it there across an unbounded subprocess wait (Finding 1). There is no signal trap and no crash-safe restore record (e.g. a sidecar `.orig` file the next run could reclaim).

**[FAILURE TRACE]**:
1. Finding 1 fires: `invalid_tex`'s `compile` wedges on a TeX prompt (or merely a slow arXiv rebuild exceeds the outer budget).
2. The outer harness — the *only* timeout in the system, since there is none internally — sends `SIGTERM` to the worker PID.
3. Default `SIGTERM` disposition terminates the process immediately. The `ensure` in `failure_recovery` never executes.
4. `paper/<main>.tex` is left on disk beginning with `\latexItDeliberatelyUndefinedProbe`, and (via Finding 1's missing `pgroup`) an orphaned `xelatex` continues writing into `paper/junk/`.
5. If the workspace is rsynced/copied back, or if the developer inspects the workspace and re-uses it, the corruption is indistinguishable from an authored edit — the probe line carries no marker that a tool wrote it.

The `change_dependency` probe has the identical window on an arbitrary included `.tex` file.

**[REMEDIATION]**: Register the pending restore in process-global state and install traps:
```ruby
    def initialize(root)
      # ...
      @restores = {}
      %w[INT TERM HUP].each do |sig|
        Signal.trap(sig) { restore_all; exit!(130) }
      end
    end

    def with_original(path)
      @restores[path] = [File.binread(path), File.stat(path)]
      yield
    ensure
      restore_one(path)
    end

    def restore_one(path)
      body, stat = @restores.delete(path)
      return unless body
      File.binwrite(path, body)
      File.utime(stat.atime, stat.mtime, path)
    end

    def restore_all
      @restores.keys.each { |p| restore_one(p) rescue nil }
    end

    def failure_recovery
      with_original(@main) do
        check('invalid_tex') { ... }
        restore_one(@main) && @restores[@main] = [original, stat] # or re-read
        check('recovery') { ... }
      end
    end
```
Also emit the probe as `%%latex_it-probe` marked content so any surviving corruption is greppable.

---

### FINDING 4

**[SEVERITY]**: Major

**[LOCATION]**: `#prepare`:
```ruby
      required = [*@engine, 'pdftotext', 'pdftoppm', 'zip', 'unzip']
      missing = required.reject { |name| executable(name) }
      assert(missing.empty?, "Missing tools: #{missing.join(', ')}")
      real_engine = executable(@engine || 'xelatex')
      @report[:engine_version] = Open3.capture2e(real_engine, '--version').first.lines.first.to_s.strip
```

**[ROOT CAUSE]**: When `@engine` is `nil` (automatic mode), `[*@engine]` is `[]`, so **no engine is in the `required` set** — the presence assertion covers only the PDF/zip utilities. Two lines later the code unconditionally probes the hard-coded default `xelatex`, whose absence yields `real_engine == nil` and `Open3.capture2e(nil, '--version')` → `TypeError`. The "missing external dependency ⇒ actionable message" invariant is broken precisely for the dependency that matters most.

**[FAILURE TRACE]**:
1. `test-config.json` omits `"engine"` (automatic mode — the documented default, per `engine: @engine || 'automatic'`).
2. Host has a TeX Live `scheme-small` / `pdflatex`+`lualatex`-only install; `xelatex` is absent.
3. `missing` is `[]` → assertion passes.
4. `executable('xelatex')` → `nil`.
5. `Open3.capture2e(nil, '--version')` raises `TypeError: no implicit conversion of nil into String`.
6. `check('environment')` records `FAIL — TypeError: no implicit conversion of nil into String`. Every downstream check records `SKIP: Requires a successful fresh build.` The operator is handed a Ruby type error that names neither `xelatex` nor `PATH`, for a configuration (`lualatex` available, auto-select) that the worker's own wrapper loop at `wrapper_engines = %w[xelatex lualatex pdflatex]` explicitly supports.

**[REMEDIATION]**:
```ruby
      candidates = @engine ? [@engine] : %w[xelatex lualatex pdflatex]
      real_engine = candidates.lazy.map { |e| executable(e) }.find(&:itself)
      assert(real_engine,
             "No LaTeX engine found on PATH (looked for #{candidates.join(', ')}); " \
             'install TeX Live or set "engine" in test-config.json.')
      required = ['pdftotext', 'pdftoppm', 'zip', 'unzip']
      missing = required.reject { |name| executable(name) }
      assert(missing.empty?,
             "Missing tools: #{missing.join(', ')} (poppler-utils / zip provide these)")
```

---

### FINDING 5

**[SEVERITY]**: Major

**[LOCATION]**: `#prepare`:
```ruby
      @report[:engine_version] = Open3.capture2e(real_engine, '--version').first.lines.first.to_s.strip
      @report[:latex_it_version] = Open3.capture2e(RbConfig.ruby, @latex, '--version').first.strip
```

**[ROOT CAUSE]**: `Open3.capture2e` returns `[output, status]`; the status is discarded with `.first`. A nonzero exit, a Ruby exception backtrace, or an engine that aborts on a broken `texmf.cnf` is silently promoted into the report as if it were a version string. The `environment` check then reports `PASS`, and the harness proceeds to attribute the resulting downstream explosion to whatever check happens to run first.

**[FAILURE TRACE]**:
1. `latex_it` is staged but a required gem/relative `require` is not (a realistic staging omission, identical class of bug to Finding 2).
2. `ruby latex_it --version` exits 1, printing `latex_it:12:in 'require': cannot load such file -- foo (LoadError)` to **stderr**, which `capture2e` folds into `first`.
3. `@report[:latex_it_version]` becomes `"latex_it:12:in 'require': cannot load such file -- foo (LoadError)\n\tfrom ..."` (a multi-line blob, since only the engine probe takes `.lines.first`).
4. `environment` → `PASS`. `fresh_build` → `FAIL — Command exited 1; see test-logs/02-fresh_build.log`. Every remaining check → `SKIP`.
5. The report's authoritative provenance field (`latex_it_version`, alongside `latex_it_sha256`) now contains a backtrace, and the root cause is buried in a log file rather than surfaced at the check that was designed to detect exactly this.

**[REMEDIATION]**:
```ruby
      engine_out, engine_st = Open3.capture2e(real_engine, '--version')
      assert(engine_st.success?,
             "#{real_engine} --version failed (exit #{engine_st.exitstatus}): #{engine_out.lines.first}")
      @report[:engine_version] = engine_out.lines.first.to_s.strip

      latex_out, latex_st = Open3.capture2e(RbConfig.ruby, @latex, '--version')
      assert(latex_st.success?,
             "#{@latex} --version failed (exit #{latex_st.exitstatus}): #{latex_out.lines.first(3).join}")
      @report[:latex_it_version] = latex_out.strip
```

---

### FINDING 6

**[SEVERITY]**: Moderate

**[LOCATION]**: `#failure_recovery`, `check('invalid_tex')`:
```ruby
        assert(result[:exit_status] != 0, 'Invalid TeX unexpectedly returned success')
```
combined with `#command`: `exit_status: status.exitstatus || 128 + status.termsig`.

**[ROOT CAUSE]**: The negative test's success predicate is "not zero", which is satisfied by *every* failure mode of the toolchain, not just the intended "compiler rejected bad TeX" path. Signal deaths are encoded as `128 + termsig` and are therefore indistinguishable from a clean nonzero exit. The check cannot fail, so it provides no signal.

**[FAILURE TRACE]**:
1. `latex_it` is OOM-killed by the kernel during the probe compile (large document + `lualatex`, constrained CI container) → `termsig == 9` → `exit_status == 137`.
   *Or*: the engine wrapper in `test-engine-bin` fails (`@counter` path unwritable after log rotation) → the wrapper's `File.open` raises → exit 1 before `exec`.
2. `result[:passes]` is ≥ 1 (the wrapper logged the invocation before dying, or `latex_it` invoked the engine), so the first assertion passes.
3. `exit_status != 0` → `invalid_tex` records **PASS — "Deliberately invalid TeX correctly returned a nonzero exit status."**
4. Should `latex_it` ever regress to *silently accepting* undefined control sequences while simultaneously crashing for an unrelated reason, the regression is masked. The check certifies error propagation it never observed.

**[REMEDIATION]**:
```ruby
        assert(result[:exit_status].positive? && result[:exit_status] < 128,
               "Expected a clean nonzero exit; got #{result[:exit_status]} " \
               "(signal death or crash) — see #{result[:log]}")
        assert(File.read(result[:log]).scrub.include?('latexItDeliberatelyUndefinedProbe'),
               "Compiler failed for a reason unrelated to the probe; see #{result[:log]}")
```

---

### FINDING 7

**[SEVERITY]**: Moderate

**[LOCATION]**: `Runner#initialize` and the bottom-of-file driver `exit ArxivTestWorker::Runner.new(Dir.pwd).run if __FILE__ == $PROGRAM_NAME`.

**[ROOT CAUSE]**: Every fallible I/O operation that establishes the worker's contract runs in the constructor, before any report file exists:
`JSON.parse(File.read(.../test-config.json))`, `@config.fetch('main')`, `Digest::SHA256.file(@latex)`. A failure here produces a raw backtrace and **no `test-worker-report.json` at all** — the orchestrator cannot distinguish "worker never started" (staging bug) from "worker exited before writing" (crash) from "worker is still running" (no file yet).

**[FAILURE TRACE]**:
1. `bws_run` stages the workspace; `test-config.json` is written by a generator that omits `"main"` for a project whose entry point could not be auto-detected.
2. `Runner.new` → `@config.fetch('main')` → `KeyError: key not found: "main"`.
3. Process aborts with exit 1 and `arxiv_test_worker.rb:24:in 'fetch': key not found: "main" (KeyError)`.
4. No report file. The orchestrator's report reader raises `Errno::ENOENT`, producing a second, even less related error at the outer layer. The actionable fact — "test-config.json has no `main` key" — is two stack frames deep in a stream the outer tool may discard.

Identical outcome if `latex_it` is not staged: `Digest::SHA256.file(@latex)` → `Errno::ENOENT` naming the file but with no guidance.

**[REMEDIATION]**:
```ruby
if __FILE__ == $PROGRAM_NAME
  begin
    exit ArxivTestWorker::Runner.new(Dir.pwd).run
  rescue StandardError, ScriptError => e
    File.write(File.join(Dir.pwd, 'test-worker-report.json'),
               JSON.pretty_generate(status: 'ERROR', completed: true,
                                    error: "#{e.class}: #{e.message}",
                                    backtrace: e.backtrace&.first(10),
                                    updated_at: Time.now.utc.iso8601) + "\n")
    warn "arxiv_test_worker: #{e.class}: #{e.message}"
    exit 2
  end
end
```
and make the config errors self-describing:
```ruby
      @config = JSON.parse(File.read(cfg = File.join(root, 'test-config.json')))
      main = @config['main'] or
        raise CheckError, %(#{cfg}: missing required key "main" (path to the entry .tex, relative to paper/))
      File.file?(@latex) or
        raise CheckError, "#{@latex}: latex_it was not staged into the workspace"
```

---

### FINDING 8

**[SEVERITY]**: Moderate

**[LOCATION]**: `#run` — the `else` branch skip list, and `#save`.

**[ROOT CAUSE]**: Two report-integrity gaps in the failure path:

* The skip list enumerates 13 names but omits **`fresh_build`** and **`settle_before_dependency`**. When `prepare` fails, `built` is `false` and `check('fresh_build')` is never invoked, so the report contains an `environment: FAIL` entry followed immediately by `unchanged_rerun: SKIP` — with no record that `fresh_build` was ever supposed to run. The set of check names in the report is path-dependent, so a consumer cannot use "check X absent" to mean anything.
* `#save` writes `path + '.tmp'` and renames. If the write raises (ENOSPC — plausible, since a multi-pass LaTeX + PDF-diff + archive workflow can fill a small tmpfs workspace), the stale `test-worker-report.json.tmp` is left behind and the exception escapes `save` → escapes `record` → escapes `check` (it's a `StandardError`, so it is caught, which then calls `record` → `save` → raises again) → escapes `run` per Finding 2.

**[FAILURE TRACE]**:
1. `pdftoppm` is not installed (`poppler-utils` split packaging on minimal images).
2. `prepare` → `assert(missing.empty?, "Missing tools: pdftoppm")` → `environment: FAIL`.
3. `ready` is `false`; `built` short-circuits to `false` without evaluating `check('fresh_build')`.
4. Final report: `checks: [environment(FAIL), unchanged_rerun(SKIP), …, arxiv_archive(SKIP)]` — 14 entries where the success path produces 16, and `fresh_build` silently absent. A dashboard keyed on check name renders a hole rather than a skip.

**[REMEDIATION]**:
```ruby
      ALL_CHECKS = %w[environment fresh_build unchanged_rerun fast_rerun single_pass
                      settle_after_single_pass pdf_diff settle_before_dependency
                      dependency_change dependency_rerun invalid_tex recovery
                      metadata portable_archive arxiv_archive].freeze
      # ...
      unless built
        (ALL_CHECKS - @report[:checks].map { |c| c[:name] }).each do |name|
          record(name, 'SKIP', detail: 'Requires a successful fresh build.')
        end
      end
```
and make `save` non-fatal / self-cleaning:
```ruby
    def save
      @report[:updated_at] = Time.now.utc.iso8601
      path = File.join(@root, 'test-worker-report.json')
      tmp  = path + '.tmp'
      File.write(tmp, JSON.pretty_generate(@report) + "\n")
      File.rename(tmp, path)
    rescue SystemCallError => e
      FileUtils.rm_f(tmp)
      warn "arxiv_test_worker: could not persist report: #{e.message}"
    end
```
