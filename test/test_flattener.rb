#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/latex_it/utils'
require_relative '../lib/latex_it/flattener'

# The flattener's output is the .tex that ships inside arxiv_<base>.zip, so
# anything it gets wrong is published. Brace balance is the invariant that
# matters most: unbalanced output is not LaTeX at all.
class TestFlattener < Minitest::Test
  def assert_balanced(text, label)
    assert_equal text.count('{'), text.count('}'),
                 "#{label} produced unbalanced braces: #{text.inspect}"
  end

  def test_host_conditionals_are_removed_without_breaking_braces
    {
      'nested \\input in the true branch' =>
        '\IfFileExists{local.tex}{\input{local.tex}}{}',
      'nested \\usepackage and a false branch' =>
        '\IfFileExists{mycomputer.cfg}{\usepackage{x}}{\relax}',
      'two-argument form with a nested group' =>
        '\IfFileExists{local.tex}{\typeout{hi}}',
      'flat arguments' =>
        '\IfFileExists{local.tex}{AAA}{BBB}',
      'deeply nested branch' =>
        '\IfFileExists{private.sty}{\def\x{\y{z}}}{\relax}'
    }.each do |label, src|
      cleaned = LaTeXFlattener.clean_host_specific(src)
      assert_balanced(cleaned, label)
      refute_match(/IfFileExists/, cleaned, "#{label}: the conditional was not removed")
    end
  end

  def test_surrounding_content_survives
    src = "BEFORE\n\\IfFileExists{local.tex}{\\input{local.tex}}{}\nAFTER\n"
    cleaned = LaTeXFlattener.clean_host_specific(src)

    assert_includes cleaned, 'BEFORE'
    assert_includes cleaned, 'AFTER'
    assert_balanced(cleaned, 'surrounding content')
  end

  def test_unrelated_conditionals_are_left_untouched
    src = '\IfFileExists{figures.cfg}{\input{figures.cfg}}{\relax}'
    assert_equal src, LaTeXFlattener.clean_host_specific(src),
                 'a conditional not matching any host pattern must be preserved verbatim'
  end

  def test_custom_patterns_only_strip_their_own_matches
    src = "\\IfFileExists{secret.tex}{\\input{secret}}{}\n\\IfFileExists{computer.tex}{\\input{computer}}{}\nKeep this"
    cleaned = LaTeXFlattener.clean_host_specific(src, ['secret'])

    refute_includes cleaned, 'secret.tex'
    assert_includes cleaned, 'computer.tex'
    assert_includes cleaned, 'Keep this'
    assert_balanced(cleaned, 'custom patterns')
  end

  def test_malformed_conditional_is_left_alone
    src = '\IfFileExists{local.tex}{unterminated'
    assert_equal src, LaTeXFlattener.clean_host_specific(src),
                 'an unbalanced conditional must be preserved rather than half-deleted'
  end

  def test_verbatim_content_is_protected
    src = "\\begin{verbatim}\n\\IfFileExists{local.tex}{a}{b}\n\\end{verbatim}\n"
    assert_equal src, LaTeXFlattener.clean_host_specific(src),
                 'a conditional inside verbatim must be shown, not stripped'
  end
end
