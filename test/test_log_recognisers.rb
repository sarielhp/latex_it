#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

load File.expand_path('../latex_it', __dir__)

# The engine's terminal log is the only evidence the tool has about a build.
# These tests pin the three recognisers that read it: the gate that decides a
# pass failed, the pattern that finds a warning, and the bibliography scanner.
class TestLogRecognisers < Minitest::Test
  OPTIONS = {
    engine: 'xelatex', score: false, emacs: true, verbose: false, werror: false,
    suppress_whatevers: true, suppress_warnings: false, suppress_alerts: false,
    alert_overfull_pt: 24.0, whatever_overfull_pt: 2.5, explain: false, passes: 3,
    lock: false
  }.freeze

  def builder(biberr = nil)
    b = LatexBuilder.new('paper.tex', OPTIONS)
    b.instance_variable_set(:@biberr, biberr)
    b
  end

  def with_log(content)
    Dir.mktmpdir('latex_it_log_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('junk/err_xelatex_1', content)
        yield 'junk/err_xelatex_1', content
      end
    end
  end

  # TeX echoes the offending paragraph after every Overfull \hbox, so document
  # text reaches the log verbatim. An unanchored substring scan counted it.
  def test_document_text_containing_error_does_not_fail_the_build
    log = <<~LOG
      Overfull \\hbox (7.0pt too wide) in paragraph at lines 21--22
      []\\OT1/cmr/m/n/10 the tool prints Error: no such file when the path is wrong,
      Output written on junk/paper.pdf (1 page).
    LOG

    with_log(log) do |path, content|
      b = builder
      assert_equal 0, b.send(:count_errors_in_log, 0, path),
                   'a document containing the literal "Error:" failed its own successful build'
      assert_equal 0, b.send(:count_latex_errors, content, 0)
    end
  end

  def test_document_text_naming_tex_diagnostics_does_not_fail_the_build
    log = <<~LOG
      Overfull \\hbox (9.0pt too wide) in paragraph at lines 8--9
      []\\OT1/cmr/m/n/10 an Undefined control sequence is what TeX re-ports here,
      Overfull \\hbox (3.0pt too wide) in paragraph at lines 12--13
      []\\OT1/cmr/m/n/10 a Runaway argument? is the other com-mon shape,
    LOG

    with_log(log) do |path, _content|
      assert_equal 0, builder.send(:count_errors_in_log, 0, path)
    end
  end

  def test_real_errors_are_still_counted
    file_line = "./paper.tex:12: LaTeX Error: Environment foo undefined.\nl.12 \\begin{foo}\n"
    bang = "! Undefined control sequence.\nl.5 \\badmacro\n"

    with_log(file_line) do |path, content|
      assert_operator builder.send(:count_errors_in_log, 0, path), :>, 0,
                      'a real file-line-error was not counted'
      assert_operator builder.send(:count_latex_errors, content, 0), :>, 0
    end

    with_log(bang) do |path, _content|
      assert_operator builder.send(:count_errors_in_log, 0, path), :>, 0,
                      'a real "!" error was not counted'
    end
  end

  def test_nonzero_engine_status_always_counts
    with_log("Output written on junk/paper.pdf (1 page).\n") do |path, _content|
      assert_operator builder.send(:count_errors_in_log, 1, path), :>, 0,
                      'a non-zero engine exit status must always count as a failure'
    end
  end
end
