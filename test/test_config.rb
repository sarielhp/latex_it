# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/latex_it/config'
require_relative '../lib/latex_it/utils'
require_relative '../lib/latex_it/flattener'
require_relative '../lib/latex_it/builder'

class TestLaTeXConfigAndConventions < Minitest::Test
  def test_default_config_keys
    cfg = LaTeXConfig.parse_jsonc(LaTeXConfig::DEFAULT_CONFIG_TEMPLATE)

    assert_includes cfg['exclude_main_tex'], 'prefix*.tex'
    assert_includes cfg['exclude_main_tex'], 'prelim*.tex'
    assert_includes cfg['exclude_main_tex'], 'preamble*.tex'
    assert_includes cfg['exclude_main_tex'], '*.num.tex'
    assert_includes cfg['exclude_main_tex'], 'pratenddefaultcategory.tex'

    assert_includes cfg['exclude_source_tex'], 'styles/*'
    assert_includes cfg['exclude_source_tex'], '*prefix*.tex'

    assert_equal %w[refs bib bibliography], cfg['bib_dirs']
    assert_equal true, cfg['auto_mirror_subdirs']
    assert_equal %w[figs fragment], cfg['junk_subdirs']
    assert_equal %w[computer local private], cfg.dig('arxiv', 'strip_host_patterns')
  end

  def test_candidate_tex_files_default_exclusions
    Dir.mktmpdir('latex_it_cand_test') do |dir|
      FileUtils.touch(File.join(dir, 'main.tex'))
      FileUtils.touch(File.join(dir, 'prefix.tex'))
      FileUtils.touch(File.join(dir, 'prefix_defs.tex'))
      FileUtils.touch(File.join(dir, 'prelim.tex'))
      FileUtils.touch(File.join(dir, 'preamble.tex'))
      FileUtils.touch(File.join(dir, 'paper.num.tex'))
      FileUtils.touch(File.join(dir, 'pratenddefaultcategory.tex'))
      FileUtils.touch(File.join(dir, 'flycheck_main.tex'))
      FileUtils.touch(File.join(dir, 'main.tex~'))
      FileUtils.touch(File.join(dir, 'main.tex.bak'))

      candidates = LaTeXUtils.candidate_tex_files(dir)
      assert_equal ['main.tex'], candidates
    end
  end

  def test_candidate_tex_files_custom_exclusions
    Dir.mktmpdir('latex_it_custom_cand_test') do |dir|
      FileUtils.touch(File.join(dir, 'main.tex'))
      FileUtils.touch(File.join(dir, 'prefix.tex'))
      FileUtils.touch(File.join(dir, 'custom_header.tex'))

      candidates = LaTeXUtils.candidate_tex_files(dir, ['custom*.tex'])
      assert_includes candidates, 'main.tex'
      assert_includes candidates, 'prefix.tex'
      refute_includes candidates, 'custom_header.tex'
    end
  end

  def test_find_main_latex_file_with_defaults
    Dir.mktmpdir('latex_it_find_main_test') do |dir|
      File.write(File.join(dir, 'main.tex'), "\\begin{document}\nHello\n\\end{document}\n")
      File.write(File.join(dir, 'prefix.tex'), "\\usepackage{amsmath}\n")
      File.write(File.join(dir, 'preamble.tex'), "\\usepackage{amssymb}\n")

      assert_equal 'main.tex', LaTeXUtils.find_main_latex_file(dir)
    end
  end

  def test_flattener_clean_host_specific_default
    raw = "\\IfFileExists{computer.tex}{\\input{computer.tex}}{}\n\\IfFileExists{local.tex}{\\input{local}}{}\nKeep this"
    cleaned = LaTeXFlattener.clean_host_specific(raw)
    refute_includes cleaned, 'computer.tex'
    refute_includes cleaned, 'local.tex'
    assert_includes cleaned, 'Keep this'
    # Absence of the pattern is not enough: the previous regex-based
    # implementation deleted only a prefix of the conditional and left stray
    # braces behind, and this test passed on that output.
    assert_equal cleaned.count('{'), cleaned.count('}'), "unbalanced braces: #{cleaned.inspect}"
  end

  def test_flattener_clean_host_specific_custom
    raw = "\\IfFileExists{secret.tex}{\\input{secret}}{}\n\\IfFileExists{computer.tex}{\\input{computer}}{}\nKeep this"
    cleaned = LaTeXFlattener.clean_host_specific(raw, ['secret'])
    refute_includes cleaned, 'secret.tex'
    assert_includes cleaned, 'computer.tex'
    assert_includes cleaned, 'Keep this'
    assert_equal cleaned.count('{'), cleaned.count('}'), "unbalanced braces: #{cleaned.inspect}"
  end

  def test_builder_junk_subdirs_auto_mirroring
    Dir.mktmpdir('latex_it_junk_mirror_test') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'sections'))
      FileUtils.mkdir_p(File.join(dir, 'figs'))
      FileUtils.mkdir_p(File.join(dir, 'custom_code'))

      Dir.chdir(dir) do
        builder = LatexBuilder.allocate
        builder.instance_variable_set(:@options, { auto_mirror_subdirs: true, junk_subdirs: ['figs', 'fragment'] })
        builder.send(:junk_dir_create)

        assert File.directory?('junk/junk')
        assert File.directory?('junk/figs')
        assert File.directory?('junk/fragment')
        assert File.directory?('junk/sections')
        assert File.directory?('junk/custom_code')
      end
    end
  end

  def test_builder_collect_bib_candidates_custom_dirs
    Dir.mktmpdir('latex_it_bib_test') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'my_bibs'))
      FileUtils.touch(File.join(dir, 'my_bibs', 'refs.bib'))

      Dir.chdir(dir) do
        builder = LatexBuilder.allocate
        builder.instance_variable_set(:@options, { bib_dirs: ['my_bibs'] })
        files = []
        builder.send(:collect_bib_candidates, 'refs', files)
        assert_equal ['my_bibs/refs.bib'], files
      end
    end
  end
end
