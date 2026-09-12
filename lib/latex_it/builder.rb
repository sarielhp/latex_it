# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/builder.rb
#
# LaTeX compilation lifecycle manager, pass scheduler, junk/ directory isolation,
# bibliography handling, lockfile protection, and artifact staging.
# ==============================================================================

require 'fileutils'
require 'open3'
require 'digest'
require 'json'
require 'tmpdir'
require 'time'

require_relative 'color'
require_relative 'utils'
require_relative 'compatibility'
require_relative 'diagnostics'
require_relative 'brace_checker'

class LatexBuilder
  include LaTeXDiagnostics

  attr_reader :options, :filename, :bfilename, :bdir, :engine_name

  CACHE_ENV_KEYS = %w[
    LATEXOPTS LATEXOPTIONS TEXINPUTS PDFTEXINPUTS XETEXINPUTS LUATEXINPUTS
    LUAINPUTS BIBINPUTS BSTINPUTS TEXMFHOME TEXMFCONFIG TEXMFVAR TEXMFCNF
    TEXMF TEXMFDBS TEXMFCACHE
  ].freeze

  DEFAULT_PASS_TIMEOUT = 180

  ProcessResultStatus = Struct.new(:exitstatus, :success, :termsig, :signaled) do
    def success?
      self[:success] == true
    end

    def signaled?
      self[:signaled] == true
    end
  end

  def initialize(target, options)
    @options = options
    @bdir = File.dirname(target)
    @target_base = File.basename(target)
    @bfilename = File.basename(@target_base, '.*')
    @filename = "#{@bfilename}.tex"
    @orig_stdout = $stdout
    @engine_name = LaTeXUtils.normalize_engine(@options[:engine] || @options[:config_engine] || 'xelatex')
    @pdferr = "junk/err_#{@engine_name}"
    @biberrbase = 'err_bib'
    @biberr = "junk/#{@biberrbase}"
    @explained_categories = {}
  end

  def run!
    build_dir = File.expand_path(@bdir)
    puts "      cd #{build_dir}" if !@options[:score] && build_dir != File.expand_path('.')
    Dir.chdir(build_dir) { run_in_current_directory! }
  end

  def run_in_current_directory!
    if @options[:score]
      @orig_stdout = $stdout
      $stdout = File.open(File::NULL, 'w')
      begin
        compile_target
      ensure
        $stdout.close rescue nil
        $stdout = @orig_stdout
      end
    else
      compile_target
    end
  end

  private

  def compile_target
    unless File.exist?(@filename)
      warn "Error: File '#{@filename}' not found."
      exit 1
    end

    if @options[:deps]
      export_dependencies
      return true
    end

    with_lock { execute_compile_pipeline } == true
  end

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
    clean_pass_logs
    junk_dir_create
    snapshot_build_inputs!
    total_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @options[:time]

    return false unless run_convergence_loop

    puts ''
    finalize_build_outputs(total_t0)
    true
  end

  def clean_pass_logs
    FileUtils.rm_f([@log, @loga, @biberr, @pdferr, "#{@pdferr}_1", "#{@pdferr}_2", "#{@pdferr}_3"])
  end

  def finalize_build_outputs(total_t0)
    update_target_file("junk/#{@bfilename}.pdf", "#{@bfilename}.pdf", update_on_diff: @options[:update_on_diff])
    update_target_file("junk/#{@bfilename}.bbl", "#{@bfilename}.bbl") if LaTeXUtils.bbl_has_entries?("junk/#{@bfilename}.bbl")
    update_target_file("junk/#{@bfilename}.synctex.gz", "#{@bfilename}.synctex.gz")

    if @options[:time]
      total_t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      printf("Total Build Time: %s seconds\n", Rainbow(format('%.2f', total_t1 - total_t0)).green.bright)
    end

    analyze_output
    save_build_state!
  end

  # -a, -e, -v and --emacs exist to show more output, so returning early from
  # the up-to-date branch made exactly the flags a user reaches for print
  # nothing at all -- an AUCTeX run would report an empty error list for a
  # document that has warnings. Re-reporting from the cached log keeps the
  # cache fast and the flags honest.
  def diagnostics_requested?
    @options[:all] || @options[:explain] || @options[:verbose] || @options[:emacs]
  end

  def targets_up_to_date?
    return false if @options[:clean] || @options[:single_pass] || @options[:force] || @options[:score] || @options[:werror]
    return false if @options[:bib] == true

    target_pdf = "#{@bfilename}.pdf"
    return false unless File.exist?(target_pdf) && File.size(target_pdf) > 0

    state_file = 'junk/.build_state.json'
    return false unless File.exist?(state_file)

    state = JSON.parse(File.read(state_file)) rescue nil
    return false unless state.is_a?(Hash) && state['target'] == target_pdf
    return false unless state['signature'] == build_signature

    sources = state['sources']
    return false unless sources.is_a?(Hash) && !sources.empty?

    build_time = state['saved_at'] || (File.exist?(state_file) ? File.mtime(state_file).to_i : 0)
    root_files = Dir['*.tex'].select { |f| File.file?(f) } + bib_files_on_disk
    return false if root_files.any? do |f|
      File.mtime(f).to_i > build_time && (!sources[f] || Digest::SHA256.file(f).hexdigest != sources[f]['sha'])
    end

    sources.all? do |path, meta|
      next false unless File.exist?(path)

      meta['sha'] && Digest::SHA256.file(path).hexdigest == meta['sha']
    end
  end

  def run_convergence_loop
    @cacheable_build = true
    if @options[:single_pass]
      print "      #{Rainbow(@engine_name).bright}"
      @cacheable_build = false
      return run_latex_pass('_1')
    end

    max_passes = @options[:passes]
    bib_ran = false

    bib_tool = detect_bib_tool
    if bib_tool && bib_files_newer_than_bbl?
      print "      #{Rainbow(bib_tool).bright}"
      return false unless run_bib_pass(bib_tool)

      bib_ran = true
    end

    run_pass_iterations(max_passes, bib_ran, bib_tool)
  end

  def run_pass_iterations(max_passes, bib_ran, bib_tool)
    pass = 0
    aux_before = compute_aux_hash
    loop do
      pass += 1
      prefix = (pass == 1 && !bib_ran) ? '      ' : ', '
      print "#{prefix}#{Rainbow(@engine_name).bright} (#{pass})"

      return false unless run_latex_pass("_#{pass}")

      curr_aux_hash = compute_aux_hash
      rerun_needed = needs_latex_rerun?("#{@pdferr}_#{pass}", aux_before, curr_aux_hash)
      aux_before = curr_aux_hash
      if pass >= max_passes
        @cacheable_build = false if rerun_needed
        break
      end

      bib_tool ||= detect_bib_tool(curr_aux_hash)
      if bib_tool && !bib_ran && needs_bib_pass?(bib_tool, "#{@pdferr}_#{pass}", curr_aux_hash)
        print ", #{Rainbow(bib_tool).bright}"
        return false unless run_bib_pass(bib_tool)

        bib_ran = true
        next
      end

      break unless rerun_needed
    end
    true
  end

  def bib_files_newer_than_bbl?
    fnbbl = "junk/#{@bfilename}.bbl"
    return false unless File.exist?(fnbbl) && File.size(fnbbl) > 0
    return false unless File.exist?("junk/#{@bfilename}.aux") || File.exist?("junk/#{@bfilename}.bcf")

    bbl_mtime = File.mtime(fnbbl)
    bib_files_on_disk.any? { |b| File.mtime(b) > bbl_mtime }
  end

  def extract_fls_dependencies(fls_path)
    return [] unless File.exist?(fls_path)

    root_abs = File.expand_path('.')
    deps = []

    File.foreach(fls_path) do |line|
      next unless line.start_with?('INPUT ')

      path = line.sub(/\AINPUT\s+/, '').strip
      next if path.empty?

      abs = File.expand_path(path)
      if abs.start_with?(root_abs) && File.file?(abs)
        rel = abs.sub(%r{\A#{Regexp.escape(root_abs)}/?}, '')
        next if rel.start_with?('junk/') || rel.empty?

        deps << rel
      end
    end

    deps.uniq
  end

  def snapshot_build_inputs!
    @build_start_time = Time.now
    @input_snapshots = {}
    files_to_snapshot = [@filename]
    files_to_snapshot.concat(Dir['*.tex'].select { |f| File.file?(f) })
    files_to_snapshot.concat(bib_files_on_disk)
    if File.exist?("junk/#{@bfilename}.fls")
      files_to_snapshot.concat(extract_fls_dependencies("junk/#{@bfilename}.fls"))
    end
    files_to_snapshot.uniq.each do |f|
      next unless File.file?(f)

      @input_snapshots[f] = {
        mtime: File.mtime(f).to_f,
        sha: (Digest::SHA256.file(f).hexdigest rescue nil)
      }
    end
  end

  def save_build_state!
    return if @cacheable_build == false
    return unless File.exist?("junk/#{@bfilename}.pdf") && File.size("junk/#{@bfilename}.pdf") > 0

    deps = collect_active_dependencies
    sources, tainted = inspect_source_snapshots(deps)

    if tainted
      FileUtils.rm_f('junk/.build_state.json')
      puts "      #{Rainbow('Note: Source files modified during compilation; re-run required.').yellow}" unless @options[:score]
      return
    end

    state = {
      'target' => "#{@bfilename}.pdf",
      'engine' => @engine_name,
      'signature' => build_signature,
      'saved_at' => Time.now.to_i,
      'sources' => sources
    }

    File.write('junk/.build_state.json', JSON.generate(state))
  rescue StandardError => e
    warn "Warning: Could not save build state: #{e.message}" if @options[:verbose]
  end

  def collect_active_dependencies
    fls_path = "junk/#{@bfilename}.fls"
    deps = extract_fls_dependencies(fls_path)
    deps << @filename if File.exist?(@filename)
    bib_files_on_disk.each { |b| deps << b }
    deps.uniq
  end

  def inspect_source_snapshots(deps)
    tainted = false
    sources = {}
    deps.each do |dep|
      next unless File.file?(dep)

      current_sha = Digest::SHA256.file(dep).hexdigest
      current_mtime = File.mtime(dep).to_f

      if @input_snapshots && @input_snapshots[dep]
        snap = @input_snapshots[dep]
        tainted = true if snap[:sha] && snap[:sha] != current_sha
      elsif @build_start_time && current_mtime >= @build_start_time.to_f
        tainted = true
      end

      sources[dep] = { 'mtime' => File.mtime(dep).to_i, 'sha' => current_sha }
    end
    [sources, tainted]
  end

  def build_signature
    values = CACHE_ENV_KEYS.to_h { |key| [key, ENV[key].to_s] }
    payload = {
      engine: @engine_name,
      bib: @options[:bib],
      passes: @options[:passes],
      single_pass: @options[:single_pass] == true,
      no_env: @options[:no_env] == true,
      environment: values
    }
    Digest::SHA256.hexdigest(JSON.generate(payload))
  end

  # The single source of truth for where bibliographies live. Five call sites
  # used to hardcode Dir['*.bib', 'refs/*.bib'] while discover_bib_files knew
  # about bib/ and bibliography/ as well, and bib_dirs is user-configurable.
  # A .bib never appears in the .fls either -- LaTeX reads the .bbl out of
  # junk/, which extract_fls_dependencies excludes -- so a bibliography under
  # bib/ was tracked by nothing at all, and editing it left targets_up_to_date?
  # reporting the stale PDF as current.
  def bib_globs
    dirs = @options[:bib_dirs] || LaTeXUtils::DEFAULT_BIB_DIRS
    ['*.bib'] + dirs.map { |d| "#{d.to_s.chomp('/')}/*.bib" }
  end

  def bib_files_on_disk
    Dir[*bib_globs].select { |f| File.file?(f) }
  end

  def export_dependencies
    deps = []
    if File.exist?('junk/.build_state.json')
      state = JSON.parse(File.read('junk/.build_state.json')) rescue nil
      deps = state['sources'].keys if state.is_a?(Hash) && state['sources'].is_a?(Hash)
    end

    if deps.empty? && File.exist?("junk/#{@bfilename}.fls")
      deps = extract_fls_dependencies("junk/#{@bfilename}.fls")
    end

    if deps.empty?
      with_lock do
        setup_environment
        junk_dir_create
        run_latex_pass('_1')
        deps = extract_fls_dependencies("junk/#{@bfilename}.fls")
      end
    end

    deps << @filename if File.exist?(@filename)
    bib_files_on_disk.each { |b| deps << b }
    deps.uniq!
    deps.sort!

    puts "#{@bfilename}.pdf: #{deps.join(' ')}"
  end

  def canonical_build_dir
    target_dir = @bdir ? File.expand_path(@bdir) : Dir.pwd
    File.realpath(target_dir) rescue target_dir
  end

  def path_hash
    @path_hash ||= Digest::SHA256.hexdigest(canonical_build_dir)[0..15]
  end

  NOFOLLOW = defined?(File::NOFOLLOW) ? File::NOFOLLOW : 0

  def project_tmp_dir
    @project_tmp_dir ||= begin
      dir = File.join(Dir.tmpdir, "latex_it_#{Process.uid}")
      begin
        Dir.mkdir(dir, 0o700)
      rescue Errno::EEXIST
        nil
      end
      verify_private_dir!(dir)
      dir
    end
  end

  # FileUtils.mkdir_p does not repair the mode or ownership of a path that
  # already exists, and the name here is predictable. On a shared /tmp another
  # user could pre-create this directory world-writable and replace the lock
  # file with a symlink; with_lock opens that path and truncates it, which
  # would destroy whatever it pointed at. Linux's protected_symlinks does not
  # help, because it only covers directories that are both world-writable and
  # sticky. Refuse anything that is not a private directory we own.
  def verify_private_dir!(dir)
    stat = File.lstat(dir)
    return if stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o077).zero?

    abort "latex_it: refusing to use #{dir}: not a private directory owned by uid #{Process.uid}"
  end

  def project_tmp_file(suffix)
    File.join(project_tmp_dir, "#{path_hash}_#{@bfilename}_#{suffix}")
  end

  def with_lock
    return yield unless @options[:lock]

    lock_file = project_tmp_file('build.lock')
    File.open(lock_file, File::RDWR | File::CREAT | NOFOLLOW, 0o600) do |f|
      unless f.flock(File::LOCK_EX | File::LOCK_NB)
        puts "      #{Rainbow("Another latex_it process is running for #{@bfilename}. Waiting for it to finish...").yellow}" unless @options[:score]
        f.flock(File::LOCK_EX)
      end

      f.truncate(0) rescue nil
      f.puts "pid: #{Process.pid}\nstarted: #{Time.now.iso8601}\ntarget: #{File.expand_path(@filename)}" rescue nil
      f.flush rescue nil

      yield
    ensure
      f.flock(File::LOCK_UN) rescue nil
    end
  end

  def setup_environment
    junk_dir_create

    LaTeXUtils.reset_latex_environment! if @options[:no_env]

    @engine_name = resolve_engine
    LaTeXUtils.check_program(@engine_name)

    @latex_flags = ['-interaction=nonstopmode', '-synctex=1', '-no-mktex=tfm', '-recorder', '-output-directory=junk', '-file-line-error']

    @pdferr = "junk/err_#{@engine_name}"
    @biberrbase = 'err_bib'
    @biberr = "junk/#{@biberrbase}"
    @log = 'junk/log.txt'
    @loga = 'junk/log.txt.1'
  end

  def resolve_engine
    file_engine = LaTeXUtils.detect_engine_from_file(@filename)
    candidate_engine = @options[:engine] || ENV['PDFBINONLY'] || file_engine ||
                       @options[:config_engine] || ENV['PDFBIN'] || ENV['LATEX_ENGINE'] || 'xelatex'
    requested_engine = LaTeXUtils.normalize_engine(candidate_engine)
    pdflatex_reasons = LaTeXUtils.source_pdflatex_reasons(@filename)
    incompatible = %w[xelatex lualatex].include?(requested_engine) && !pdflatex_reasons.empty?
    reason = pdflatex_reasons.join(' and ')

    if incompatible && @options[:engine_explicit]
      puts Rainbow(" -- Source uses #{reason}; #{requested_engine} may fail. Recommended: --pdflatex").yellow
      requested_engine
    elsif incompatible
      puts Rainbow(" -- Source uses #{reason}; selecting pdflatex automatically.").cyan
      LaTeXUtils.compatible_engine(requested_engine, @filename)
    else
      requested_engine
    end
  end

  def junk_dir_create
    FileUtils.mkdir_p('junk/junk')
    target_subdirs = @options[:junk_subdirs] || LaTeXUtils::DEFAULT_JUNK_SUBDIRS
    target_subdirs.each { |dir| FileUtils.mkdir_p(File.join('junk', dir)) }
    mirror_project_subdirs_to_junk if @options[:auto_mirror_subdirs] != false
  end

  def mirror_project_subdirs_to_junk
    Dir.glob('*/').each do |d|
      clean_dir = d.chomp('/')
      next if clean_dir.start_with?('junk', '.', 'backup')

      FileUtils.mkdir_p(File.join('junk', clean_dir))
    end
  end

  def deep_clean
    LaTeXUtils.clean_directory('.', true)
  end

  def paper_cleanup
    if File.exist?("#{@bfilename}.aux") && !File.exist?("junk/#{@bfilename}.aux")
      FileUtils.mkdir_p('junk')
      FileUtils.cp("#{@bfilename}.aux", "junk/#{@bfilename}.aux")
    end

    root_bbl = "#{@bfilename}.bbl"
    if File.exist?(root_bbl) && !File.exist?("junk/#{root_bbl}") && LaTeXUtils.bbl_has_entries?(root_bbl)
      FileUtils.mkdir_p('junk')
      FileUtils.cp(root_bbl, "junk/#{root_bbl}")
    end

    # Every entry must be anchored to the document stem or be a name TeX itself
    # reserves. A bare 'log.txt' was removed: this tool writes its transcript to
    # junk/log.txt, so a root log.txt can only be a file the user wrote, and
    # paper_cleanup runs on every build with no flag guarding it.
    files = ["#{@bfilename}.ps", "#{@bfilename}.blg", "#{@bfilename}.dvi",
             "#{@bfilename}.thm", "#{@bfilename}.aux", "#{@bfilename}.idx", "#{@bfilename}.log",
             "#{@bfilename}.out", "#{@bfilename}.vtc", 'texput.log', 'missfont.log', 'mfput.log',
             "#{@bfilename}.bcf", "#{@bfilename}.run.xml"]
    files.each { |f| FileUtils.rm_f(f) }

    root_bbl = "#{@bfilename}.bbl"
    FileUtils.rm_f(root_bbl) if File.exist?(root_bbl) && !LaTeXUtils.bbl_has_entries?(root_bbl)
  end

  def pass_environment
    env = LaTeXCompatibility.compiler_environment(@options).dup
    env['max_print_line'] ||= '2048'
    env
  end

  def kill_process_group(pid)
    pgid = Process.getpgid(pid) rescue nil
    Process.kill('-KILL', pgid) if pgid rescue nil
    Process.kill('KILL', pid) rescue nil
  end

  def capture_pass_output(cmd_args)
    timeout = (@options[:timeout] || ENV['LATEX_IT_TIMEOUT'] || DEFAULT_PASS_TIMEOUT).to_i
    env = pass_environment
    return Open3.capture2e(env, *cmd_args) if timeout <= 0

    Open3.popen2e(env, *cmd_args, pgroup: true) do |stdin, stdout_err, wait_thr|
      stdin.close rescue nil
      output = +''
      reader = Thread.new { output = stdout_err.read }
      begin
        unless wait_thr.join(timeout)
          kill_process_group(wait_thr.pid)
          reader.kill rescue nil
          msg = "\n! LaTeX Error: Compilation timed out after #{timeout}s (suspected runaway loop).\n"
          return [msg, ProcessResultStatus.new(124, false, nil, false)]
        end
        reader.join(2.0) || reader.kill rescue nil
        [output, wait_thr.value]
      ensure
        kill_process_group(wait_thr.pid) if wait_thr&.alive?
        reader.kill rescue nil
      end
    end
  rescue Errno::ENOENT
    raise
  rescue StandardError => e
    ["\n! Process Error: #{e.message}\n", ProcessResultStatus.new(1, false, nil, false)]
  end

  def run_latex_pass(suffix)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @options[:time]
    lgx = "#{@pdferr}#{suffix}"
    FileUtils.rm_f(lgx)

    cmd_args = build_latex_pass_cmd
    write_pass_header(lgx, cmd_args)

    stdout_stderr, status = capture_pass_output(cmd_args)
    st = status.exitstatus || (status.respond_to?(:termsig) && status.termsig ? 128 + status.termsig : 1)

    File.open(lgx, 'a') { |f| f.write(stdout_stderr) }
    if status.respond_to?(:signaled?) && status.signaled?
      warn "\nLaTeX engine terminated by signal #{status.termsig} (fatal crash).\n"
    elsif st > 0
      puts "\nLaTeX process exited with status: #{st}\n"
    end

    handle_pass_errors(st, lgx)
    File.open(@log, 'a') { |f| f.write(stdout_stderr) }

    if @options[:time]
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      printf(" [%s]", Rainbow(format('%.2fs', t1 - t0)).green)
    end
    status.success?
  end

  def build_latex_pass_cmd
    latexopts = ENV['LATEXOPTS'] || ''
    latexoptions = ENV['LATEXOPTIONS'] || ''

    cfilename = if !latexoptions.empty?
                  "#{latexoptions} \\input{#{@filename}}"
                elsif !latexopts.empty?
                  "#{latexopts}\\input{#{@filename}}"
                else
                  "\\input{#{@filename}}"
                end

    [@engine_name] + @latex_flags + [cfilename]
  end

  def write_pass_header(lgx, cmd_args)
    File.open(lgx, 'a') do |f|
      f.puts '========================================'
      f.puts cmd_args.map(&:to_s).join(' ')
      f.puts '========================================'
      f.puts Time.now.strftime('%a %b %d %H:%M:%S %Z %Y')
      f.puts '========================================'
    end
  end

  def handle_pass_errors(st, lgx)
    errcnt = count_errors_in_log(st, lgx)
    return unless errcnt > 0

    if @options[:score]
      output_score(lgx, st)
      exit 1
    else
      report_errors(lgx)
    end
  end

  def detect_bib_tool(aux_contents = nil)
    return nil if @options[:bib] == false

    biber_detected = detect_biber_control_file
    return :biber if biber_detected

    if aux_contents.nil?
      aux_files = Dir.glob('junk/**/*.aux')
      return (@options[:bib] == true ? :bibtex : nil) if aux_files.empty?

      aux_contents = aux_files.map { |f| LaTeXUtils.safe_read(f) }.join("\n")
    elsif aux_contents.empty?
      return (@options[:bib] == true ? :bibtex : nil)
    end

    detect_bib_tool_from_aux(aux_contents)
  end

  def detect_biber_control_file
    if File.exist?("junk/#{@bfilename}.bcf")
      bcf_content = LaTeXUtils.safe_read("junk/#{@bfilename}.bcf")
      return true if bcf_content.include?('<bcf:citekey>') || @options[:bib] == true
    end

    run_xml_path = "junk/#{@bfilename}.run.xml"
    if File.exist?(run_xml_path)
      run_xml_content = LaTeXUtils.safe_read(run_xml_path)
      return true if run_xml_content =~ /biber/i && (run_xml_content =~ /active="1"/ || @options[:bib] == true)
    end

    false
  end

  def detect_bib_tool_from_aux(aux_contents)
    return :biber if detect_biber_aux(aux_contents)
    return :bibtex if detect_bibtex_aux(aux_contents)

    @options[:bib] == true ? :bibtex : nil
  end

  def detect_biber_aux(aux_contents)
    return false unless aux_contents.include?('\abx@aux@bcf')

    bcf_path = "junk/#{@bfilename}.bcf"
    if File.exist?(bcf_path)
      bcf_content = LaTeXUtils.safe_read(bcf_path)
      bcf_content.include?('<bcf:citekey>') || @options[:bib] == true
    else
      @options[:bib] == true
    end
  end

  def detect_bibtex_aux(aux_contents)
    has_bibdata = aux_contents =~ /\\bibdata\{/
    needs_bib = aux_contents =~ /\\citation/ || @options[:bib] == true
    return false unless has_bibdata && needs_bib
    return true if @options[:bib] == true

    has_bbl = LaTeXUtils.bbl_has_entries?("junk/#{@bfilename}.bbl") || LaTeXUtils.bbl_has_entries?("#{@bfilename}.bbl")
    return false if has_bbl && !bib_files_exist_for_bibdata?(aux_contents)

    true
  end

  def bib_files_exist_for_bibdata?(aux_contents)
    targets = aux_contents.scan(/\\bibdata\{([^}]+)\}/).flatten.flat_map { |s| s.split(',') }.map(&:strip)
    return true if targets.empty?

    configured_dirs = @options[:bib_dirs] || LaTeXUtils::DEFAULT_BIB_DIRS
    bib_dirs = (['.'] + configured_dirs + ENV['BIBINPUTS'].to_s.split(':')).reject(&:empty?)
    targets.any? do |target|
      bib_dirs.any? do |d|
        File.file?(File.join(d, "#{target}.bib")) || File.file?(File.join(d, target))
      end
    end
  end

  def run_bib_pass(tool)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @options[:time]
    fnbbl = "junk/#{@bfilename}.bbl"
    root_bbl = "#{@bfilename}.bbl"
    previous = bibliography_source(fnbbl, root_bbl)
    preserve_bibliography_backup(previous, root_bbl)
    FileUtils.rm_f(fnbbl)

    return false unless execute_bib_and_verify(tool, fnbbl, previous, root_bbl)

    if @options[:time]
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      printf(" [%s]", Rainbow(format('%.2fs', t1 - t0)).green)
    end
    true
  end

  def execute_bib_and_verify(tool, fnbbl, previous, root_bbl)
    begin
      bib_out, status = execute_bibliography(tool)
    rescue Errno::ENOENT => e
      File.write(@biberr, e.message)
      restore_bibliography(fnbbl, previous)
      warn "\nBibliography tool unavailable: #{e.message}"
      return false
    end
    File.write(@biberr, bib_out)

    valid = status.success? && LaTeXUtils.bbl_has_entries?(fnbbl)
    unless valid
      restore_bibliography(fnbbl, previous)
      warn "\nBibliography process failed or produced no valid entries. See #{@biberr}."
      return false
    end

    FileUtils.cp(fnbbl, root_bbl)
    true
  end

  def bibliography_source(junk_bbl, root_bbl)
    return root_bbl if LaTeXUtils.bbl_has_entries?(root_bbl)
    return junk_bbl if LaTeXUtils.bbl_has_entries?(junk_bbl)

    nil
  end

  def preserve_bibliography_backup(previous, root_bbl)
    return unless previous

    backup = "#{root_bbl}.bak"
    FileUtils.cp(previous, backup)
    FileUtils.cp(previous, "junk/#{File.basename(backup)}")
  end

  def restore_bibliography(junk_bbl, previous)
    unless previous
      FileUtils.rm_f(junk_bbl)
      return
    end

    backup = "#{@bfilename}.bbl.bak"
    source = File.file?(backup) ? backup : previous
    FileUtils.cp(source, junk_bbl) unless source == junk_bbl
  end

  def discover_bib_files(aux_contents = nil)
    bibs = bib_files_on_disk
    bibs.concat(extract_aux_bib_files(aux_contents))
    bibs.concat(extract_bcf_bib_files)
    bibs.uniq
  end

  def extract_bcf_bib_files
    bcf_path = "junk/#{@bfilename}.bcf"
    return [] unless File.exist?(bcf_path)

    files = []
    bcf_content = LaTeXUtils.safe_read(bcf_path)
    bcf_content.scan(/<bcf:datasource[^>]*>(.*?)<\/bcf:datasource>/) do |m|
      collect_bib_candidates(m.first.strip, files)
    end
    files
  end

  def extract_aux_bib_files(aux_contents = nil)
    files = []
    if aux_contents
      aux_contents.scan(/\\bibdata\{([^}]+)\}/) do |m|
        collect_bib_candidates(m.first, files)
      end
    else
      Dir.glob('junk/**/*.aux').each do |aux|
        LaTeXUtils.safe_read(aux).scan(/\\bibdata\{([^}]+)\}/) do |m|
          collect_bib_candidates(m.first, files)
        end
      end
    end
    files
  end

  def collect_bib_candidates(bibdata_str, files)
    configured_dirs = @options[:bib_dirs] || LaTeXUtils::DEFAULT_BIB_DIRS
    prefixes = [''] + configured_dirs.map { |d| "#{d.chomp('/')}/" }
    prefixes += ENV['BIBINPUTS'].to_s.split(':').reject(&:empty?).map { |d| "#{d.chomp('/')}/" }
    bibdata_str.split(',').map(&:strip).each do |name|
      stem = name.delete_suffix('.bib')
      match = prefixes.map { |pfx| "#{pfx}#{stem}.bib" }.find { |cand| File.file?(cand) }
      files << match if match
    end
  end

  def execute_bibliography(tool)
    discover_bib_files.each { |b| FileUtils.cp(b, 'junk/') }
    cmd = if tool == :biber
            ['biber', '--output_safechars', '--input-directory', '.', '--output-directory', '.', @bfilename]
          else
            copy_style_files_for_bibtex
            ['bibtex', @bfilename]
          end
    Dir.chdir('junk') do
      capture_pass_output(cmd)
    end
  end

  def copy_style_files_for_bibtex
    return unless File.directory?('styles')

    FileUtils.mkdir_p('junk/styles')
    Dir['styles/*'].each { |s| FileUtils.cp_r(s, 'junk/styles/') unless File.basename(s) == 'junk' }
  end

  def compute_aux_hash
    aux_files = Dir.glob('junk/**/*.aux').sort
    aux_files.map { |f| "#{f}:#{LaTeXUtils.safe_read(f)}" }.join("\n")
  end

  def needs_bib_pass?(tool, loga, aux_contents = nil)
    return false if @options[:bib] == false
    return true if @options[:bib] == true

    fnbbl = "junk/#{@bfilename}.bbl"
    return true unless File.exist?(fnbbl) && File.size(fnbbl) > 0

    bbl_mtime = File.mtime(fnbbl)
    bib_files = discover_bib_files(aux_contents)
    return true if bib_files.any? { |b| File.mtime(b) > bbl_mtime }

    log_content = LaTeXUtils.safe_read(loga)
    bib_rerun_requested?(log_content)
  end

  def bib_rerun_requested?(log_content)
    return true if log_content =~ /Please \(re\)run Biber/i
    return true if log_content =~ /No file .*\.bbl/i
    return true if log_content =~ /Citation .* undefined/i
    return true if log_content =~ /There were undefined citations/i
    return true if log_content =~ /Package biblatex Warning: Please rerun/i
    return true if log_content =~ /Package natbib Warning: Citation\(s\) may have changed/i

    false
  end

  def needs_latex_rerun?(loga, prev_aux_hash = nil, curr_aux_hash = nil)
    curr_aux_hash ||= compute_aux_hash
    if prev_aux_hash && !prev_aux_hash.empty?
      return true if curr_aux_hash != prev_aux_hash
    elsif prev_aux_hash && prev_aux_hash.empty?
      return true if aux_has_cross_references?(curr_aux_hash)
    end

    log_content = LaTeXUtils.safe_read(loga)
    latex_rerun_requested?(log_content)
  end

  def latex_rerun_requested?(log_content)
    return true if log_content =~ /Label\(s\) may have changed/i
    return true if log_content =~ /Rerun to get/i
    return true if log_content =~ /Please rerun LaTeX/i
    return true if log_content =~ /There were undefined references/i
    return true if log_content =~ /There were undefined citations/i
    return true if log_content =~ /Package rerunfilecheck Warning: File .* has changed/i
    return true if log_content =~ /Package ocgx2 Warning: Rerun/i

    false
  end

  def aux_has_cross_references?(aux_hash)
    aux_hash.match?(/\\(?:newlabel|citation|@writefile)/)
  end

  def check_source_braces
    if File.file?(@filename)
      errs = LaTeXBraceChecker.check_file(@filename)
      return errs unless errs.empty?
    end

    candidates = collect_brace_check_candidates
    candidates.each do |f|
      errs = LaTeXBraceChecker.check_file(f)
      return errs unless errs.empty?
    end

    []
  rescue StandardError => e
    warn "Warning: Brace check failed: #{e.message}" if @options[:verbose]
    []
  end

  def collect_brace_check_candidates
    candidates = []
    if File.exist?("junk/#{@bfilename}.fls")
      candidates.concat(extract_fls_dependencies("junk/#{@bfilename}.fls").select { |f| f.end_with?('.tex') })
    end
    candidates.concat(Dir['*.tex', '*/*.tex'].select { |f| File.file?(f) })
    patterns = @options[:exclude_source_tex] || LaTeXUtils::DEFAULT_EXCLUDE_SOURCE_PATTERNS
    candidates.uniq.reject do |f|
      f == @filename || patterns.any? { |pat| File.fnmatch?(pat, f, File::FNM_CASEFOLD | File::FNM_EXTGLOB) }
    end
  end

  def update_target_file(src, dst, update_on_diff: false)
    return unless File.exist?(src)

    if update_on_diff && File.exist?(dst) && dst.end_with?('.pdf') && LaTeXUtils.command_available?('pdftotext')
      return if pdf_text_unchanged?(src, dst)
    end

    atomic_copy(src, dst)
    puts "  Updated target: #{dst}" if update_on_diff
  end

  # The exit status used to be discarded and only the captured output compared,
  # so two failure modes both looked like "no change": a figure-only document
  # has no text layer, making both extractions the empty string, and a
  # pdftotext failure returns the same error text for both. Either one kept the
  # previous PDF in place forever. update_on_diff can be enabled globally in
  # config, so this was not limited to an explicit -d.
  def pdf_text_unchanged?(src, dst)
    txt_src, status_src = Open3.capture2e('pdftotext', '-layout', src, '-')
    txt_dst, status_dst = Open3.capture2e('pdftotext', '-layout', dst, '-')
    return false unless status_src.success? && status_dst.success?

    if txt_src.strip.empty?
      puts "\n  #{Rainbow('No extractable text layer; comparing bytes instead.').yellow}"
      return FileUtils.identical?(src, dst)
    end
    return false unless txt_src == txt_dst

    puts "\n  \e[37;45m PDF text content unchanged (skipped target overwrite) \e[0m"
    true
  end

  def atomic_copy(src, dst)
    tmp = "#{dst}.tmp.#{Process.pid}"
    FileUtils.cp(src, tmp)
    File.rename(tmp, dst)
  rescue StandardError
    FileUtils.cp(src, dst)
  ensure
    FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
  end
end
