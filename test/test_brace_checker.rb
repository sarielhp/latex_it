#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'

require_relative '../lib/latex_it/utils'
require_relative '../lib/latex_it/brace_checker'

# The brace checker runs on every failed build and its findings are stamped
# index: -1000, which sorts them ahead of every real TeX error. A false positive
# here is therefore the first thing a user reads when something goes wrong, so
# these tests are mostly about valid LaTeX it must stay silent on.
class TestBraceChecker < Minitest::Test
  def check(source)
    Dir.mktmpdir('latex_it_brace_test') do |dir|
      path = File.join(dir, 'doc.tex')
      File.write(path, source)
      LaTeXBraceChecker.check_file(path)
    end
  end

  def assert_silent(source, label)
    errors = check(source)
    assert_empty errors.map { |e| e[:text] }, "false positive on #{label}"
  end

  def test_macro_definitions_containing_environments_are_not_flagged
    {
      'newenvironment' => "\\newenvironment{note}{\\begin{quote}\\itshape}{\\end{quote}}\n",
      'renewenvironment' => "\\renewenvironment{abstract}{\\begin{center}}{\\end{center}}\n",
      'newcommand wrapping begin' => "\\newcommand{\\startbox}{\\begin{center}}\n",
      'def wrapping end' => "\\def\\stopbox{\\end{center}}\n",
      'providecommand' => "\\providecommand{\\x}{\\begin{itemize}}\n",
      'DeclareRobustCommand' => "\\DeclareRobustCommand{\\y}{\\begin{tabular}{ll}}\n"
    }.each { |label, src| assert_silent(src, label) }
  end

  def test_full_preamble_with_newenvironment_is_clean
    source = <<~TEX
      \\documentclass{article}
      \\newenvironment{note}{\\begin{quote}\\itshape}{\\end{quote}}
      \\begin{document}
      \\begin{note}Hello\\end{note}
      \\end{document}
    TEX

    assert_silent(source, 'a document whose preamble defines an environment')
  end

  def test_genuine_unclosed_brace_is_still_reported
    source = <<~TEX
      \\documentclass{article}
      \\begin{document}
      \\begin{theorem}
      \\frac{Y_{i-1}{2}.
      \\end{theorem}
      \\end{document}
    TEX

    errors = check(source)
    refute_empty errors, 'the checker stopped reporting a real unclosed brace'
    assert_match(/Unclosed open brace/, errors.first[:text])
  end

  def test_genuine_extra_closing_brace_is_still_reported
    errors = check("\\documentclass{article}\n\\begin{document}\nx}y\n\\end{document}\n")
    refute_empty errors, 'the checker stopped reporting a real extra closing brace'
    assert_match(/Extra closing brace/, errors.first[:text])
  end
end
