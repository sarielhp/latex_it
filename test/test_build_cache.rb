#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'digest'

require_relative '../lib/latex_it/utils'
require_relative '../lib/latex_it/builder'
load File.expand_path('../latex_it', __dir__)

# targets_up_to_date? decides whether to skip the build entirely, so anything
# it fails to watch produces a silently stale PDF and an "up-to-date" message.
class TestBuildCache < Minitest::Test
  def options(extra = {})
    { engine: 'xelatex', passes: 3, lock: false, bib: nil }.merge(extra)
  end

  # Builds a project that is genuinely up to date, with a .bib in `bib_subdir`.
  def in_cached_project(bib_subdir, opts = {})
    Dir.mktmpdir('latex_it_cache_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(['junk', bib_subdir])
        File.write('paper.tex', "\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
        bib_path = File.join(bib_subdir, 'refs.bib')
        File.write(bib_path, "@book{a, title={T}}\n")

        builder = LatexBuilder.new('paper.tex', options(opts))
        write_pdf_and_state(builder, bib_path)
        yield builder, bib_path
      end
    end
  end

  # Records the build state the way the builder itself does, so the test cannot
  # accidentally track a file the real save path would have missed.
  def write_pdf_and_state(builder, _bib_path)
    File.write('junk/paper.pdf', '%PDF-1.5 fake')
    builder.send(:snapshot_build_inputs!)
    builder.send(:save_build_state!)
    FileUtils.cp('junk/paper.pdf', 'paper.pdf')
    future = Time.now + 5
    File.utime(future, future, 'paper.pdf')
  end

  def test_baseline_project_is_reported_up_to_date
    in_cached_project('refs') do |builder, _bib|
      assert builder.send(:targets_up_to_date?), 'the fixture itself is not up to date; the test is wrong'
    end
  end

  # DEFAULT_BIB_DIRS is refs, bib, bibliography and bib_dirs is configurable,
  # but the freshness checks used to hardcode only '*.bib' and 'refs/*.bib'.
  def test_edited_bibliography_invalidates_the_cache_in_every_default_dir
    %w[refs bib bibliography].each do |subdir|
      in_cached_project(subdir) do |builder, bib_path|
        later = Time.now + 60
        File.write(bib_path, "@book{a, title={T}}\n@book{b, title={U}}\n")
        File.utime(later, later, bib_path)

        refute builder.send(:targets_up_to_date?),
               "editing #{bib_path} left the stale PDF reported as up to date"
      end
    end
  end

  def test_configured_bib_dirs_are_watched
    in_cached_project('citations', bib_dirs: ['citations']) do |builder, bib_path|
      later = Time.now + 60
      File.write(bib_path, "@book{a, title={Changed}}\n")
      File.utime(later, later, bib_path)

      refute builder.send(:targets_up_to_date?),
             'a .bib in a configured bib_dirs directory was not watched'
    end
  end

  def test_discover_bib_files_honours_configured_dirs
    Dir.mktmpdir('latex_it_discover_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(%w[citations refs])
        File.write('citations/a.bib', '@book{a,}')
        File.write('refs/b.bib', '@book{b,}')

        builder = LatexBuilder.new('paper.tex', options(bib_dirs: ['citations']))
        found = builder.send(:discover_bib_files)

        assert_includes found, 'citations/a.bib'
        refute_includes found, 'refs/b.bib',
                        'discover_bib_files ignored bib_dirs and used its own hardcoded list'
      end
    end
  end

  def test_force_defeats_the_cache
    in_cached_project('refs', force: true) do |builder, _bib|
      refute builder.send(:targets_up_to_date?), 'force must always rebuild'
    end
  end

  def test_arxiv_always_forces_a_rebuild
    merged = LatexCLI.arxiv_build_options(engine: 'xelatex', passes: 3)
    assert_equal true, merged[:force],
                 '--arxiv must not assemble a submission package from a cached build'
  end

  def test_magic_comment_selects_the_engine
    Dir.mktmpdir('latex_it_engine_test') do |dir|
      Dir.chdir(dir) do
        File.write('paper.tex', "% !TEX TS-program = lualatex\n\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
        FileUtils.mkdir_p('junk')

        builder = LatexBuilder.new('paper.tex', options(engine: nil))
        assert_equal 'lualatex', builder.send(:resolve_engine),
                     'a "% !TEX program =" magic comment did not select the engine'
      end
    end
  end

  def test_explicit_engine_outranks_the_magic_comment
    Dir.mktmpdir('latex_it_engine_test') do |dir|
      Dir.chdir(dir) do
        File.write('paper.tex', "% !TEX TS-program = lualatex\n\\documentclass{article}\n")
        builder = LatexBuilder.new('paper.tex', options(engine: 'pdflatex', engine_explicit: true))
        assert_equal 'pdflatex', builder.send(:resolve_engine)
      end
    end
  end

  def test_magic_comment_outranks_the_configured_default
    Dir.mktmpdir('latex_it_engine_test') do |dir|
      Dir.chdir(dir) do
        File.write('paper.tex', "% !TEX TS-program = lualatex\n\\documentclass{article}\n")
        builder = LatexBuilder.new('paper.tex', options(engine: nil, config_engine: 'xelatex'))
        assert_equal 'lualatex', builder.send(:resolve_engine)
      end
    end
  end

  def test_configured_default_is_used_without_a_magic_comment
    Dir.mktmpdir('latex_it_engine_test') do |dir|
      Dir.chdir(dir) do
        File.write('paper.tex', "\\documentclass{article}\n")
        builder = LatexBuilder.new('paper.tex', options(engine: nil, config_engine: 'lualatex'))
        assert_equal 'lualatex', builder.send(:resolve_engine)
      end
    end
  end

  def test_default_is_xelatex_when_nothing_is_specified
    Dir.mktmpdir('latex_it_engine_test') do |dir|
      Dir.chdir(dir) do
        File.write('paper.tex', "\\documentclass{article}\n")
        builder = LatexBuilder.new('paper.tex', options(engine: nil, config_engine: nil))
        assert_equal 'xelatex', builder.send(:resolve_engine)
      end
    end
  end

  def test_cached_build_preserves_diagnostic_logs
    in_cached_project('refs', all_warnings: true) do |builder, _bib|
      File.write('junk/err_xelatex_1', "LaTeX Warning: Citation 'missing' undefined on input line 5.\n")
      File.write('junk/log.txt', 'previous compilation log')
      out, = capture_io do
        assert builder.send(:execute_compile_pipeline)
      end
      assert_includes out, 'All targets (paper.pdf) are up-to-date.'
      assert File.exist?('junk/err_xelatex_1'), 'diagnostic log was deleted on cached build'
      assert File.exist?('junk/log.txt'), 'build log was deleted on cached build'
    end
  end

  def test_targets_up_to_date_when_pdf_timestamp_is_older_than_build_state
    in_cached_project('refs') do |builder, _bib|
      # Simulate update_on_diff preserving an older PDF while build state has current timestamp
      older = Time.now - 100
      File.utime(older, older, 'paper.pdf')

      assert builder.send(:targets_up_to_date?),
             'an older PDF preserved by update_on_diff must not falsely invalidate cache'
    end
  end

  def test_targets_up_to_date_when_file_touched_without_content_change
    in_cached_project('refs') do |builder, _bib|
      future = Time.now + 100
      File.utime(future, future, 'paper.tex')

      assert builder.send(:targets_up_to_date?),
             'touching a source file without modifying content must not invalidate build cache'
    end
  end

  def test_targets_up_to_date_invalidates_when_content_changes
    in_cached_project('refs') do |builder, _bib|
      future = Time.now + 100
      File.write('paper.tex', "\\documentclass{article}\n% Modified content\n")
      File.utime(future, future, 'paper.tex')

      refute builder.send(:targets_up_to_date?),
             'modifying source content must invalidate build cache'
    end
  end

  def test_targets_up_to_date_invalidates_when_untracked_root_file_added
    in_cached_project('refs') do |builder, _bib|
      future = Time.now + 100
      File.write('chapter2.tex', "\\section{Two}\n")
      File.utime(future, future, 'chapter2.tex')

      refute builder.send(:targets_up_to_date?),
             'adding a new root .tex file must invalidate build cache'
    end
  end

  def test_needs_latex_rerun_uses_passed_curr_aux_hash
    builder = LatexBuilder.new('paper.tex', options)
    assert builder.send(:needs_latex_rerun?, 'nonexistent_log', 'old_hash', 'new_hash')
    refute builder.send(:needs_latex_rerun?, 'nonexistent_log', 'same_hash', 'same_hash')
  end

  def test_extract_aux_bib_files_with_in_memory_aux_contents
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('refs')
        File.write('refs/refs.bib', '@book{a, title={Test}}')
        builder = LatexBuilder.new('paper.tex', options(bib_dirs: ['refs']))

        aux_data = "junk/paper.aux:\\relax\n\\bibdata{refs}\n"
        found = builder.send(:extract_aux_bib_files, aux_data)
        assert_equal ['refs/refs.bib'], found
      end
    end
  end

  def test_detect_bib_tool_with_in_memory_aux_contents
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('refs')
        File.write('refs/refs.bib', '@book{a, title={Test}}')
        builder = LatexBuilder.new('paper.tex', options(bib_dirs: ['refs']))

        aux_data = "junk/paper.aux:\\relax\n\\bibdata{refs}\n\\citation{a}\n"
        assert_equal :bibtex, builder.send(:detect_bib_tool, aux_data)

        FileUtils.mkdir_p('junk')
        File.write('junk/paper.bcf', '<bcf:citekey>key1</bcf:citekey>')
        biber_aux = "junk/paper.aux:\\relax\n\\abx@aux@bcf{paper.bcf}\n"
        assert_equal :biber, builder.send(:detect_bib_tool, biber_aux)
      end
    end
  end
end
