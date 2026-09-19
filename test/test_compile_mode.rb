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

  def test_multiply_defined_label_pinpointing_in_compile_mode
    Dir.mktmpdir('compile_dup_labels') do |dir|
      File.write(File.join(dir, 'chap1.tex'), <<~TEX)
        \\section{Chapter One}
        \\label{sec:duplicate}
        Content of chapter one.
      TEX

      File.write(File.join(dir, 'chap2.tex'), <<~TEX)
        \\section{Chapter Two}
        \\label{sec:duplicate}
        Content of chapter two.
      TEX

      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\input{chap1}
        \\input{chap2}
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '-cc', '--no-color', 'main.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"

      lines = out.lines.map(&:strip)
      loc1 = lines.find { |l| l.include?('chap1.tex:2:') && l.include?('multiply defined (location 1 of 2)') }
      loc2 = lines.find { |l| l.include?('chap2.tex:2:') && l.include?('multiply defined (location 2 of 2)') }

      refute_nil loc1, "Expected location 1 in chap1.tex:2. Output:\n#{out}"
      refute_nil loc2, "Expected location 2 in chap2.tex:2. Output:\n#{out}"
      refute_match(/\.aux:1:/, out, 'Must not attribute multiply defined label to the .aux file')
    end
  end

  def test_multiply_defined_label_with_macro_in_compile_mode
    Dir.mktmpdir('compile_macro_dup') do |dir|
      File.write(File.join(dir, 'chap1.tex'), <<~TEX)
        \\section{Chapter One}
        \\mylabel{sec:custom}
        Content of chapter one.
      TEX

      File.write(File.join(dir, 'chap2.tex'), <<~TEX)
        \\section{Chapter Two}
        \\mylabel{sec:custom}
        Content of chapter two.
      TEX

      File.write(File.join(dir, 'main.tex'), <<~TEX)
        \\documentclass{article}
        \\newcommand{\\mylabel}[1]{\\label{#1}}
        \\begin{document}
        \\input{chap1}
        \\input{chap2}
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '-cc', '--no-color', 'main.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"

      lines = out.lines.map(&:strip)
      loc1 = lines.find { |l| l.include?('chap1.tex:2:') && l.include?('multiply defined (location 1 of 2)') }
      loc2 = lines.find { |l| l.include?('chap2.tex:2:') && l.include?('multiply defined (location 2 of 2)') }

      refute_nil loc1, "Expected location 1 in chap1.tex:2. Output:\n#{out}"
      refute_nil loc2, "Expected location 2 in chap2.tex:2. Output:\n#{out}"
      refute_match(/\.aux:1:/, out, 'Must not attribute multiply defined label to the .aux file')
    end
  end

  def test_compile_mode_with_link_flag
    Dir.mktmpdir('compile_links') do |dir|
      File.write(File.join(dir, 'doc.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefcommand
        \\end{document}
      TEX

      # Explicit --link enables OSC 8 escape sequences even in non-tty subprocess
      out, status = Open3.capture2e(@bin_path, '-cc', '--link', 'doc.tex', chdir: dir)
      assert_equal 1, status.exitstatus
      assert_includes out, "\e]8;;file://"
      assert_includes out, "doc.tex:3:1:\e]8;;\e\\"

      # Explicit --no-link guarantees zero OSC 8 sequences
      out_nolink, status_nolink = Open3.capture2e(@bin_path, '-cc', '--no-link', 'doc.tex', chdir: dir)
      assert_equal 1, status_nolink.exitstatus
      refute_includes out_nolink, "\e]8;;"
      assert_match(/^doc\.tex:3:1: error: undefined control sequence/, out_nolink)
    end
  end

  def test_compile_mode_auto_detects_kitty_in_tty
    Dir.mktmpdir('compile_pty') do |dir|
      File.write(File.join(dir, 'doc.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\undefcommand
        \\end{document}
      TEX

      env = { 'KITTY_WINDOW_ID' => '1', 'TERM' => 'xterm-kitty', 'LATEX_IT_THEME' => 'blush' }
      cmd = "cd #{dir} && #{@bin_path} -cc doc.tex"
      output = String.new
      require 'pty'
      PTY.spawn(env, 'bash', '-c', cmd) do |r, _w, _pid|
        begin
          r.each_line { |line| output << line }
        rescue Errno::EIO
        end
      end
      assert_includes output, "\e]8;;file://"
      assert_includes output, "doc.tex:3:1:"
      assert_includes output, "\e]8;;\e\\"
    end
  end

  def test_compile_mode_on_latex_file_via_ll_symlink
    Dir.mktmpdir('compile_ll_symlink') do |dir|
      ll_bin = File.join(dir, 'll')
      FileUtils.ln_s(@bin_path, ll_bin)

      File.write(File.join(dir, 'sample.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        Hello world from ll compile mode.
        \\end{document}
      TEX

      # Explicit file target via ll -cc
      out, status = Open3.capture2e(ll_bin, '-cc', 'sample.tex', chdir: dir)
      assert_equal 0, status.exitstatus, "Expected exit 0. Output: #{out}"
      assert File.file?(File.join(dir, 'sample.pdf')), 'Expected sample.pdf to be generated'

      # Implicit target via ll -cc (auto-detect main file in directory)
      FileUtils.rm_f(File.join(dir, 'sample.pdf'))
      FileUtils.rm_rf(File.join(dir, 'junk'))
      out_auto, status_auto = Open3.capture2e(ll_bin, '-cc', chdir: dir)
      assert_equal 0, status_auto.exitstatus, "Expected exit 0 with auto-detected file. Output: #{out_auto}"
      assert File.file?(File.join(dir, 'sample.pdf')), 'Expected sample.pdf to be generated on auto-detect'
    end
  end

  def test_compile_mode_in_directory_with_no_tex_files
    Dir.mktmpdir('compile_no_tex') do |dir|
      out, status = Open3.capture2e(@bin_path, '-cc', chdir: dir)
      assert_equal 1, status.exitstatus
      refute_includes out, 'from /'
      refute_includes out, 'Traceback'
      assert_includes out, 'No LaTeX (.tex) files found'
    end
  end

  def test_compile_mode_suppresses_warnings_when_errors_present
    Dir.mktmpdir('compile_err_and_warn') do |dir|
      File.write(File.join(dir, 'bad.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        \\hbox to 20pt{\\rule{100pt}{10pt}}
        Missing ref: \\ref{nonexistent_ref}.
        \\fatalundefinedcmd
        \\end{document}
      TEX

      # Default -cc: errors are emitted, but alerts and warnings are suppressed
      out, status = Open3.capture2e(@bin_path, '-cc', '--no-color', 'bad.tex', chdir: dir)
      assert_equal 1, status.exitstatus
      assert_includes out, 'error: undefined control sequence'
      refute_includes out, 'warning:'
      refute_includes out, 'overfull'
      refute_includes out, 'nonexistent_ref'

      # With -a / --all: warnings and alerts are shown alongside errors
      out_all, status_all = Open3.capture2e(@bin_path, '-cc', '-a', '--no-color', 'bad.tex', chdir: dir)
      assert_equal 1, status_all.exitstatus
      assert_includes out_all, 'error: undefined control sequence'
      assert_includes out_all, 'warning: [alert] overfull'
      assert_includes out_all, 'warning: reference `nonexistent_ref\''
    end
  end

  def test_compile_mode_throttles_errors_to_ten_by_default
    Dir.mktmpdir('compile_throttle') do |dir|
      bad_tex = File.join(dir, 'many_errors.tex')
      error_cmds = (1..15).map { |i| "\\errCommand#{i}" }.join("\n")
      File.write(bad_tex, <<~TEX)
        \\documentclass{article}
        \\begin{document}
        #{error_cmds}
        \\end{document}
      TEX

      out, status = Open3.capture2e(@bin_path, '-cc', '--no-color', 'many_errors.tex', chdir: dir)
      assert_equal 1, status.exitstatus
      error_lines = out.lines.select { |l| l.include?('error: undefined control sequence') }
      assert_equal 10, error_lines.size, "Expected exactly 10 errors displayed, got #{error_lines.size}: #{out}"
      assert_includes out, 'note: 5 more errors in many_errors.tex were truncated'
      assert_includes out, "(run with 'l -a' to display all)"

      # With -a, all 15 errors should be displayed
      out_all, status_all = Open3.capture2e(@bin_path, '-cc', '-a', '--no-color', 'many_errors.tex', chdir: dir)
      assert_equal 1, status_all.exitstatus
      error_lines_all = out_all.lines.select { |l| l.include?('error: undefined control sequence') }
      assert_equal 15, error_lines_all.size, "Expected 15 errors with -a, got #{error_lines_all.size}: #{out_all}"
      refute_includes out_all, 'were truncated'
    end
  end
end
