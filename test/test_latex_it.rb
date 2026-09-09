#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class TestLatexItCLI < Minitest::Test
  BIN = File.expand_path('../latex_it', __dir__)
  load BIN

  def test_version_flag
    stdout, status = Open3.capture2(BIN, '-V')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert_match(/^l \d+\.\d+\.\d+/, stdout)
  end

  def test_help_flag
    stdout, status = Open3.capture2(BIN, '-h')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert_includes stdout, 'Usage: l [options]'
    assert_includes stdout, '--engine'
    assert_includes stdout, '--fast'
    assert_includes stdout, '-Werror'
    assert_includes stdout, '--deps'
  end

  def test_pdflatex_rejected
    _stdout, stderr, status = Open3.capture3(BIN, '--pdflatex')
    refute status.success?, 'Expected pdflatex to be rejected with non-zero exit code'
    assert_includes stderr, 'PDFLatex by now is outdated'
  end

  def test_find_main_flag_with_mainfile
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.mainfile'), "document.tex\n")
      File.write(File.join(dir, 'other.tex'), "\\begin{document}\\end{document}\n")

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-m')
        assert status.success?
        assert_equal "document.tex\n", stdout
      end
    end
  end

  def test_find_main_flag_directory_name_heuristic
    Dir.mktmpdir('my_paper') do |dir|
      dir_name = File.basename(dir)
      File.write(File.join(dir, "#{dir_name}.tex"), "\\begin{document}\\end{document}\n")
      File.write(File.join(dir, 'random.tex'), "content\n")

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-m')
        assert status.success?
        assert_equal "#{dir_name}.tex\n", stdout
      end
    end
  end

  def test_clean_only_flag
    Dir.mktmpdir do |dir|
      # Create mock junk files
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'temp.aux'), 'temp')
      File.write(File.join(dir, 'test.aux'), 'aux')
      File.write(File.join(dir, 'test.log'), 'log')

      Dir.chdir(dir) do
        _stdout, status = Open3.capture2(BIN, '-C')
        assert status.success?
        refute File.exist?(File.join(dir, 'junk'))
        refute File.exist?(File.join(dir, 'test.aux'))
        refute File.exist?(File.join(dir, 'test.log'))
      end
    end
  end

  def test_deps_flag_cli
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\begin{document}\\end{document}\n")
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => {}, 'extra.tex' => {} }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-M', 'paper.tex')
        assert status.success?
        assert_equal "paper.pdf: extra.tex paper.tex\n", stdout

        stdout_long, status_long = Open3.capture2(BIN, '--deps', 'paper.tex')
        assert status_long.success?
        assert_equal "paper.pdf: extra.tex paper.tex\n", stdout_long
      end
    end
  end

  def test_diagnostic_formatting_no_redundant_w
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)
    formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    refute_includes formatted, 'W:'
    assert_includes formatted, Rainbow('42').cyan.bright.to_s
    assert_includes formatted, Rainbow(': ').yellow.bright.to_s

    # In plain/monochrome mode, verify plain 42: prefix
    Rainbow.enabled = false
    mono_formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    refute_includes mono_formatted, 'W:'
    assert_equal '42: Package hyperref Warning: Token not allowed on input line 42.', mono_formatted

    # In emacs mode, verify line prefixes are completely suppressed
    emacs_builder = LatexBuilder.new('sample.tex', emacs: true)
    emacs_formatted = emacs_builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    assert_equal 'Package hyperref Warning: Token not allowed on input line 42.', emacs_formatted
  end

  def test_diagnostic_formatting_empty_line_str
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)
    formatted = builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    refute_includes formatted, 'W:'
    assert_includes formatted, Rainbow(': ').yellow.bright.to_s

    Rainbow.enabled = false
    mono_formatted = builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    assert_equal ': LaTeX Warning: Label(s) may have changed.', mono_formatted

    emacs_builder = LatexBuilder.new('sample.tex', emacs: true)
    emacs_formatted = emacs_builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    assert_equal 'LaTeX Warning: Label(s) may have changed.', emacs_formatted
  end

  def test_line_number_colorization_left_and_inside
    Rainbow.enabled = true
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)

    formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: on input line 42.', :yellow)
    cyan_bright_42 = Rainbow('42').cyan.bright.to_s
    assert_includes formatted, cyan_bright_42

    # Verify both left side and message interior have the highlighted number
    occurrences = formatted.scan(cyan_bright_42).size
    assert_equal 2, occurrences, 'Expected 42 to be highlighted in cyan.bright both on left side and inside message'
  end

  def test_error_line_number_colorization
    Rainbow.enabled = true
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)

    err_lines = ['./sample.tex:42: Undefined control sequence.', 'l.42 \\badcommand']
    formatted = builder.send(:format_error_block, err_lines, 42)
    cyan_bright_42 = Rainbow('42').cyan.bright.to_s
    assert_includes formatted, cyan_bright_42
  end

  def test_left_width_alignment
    Rainbow.enabled = false
    builder = LatexBuilder.new('sample.tex', emacs: false, color: false)

    # Testing formatting with width = 10 (as in 1071--1075)
    f_range = builder.send(:format_diagnostic_line, '1071--1075', 'Overfull \\hbox ...', :magenta, width: 10)
    f_short = builder.send(:format_diagnostic_line, '448', 'Overfull \\hbox ...', :magenta, width: 10)
    f_empty = builder.send(:format_diagnostic_line, '', 'Warning without line', :yellow, width: 10)

    assert_match(/^1071--1075: Overfull/, f_range)
    assert_match(/^       448: Overfull/, f_short)
    assert_match(/^          : Warning/, f_empty)

    # Check colon positions: all must align at index 10 (11th character)
    assert_equal 10, f_range.index(':')
    assert_equal 10, f_short.index(':')
    assert_equal 10, f_empty.index(':')
  end

  def test_extract_fls_dependencies
    Dir.mktmpdir do |dir|
      fls_content = <<~FLS
        PWD #{dir}
        INPUT /usr/share/texmf/base.cls
        INPUT #{dir}/main.tex
        INPUT #{dir}/sections/intro.tex
        INPUT #{dir}/junk/main.aux
        OUTPUT #{dir}/junk/main.pdf
      FLS

      FileUtils.mkdir_p(File.join(dir, 'junk'))
      FileUtils.mkdir_p(File.join(dir, 'sections'))
      File.write(File.join(dir, 'main.tex'), 'test')
      File.write(File.join(dir, 'sections', 'intro.tex'), 'intro')
      fls_path = File.join(dir, 'junk', 'main.fls')
      File.write(fls_path, fls_content)

      builder = LatexBuilder.new('main.tex', {})
      Dir.chdir(dir) do
        deps = builder.send(:extract_fls_dependencies, fls_path)
        assert_includes deps, 'main.tex'
        assert_includes deps, 'sections/intro.tex'
        refute_includes deps, 'junk/main.aux'
        refute deps.any? { |d| d.include?('/usr/share') }
      end
    end
  end

  def test_aux_has_cross_references
    builder = LatexBuilder.new('main.tex', {})
    refute builder.send(:aux_has_cross_references?, "\\relax\n\\@abspage@last{1}\n")
    assert builder.send(:aux_has_cross_references?, "\\newlabel{sec:one}{{1}{1}}\n")
    assert builder.send(:aux_has_cross_references?, "\\citation{knuth1984}\n")
    assert builder.send(:aux_has_cross_references?, "\\@writefile{toc}{\\contentsline {section}}\n")
  end

  def test_targets_up_to_date_logic
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      File.write(File.join(dir, 'paper.pdf'), 'mock pdf')
      FileUtils.mkdir_p(File.join(dir, 'junk'))

      sha = Digest::SHA256.file(File.join(dir, 'paper.tex')).hexdigest
      mtime = File.mtime(File.join(dir, 'paper.tex')).to_i
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => { 'mtime' => mtime, 'sha' => sha } }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      builder = LatexBuilder.new('paper.tex', {})
      Dir.chdir(dir) do
        assert builder.send(:targets_up_to_date?), 'Expected build to be up to date'

        # Test single_pass forces rebuild
        single_builder = LatexBuilder.new('paper.tex', single_pass: true)
        refute single_builder.send(:targets_up_to_date?)

        # Test clean forces rebuild
        clean_builder = LatexBuilder.new('paper.tex', clean: true)
        refute clean_builder.send(:targets_up_to_date?)

        # Test modified source triggers rebuild
        sleep 0.05
        File.write(File.join(dir, 'paper.tex'), 'modified content')
        refute builder.send(:targets_up_to_date?), 'Expected modified file to trigger rebuild'
      end
    end
  end

  def test_werror_forces_rebuild
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      File.write(File.join(dir, 'paper.pdf'), 'mock pdf')
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      sha = Digest::SHA256.file(File.join(dir, 'paper.tex')).hexdigest
      mtime = File.mtime(File.join(dir, 'paper.tex')).to_i
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => { 'mtime' => mtime, 'sha' => sha } }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      builder = LatexBuilder.new('paper.tex', werror: true)
      Dir.chdir(dir) do
        refute builder.send(:targets_up_to_date?), 'Expected werror to force rebuild'
      end
    end
  end

  def test_export_dependencies
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => {}, 'figures/fig1.pdf' => {} }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      builder = LatexBuilder.new('paper.tex', deps: true)
      Dir.chdir(dir) do
        out, = capture_io { builder.send(:export_dependencies) }
        assert_equal "paper.pdf: figures/fig1.pdf paper.tex\n", out
      end
    end
  end

  def test_multi_file_diagnostics
    log_content = <<~LOG
      This is XeTeX, Version 3.141592653-2.6-0.999996
      (./main.tex
      (./chapters/ch1.tex
      LaTeX Warning: Reference `sec:unknown' on page 1 undefined on input line 42.
      )
      (./chapters/ch2.tex
      Overfull \\hbox (15.0pt too wide) in paragraph at lines 10--15
      )
      ! LaTeX Error: File `missing.sty' not found.
      )
    LOG

    builder = LatexBuilder.new('main.tex', {})
    warnings = builder.send(:extract_warnings, log_content)
    errors = builder.send(:extract_errors, log_content)

    ch1_warn = warnings.find { |w| w[:text].include?('sec:unknown') }
    assert ch1_warn
    assert_equal './chapters/ch1.tex', ch1_warn[:file]
    assert_equal 42, ch1_warn[:line]

    ch2_warn = warnings.find { |w| w[:text].include?('Overfull') }
    assert ch2_warn
    assert_equal './chapters/ch2.tex', ch2_warn[:file]
    assert_equal 10, ch2_warn[:line]

    assert_equal 1, errors.size
    assert_equal './main.tex', errors.first[:file]

    out, = capture_io { builder.send(:print_diagnostics_body, warnings, errors) }
    assert_includes out, '(./chapters/ch1.tex'
    assert_includes out, '(./chapters/ch2.tex'
  end

  def test_werror_aborts_on_warnings
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_content = <<~LOG
        LaTeX Warning: Reference `sec:foo' on page 1 undefined on input line 10.
      LOG
      File.write(File.join(dir, 'junk', 'err_xelatex'), log_content)

      builder = LatexBuilder.new('paper.tex', werror: true)
      Dir.chdir(dir) do
        assert_raises(SystemExit) do
          capture_io { builder.send(:analyze_output) }
        end
      end
    end
  end
end
