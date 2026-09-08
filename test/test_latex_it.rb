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
end
