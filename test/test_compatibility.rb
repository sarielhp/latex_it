#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
load File.expand_path('../latex_it', __dir__)

class TestCompatibility < Minitest::Test
  def test_revtex4_tree_is_available_to_compiler_subprocesses
    environment = LaTeXCompatibility.compiler_environment(revtex4: { 'enabled' => true })
    expected = File.join(LaTeXCompatibility::REPO_TEXMF, 'tex', 'latex', 'revtex4')
    assert_includes environment.fetch('TEXINPUTS').split(File::PATH_SEPARATOR), expected
  end

  def test_revtex4_can_be_disabled
    environment = LaTeXCompatibility.compiler_environment({ revtex4: { 'enabled' => false } }, {})
    assert_empty environment
  end

  def test_compiler_environment_preserves_bibinputs
    base = { 'BIBINPUTS' => '/path/to/my/bibs:' }
    environment = LaTeXCompatibility.compiler_environment({ revtex4: { 'enabled' => true } }, base)
    assert_equal '/path/to/my/bibs:', environment['BIBINPUTS']
  end

  def test_fls_identifies_used_compatibility_files
    Dir.mktmpdir('latex-it-compat-') do |dir|
      path = File.join(LaTeXCompatibility::REPO_TEXMF, 'tex/latex/revtex4/revtex4.cls')
      fls = File.join(dir, 'paper.fls')
      File.write(fls, "INPUT #{path}\nINPUT /usr/share/texlive/texmf-dist/tex/latex/base/article.cls\n")
      assert_equal [path], LaTeXCompatibility.files_used_by_fls(fls, revtex4: { 'enabled' => true })
    end
  end

  def test_portable_packager_treats_revtex_rtx_files_as_styles
    Dir.mktmpdir('latex-it-compat-') do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('junk')
        File.write('paper.tex', '\\documentclass{revtex4}')
        rtx = File.join(LaTeXCompatibility::REPO_TEXMF, 'tex/latex/revtex4/aps.rtx')
        File.write('junk/paper.fls', "INPUT #{rtx}\n")
        packager = LatexPackager.new(LatexBuilder.new('paper.tex', {}))
        assert_includes packager.send(:collect_fls_dependencies, 'junk/paper.fls')[:styles], rtx
      end
    end
  end
end
