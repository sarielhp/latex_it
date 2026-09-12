# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/latex_it/utils'
require_relative '../lib/latex_it/builder'

# Guards every path that deletes files in the user's project directory.
# The tool writes all of its own scratch output under junk/; anything these
# sweeps match in the project root can therefore only be a file the user wrote.
class TestDestructivePaths < Minitest::Test
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
end
