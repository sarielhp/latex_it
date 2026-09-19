#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/latex_it/utils'

class TestCompileMode < Minitest::Test
  def setup
    @bin_path = File.expand_path('../latex_it', __dir__)
  end

  def test_clean_build_in_compile_mode_is_silent
    Dir.mktmpdir('compile_clean') do |dir|
      tex = File.join(dir, 'clean.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Clean document text.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', 'clean.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"
      assert_empty out.strip, "Expected zero stdout/stderr on clean build, got: #{out}"
    end
  end

  def test_error_formatting_and_gnu_compliance
    Dir.mktmpdir('compile_err') do |dir|
      tex = File.join(dir, 'bad.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\foobarunknown
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', '--no-color', 'bad.tex', chdir: dir)
      assert_equal 1, status.exitstatus, "Expected exit 1 on error. Output: #{out}"

      lines = out.lines.map(&:strip).reject(&:empty?)
      refute_empty lines, 'Expected at least one error line'

      # Assert standard GNU format: file:line:col: error: msg
      error_line = lines.find { |l| l.include?('error:') }
      refute_nil error_line, "Expected an error line in output: #{out}"
      assert_match(/\Abad\.tex:\d+(?::\d+)?: error: undefined control sequence/, error_line)
      refute_match(/\.\z/, error_line, 'GNU standard specifies message must not end with a period')

      # Assert no TUI artifacts
      refute_includes out, '── bad.tex'
      refute_includes out, 'Errors:'
      refute_includes out, 'Latex compilation failed'
    end
  end

  def test_alert_and_warning_formatting
    Dir.mktmpdir('compile_warn') do |dir|
      tex = File.join(dir, 'warn.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\hbox to 20pt{\\rule{100pt}{10pt}}
        Missing ref: \\ref{nonexistent_ref}.
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '--compile', '--no-color', '-u', 'warn.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"

      lines = out.lines.map(&:strip).reject(&:empty?)
      alert_line = lines.find { |l| l.include?('warning: [alert]') }
      refute_nil alert_line, "Expected alert warning in output: #{out}"
      assert_match(/\Awarn\.tex:3: warning: \[alert\] overfull \\hbox/, alert_line)
      refute_match(/\.\z/, alert_line)

      warn_line = lines.find { |l| l.include?('warning: reference') }
      refute_nil warn_line, "Expected regular warning in output: #{out}"
      assert_match(/\Awarn\.tex:4: warning: reference.*undefined/, warn_line)
      refute_match(/\.\z/, warn_line)
    end
  end

  def test_whatevers_hidden_by_default_and_shown_with_all
    Dir.mktmpdir('compile_what') do |dir|
      tex = File.join(dir, 'what.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\hbox to 20pt{\\rule{21.5pt}{10pt}}
        \\end{document}
      TEX

      # Default: whatevers are suppressed
      out_default, = Open3.capture2e(@bin_path, '--compile', '--no-color', '-u', 'what.tex', chdir: dir)
      refute_includes out_default, 'note: overfull \hbox'

      # With -a (--all): whatevers are shown as note:
      out_all, = Open3.capture2e(@bin_path, '--compile', '--no-color', '-u', '-a', 'what.tex', chdir: dir)
      assert_includes out_all, 'what.tex:3: note: overfull \hbox (1.5pt too wide) detected'
    end
  end

  def test_mutual_exclusion_with_emacs_flag
    out, status = Open3.capture2e(@bin_path, '--compile', '--emacs', 'some_file.tex')
    assert_equal 2, status.exitstatus
    assert_includes out, 'cannot be used together'
  end

  def test_color_controls
    Dir.mktmpdir('compile_color') do |dir|
      tex = File.join(dir, 'doc.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefcmd
        \\end{document}
      TEX

      # --no-color suppresses all escapes
      out_nocolor, = Open3.capture2e(@bin_path, '--compile', '--no-color', 'doc.tex', chdir: dir)
      refute_includes out_nocolor, "\e["

      # --color forces ANSI escapes
      out_color, = Open3.capture2e(@bin_path, '--compile', '--color', 'doc.tex', chdir: dir)
      assert_includes out_color, "\e["
    end
  end

  def test_shorthand_cc_flags
    Dir.mktmpdir('compile_shorthand') do |dir|
      tex = File.join(dir, 'doc.tex')
      File.write(tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefcmd
        \\end{document}
      TEX

      out_short, status_short = Open3.capture2e(@bin_path, '-cc', '--no-color', 'doc.tex', chdir: dir)
      assert_equal 1, status_short.exitstatus
      assert_match(/^doc\.tex:3:1: error: undefined control sequence/, out_short)

      out_double, status_double = Open3.capture2e(@bin_path, '--cc', '--no-color', 'doc.tex', chdir: dir)
      assert_equal 1, status_double.exitstatus
      assert_match(/^doc\.tex:3:1: error: undefined control sequence/, out_double)
    end
  end
end
