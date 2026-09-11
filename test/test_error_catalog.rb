#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
load File.expand_path('../latex_it', __dir__)

class TestErrorCatalog < Minitest::Test
  def test_classify_misplaced_alignment_tab
    text = "./main.tex:10: Misplaced alignment tab character &.\nl.10 x = 1 &"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :misplaced_alignment_tab, item[:id]
    assert_includes item[:hint], '&'
    assert_equal '01_misplaced_alignment_tab', item[:doc_slug]
  end

  def test_classify_undefined_control_sequence_extracts_token
    text = "./main.tex:5: Undefined control sequence.\nl.5 \\badcommand{foo}"
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :undefined_control_sequence, item[:id]
    assert_equal '\\badcommand', item[:token]
    assert_includes item[:hint], "Undefined command '\\badcommand'"
  end

  def test_classify_missing_item
    text = "./main.tex:4: LaTeX Error: Something's wrong--perhaps a missing \\item."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_item, item[:id]
    assert_includes item[:hint], '\\item'
  end

  def test_classify_missing_dollar
    text = "./main.tex:8: Missing $ inserted."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_dollar, item[:id]
    assert_includes item[:hint], '$'
  end

  def test_classify_extra_closing_brace
    text = "./main.tex:12: Too many }'s."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :extra_closing_brace, item[:id]

    text2 = "./main.tex:12: Extra }, or forgotten $."
    item2 = LaTeXErrorCatalog.classify(text2, text2.lines)
    assert item2
    assert_equal :extra_closing_brace, item2[:id]
  end

  def test_classify_paragraph_ended_before_complete
    text = "Runaway argument?\n{some unclosed brace\nParagraph ended before \\foo was complete."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :paragraph_ended_before_complete, item[:id]
  end

  def test_classify_environment_undefined_extracts_token
    text = "./main.tex:3: LaTeX Error: Environment myenv undefined."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :environment_undefined, item[:id]
    assert_equal 'myenv', item[:token]
    assert_includes item[:hint], "Undefined environment 'myenv'"
  end

  def test_classify_no_line_here_to_end
    text = "./main.tex:6: LaTeX Error: There's no line here to end."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :no_line_here_to_end, item[:id]
  end

  def test_classify_file_not_found_extracts_token
    text = "./main.tex:2: LaTeX Error: File `myheader.sty' not found."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :file_not_found, item[:id]
    assert_equal 'myheader.sty', item[:token]
    assert_includes item[:hint], "File 'myheader.sty' not found"
  end

  def test_classify_command_already_defined_extracts_token
    text = "./main.tex:2: LaTeX Error: Command \\foo already defined."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :command_already_defined, item[:id]
    assert_equal '\\foo', item[:token]
    assert_includes item[:hint], "Command '\\foo' already defined"
  end

  def test_classify_extra_alignment_tab
    text = "./main.tex:4: Extra alignment tab has been changed to \\cr."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :extra_alignment_tab, item[:id]
  end

  def test_classify_missing_number_treated_as_zero
    text = "./main.tex:3: Missing number, treated as zero."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_number_treated_as_zero, item[:id]
  end

  def test_classify_illegal_unit_of_measure
    text = "./main.tex:3: Illegal unit of measure (pt inserted)."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :illegal_unit_of_measure, item[:id]
  end

  def test_classify_double_subscript
    text = "./main.tex:3: Double subscript."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :double_subscript, item[:id]
  end

  def test_classify_double_superscript
    text = "./main.tex:3: Double superscript."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :double_superscript, item[:id]
  end

  def test_classify_option_clash_for_package_extracts_token
    text = "./main.tex:3: LaTeX Error: Option clash for package geometry."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :option_clash_for_package, item[:id]
    assert_equal 'geometry', item[:token]
    assert_includes item[:hint], "package 'geometry'"
  end

  def test_classify_lonely_item
    text = "./main.tex:3: LaTeX Error: Lonely \\item--perhaps a missing list environment."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :lonely_item, item[:id]
  end

  def test_classify_cannot_determine_size_of_graphic_extracts_token
    text = "./main.tex:3: LaTeX Error: Cannot determine size of graphic in mypic.xyz (no BoundingBox)."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :cannot_determine_size_of_graphic, item[:id]
    assert_equal 'mypic.xyz', item[:token]
  end

  def test_classify_not_in_outer_par_mode
    text = "./main.tex:3: LaTeX Error: Not in outer par mode."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :not_in_outer_par_mode, item[:id]
  end

  def test_classify_missing_delimiter
    text = "./main.tex:3: Missing delimiter (. inserted)."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_delimiter, item[:id]
  end

  def test_classify_only_in_preamble
    text = "./main.tex:3: LaTeX Error: Can be used only in preamble."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :only_in_preamble, item[:id]
  end

  def test_classify_extra_right
    text = "./main.tex:3: Extra \\right."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :extra_right, item[:id]
  end

  def test_classify_missing_begin_document
    text = "./main.tex:3: LaTeX Error: Missing \\begin{document}."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :missing_begin_document, item[:id]
  end

  def test_classify_dimension_too_large
    text = "./main.tex:3: Dimension too large."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :dimension_too_large, item[:id]
  end

  def test_classify_misplaced_noalign
    text = "./main.tex:3: Misplaced \\noalign."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :misplaced_noalign, item[:id]
  end

  def test_classify_bad_math_environment_delimiter
    text = "./main.tex:3: LaTeX Error: Bad math environment delimiter."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :bad_math_environment_delimiter, item[:id]
  end

  def test_classify_counter_too_large
    text = "./main.tex:3: LaTeX Error: Counter too large."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :counter_too_large, item[:id]
  end

  def test_classify_amsmath_multiple_tag
    text = "./main.tex:3: Package amsmath Error: Multiple \\tag."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :amsmath_multiple_tag, item[:id]
  end

  def test_classify_undefined_color_extracts_token
    text = "./main.tex:3: Package xcolor Error: Undefined color `mycolor'."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :undefined_color, item[:id]
    assert_equal 'mycolor', item[:token]
    assert_includes item[:hint], "color 'mycolor'"
  end

  def test_classify_mismatched_environment_extracts_token
    text = "./main.tex:3: LaTeX Error: \\begin{itemize} on input line 3 ended by \\end{enumerate}."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert item
    assert_equal :mismatched_environment, item[:id]
    assert_equal 'itemize vs enumerate', item[:token]
    assert_includes item[:hint], 'itemize vs enumerate'
  end

  def test_classify_unknown_error_returns_nil
    text = "./main.tex:10: Some totally unheard of exotic error message."
    item = LaTeXErrorCatalog.classify(text, text.lines)
    assert_nil item
  end

  def test_find_by_id
    entry = LaTeXErrorCatalog.find_by_id(:misplaced_alignment_tab)
    assert entry
    assert_equal 'Misplaced Alignment Tab Character (&)', entry[:title]

    assert_nil LaTeXErrorCatalog.find_by_id(:nonexistent_error_id)
  end

  def test_extract_errors_populates_catalog_id
    log_content = <<~LOG
      ./main.tex:5: Undefined control sequence.
      l.5 \\nonexistentmacro
    LOG

    builder = LatexBuilder.new('main.tex', {})
    errors = builder.send(:extract_errors, log_content)
    assert_equal 1, errors.size
    assert_equal :undefined_control_sequence, errors.first[:catalog_id]
    assert errors.first[:catalog]
    assert_equal '\\nonexistentmacro', errors.first[:catalog][:token]
  end
end
