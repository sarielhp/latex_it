#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/latex_it/utils'
require_relative '../lib/latex_it/builder'
load File.expand_path('../latex_it', __dir__)

# Drives run_convergence_loop with a scripted engine: each LaTeX pass "writes"
# the next aux state and the calls made are recorded, so pass accounting can be
# asserted without running TeX.
class TestConvergenceLoop < Minitest::Test
  def in_project(opts = {})
    Dir.mktmpdir('latex_it_loop_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('paper.tex', "\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
        yield LatexBuilder.new('paper.tex', { engine: 'xelatex', passes: 3, lock: false, bib: nil }.merge(opts))
      end
    end
  end

  # aux_states[i] is the aux content after LaTeX pass i+1; `initial` is what a
  # previous build left in junk/. bib_stale answers bib_stale_since_last_run?.
  def script(builder, aux_states:, initial: '', bib_stale: [])
    calls = []
    aux = initial
    passes = 0
    builder.define_singleton_method(:compute_aux_hash) { aux }
    builder.define_singleton_method(:log_pass_start) { |*_a, **_k| nil }
    builder.define_singleton_method(:log_bib_start) { |*_a, **_k| nil }
    builder.define_singleton_method(:run_latex_pass) do |_suffix|
      aux = aux_states[[passes, aux_states.size - 1].min]
      passes += 1
      calls << :latex
      true
    end
    builder.define_singleton_method(:detect_bib_tool) { |_aux = nil| :bibtex }
    builder.define_singleton_method(:needs_bib_pass?) { |*_a| calls.count(:bib).zero? }
    builder.define_singleton_method(:run_bib_pass) { |*_a| calls << :bib && true }
    builder.send(:bib_manager).define_singleton_method(:bib_stale_since_last_run?) { |*_a| bib_stale.shift || false }
    calls
  end

  def test_single_pass_cap_never_runs_bib_or_a_second_latex_pass
    in_project(passes: 1) do |builder|
      calls = script(builder, aux_states: ['\citation{a}'])
      assert builder.send(:run_convergence_loop)
      assert_equal %i[latex], calls
      refute builder.instance_variable_get(:@cacheable_build), 'a skipped bibliography must not be cached'
    end
  end

  def test_pass_after_bib_is_compared_with_the_aux_the_previous_pass_wrote
    in_project(passes: 2) do |builder|
      calls = script(builder, initial: '\old', aux_states: ['\abx@aux@cite{a}'])
      assert builder.send(:run_convergence_loop)
      assert_equal %i[latex bib latex], calls
      assert builder.instance_variable_get(:@cacheable_build), 'converged at pass 2 but treated as unconverged'
    end
  end

  def test_second_bib_run_when_the_first_is_out_of_date
    in_project(passes: 5) do |builder|
      calls = script(builder, aux_states: %w[a b c c c], bib_stale: [true])
      assert builder.send(:run_convergence_loop)
      assert_equal %i[latex bib latex bib latex latex], calls
    end
  end

  def test_bib_runs_are_capped_and_an_unsatisfied_bibliography_is_not_cached
    in_project(passes: 6) do |builder|
      calls = script(builder, aux_states: %w[a b c d e f], bib_stale: [true] * 20)
      assert builder.send(:run_convergence_loop)
      assert_equal 2, calls.count(:bib)
      refute builder.instance_variable_get(:@cacheable_build)
    end
  end

  def test_stale_bcf_from_an_earlier_biblatex_build_does_not_select_biber
    in_project do |builder|
      File.write('junk/paper.bcf', '<bcf:citekey order="1">a</bcf:citekey>')
      File.write('junk/paper.run.xml', '<requests><external package="biber" active="1"/></requests>')
      aux = "\\relax\n\\citation{a}\n\\bibdata{refs}\n"
      assert_equal :bibtex, builder.detect_bib_tool(aux)
      refute File.exist?('junk/paper.bcf'), 'stale control file should be discarded'
    end
  end

  def test_current_bcf_still_selects_biber
    in_project do |builder|
      File.write('junk/paper.bcf', '<bcf:citekey order="1">a</bcf:citekey>')
      assert_equal :biber, builder.detect_bib_tool("\\relax\n\\abx@aux@cite{0}{a}\n")
    end
  end

  def test_biblatex_bbl_is_discarded_when_no_source_uses_biblatex
    in_project do |builder|
      File.write('junk/paper.bbl', "% $ biblatex bbl format version 3.3 $\n")
      FileUtils.cp('junk/paper.bbl', 'paper.bbl')
      File.write('junk/paper.bcf', '<bcf:citekey>a</bcf:citekey>')
      builder.send(:discard_stale_bib_format_files)
      assert_empty Dir['paper.bbl', 'junk/paper.bbl', 'junk/paper.bcf']
    end
  end

  def test_biblatex_bbl_is_kept_when_a_source_uses_biblatex
    in_project do |builder|
      File.write('paper.tex', "\\usepackage{biblatex}\n")
      File.write('junk/paper.bbl', "% $ biblatex bbl format version 3.3 $\n")
      builder.send(:discard_stale_bib_format_files)
      assert File.file?('junk/paper.bbl')
    end
  end

  def test_bibtex_bbl_is_discarded_when_the_document_now_uses_biblatex
    in_project do |builder|
      File.write('paper.tex', "\\usepackage[backend=biber]{biblatex}\n")
      File.write('junk/paper.bbl', "\\begin{thebibliography}{1}\n\\end{thebibliography}\n")
      builder.send(:discard_stale_bib_format_files)
      refute File.exist?('junk/paper.bbl')
    end
  end

  def test_commented_out_biblatex_does_not_count_as_use
    in_project do |builder|
      File.write('paper.tex', "% \\usepackage{biblatex}\n")
      File.write('junk/paper.bbl', "\\begin{thebibliography}{1}\n\\end{thebibliography}\n")
      builder.send(:discard_stale_bib_format_files)
      assert File.exist?('junk/paper.bbl')
    end
  end

  def test_biblatex_aux_is_discarded_when_no_source_uses_biblatex
    in_project do |builder|
      File.write('junk/paper.aux', "\\relax\n\\abx@aux@cite{0}{a}\n")
      builder.send(:discard_stale_bib_format_files)
      refute File.exist?('junk/paper.aux')
    end
  end

  def last_pass_log(builder, pass)
    File.read("#{builder.instance_variable_get(:@pdferr)}_#{pass}")
  end

  def test_default_pass_cap_allows_more_than_three_passes
    assert_operator LaTeXUtils::DEFAULT_PASSES, :>=, 5
    in_project(passes: LaTeXUtils::DEFAULT_PASSES) do |builder|
      calls = script(builder, aux_states: %w[a b c d d])
      assert builder.send(:run_convergence_loop)
      assert_equal 5, calls.count(:latex)
      assert builder.instance_variable_get(:@cacheable_build)
    end
  end

  def test_running_out_of_passes_warns_and_disables_the_cache
    in_project(passes: 3) do |builder|
      calls = script(builder, aux_states: %w[a b c d e])
      FileUtils.mkdir_p('junk')
      builder.send(:run_convergence_loop)
      assert_equal 3, calls.count(:latex)
      refute builder.instance_variable_get(:@cacheable_build)
      assert_match(/LaTeX Warning: latex_it: build did not converge; a rerun is still requested after 3 passes/, last_pass_log(builder, 3))
    end
  end

  def test_cycling_aux_state_stops_early_with_a_warning
    in_project(passes: 8) do |builder|
      calls = script(builder, aux_states: %w[a b a b a b a b])
      builder.send(:run_convergence_loop)
      assert_operator calls.count(:latex), :<, 8
      refute builder.instance_variable_get(:@cacheable_build)
      assert_match(/keep cycling/, last_pass_log(builder, calls.count(:latex)))
    end
  end

  def test_unchanged_aux_is_not_mistaken_for_a_cycle
    in_project(passes: 8) do |builder|
      script(builder, aux_states: %w[a a a])
      assert builder.send(:run_convergence_loop)
      assert builder.instance_variable_get(:@cacheable_build)
    end
  end

  def test_last_pass_log_is_numeric_not_lexicographic_and_cleanup_removes_all
    in_project do |builder|
      base = builder.instance_variable_get(:@pdferr)
      FileUtils.mkdir_p(File.dirname(base))
      %i[@log @loga @biberr].each { |v| builder.instance_variable_set(v, "junk/#{v.to_s.delete('@')}.txt") }
      [1, 2, 9, 10].each { |n| File.write("#{base}_#{n}", "pass #{n}") }
      assert_equal "#{base}_10", builder.send(:find_last_latex_log)
      builder.send(:clean_pass_logs)
      assert_empty builder.send(:pass_log_files)
      assert_equal base, builder.send(:find_last_latex_log)
    end
  end
end
