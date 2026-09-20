#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'rainbow'

load File.expand_path('../latex_it', __dir__)

class TestDiagnosticFormatting < Minitest::Test
  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, '').gsub(/\e\]8;;[^\e]*\e\\/, '')
  end

  def test_box_warning_cleaning
    builder = LatexBuilder.new('main.tex', {})
    
    # 1. Floating point rounding and redundancy stripping
    cleaned = builder.send(:clean_box_diagnostic, 'Overfull \hbox (54.46506pt too wide) detected at line 125', :alert)
    assert_equal 'Alert: 54.47pt too wide', cleaned

    # 2. Paragraph range
    cleaned_range = builder.send(:clean_box_diagnostic, 'Overfull \hbox (5.72282pt too wide) in paragraph at lines 71--75', :warning)
    assert_equal 'Warning: 5.72pt too wide', cleaned_range

    # 3. Alignment
    cleaned_align = builder.send(:clean_box_diagnostic, 'Overfull \hbox (10.08925pt too wide) in alignment at lines 158--181', :warning)
    assert_equal 'Warning: 10.09pt too wide (alignment)', cleaned_align

    # 4. Underfull box badness
    cleaned_under = builder.send(:clean_box_diagnostic, 'Underfull \hbox (badness 10000) in paragraph at lines 169--171', :note)
    assert_equal 'Note: underfull \hbox (badness 10000)', cleaned_under
  end

  def test_duplicate_ranges_collapsed
    builder = LatexBuilder.new('main.tex', {})
    lines = [
      'Overfull \hbox (50.97342pt too wide) in paragraph at lines 108--108',
      'l.108 \somecode'
    ]
    item, = builder.send(:parse_box_warning, lines, 0, ['main.tex'], false)
    assert_equal '108', item[:line_str]
    assert_equal 108, item[:line]
    assert_equal 'Warning: 50.97pt too wide', item[:text]
  end

  def test_monotonic_line_number_sorting
    builder = LatexBuilder.new('main.tex', {})
    # Items with unordered lines and differing severities (which previously caused jumps)
    items = [
      { file: 'chapter.tex', line: 304, line_str: '304', text: 'Alert: 44.05pt too wide', severity: 44.05, index: 2 },
      { file: 'chapter.tex', line: 99, line_str: '99--110', text: 'Alert: 29.57pt too wide', severity: 29.57, index: 1 },
      { file: 'chapter.tex', line: 157, line_str: '157', text: 'Alert: 82.31pt too wide', severity: 82.31, index: 3 },
      { file: 'chapter.tex', line: 121, line_str: '121', text: 'Alert: 115.01pt too wide', severity: 115.01, index: 6 },
      { file: 'chapter.tex', line: 546, line_str: '546', text: 'Alert: 107.67pt too wide', severity: 107.67, index: 5 },
      { file: 'chapter.tex', line: 371, line_str: '371--393', text: 'Alert: 91.55pt too wide', severity: 91.55, index: 4 }
    ]

    all_sorted, = builder.send(:sort_diagnostic_items, items, [])
    sorted_lines = all_sorted.map { |i| i[:line] }
    assert_equal [99, 121, 157, 304, 371, 546], sorted_lines
  end

  def test_reference_and_citation_cleaning_and_deduplication
    builder = LatexBuilder.new('main.tex', {})

    # Reference cleaning
    raw_ref = "LaTeX Warning: Reference `lemma:test' on page 239 undefined on input line 219."
    assert_equal "Warning: undefined reference 'lemma:test' (page 239)", builder.send(:clean_diagnostic_warning, raw_ref)

    # Citation cleaning
    raw_cite = "LaTeX Warning: Citation 'smith2020' on page 42 undefined on input line 354."
    assert_equal "Warning: undefined citation 'smith2020' (page 42)", builder.send(:clean_diagnostic_warning, raw_cite)

    # Math mode cleaning
    raw_math = 'LaTeX Warning: Command \L invalid in math mode on input line 133.'
    assert_equal 'Warning: command \L invalid in math mode', builder.send(:clean_diagnostic_warning, raw_math)

    # Deduplication of Hyper reference and Reference
    log = <<~LOG
      (./chapter.tex
      LaTeX Warning: Hyper reference `lemma:test' on page 239 undefined on input line 219.
      LaTeX Warning: Reference `lemma:test' on page 239 undefined on input line 219.
      )
    LOG
    warns = builder.send(:extract_warnings, log)
    assert_equal 1, warns.size
    assert_equal "Warning: undefined reference 'lemma:test' (page 239)", warns.first[:text]
  end

  def test_duplicate_label_cross_referencing_with_links
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'chap1.tex'), "\\section{A}\n\\label{sec:dup}\n")
      File.write(File.join(dir, 'chap2.tex'), "\\section{B}\n\\label{sec:dup}\n")

      builder = LatexBuilder.new('main.tex', link: true)
      locs = [
        { file: File.join(dir, 'chap1.tex'), line: 2 },
        { file: File.join(dir, 'chap2.tex'), line: 2 }
      ]

      alerts = builder.send(:build_duplicate_label_alerts, 'sec:dup', locs, 0)
      assert_equal 2, alerts.size

      # Check chap1 alert mentions chap2
      a1 = alerts[0]
      assert_equal File.join(dir, 'chap1.tex'), a1[:file]
      assert_includes a1[:text], "Alert: label 'sec:dup' duplicate (also at"
      assert_includes a1[:text], 'chap2.tex:2'
      # Verify OSC 8 link is embedded for the other target
      assert_includes a1[:text], "\e]8;;file://"
      assert_includes a1[:text], 'chap2.tex#2'

      # Check chap2 alert mentions chap1
      a2 = alerts[1]
      assert_equal File.join(dir, 'chap2.tex'), a2[:file]
      assert_includes a2[:text], "Alert: label 'sec:dup' duplicate (also at"
      assert_includes a2[:text], 'chap1.tex:2'
      assert_includes a2[:text], "\e]8;;file://"
      assert_includes a2[:text], 'chap1.tex#2'
    end
  end

  def test_osc8_links_in_regular_mode
    Dir.mktmpdir do |dir|
      test_file = File.join(dir, 'test.tex')
      File.write(test_file, "line 1\nline 2\n")

      builder = LatexBuilder.new(test_file, link: true)
      
      # Line number prefix
      line_formatted = builder.send(:format_diagnostic_line, '455', 'Warning: test warning', :yellow, file: test_file)
      assert_includes line_formatted, "\e]8;;file://"
      assert_includes line_formatted, "#{test_file}#455"
      assert_includes line_formatted, '455:'

      # File header banner link
      banner = builder.send(:format_file_separator, test_file, 'alerts', 2)
      assert_includes banner, "\e]8;;file://"
      assert_includes banner, test_file
    end
  end

  def test_themes_have_magenta_and_blue
    LatexColor::THEMES.each do |theme_name, palette|
      assert palette.key?(:magenta), "Theme #{theme_name} missing :magenta"
      assert palette.key?(:blue), "Theme #{theme_name} missing :blue"
    end
  end

  def test_unwrap_log_lines_rejoins_hardwrapped_file_paths
    line1 = '(./very/deeply/nested/directory/path/with/a/long/filename_that_crosses_col_79_x'
    assert_equal 79, line1.length
    line2 = 'yz.tex'
    log = "#{line1}\n#{line2}\n[1]\n)"
    unwrapped = LaTeXUtils.unwrap_log_lines(log, 79)
    assert_includes unwrapped, "(./very/deeply/nested/directory/path/with/a/long/filename_that_crosses_col_79_xyz.tex\n"
  end

  def test_embedded_url_clean_osc8_by_default
    builder = LatexBuilder.new('main.tex', link: true, color: true)
    url = 'https://example.com/guide'
    formatted = builder.send(:format_terminal_url, url, 'underfull \hbox')
    assert_equal "\e]8;;https://example.com/guide\e\\underfull \\hbox\e]8;;\e\\", formatted
  end

  def test_embedded_link_in_diagnostic_line_preserves_surrounding_base_color
    builder = LatexBuilder.new('main.tex', link: true, color: true)
    orig_rainbow = Rainbow.enabled
    begin
      Rainbow.enabled = true
      item = {
        type: 'Underfull \hbox',
        file: 'test.tex',
        line: 12,
        line_str: '12',
        text: 'Note: underfull \hbox (badness 10000)',
        base_color: :cyan
      }
      rendered = builder.send(:render_diagnostic_item, item, width: 3)
      assert_includes rendered, "\e]8;;https://sarielhp.github.io/latex_it/docs/guides/underfull_boxes/\e\\underfull \\hbox\e]8;;\e\\"
      # Verify that the suffix text after the link is also colored in cyan
      assert_includes rendered, '(badness 10000)'
      refute_includes rendered, "\e[4m"
    ensure
      Rainbow.enabled = orig_rainbow
    end
  end

  def test_duplicate_label_link_is_cyan_without_forced_underline
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'chap1.tex'), "\\section{A}\n\\label{sec:dup}\n")
      File.write(File.join(dir, 'chap2.tex'), "\\section{B}\n\\label{sec:dup}\n")

      builder = LatexBuilder.new('main.tex', link: true, color: true)
      locs = [
        { file: File.join(dir, 'chap1.tex'), line: 2 },
        { file: File.join(dir, 'chap2.tex'), line: 2 }
      ]

      alerts = builder.send(:build_duplicate_label_alerts, 'sec:dup', locs, 0)
      a1 = alerts[0]
      assert_includes a1[:text], "\e]8;;file://"
      refute_includes a1[:text], "\e[4m"
      refute_includes a1[:text], "\e[24m"
      assert_includes a1[:text], 'chap2.tex:2'
    end
  end

  def test_boxed_explanation_doc_url_styled_in_blue
    builder = LatexBuilder.new('main.tex', link: true, color: true, explain: true)
    orig_rainbow = Rainbow.enabled
    begin
      Rainbow.enabled = true
      box = builder.send(:format_boxed_explanation, :underfull_hbox)
      assert_includes box, "\e]8;;https://sarielhp.github.io/latex_it/docs/guides/underfull_boxes/\e\\"
      # Check that blue color is included in the URL field
      assert_includes box, 'See:'
    ensure
      Rainbow.enabled = orig_rainbow
    end
  end
end
