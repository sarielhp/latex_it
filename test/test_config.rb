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

  def test_create_vscode_template_from_scratch
    Dir.mktmpdir('latex_it_vscode_test') do |dir|
      tasks_path, settings_path = LaTeXConfig.create_vscode_template!(dir)

      assert File.file?(tasks_path)
      assert File.file?(settings_path)

      tasks_data = JSON.parse(File.read(tasks_path))
      assert_equal '2.0.0', tasks_data['version']
      tasks = tasks_data['tasks']
      assert_equal 1, tasks.length
      task = tasks.first
      assert_equal 'Build LaTeX (latex_it)', task['label']
      assert_equal 'l', task['command']
      assert_equal ['--compile'], task['args']
      assert_equal true, task.dig('group', 'isDefault')
      assert_equal 'latex', task.dig('problemMatcher', 'owner')

      settings_data = JSON.parse(File.read(settings_path))
      assert_equal 'latex_it', settings_data['latex-workshop.latex.recipe.default']
      assert_equal '%DIR%/junk', settings_data['latex-workshop.latex.outDir']
      assert settings_data['latex-workshop.latex.tools'].any? { |t| t['name'] == 'latex_it' }
      assert settings_data['latex-workshop.latex.recipes'].any? { |r| r['name'] == 'latex_it' }
    end
  end

  def test_create_vscode_template_preserves_existing_configurations
    Dir.mktmpdir('latex_it_vscode_merge_test') do |dir|
      vscode_dir = File.join(dir, '.vscode')
      FileUtils.mkdir_p(vscode_dir)

      existing_tasks = {
        'version' => '2.0.0',
        'tasks' => [
          { 'label' => 'Custom Test', 'type' => 'shell', 'command' => 'make test' }
        ]
      }
      File.write(File.join(vscode_dir, 'tasks.json'), JSON.pretty_generate(existing_tasks))

      existing_settings = {
        'editor.tabSize' => 2,
        'latex-workshop.latex.tools' => [
          { 'name' => 'pdflatex', 'command' => 'pdflatex' }
        ]
      }
      File.write(File.join(vscode_dir, 'settings.json'), JSON.pretty_generate(existing_settings))

      LaTeXConfig.create_vscode_template!(dir)

      merged_tasks = JSON.parse(File.read(File.join(vscode_dir, 'tasks.json')))
      labels = merged_tasks['tasks'].map { |t| t['label'] }
      assert_includes labels, 'Custom Test'
      assert_includes labels, 'Build LaTeX (latex_it)'
      assert_equal 2, merged_tasks['tasks'].length

      merged_settings = JSON.parse(File.read(File.join(vscode_dir, 'settings.json')))
      assert_equal 2, merged_settings['editor.tabSize']
      tool_names = merged_settings['latex-workshop.latex.tools'].map { |t| t['name'] }
      assert_includes tool_names, 'pdflatex'
      assert_includes tool_names, 'latex_it'

      # Idempotency: re-running should not duplicate
      LaTeXConfig.create_vscode_template!(dir)
      reloaded_tasks = JSON.parse(File.read(File.join(vscode_dir, 'tasks.json')))
      assert_equal 2, reloaded_tasks['tasks'].length
    end
  end

  def test_cli_vscode_init_flag
    Dir.mktmpdir('latex_it_cli_vscode') do |dir|
      bin = File.expand_path('../latex_it', __dir__)
      out, status = Open3.capture2(bin, '--vscode-init', chdir: dir)
      assert_equal 0, status.exitstatus
      assert_includes out, 'Configured VS Code workspace'
      assert File.file?(File.join(dir, '.vscode', 'tasks.json'))
      assert File.file?(File.join(dir, '.vscode', 'settings.json'))
    end
  end

  def test_init_gitignore_creates_new_file
    Dir.mktmpdir('latex_it_gi_new') do |dir|
      _target, action = LaTeXConfig.init_gitignore!(dir)
      assert_equal :created, action

      gi = File.join(dir, '.gitignore')
      assert File.file?(gi)
      content = File.read(gi)
      assert_includes content, 'junk/'
      assert_includes content, '.junk/'
      assert_includes content, '*.synctex.gz'
      assert_includes content, '*.aux'
      assert_includes content, '*.bbl'
      assert_includes content, '# *.pdf'
    end
  end

  def test_init_gitignore_additive_and_idempotent
    Dir.mktmpdir('latex_it_gi_add') do |dir|
      gi = File.join(dir, '.gitignore')
      File.write(gi, "custom_secret.env\n*.aux\njunk/\n")

      _target, action = LaTeXConfig.init_gitignore!(dir)
      assert_equal :updated, action

      content = File.read(gi)
      assert_includes content, 'custom_secret.env'
      assert_includes content, '# Added by latex_it --gitignore-init'
      assert_includes content, '.junk/'
      assert_includes content, '*.synctex.gz'

      # junk/ should not be duplicated in the addition block
      added_section = content.split('# Added by latex_it --gitignore-init').last
      refute_match(%r{^junk/?$}, added_section)

      # Idempotency: second run when fully populated does not add anything
      _target2, action2 = LaTeXConfig.init_gitignore!(dir)
      assert_equal :unchanged, action2
    end
  end

  def test_cli_gitignore_init_flag
    Dir.mktmpdir('latex_it_cli_gi') do |dir|
      bin = File.expand_path('../latex_it', __dir__)
      out, status = Open3.capture2(bin, '--gitignore-init', chdir: dir)
      assert_equal 0, status.exitstatus
      assert_includes out, 'Created'
      assert File.file?(File.join(dir, '.gitignore'))
    end
  end
end
