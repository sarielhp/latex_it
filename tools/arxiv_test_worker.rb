#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'time'

# Internal worker for test_arxiv. Runs only in the workspace staged by bws_run.
module ArxivTestWorker
  class CheckError < StandardError; end

  class Runner
    def initialize(root)
      ENV['LANG'] = ENV['LC_ALL'] = 'C.UTF-8'
      Encoding.default_external = Encoding::UTF_8
      @root = root
      @config = JSON.parse(File.read(File.join(root, 'test-config.json')))
      @engine = @config['engine']
      @main = File.join(root, 'paper', @config.fetch('main'))
      @project = File.dirname(@main)
      @pdf = @main.sub(/\.tex\z/i, '.pdf')
      @latex = File.join(root, 'latex_it')
      @logs = File.join(root, 'test-logs')
      @counter = File.join(@logs, 'engine-invocations.jsonl')
      FileUtils.mkdir_p(@logs)
      @report = { status: 'RUNNING', completed: false, main: @config['main'], engine: @engine || 'automatic',
                  latex_it_sha256: Digest::SHA256.file(@latex).hexdigest, locale: 'C.UTF-8', checks: [] }
    end

    def run
      ready = check('environment') { prepare }
      built = ready && check('fresh_build') do
        FileUtils.rm_f(@pdf)
        result = compile
        require_success(result)
        assert(result[:passes].positive?, 'fresh build did not invoke the compiler')
        assert(File.file?(@pdf) && File.binread(@pdf, 5) == '%PDF-', 'build did not produce a PDF')
        text = command(['pdftotext', '-layout', @pdf, File.join(@logs, 'reference.txt')])
        require_success(text)
        { detail: 'Fresh compilation produced a readable PDF.', **result }
      end
      if built
        exercise_build
        check('metadata') { metadata }
        check('portable_archive') { package('--zip', '--verify') }
        check('arxiv_archive') { package('--arxiv', '--arxiv-verify', '--arxiv-visual-verify') }
      else
        %w[unchanged_rerun fast_rerun single_pass settle_after_single_pass pdf_diff
           dependency_change dependency_rerun invalid_tex recovery metadata portable_archive arxiv_archive].each do |name|
          record(name, 'SKIP', detail: 'Requires a successful fresh build.')
        end
      end
      @report[:completed] = true
      @report[:status] = @report[:checks].all? { |c| c[:status] == 'PASS' } ? 'PASS' : 'FAIL'
      save
      @report[:status] == 'PASS' ? 0 : 1
    end

    def prepare
      required = [*@engine, 'pdftotext', 'pdftoppm', 'zip', 'unzip']
      missing = required.reject { |name| executable(name) }
      assert(missing.empty?, "Missing tools: #{missing.join(', ')}")
      real_engine = executable(@engine || 'xelatex')
      @report[:engine_version] = Open3.capture2e(real_engine, '--version').first.lines.first.to_s.strip
      @report[:latex_it_version] = Open3.capture2e(RbConfig.ruby, @latex, '--version').first.strip
      wrappers = File.join(@root, 'test-engine-bin')
      FileUtils.mkdir_p(wrappers)
      wrapper_engines = @engine ? [@engine] : %w[xelatex lualatex pdflatex]
      wrapper_engines.each do |engine|
        real_engine = executable(engine)
        next unless real_engine

        wrapper = "#!/usr/bin/env ruby\nrequire 'json'\n" \
                  "File.open(#{@counter.dump}, 'a') { |f| f.puts(JSON.generate(ARGV)) }\n" \
                  "exec(#{real_engine.dump}, *ARGV)\n"
        File.write(File.join(wrappers, engine), wrapper)
        File.chmod(0o755, File.join(wrappers, engine))
      end
      ENV['PATH'] = "#{wrappers}:#{ENV.fetch('PATH')}"
      { detail: 'Required tools available; compiler invocations recorded independently.' }
    end

    def executable(name)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
         .find { |path| File.file?(path) && File.executable?(path) }
    end

    def exercise_build
      check('unchanged_rerun') { unchanged }
      check('fast_rerun') { unchanged('--fast') }
      check('single_pass') do
        result = compile('--single-pass')
        require_success(result)
        assert(result[:passes] == 1, "Expected exactly one compiler pass; got #{result[:passes]}")
        result
      end
      check('settle_after_single_pass') { require_success(compile) }
      check('pdf_diff') { diff }
      change_dependency
      failure_recovery
    end

    def unchanged(*flags)
      before = pdf_state
      result = compile(*flags)
      require_success(result)
      assert(result[:passes].zero?, "Unchanged input caused #{result[:passes]} compiler passes")
      assert(before == pdf_state, 'Unchanged rerun replaced the PDF')
      result.merge(detail: 'Zero compiler passes; PDF hash and modification time unchanged.')
    end

    def diff
      before = pdf_state
      result = compile('--single-pass', '--diff')
      require_success(result)
      assert(result[:passes] == 1, 'Diff test did not perform its forced compiler pass')
      assert(before == pdf_state, 'Text-identical forced build replaced the PDF')
      result.merge(detail: 'Forced rebuild preserved PDF hash and modification time.')
    end

    def dependency
      recorder = File.join(@project, 'junk', File.basename(@main, File.extname(@main)) + '.fls')
      paths = if File.file?(recorder)
                File.readlines(recorder).grep(/^INPUT /).map do |line|
                  line.delete_prefix('INPUT ').strip
                end
              else
                []
              end
      paths.map { |path| File.expand_path(path, @project) }.find do |path|
        path != @main && path.start_with?(File.join(@root, 'paper') + '/') &&
          !path.include?('/junk/') && path.end_with?('.tex') && File.file?(path)
      end || @main
    end

    def change_dependency
      # Restore ordinary cache settings before the same-mtime dependency probe.
      settled = check('settle_before_dependency') { require_success(compile) }
      return record('dependency_change', 'SKIP', detail: 'Could not establish baseline.') unless settled

      path = dependency
      original = File.binread(path)
      stat = File.stat(path)
      check('dependency_change') do
        File.binwrite(path, original + "\n% latex_it dependency probe\n")
        File.utime(stat.atime, stat.mtime, path)
        result = compile
        require_success(result)
        assert(result[:passes].positive?, 'Changed source with preserved mtime was incorrectly cached')
        result.merge(detail: "Rebuilt after changing #{path.delete_prefix(@root + '/')} with its mtime preserved.")
      end
      check('dependency_rerun') { unchanged }
    ensure
      if original
        File.binwrite(path, original)
        File.utime(stat.atime, stat.mtime, path)
      end
    end

    def failure_recovery
      original = File.binread(@main)
      stat = File.stat(@main)
      check('invalid_tex') do
        File.binwrite(@main, "\\latexItDeliberatelyUndefinedProbe\n" + original)
        result = compile
        assert(result[:passes].positive?, 'Invalid-input check never invoked the compiler')
        assert(result[:exit_status] != 0, 'Invalid TeX unexpectedly returned success')
        result.merge(detail: 'Deliberately invalid TeX correctly returned a nonzero exit status.')
      end
      File.binwrite(@main, original)
      File.utime(stat.atime, stat.mtime, @main)
      check('recovery') do
        result = compile
        require_success(result)
        assert(result[:passes].positive?, 'Recovery incorrectly reused the failed build cache')
        result
      end
    ensure
      if original
        File.binwrite(@main, original)
        File.utime(stat.atime, stat.mtime, @main)
      end
    end

    def metadata
      load File.join(@root, 'tools', 'check_arxiv_metadata')
      reference = ArxivMetadataReport.reference_metadata(JSON.parse(File.read(File.join(@root, 'metadata.json'))))
      content = ArxivMetadataReport.utf8(File.binread(@main))
      extracted = { title: LaTeXMetaExtractor.extract_title(content),
                    authors: LaTeXMetaExtractor.extract_author_names(content),
                    abstract: LaTeXMetaExtractor.extract_abstract(content) }
      comparisons = ArxivMetadataReport.compare_metadata(reference, extracted)
      pdf = ArxivMetadataReport.check_pdf(@pdf, reference[:authors])
      details = { comparisons: comparisons, pdf: pdf }
      File.write(File.join(@logs, 'metadata.json'), JSON.pretty_generate(details) + "\n")
      matched = %i[title authors].all? { |key| comparisons[key][:status] == 'match' } && pdf[:status] == 'match'
      assert(matched,
             'arXiv title/authors or PDF page-one authors differ; see test-logs/metadata.json. Source metadata can legitimately differ.')
      { detail: 'Extracted title/authors match arXiv metadata; reference authors appear on PDF page one.',
        metadata: details }
    end

    def package(*flags)
      result = compile(*flags)
      require_success(result)
      output = File.read(result[:log])
      assert(output.include?('[VERIFIED]'), 'Command succeeded without confirming archive verification')
      if flags.include?('--arxiv')
        assert(output.match?(/visual|pixel|rendered/i) && !output.match?(/visual.*skip/i),
               'arXiv visual verification did not run')
      end
      result.merge(detail: if flags.include?('--arxiv')
                             'arXiv rebuild, text, author and rendered-page checks passed.'
                           else
                             'Portable archive rebuilt and passed PDF text comparison.'
                           end)
    end

    def pdf_state
      [Digest::SHA256.file(@pdf).hexdigest, File.stat(@pdf).mtime.to_r.to_s]
    end

    def compile(*flags)
      args = [RbConfig.ruby, @latex, '--emacs']
      args += ['--engine', @engine] if @engine
      command([*args, *flags, File.basename(@main)])
    end

    def command(argv)
      before = File.file?(@counter) ? File.foreach(@counter).count : 0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @command_index = (@command_index || 0) + 1
      log = File.join(@logs, format('%02d-%s.log', @command_index, @active_check))
      @last_command = { command: argv, log: log }
      pid = Process.spawn(*argv, chdir: @project, out: log, err: %i[child out])
      _, status = Process.wait2(pid)
      after = File.file?(@counter) ? File.foreach(@counter).count : 0
      @last_command.merge!(exit_status: status.exitstatus || 128 + status.termsig,
                           elapsed: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
                           passes: after - before)
      @last_command.dup
    end

    def require_success(result)
      assert(result[:exit_status].zero?, "Command exited #{result[:exit_status]}; see #{result[:log]}")
      result
    end

    def assert(condition, message)
      raise CheckError, message unless condition
    end

    def check(name)
      @active_check = name
      @last_command = {}
      @report[:running_check] = name
      save
      result = yield
      record(name, 'PASS', **(result || {}))
      true
    rescue StandardError => e
      record(name, 'FAIL', **@last_command, detail: "#{e.class}: #{e.message}")
      false
    end

    def record(name, status, **details)
      @report[:checks] << details.merge(name: name, status: status)
      @report.delete(:running_check)
      save
      puts "#{status}: #{name}#{details[:detail] ? ' — ' + details[:detail] : ''}"
      $stdout.flush
    end

    def save
      @report[:updated_at] = Time.now.utc.iso8601
      path = File.join(@root, 'test-worker-report.json')
      File.write(path + '.tmp', JSON.pretty_generate(@report) + "\n")
      File.rename(path + '.tmp', path)
    end
  end
end

exit ArxivTestWorker::Runner.new(Dir.pwd).run if __FILE__ == $PROGRAM_NAME
