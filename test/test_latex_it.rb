#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class TestLatexItCLI < Minitest::Test
  BIN = File.expand_path('../latex_it', __dir__)
  load BIN

  def strip_ansi(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, '')
  end

  def test_version_flag
    stdout, status = Open3.capture2(BIN, '-V')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert_match(/^l \d+\.\d+\.\d+/, stdout)
  end

  def test_help_flag
    stdout, status = Open3.capture2(BIN, '-h')
    assert status.success?, "Expected exit code 0, got: #{status.exitstatus}"
    assert_includes stdout, 'Usage: l [options]'
    assert_includes stdout, '--engine'
    assert_includes stdout, '--fast'
    assert_includes stdout, '-Werror'
    assert_includes stdout, '--deps'
  end

  def test_pdflatex_is_supported_engine
    assert_equal 'pdflatex', LaTeXUtils.normalize_engine('pdflatex')
    assert_equal 'pdflatex', LaTeXUtils.normalize_engine('pdftex')
  end

  def test_inputenc_source_selects_pdflatex
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "\\documentclass{article}\n\\usepackage[latin9]{inputenc}\n")
      assert_equal 'pdflatex', LaTeXUtils.detect_engine_from_file(path)
    end
  end

  def test_inputenc_detection_handles_requirepackage
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "\\documentclass{article}\n\\RequirePackage { inputenc }\n")
      assert_equal 'pdflatex', LaTeXUtils.detect_engine_from_file(path)
    end
  end

  def test_explicit_magic_comment_overrides_inputenc_fallback
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "%!TEX TS-program = xelatex\n\\usepackage[utf8]{inputenc}\n")
      assert_equal 'xelatex', LaTeXUtils.detect_engine_from_file(path)
    end
  end

  def test_incompatible_explicit_engine_falls_back_to_pdflatex
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "\\documentclass{article}\n\\usepackage[latin9]{inputenc}\n")
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('xelatex', path)
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('lualatex', path)
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('pdflatex', path)
    end
  end

  def test_eps_graphics_require_pdflatex
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, <<~TEX)
        \\usepackage{graphicx}
        \\includegraphics[width=.5\\linewidth]{figures/result.eps}
        \\epsfig{file=old.eps,width=2cm}
      TEX
      assert_equal ['EPS graphics'], LaTeXUtils.source_pdflatex_reasons(path)
      assert LaTeXUtils.source_requires_pdflatex?(path)
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('xelatex', path)
      assert_equal 'pdflatex', LaTeXUtils.compatible_engine('lualatex', path)
    end
  end

  def test_commented_eps_reference_does_not_trigger_detection
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'paper.tex')
      File.write(path, "% \\includegraphics{commented.eps}\n% \\epsfig{file=commented.eps}\n")
      assert_empty LaTeXUtils.source_pdflatex_reasons(path)
    end
  end

  def test_pdflatex_symlink_personality_selects_engine
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), <<~TEX)
        \\documentclass{article}
        \\begin{document}
        pdflatex personality
        \\end{document}
      TEX
      launcher = File.join(dir, 'lp')
      File.symlink(BIN, launcher)

      Dir.chdir(dir) do
        stdout, stderr, status = Open3.capture3(launcher, 'paper.tex')
        assert status.success?, "pdflatex personality failed: #{stdout}\n#{stderr}"
        assert File.file?(File.join(dir, 'paper.pdf'))
        assert_includes stdout, 'pdflatex'
      end
    end
  end

  def test_find_main_flag_with_mainfile
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.mainfile'), "document.tex\n")
      File.write(File.join(dir, 'other.tex'), "\\begin{document}\\end{document}\n")

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-m')
        assert status.success?
        assert_equal "document.tex\n", stdout
      end
    end
  end

  def test_find_main_flag_directory_name_heuristic
    Dir.mktmpdir('my_paper') do |dir|
      dir_name = File.basename(dir)
      File.write(File.join(dir, "#{dir_name}.tex"), "\\begin{document}\\end{document}\n")
      File.write(File.join(dir, 'random.tex'), "content\n")

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-m')
        assert status.success?
        assert_equal "#{dir_name}.tex\n", stdout
      end
    end
  end

  def test_clean_only_flag
    Dir.mktmpdir do |dir|
      # Create mock junk files
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'temp.aux'), 'temp')
      File.write(File.join(dir, 'test.aux'), 'aux')
      File.write(File.join(dir, 'test.log'), 'log')

      Dir.chdir(dir) do
        _stdout, status = Open3.capture2(BIN, '-C')
        assert status.success?
        refute File.exist?(File.join(dir, 'junk'))
        refute File.exist?(File.join(dir, 'test.aux'))
        refute File.exist?(File.join(dir, 'test.log'))
      end
    end
  end

  def test_deps_flag_cli
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\begin{document}\\end{document}\n")
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => {}, 'extra.tex' => {} }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-M', 'paper.tex')
        assert status.success?
        assert_equal "paper.pdf: extra.tex paper.tex\n", stdout

        stdout_long, status_long = Open3.capture2(BIN, '--deps', 'paper.tex')
        assert status_long.success?
        assert_equal "paper.pdf: extra.tex paper.tex\n", stdout_long
      end
    end
  end

  def test_diagnostic_formatting_no_redundant_w
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)
    formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    refute_includes formatted, 'W:'
    assert_includes formatted, Rainbow('42').cyan.bright.to_s
    assert_includes formatted, Rainbow(': ').yellow.bright.to_s

    # In plain/monochrome mode, verify plain 42: prefix
    Rainbow.enabled = false
    mono_formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    refute_includes mono_formatted, 'W:'
    assert_equal '42: Package hyperref Warning: Token not allowed on input line 42.', mono_formatted

    # In emacs mode, verify line prefixes are completely suppressed
    emacs_builder = LatexBuilder.new('sample.tex', emacs: true)
    emacs_formatted = emacs_builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: Token not allowed on input line 42.', :yellow)
    assert_equal 'Package hyperref Warning: Token not allowed on input line 42.', emacs_formatted
  end

  def test_diagnostic_formatting_empty_line_str
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)
    formatted = builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    refute_includes formatted, 'W:'
    assert_includes formatted, Rainbow(': ').yellow.bright.to_s

    Rainbow.enabled = false
    mono_formatted = builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    assert_equal ': LaTeX Warning: Label(s) may have changed.', mono_formatted

    emacs_builder = LatexBuilder.new('sample.tex', emacs: true)
    emacs_formatted = emacs_builder.send(:format_diagnostic_line, '', 'LaTeX Warning: Label(s) may have changed.', :yellow)
    assert_equal 'LaTeX Warning: Label(s) may have changed.', emacs_formatted
  end

  def test_line_number_colorization_left_and_inside
    Rainbow.enabled = true
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)

    formatted = builder.send(:format_diagnostic_line, '42', 'Package hyperref Warning: on input line 42.', :yellow)
    cyan_bright_42 = Rainbow('42').cyan.bright.to_s
    assert_includes formatted, cyan_bright_42

    # Verify both left side and message interior have the highlighted number
    occurrences = formatted.scan(cyan_bright_42).size
    assert_equal 2, occurrences, 'Expected 42 to be highlighted in cyan.bright both on left side and inside message'
  end

  def test_error_line_number_colorization
    Rainbow.enabled = true
    builder = LatexBuilder.new('sample.tex', emacs: false, color: true)

    err_lines = ['./sample.tex:42: Undefined control sequence.', 'l.42 \\badcommand']
    formatted = builder.send(:format_error_block, err_lines, 42)
    cyan_bright_42 = Rainbow('42').cyan.bright.to_s
    assert_includes formatted, cyan_bright_42
  end

  def test_left_width_alignment
    Rainbow.enabled = false
    builder = LatexBuilder.new('sample.tex', emacs: false, color: false)

    # Testing formatting with width = 10 (as in 1071--1075)
    f_range = builder.send(:format_diagnostic_line, '1071--1075', 'Overfull \\hbox ...', :magenta, width: 10)
    f_short = builder.send(:format_diagnostic_line, '448', 'Overfull \\hbox ...', :magenta, width: 10)
    f_empty = builder.send(:format_diagnostic_line, '', 'Warning without line', :yellow, width: 10)

    assert_match(/^1071--1075: Overfull/, f_range)
    assert_match(/^       448: Overfull/, f_short)
    assert_match(/^          : Warning/, f_empty)

    # Check colon positions: all must align at index 10 (11th character)
    assert_equal 10, f_range.index(':')
    assert_equal 10, f_short.index(':')
    assert_equal 10, f_empty.index(':')
  end

  def test_extract_fls_dependencies
    Dir.mktmpdir do |dir|
      fls_content = <<~FLS
        PWD #{dir}
        INPUT /usr/share/texmf/base.cls
        INPUT #{dir}/main.tex
        INPUT #{dir}/sections/intro.tex
        INPUT #{dir}/junk/main.aux
        OUTPUT #{dir}/junk/main.pdf
      FLS

      FileUtils.mkdir_p(File.join(dir, 'junk'))
      FileUtils.mkdir_p(File.join(dir, 'sections'))
      File.write(File.join(dir, 'main.tex'), 'test')
      File.write(File.join(dir, 'sections', 'intro.tex'), 'intro')
      fls_path = File.join(dir, 'junk', 'main.fls')
      File.write(fls_path, fls_content)

      builder = LatexBuilder.new('main.tex', {})
      Dir.chdir(dir) do
        deps = builder.send(:extract_fls_dependencies, fls_path)
        assert_includes deps, 'main.tex'
        assert_includes deps, 'sections/intro.tex'
        refute_includes deps, 'junk/main.aux'
        refute deps.any? { |d| d.include?('/usr/share') }
      end
    end
  end

  def test_aux_has_cross_references
    builder = LatexBuilder.new('main.tex', {})
    refute builder.send(:aux_has_cross_references?, "\\relax\n\\@abspage@last{1}\n")
    assert builder.send(:aux_has_cross_references?, "\\newlabel{sec:one}{{1}{1}}\n")
    assert builder.send(:aux_has_cross_references?, "\\citation{knuth1984}\n")
    assert builder.send(:aux_has_cross_references?, "\\@writefile{toc}{\\contentsline {section}}\n")
  end

  def test_targets_up_to_date_logic
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      File.write(File.join(dir, 'paper.pdf'), 'mock pdf')
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      builder = LatexBuilder.new('paper.tex', {})

      sha = Digest::SHA256.file(File.join(dir, 'paper.tex')).hexdigest
      mtime = File.mtime(File.join(dir, 'paper.tex')).to_i
      state = {
        'target' => 'paper.pdf',
        'engine' => 'xelatex',
        'signature' => builder.send(:build_signature),
        'sources' => { 'paper.tex' => { 'mtime' => mtime, 'sha' => sha } }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      Dir.chdir(dir) do
        assert builder.send(:targets_up_to_date?), 'Expected build to be up to date'

        # Test single_pass forces rebuild
        single_builder = LatexBuilder.new('paper.tex', single_pass: true)
        refute single_builder.send(:targets_up_to_date?)

        # Test clean forces rebuild
        clean_builder = LatexBuilder.new('paper.tex', clean: true)
        refute clean_builder.send(:targets_up_to_date?)

        # Test modified source triggers rebuild
        sleep 0.05
        File.write(File.join(dir, 'paper.tex'), 'modified content')
        refute builder.send(:targets_up_to_date?), 'Expected modified file to trigger rebuild'
      end
    end
  end

  def test_werror_forces_rebuild
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      File.write(File.join(dir, 'paper.pdf'), 'mock pdf')
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      sha = Digest::SHA256.file(File.join(dir, 'paper.tex')).hexdigest
      mtime = File.mtime(File.join(dir, 'paper.tex')).to_i
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => { 'mtime' => mtime, 'sha' => sha } }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      builder = LatexBuilder.new('paper.tex', werror: true)
      Dir.chdir(dir) do
        refute builder.send(:targets_up_to_date?), 'Expected werror to force rebuild'
      end
    end
  end

  def test_export_dependencies
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), 'content')
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      state = {
        'target' => 'paper.pdf',
        'sources' => { 'paper.tex' => {}, 'figures/fig1.pdf' => {} }
      }
      File.write(File.join(dir, 'junk', '.build_state.json'), JSON.generate(state))

      builder = LatexBuilder.new('paper.tex', deps: true)
      Dir.chdir(dir) do
        out, = capture_io { builder.send(:export_dependencies) }
        assert_equal "paper.pdf: figures/fig1.pdf paper.tex\n", out
      end
    end
  end

  def test_multi_file_diagnostics
    log_content = <<~LOG
      This is XeTeX, Version 3.141592653-2.6-0.999996
      (./main.tex
      (./chapters/ch1.tex
      LaTeX Warning: Reference `sec:unknown' on page 1 undefined on input line 42.
      )
      (./chapters/ch2.tex
      Overfull \\hbox (15.0pt too wide) in paragraph at lines 10--15
      )
      ! LaTeX Error: File `missing.sty' not found.
      )
    LOG

    builder = LatexBuilder.new('main.tex', {})
    warnings = builder.send(:extract_warnings, log_content)
    errors = builder.send(:extract_errors, log_content)

    ch1_warn = warnings.find { |w| w[:text].include?('sec:unknown') }
    assert ch1_warn
    assert_equal './chapters/ch1.tex', ch1_warn[:file]
    assert_equal 42, ch1_warn[:line]

    ch2_warn = warnings.find { |w| w[:text].include?('Overfull') }
    assert ch2_warn
    assert_equal './chapters/ch2.tex', ch2_warn[:file]
    assert_equal 10, ch2_warn[:line]

    assert_equal 1, errors.size
    assert_equal './main.tex', errors.first[:file]

    out, = capture_io { builder.send(:print_diagnostics_body, warnings, errors) }
    assert_includes out, '(./chapters/ch1.tex'
    assert_includes out, '(./chapters/ch2.tex'
  end

  def test_werror_aborts_on_warnings
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_content = <<~LOG
        LaTeX Warning: Reference `sec:foo' on page 1 undefined on input line 10.
      LOG
      File.write(File.join(dir, 'junk', 'err_xelatex'), log_content)

      builder = LatexBuilder.new('paper.tex', werror: true)
      Dir.chdir(dir) do
        assert_raises(SystemExit) do
          capture_io { builder.send(:analyze_output) }
        end
      end
    end
  end

  def test_parse_jsonc_with_comments_and_trailing_commas
    jsonc = <<~JSONC
      {
        // Line comment
        "engine": "lualatex",
        /* Block
           comment */
        "url": "https://example.com/test",
        "zip": {
          "inject_styles": true,
          "include": ["foo.txt", "bar.csv",], // trailing comma in array
        }, // trailing comma in hash
      }
    JSONC

    parsed = LaTeXConfig.parse_jsonc(jsonc)
    assert_equal 'lualatex', parsed['engine']
    assert_equal 'https://example.com/test', parsed['url']
    assert_equal true, parsed.dig('zip', 'inject_styles')
    assert_equal %w[foo.txt bar.csv], parsed.dig('zip', 'include')
  end

  def test_parse_jsonc_error_resilience
    assert_equal({}, LaTeXConfig.parse_jsonc(nil))
    assert_equal({}, LaTeXConfig.parse_jsonc('   '))
    _out, err = capture_io do
      assert_equal({}, LaTeXConfig.parse_jsonc('{ invalid json: }}'))
    end
    assert_includes err, 'Warning: Could not parse JSONC config'
  end

  def test_load_merged_config
    Dir.mktmpdir do |dir|
      local_jsonc = <<~JSONC
        {
          "engine": "lualatex",
          "zip": {
            "inject_styles": true
          }
        }
      JSONC
      File.write(File.join(dir, '.l.jsonc'), local_jsonc)

      cfg = LaTeXConfig.load_merged_config(dir)
      assert_equal 'lualatex', cfg['engine']
      assert_equal true, cfg.dig('zip', 'inject_styles')
      assert_equal false, cfg['fast']
    end
  end

  def test_init_config_cli
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '--init-config')
        assert status.success?
        assert_includes stdout, 'Created local configuration file: ./.l.jsonc'
        assert File.file?('.l.jsonc')
        content = File.read('.l.jsonc')
        assert_includes content, 'latex_it Global Configuration File'
        assert_includes content, '"engine": "xelatex"'
      end
    end
  end

  def test_bbl_without_bib_lifecycle
    Dir.mktmpdir do |dir|
      bbl_content = <<~BBL
        \\begin{thebibliography}{1}
        \\bibitem{ref1} Author. Title. 2026.
        \\end{thebibliography}
      BBL
      File.write(File.join(dir, 'paper.bbl'), bbl_content)
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'junk', 'paper.aux'), "\\bibdata{refs}\n\\citation{ref1}\n")

      builder = LatexBuilder.new('paper.tex', {})
      Dir.chdir(dir) do
        # 1. paper_cleanup should seed bbl into junk/
        builder.send(:paper_cleanup)
        assert File.file?('junk/paper.bbl')
        assert_equal bbl_content, File.read('junk/paper.bbl')

        # 2. detect_bib_tool should skip bibtex because valid bbl exists and no .bib is present
        assert_nil builder.send(:detect_bib_tool)
      end
    end
  end

  def test_figure_discovery_and_zip_creation
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'figs'))
      FileUtils.mkdir_p(File.join(dir, 'junk'))

      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}Hello\\end{document}\n")
      File.write(File.join(dir, 'paper.pdf'), 'PDF-DUMMY')
      File.write(File.join(dir, 'paper.bbl'), "\\begin{thebibliography}{1}\n\\bibitem{a} A\n\\end{thebibliography}\n")
      File.write(File.join(dir, 'paper.bib'), "@article{a, title={A}}\n")
      File.write(File.join(dir, 'figs', 'diagram.pdf'), 'PDF-FIG')
      File.write(File.join(dir, 'figs', 'diagram.fig'), 'FIG-SOURCE')
      File.write(File.join(dir, 'figs', 'diagram.ipe'), 'IPE-SOURCE')
      File.write(File.join(dir, 'figs', 'standard.isy'), 'ISY-STYLESHEET')
      File.write(File.join(dir, 'figs', 'diagram.bak'), 'JUNK-BAK')
      File.write(File.join(dir, 'extra.txt'), 'EXTRA-CONTENT')

      fls_content = <<~FLS
        INPUT /usr/share/texlive/texmf-dist/tex/latex/base/article.cls
        INPUT ./figs/diagram.pdf
        INPUT ./paper.tex
      FLS
      File.write(File.join(dir, 'junk', 'paper.fls'), fls_content)

      builder = LatexBuilder.new('paper.tex', extra_files: ['extra.txt'])
      packager = LatexPackager.new(builder)

      Dir.chdir(dir) do
        packager.package!
        assert File.file?('paper.zip')

        entries, = Open3.capture2('unzip', '-l', 'paper.zip')
        assert_includes entries, 'paper.tex'
        assert_includes entries, 'paper.pdf'
        assert_includes entries, 'paper.bbl'
        assert_includes entries, 'paper.bib'
        assert_includes entries, 'figs/diagram.pdf'
        assert_includes entries, 'figs/diagram.fig'
        assert_includes entries, 'figs/diagram.ipe'
        assert_includes entries, 'figs/standard.isy'
        assert_includes entries, 'extra.txt'
        refute_includes entries, 'diagram.bak'
      end
    end
  end

  def test_inject_styles_mode
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      File.write(File.join(dir, 'paper.tex'), "%!TEX TS-program = xelatex\n\\documentclass{article}\n\\usepackage{mystyle}\n\\begin{document}X\\end{document}\n")
      File.write(File.join(dir, 'paper.pdf'), 'PDF-DUMMY')
      File.write(File.join(dir, 'mystyle.sty'), "\\ProvidesPackage{mystyle}\n")

      fls_content = <<~FLS
        INPUT ./mystyle.sty
        INPUT ./paper.tex
      FLS
      File.write(File.join(dir, 'junk', 'paper.fls'), fls_content)

      builder = LatexBuilder.new('paper.tex', inject_styles: true)
      packager = LatexPackager.new(builder)

      Dir.chdir(dir) do
        packager.package!
        assert File.file?('paper.zip')

        Dir.mktmpdir do |unzip_dir|
          Open3.capture2('unzip', '-q', File.join(dir, 'paper.zip'), '-d', unzip_dir)
          assert File.file?(File.join(unzip_dir, 'styles', 'mystyle.sty'))

          tex_content = File.read(File.join(unzip_dir, 'paper.tex'))
          assert_includes tex_content, "\\def\\input@path{{styles/}{./}}"
          # Verify magic comments remain at the top
          assert tex_content.start_with?("%!TEX TS-program = xelatex\n")
        end
      end
    end
  end

  def test_cli_zip_with_separator
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}Hi\\end{document}\n")
      File.write(File.join(dir, 'notes.txt'), "Important notes\n")
      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-z', 'paper.tex', '--', 'notes.txt')
        assert status.success?, "l -z failed: #{stdout}"
        assert File.file?('paper.zip')

        entries, = Open3.capture2('unzip', '-l', 'paper.zip')
        assert_includes entries, 'paper.tex'
        assert_includes entries, 'notes.txt'
      end
    end
  end

  def test_cli_zip_and_verify
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n\\begin{document}Verify me\\end{document}\n")
      Dir.chdir(dir) do
        stdout, status = Open3.capture2(BIN, '-z', '-t', 'paper.tex')
        assert status.success?, "l -z -t failed: #{stdout}"
        assert File.file?('paper.zip')
        assert_includes stdout, 'Created portable zip: paper.zip'
        assert_includes stdout, 'Verifying archive portability in isolated sandbox'
        assert_includes stdout, '[VERIFIED]'
        assert_includes stdout, 'Text layout exact match confirmed'
      end
    end
  end

  def test_report_errors_suppresses_warnings
    Dir.mktmpdir do |dir|
      log_file = File.join(dir, 'err_xelatex_1')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        LaTeX Warning: Reference `sec:unknown` undefined on input line 42.
        Overfull \\hbox (15.0pt too wide) in paragraph at lines 10--15
        ! LaTeX Error: File `missing.sty` not found.
        )
      LOG
      File.write(log_file, log_content)

      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        assert_raises(SystemExit) do
          builder.send(:report_errors, log_file)
        end
      end

      # Errors should be displayed
      assert_includes out, 'LaTeX Error: File `missing.sty` not found'
      # Warnings should be suppressed from the displayed body
      refute_includes out, 'Reference `sec:unknown` undefined'
      refute_includes out, 'Overfull \hbox'
      # But count is still reported in summary
      assert_includes out, 'Errors: 1'
      assert_includes out, 'Warnings: 2'
    end
  end

  def test_alerts_and_warnings_display_by_default
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        LaTeX Warning: Reference `sec:unknown` undefined on page 1.
        Overfull \\hbox (15.0pt too wide) in paragraph at lines 10--15
        (./main.aux
        LaTeX Warning: Label `sec:dup` multiply defined.
        )
        )
      LOG
      File.write(log_file, log_content)

      # Default: both alerts and warnings are displayed
      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      assert_includes plain, 'Alerts found:'
      assert_includes plain, 'Label `sec:dup` multiply defined.'
      assert_includes plain, 'Reference `sec:unknown` undefined'
      assert_includes plain, 'Errors: 0'
      assert_includes plain, 'Alerts: 1'
      assert_includes plain, 'Warnings: 2'
      assert_includes plain, 'Whatevers: 0'
      refute_includes plain, 'Warnings: 2 (suppressed)'

      # When suppress_warnings: true, warnings are suppressed
      suppressed_builder = LatexBuilder.new('main.tex', suppress_warnings: true)
      out_supp, = capture_io do
        Dir.chdir(dir) do
          suppressed_builder.send(:analyze_output)
        end
      end

      plain_supp = strip_ansi(out_supp)
      assert_includes plain_supp, 'Alerts found:'
      assert_includes plain_supp, 'Label `sec:dup` multiply defined.'
      refute_includes plain_supp, 'Reference `sec:unknown` undefined'
      assert_includes plain_supp, 'Warnings: 2 (suppressed)'
    end
  end

  def test_overfull_hbox_alert_threshold
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Overfull \\hbox (10.0pt too wide) in paragraph at lines 5--8
        Overfull \\hbox (35.0pt too wide) detected at line 42
        )
      LOG
      File.write(log_file, log_content)

      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      assert_includes plain, 'Alerts found:'
      assert_includes plain, 'Overfull \hbox (35.0pt too wide)'
      assert_includes plain, 'Overfull \hbox (10.0pt too wide)'
      assert_includes plain, 'Errors: 0'
      assert_includes plain, 'Alerts: 1'
      assert_includes plain, 'Warnings: 1'
      assert_includes plain, 'Whatevers: 0'

      # Test custom threshold
      custom_builder = LatexBuilder.new('main.tex', alert_overfull_pt: 50.0)
      out_custom, = capture_io do
        Dir.chdir(dir) do
          custom_builder.send(:analyze_output)
        end
      end

      # Under 50pt threshold, both are warnings (0 alerts)
      plain_custom = strip_ansi(out_custom)
      refute_includes plain_custom, 'Alerts found:'
      assert_includes plain_custom, 'Overfull \hbox (35.0pt too wide)'
      assert_includes plain_custom, 'Overfull \hbox (10.0pt too wide)'
      assert_includes plain_custom, 'Errors: 0'
      assert_includes plain_custom, 'Alerts: 0'
      assert_includes plain_custom, 'Warnings: 2'
    end
  end

  def test_whatevers_classification_and_suppression
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Overfull \\hbox (2.09996pt too wide) in paragraph at lines 20--25
        Package hyperref Warning: Token not allowed in a PDF string (PDFDocEncoding): removing `\\mathshift'
        LaTeX Warning: `!h' float specifier changed to `!ht' on input line 50.
        LaTeX Warning: There were multiply-defined labels.
        )
      LOG
      File.write(log_file, log_content)

      # By default, whatevers are suppressed
      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end

      plain = strip_ansi(out)
      refute_includes plain, '2.09996pt too wide'
      refute_includes plain, 'Token not allowed in a PDF string'
      refute_includes plain, 'float specifier changed to'
      assert_includes plain, 'Whatevers: 4 (suppressed)'

      # With all: true, whatevers are displayed
      all_builder = LatexBuilder.new('main.tex', all: true, suppress_whatevers: false)
      out_all, = capture_io do
        Dir.chdir(dir) do
          all_builder.send(:analyze_output)
        end
      end

      plain_all = strip_ansi(out_all)
      assert_includes plain_all, 'Whatevers found:'
      assert_includes plain_all, '2.09996pt too wide'
      assert_includes plain_all, 'Token not allowed in a PDF string'
      assert_includes plain_all, 'float specifier changed to'
      assert_includes plain_all, 'Whatevers: 4'
      refute_includes plain_all, 'Whatevers: 4 (suppressed)'
    end
  end

  def test_boxed_explanations_with_explain_flag
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        (./main.aux
        LaTeX Warning: Label `sec:first` multiply defined.
        LaTeX Warning: Label `sec:second` multiply defined.
        )
        )
      LOG
      File.write(log_file, log_content)

      # Without explain flag: no explanation box
      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end
      refute_includes out, 'Diagnostic Explanation'

      # With explain: true: boxed explanation printed only on first occurrence
      expl_builder = LatexBuilder.new('main.tex', explain: true)
      out_expl, = capture_io do
        Dir.chdir(dir) do
          expl_builder.send(:analyze_output)
        end
      end

      plain_expl = strip_ansi(out_expl)
      assert_includes plain_expl, 'Diagnostic Explanation: Alert: Multiply-Defined Label'
      assert_includes plain_expl, 'Why: Two or more \label{...} tags share the identical key'
      assert_includes plain_expl, 'Fix: Search your .tex sources for \label{<key>}'
      assert_includes plain_expl, '┌─ Diagnostic Explanation'
      assert_includes plain_expl, '└'

      # Count occurrences of Diagnostic Explanation: must be exactly 1 despite 2 duplicate labels!
      assert_equal 1, plain_expl.scan('Diagnostic Explanation').size
    end
  end

  def test_custom_whatever_pt_threshold
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'junk'))
      log_file = File.join(dir, 'junk', 'err_xelatex')
      log_content = <<~LOG
        This is XeTeX, Version 3.141592653
        (./main.tex
        Overfull \\hbox (4.0pt too wide) in paragraph at lines 10--12
        )
      LOG
      File.write(log_file, log_content)

      # Default threshold 2.5pt: 4.0pt is a Warning
      builder = LatexBuilder.new('main.tex', {})
      out, = capture_io do
        Dir.chdir(dir) do
          builder.send(:analyze_output)
        end
      end
      plain = strip_ansi(out)
      assert_includes plain, 'Warnings: 1'
      assert_includes plain, 'Whatevers: 0'

      # Custom threshold 5.0pt: 4.0pt is demoted to Whatever (suppressed)
      custom_builder = LatexBuilder.new('main.tex', whatever_overfull_pt: 5.0)
      out_custom, = capture_io do
        Dir.chdir(dir) do
          custom_builder.send(:analyze_output)
        end
      end
      plain_custom = strip_ansi(out_custom)
      assert_includes plain_custom, 'Warnings: 0'
      assert_includes plain_custom, 'Whatevers: 1 (suppressed)'
    end
  end

  def test_path_hash_and_project_tmp_file
    Dir.mktmpdir do |dir1|
      Dir.mktmpdir do |dir2|
        b1 = LatexBuilder.new(File.join(dir1, 'main.tex'), {})
        b2 = LatexBuilder.new(File.join(dir2, 'main.tex'), {})

        refute_equal b1.send(:path_hash), b2.send(:path_hash)

        lock1 = b1.send(:project_tmp_file, 'build.lock')
        lock2 = b2.send(:project_tmp_file, 'build.lock')

        refute_equal lock1, lock2
        refute_includes lock1, '/tmp/sariel'
        assert_includes lock1, "latex_it_#{Process.uid}"
        assert_includes lock1, 'main_build.lock'
      end
    end
  end

  def test_with_lock_blocks_concurrent_runs
    Dir.mktmpdir do |dir|
      builder = LatexBuilder.new(File.join(dir, 'paper.tex'), lock: true)
      executed = false

      builder.send(:with_lock) do
        executed = true
        # While locked, another process or thread attempting non-blocking lock should fail
        lock_file = builder.send(:project_tmp_file, 'build.lock')
        assert File.exist?(lock_file)

        File.open(lock_file, File::RDWR) do |f2|
          assert_equal false, f2.flock(File::LOCK_EX | File::LOCK_NB)
        end
      end

      assert executed
    end
  end

  def test_save_build_state_detects_mutation_during_build
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        tex = 'paper.tex'
        File.write(tex, "Original content\n")
        FileUtils.mkdir_p('junk')
        File.write('junk/paper.pdf', 'dummy pdf')
        File.write('paper.pdf', 'dummy pdf')

        builder = LatexBuilder.new(tex, lock: true)
        builder.send(:snapshot_build_inputs!)

        # User modifies paper.tex during compilation
        File.write(tex, "Modified content with typo fix\n")

        builder.send(:save_build_state!)

        # Build state must be discarded because paper.tex was mutated!
        refute File.exist?('junk/.build_state.json')
        refute builder.send(:targets_up_to_date?)
      end
    end
  end

  def test_save_build_state_clean_enables_targets_up_to_date
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        tex = 'paper.tex'
        File.write(tex, "Stable content\n")
        FileUtils.mkdir_p('junk')
        File.write('junk/paper.pdf', 'dummy pdf')
        File.write('paper.pdf', 'dummy pdf')

        builder = LatexBuilder.new(tex, lock: true)
        builder.send(:snapshot_build_inputs!)

        builder.send(:save_build_state!)

        # Build state must be saved cleanly
        assert File.exist?('junk/.build_state.json')
        assert builder.send(:targets_up_to_date?)
      end
    end
  end

  def test_count_errors_in_log_uses_project_tmp_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        log_file = 'junk/test.log'
        File.write(log_file, "LaTeX Warning: Label `foo' multiply defined.\n")

        FileUtils.rm_f('/tmp/sariel/latex_multiply_defined')
        builder = LatexBuilder.new('paper.tex', {})
        builder.send(:count_errors_in_log, 0, log_file)

        tmp_file = builder.send(:project_tmp_file, 'multiply_defined')
        assert File.exist?(tmp_file)
        assert_equal "1\n", File.read(tmp_file)
        refute File.exist?('/tmp/sariel/latex_multiply_defined')
      end
    end
  end

  def test_brace_checker_reproduces_occupancy_reviewed_error
    path = '/home/sariel/papers/teach/26/fa26_rand_alg/notes/07_occupancy/occupancy_reviewed.tex'
    skip 'occupancy_reviewed.tex fixture not available' unless File.file?(path)

    errs = LaTeXBraceChecker.check_file(path)
    assert_equal 1, errs.size
    err = errs.first
    assert_equal 385, err[:line]
    assert_equal 10, err[:col]
    assert_includes err[:text], "inside environment 'equation*'"
    assert_includes err[:text], '\\frac{Y_{i-1}{2}.'
  end

  def test_brace_checker_detects_mismatched_bracket_alert
    snippet = "\\begin{equation*}\n  \\frac{Y_{i-1}{2].\n\\end{equation*}\n"
    errs = LaTeXBraceChecker.new('test.tex', snippet).scan
    assert_equal 1, errs.size
    err = errs.first
    assert_equal 2, err[:line]
    assert err[:has_alert]
    assert_includes err[:text], "Probable mistype at line 2:18 of '}' as ']'"
    assert_includes err[:text], "inside environment 'equation*'"
  end

  def test_brace_checker_ignores_bourbaki_and_half_open_intervals
    snippet = <<~LATEX
      \\begin{theorem}
        Let $x \\in [0, 1)$ and $y \\in ]0, 1]$. We have $\\mathbf{P}[ X \\in (0, 1] ] = 1$.
      \\end{theorem}
    LATEX
    errs = LaTeXBraceChecker.new('test.tex', snippet).scan
    assert_empty errs
  end

  def test_brace_checker_ignores_verbatim_blocks
    snippet = <<~LATEX
      \\begin{document}
      \\begin{verbatim}
        This is { unclosed in verbatim
      \\end{verbatim}
      Text with \\verb|{ unclosed| here.
      \\end{document}
    LATEX
    errs = LaTeXBraceChecker.new('test.tex', snippet).scan
    assert_empty errs
  end

  def test_brace_checker_detects_extra_closing_brace
    snippet = "\\begin{document}\nhello}\n\\end{document}\n"
    errs = LaTeXBraceChecker.new('test.tex', snippet).scan
    assert_equal 1, errs.size
    assert_includes errs.first[:text], "Extra closing brace '}'"
  end
end
