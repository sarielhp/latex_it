#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'json'
require 'fileutils'
require_relative '../tools/arxiv_test_worker'

class TestArxivWorker < Minitest::Test
  def worker
    old_lang = ENV['LANG']
    old_locale = ENV['LC_ALL']
    old_encoding = Encoding.default_external
    Dir.mktmpdir('arxiv_worker_review_') do |root|
      File.write(File.join(root, 'test-config.json'), JSON.generate(main: 'paper.tex', engine: 'xelatex'))
      File.write(File.join(root, 'latex_it'), '# fixture executable')
      FileUtils.mkdir_p(File.join(root, 'paper'))
      File.write(File.join(root, 'paper/paper.tex'), "\\documentclass{article}\n\\begin{document}Test\\end{document}\n")
      yield ArxivTestWorker::Runner.new(root), root
    end
  ensure
    ENV['LANG'] = old_lang
    ENV['LC_ALL'] = old_locale
    Encoding.default_external = old_encoding
  end

  def test_successful_exit_is_insufficient_for_noop_build
    worker do |runner, _|
      runner.stub(:pdf_state, ['same', 'time']) do
        runner.stub(:compile, { exit_status: 0, passes: 1 }) do
          assert_raises(ArxivTestWorker::CheckError) { runner.unchanged }
        end
      end
    end
  end

  def test_diff_check_rejects_replaced_pdf_despite_success
    worker do |runner, _|
      states = [%w[old time], %w[new time]]
      runner.stub(:pdf_state, -> { states.shift }) do
        runner.stub(:compile, { exit_status: 0, passes: 1 }) do
          assert_raises(ArxivTestWorker::CheckError) { runner.diff }
        end
      end
    end
  end

  def test_failure_probe_restores_source_and_rejects_false_success
    worker do |runner, root|
      path = File.join(root, 'paper/paper.tex')
      original = File.binread(path)
      compiler = lambda do
        content = File.binread(path)
        assert content.start_with?('\\latexItDeliberatelyUndefinedProbe') || content == original
        { exit_status: 0, passes: 1 }
      end
      capture_io { runner.stub(:compile, compiler) { runner.failure_recovery } }
      assert_equal original, File.binread(path)
      report = JSON.parse(File.read(File.join(root, 'test-worker-report.json')))
      assert_equal %w[FAIL PASS], report.fetch('checks').map { |check| check.fetch('status') }
    end
  end

  def test_dependency_probe_keeps_mtime_and_restores_source
    worker do |runner, root|
      path = File.join(root, 'paper/paper.tex')
      original = File.binread(path)
      timestamp = File.mtime(path)
      call = 0
      compiler = lambda do
        call += 1
        if call == 2
          refute_equal original, File.binread(path)
          assert_equal timestamp, File.mtime(path)
        end
        { exit_status: 0, passes: call == 3 ? 0 : 1 }
      end
      runner.stub(:pdf_state, %w[hash time]) do
        capture_io { runner.stub(:compile, compiler) { runner.change_dependency } }
      end
      assert_equal original, File.binread(path)
      assert_equal timestamp, File.mtime(path)
    end
  end
end
