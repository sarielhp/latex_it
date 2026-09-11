#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'fileutils'

class TestRepairFailures < Minitest::Test
  load File.expand_path('../latex_it', __dir__)
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus == 0
    end
  end

  def with_project
    Dir.mktmpdir('latex_it_failure_test_') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('paper.tex', 'Source')
        File.write('paper.pdf', 'Previous PDF')
        File.write('junk/paper.pdf', 'Previous PDF')
        File.write('junk/paper.fls', "INPUT paper.tex\n")
        yield LatexBuilder.new('paper.tex', passes: 3)
      end
    end
  end

  def test_bibliography_replacement_and_previous_backup_for_both_tools
    %i[bibtex biber].each do |tool|
      with_project do |builder|
        previous = "\\bibitem{old} Previous bibliography\n"
        generated = "\\bibitem{new} New bibliography\n"
        File.write('paper.bbl', previous)
        File.write('junk/paper.bbl', "\\bibitem{stale} Stale junk\n")
        File.write('unrelated.bbl', 'Unrelated original')
        File.write('junk/unrelated.bbl', '\\bibitem{unrelated} Do not publish')
        command = lambda do |*args|
          assert_equal tool.to_s, args.first
          File.write('paper.bbl', generated)
          ['', Status.new(0)]
        end
        Open3.stub(:capture2e, command) { assert builder.send(:run_bib_pass, tool) }
        assert_equal generated, File.read('paper.bbl')
        assert_equal previous, File.read('paper.bbl.bak')
        assert_equal previous, File.read('junk/paper.bbl.bak')
        assert_equal 'Unrelated original', File.read('unrelated.bbl')
      end
    end
  end

  def test_arxiv_text_check_requires_extractor_and_both_pdfs
    with_project do |builder|
      packager = LatexArxivPackager.new(builder)
      _, err = capture_io do
        LaTeXUtils.stub(:command_available?, false) do
          refute packager.send(:verify_arxiv_pdf_match, 'paper.pdf', 'junk/paper.pdf')
        end
      end
      assert_includes err, "requires 'pdftotext'"
      [[nil, 'paper.pdf'], ['absent.pdf', 'paper.pdf'], ['paper.pdf', 'absent.pdf']].each do |paths|
        capture_io do
          LaTeXUtils.stub(:command_available?, true) do
            refute packager.send(:verify_arxiv_pdf_match, *paths)
          end
        end
      end
    end
  end

  def test_arxiv_text_check_rejects_extraction_failure_and_ignores_successful_stderr
    with_project do |builder|
      packager = LatexArxivPackager.new(builder)
      assert_arxiv_text_check_failures(packager)
      assert_arxiv_text_check_success_with_warnings(packager)
    end
  end

  def assert_arxiv_text_check_failures(packager)
    [0, 1].each do |failed_index|
      results = [['same text', '', Status.new(0)], ['same text', '', Status.new(0)]]
      results[failed_index] = ['same text', 'Extraction failed', Status.new(1)]
      _, err = stub_extraction_and_verify(packager, results, refute_match: true)
      assert_includes err, 'Extraction failed'
    end
  end

  def assert_arxiv_text_check_success_with_warnings(packager)
    results = [['same text', 'warning A', Status.new(0)], ['same text', 'warning B', Status.new(0)]]
    stub_extraction_and_verify(packager, results, refute_match: false)
  end

  def stub_extraction_and_verify(packager, results, refute_match: true)
    capture_io do
      LaTeXUtils.stub(:command_available?, true) do
        Open3.stub(:capture3, ->(*_args) { results.shift }) do
          if refute_match
            refute packager.send(:verify_arxiv_pdf_match, 'paper.pdf', 'junk/paper.pdf')
          else
            assert packager.send(:verify_arxiv_pdf_match, 'paper.pdf', 'junk/paper.pdf')
          end
        end
      end
    end
  end

  def test_failed_empty_and_missing_bibliography_output_preserve_old_files
    %i[bibtex biber].product([[1, '\\bibitem{bad} Partial'], [0, 'empty'], [0, nil]]).each do |tool, scenario|
      with_project do |builder|
        previous = "\\bibitem{old} Previous bibliography\n"
        File.write('paper.bbl', previous)
        File.write('junk/paper.bbl', previous)
        command = lambda do |*_args|
          File.write('paper.bbl', scenario[1]) if scenario[1]
          ['tool diagnostic', Status.new(scenario[0])]
        end
        capture_io do
          Open3.stub(:capture2e, command) { refute builder.send(:run_bib_pass, tool) }
        end
        assert_equal previous, File.read('paper.bbl')
        assert_equal previous, File.read('junk/paper.bbl')
        assert_equal previous, File.read('paper.bbl.bak')
        assert_equal 'tool diagnostic', File.read('junk/err_bib')
      end
    end
  end

  def test_missing_bibliography_executable_preserves_previous_file
    with_project do |builder|
      File.write('paper.bbl', '\\bibitem{old} Previous')
      missing = ->(*_args) { raise Errno::ENOENT, 'bibtex' }
      _, err = capture_io do
        Open3.stub(:capture2e, missing) { refute builder.send(:run_bib_pass, :bibtex) }
      end
      assert_includes err, 'unavailable'
      assert_equal '\\bibitem{old} Previous', File.read('paper.bbl')
    end
  end

  def test_archive_command_failure_does_not_announce_success
    [LatexPackager, LatexArxivPackager].each do |klass|
      verify_archive_command_failure(klass)
    end
  end

  def verify_archive_command_failure(klass)
    with_project do |builder|
      File.write('paper.bbl', '\bibitem{old} Previous')
      packager = klass.new(builder)
      out, err = capture_archive_failure(packager, builder)
      refute_includes out, 'Created portable zip'
      refute_includes out, 'Preparation Complete'
      assert_includes err, 'injected zip failure'
    end
  end

  def capture_archive_failure(packager, builder)
    capture_io do
      Open3.stub(:capture2e, ['injected zip failure', Status.new(7)]) do
        builder.stub(:run_in_current_directory!, true) { refute packager.package! }
      end
    end
  end

  def test_archive_extraction_failure_does_not_announce_verification
    { LatexPackager => :verify_archive!, LatexArxivPackager => :verify_arxiv_sandbox! }.each do |klass, method|
      with_project do |builder|
        out, err = capture_io do
          Open3.stub(:capture2e, ['broken archive', Status.new(9)]) do
            refute klass.new(builder).send(method, 'broken.zip')
          end
        end
        refute_includes out, '[VERIFIED]'
        assert_includes err, 'broken archive'
      end
    end
  end

  def test_pdf_mismatch_and_failed_extraction_are_not_matches
    [["different text", 0], ["same text", 1]].each do |text, code|
      with_project do |builder|
        command = lambda do |*_args|
          @extract_calls += 1
          [@extract_calls == 1 ? 'same text' : text, Status.new(code)]
        end
        @extract_calls = 0
        capture_io do
          Open3.stub(:capture2e, command) do
            refute LatexPackager.new(builder).send(:verify_pdf_diff, 'paper.pdf', 'junk/paper.pdf')
          end
        end
      end
    end
  end

  def test_unavailable_pdftotext_reports_skipped_comparison
    with_project do |builder|
      out, = capture_io do
        LaTeXUtils.stub(:command_available?, false) do
          assert LatexPackager.new(builder).send(:verify_pdf_diff, 'paper.pdf', 'junk/paper.pdf')
        end
      end
      assert_includes out, 'comparison skipped'
      refute_includes out, 'match confirmed'
    end
  end

  def test_cache_rejects_changed_tex_options_and_legacy_state
    old_env = ENV.to_h.slice('LATEXOPTS', 'LATEXOPTIONS')
    with_project do |builder|
      builder.send(:save_build_state!)
      assert builder.send(:targets_up_to_date?)
      %w[LATEXOPTS LATEXOPTIONS].each do |key|
        ENV[key] = 'changed options'
        refute builder.send(:targets_up_to_date?)
        ENV[key] = old_env[key]
      end
      state = JSON.parse(File.read('junk/.build_state.json'))
      state.delete('signature')
      File.write('junk/.build_state.json', JSON.generate(state))
      refute builder.send(:targets_up_to_date?)
    end
  ensure
    %w[LATEXOPTS LATEXOPTIONS].each { |key| ENV[key] = old_env[key] }
  end

  def test_explicit_bibliography_request_cannot_hit_cache
    with_project do |_builder|
      builder = LatexBuilder.new('paper.tex', passes: 3, bib: true)
      builder.send(:save_build_state!)
      refute builder.send(:targets_up_to_date?)
    end
  end

  def test_flattening_preserves_verbatim_and_inline_literals
    with_project do |_builder|
      File.write('part.tex', 'Must not inline this')
      literal = "\\begin{verbatim}\n\\input{part}\n100% literal\n\n\n\\end{verbatim}\n"
      source = literal + "Example: \\verb|50%|. % remove this\n"
      File.write('paper.tex', source)
      flattened = LaTeXFlattener.flatten('paper.tex')
      assert_includes flattened, literal
      assert_includes flattened, '\\verb|50%|'
      refute_includes flattened, 'remove this'
      refute_includes flattened, 'Must not inline this'
    end
  end
end
