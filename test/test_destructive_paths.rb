# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

require_relative '../lib/latex_it/utils'
require_relative '../lib/latex_it/builder'

# Guards every path that deletes files in the user's project directory.
# The tool writes all of its own scratch output under junk/; anything these
# sweeps match in the project root can therefore only be a file the user wrote.
class TestDestructivePaths < Minitest::Test
  BIN = File.expand_path('../latex_it', __dir__)
  load BIN

  def build_options
    { engine: 'xelatex', lock: false, junk_subdirs: [], auto_mirror_subdirs: false }
  end

  def test_paper_cleanup_preserves_user_log_txt
    Dir.mktmpdir('latex_it_cleanup_test') do |dir|
      Dir.chdir(dir) do
        File.write('paper.tex', "\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
        File.write('log.txt', "experiment results, not a LaTeX artifact\n")

        LatexBuilder.new('paper.tex', build_options).send(:paper_cleanup)

        assert_path_exists 'log.txt', 'paper_cleanup deleted a user-authored log.txt'
        assert_equal "experiment results, not a LaTeX artifact\n", File.read('log.txt')
      end
    end
  end

  def test_clean_directory_preserves_user_authored_files
    Dir.mktmpdir('latex_it_clean_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('figs/bak')
        File.write('figs/bak/old_figure.pdf', 'user backup')
        File.write('err_analysis.rb', 'user script')
        File.write('bounds.err.tex', 'user source')
        File.write('log.txt', 'user log')

        LaTeXUtils.clean_directory('.', false)

        assert_path_exists 'figs/bak/old_figure.pdf', 'clean_directory removed the user backup directory figs/bak'
        assert_path_exists 'err_analysis.rb', "clean_directory removed a user file matching 'err_*'"
        assert_path_exists 'bounds.err.tex', "clean_directory removed a user file matching '*.err*'"
        assert_path_exists 'log.txt', 'clean_directory removed a user-authored log.txt'
      end
    end
  end

  def test_clean_directory_still_removes_real_artifacts
    Dir.mktmpdir('latex_it_clean_real_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('junk/paper.aux', 'artifact')
        %w[paper.aux paper.bbl paper.blg paper.log paper.out paper.toc texput.log missfont.log].each do |f|
          File.write(f, 'artifact')
        end

        LaTeXUtils.clean_directory('.', false)

        refute Dir.exist?('junk'), 'clean_directory left junk/ in place'
        %w[paper.aux paper.bbl paper.blg paper.log paper.out paper.toc texput.log missfont.log].each do |f|
          refute_path_exists f, "clean_directory left the build artifact #{f}"
        end
      end
    end
  end

  def test_directory_argument_rejects_a_path_that_does_not_exist
    Dir.mktmpdir('latex_it_target_test') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('sub')
        File.write('paper.tex', "\\documentclass{article}\n")

        assert_nil LatexCLI.directory_argument('typo_dir'),
                   'a non-existent argument must not silently resolve to the current directory'
        assert_nil LatexCLI.directory_argument('nested/typo_dir')
        assert_equal '.', LatexCLI.directory_argument(nil)
        assert_equal 'sub', LatexCLI.directory_argument('sub')
        assert_equal '.', LatexCLI.directory_argument('paper.tex')
      end
    end
  end

  def test_clean_only_with_a_bad_directory_exits_without_cleaning
    Dir.mktmpdir('latex_it_badtarget_test') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n")
      File.write(File.join(dir, 'paper.aux'), 'artifact')

      _out, status = Open3.capture2e(BIN, '-C', 'typo_dir', chdir: dir)

      refute status.success?, 'a non-existent clean target must be an error'
      assert_path_exists File.join(dir, 'paper.aux'),
                         'l -C <typo> cleaned the current directory instead of erroring'
    end
  end

  def test_help_wins_over_clean_only
    Dir.mktmpdir('latex_it_help_test') do |dir|
      File.write(File.join(dir, 'paper.tex'), "\\documentclass{article}\n")
      File.write(File.join(dir, 'paper.aux'), 'artifact')

      stdout, status = Open3.capture2e(BIN, '-C', '-h', chdir: dir)

      assert status.success?
      assert_match(/Usage:/, stdout, 'l -C -h did not print help')
      assert_path_exists File.join(dir, 'paper.aux'),
                         'l -C -h performed the destructive sweep instead of printing help'
    end
  end

  def test_normalize_engine_rejects_arbitrary_programs
    # A project-local .l.jsonc ships inside any cloned repository, and its
    # engine value used to flow straight through to the executed binary.
    %w[python3 sh curl bash ruby nc].each do |hostile|
      assert_equal 'xelatex', LaTeXUtils.normalize_engine(hostile),
                   "normalize_engine passed #{hostile.inspect} through as an engine"
    end
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('/usr/bin/python3')
  end

  def test_normalize_engine_keeps_real_engines
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('xelatex')
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('xetex')
    assert_equal 'lualatex', LaTeXUtils.normalize_engine('lualatex')
    assert_equal 'pdflatex', LaTeXUtils.normalize_engine('pdftex')
    assert_equal 'tectonic', LaTeXUtils.normalize_engine('tectonic')
    assert_equal 'xelatex', LaTeXUtils.normalize_engine('xelatex -shell-escape')
  end
end
