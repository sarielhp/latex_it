#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'

class TestCodeMetrics < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_ast_code_metrics_zero_violations
    audit_bin = File.join(ROOT, 'tools', 'gate_audit_code')
    latex_it_bin = File.join(ROOT, 'latex_it')
    lib_files = Dir.glob(File.join(ROOT, 'lib', '**', '*.rb'))
    tool_files = Dir.glob(File.join(ROOT, 'tools', '*')).select do |p|
      File.file?(p) && (File.extname(p) == '.rb' || File.open(p, &:gets).to_s.start_with?('#!/usr/bin/env ruby'))
    end
    test_files = Dir.glob(File.join(ROOT, 'test', '**', '*.rb'))
    targets = [latex_it_bin] + lib_files + tool_files + test_files
    cmd = ['ruby', audit_bin] + targets
    output, status = Open3.capture2e(*cmd)

    assert status.success?, "Code metrics violations found:\n#{output}"
    assert_includes output, 'Code metrics check passed'
  end

  def test_standalone_bundle_syntax
    bundle_bin = File.join(ROOT, 'tools', 'bundle')
    output, status = Open3.capture2e('ruby', bundle_bin, '--check')

    assert status.success?, "Standalone bundle verification failed:\n#{output}"
    assert_includes output, 'Bundle verified: Syntax OK'
  end
end
