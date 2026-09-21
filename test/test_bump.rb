#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'

class TestBump < Minitest::Test
  BUMP_BIN = File.expand_path('../tools/bump', __dir__)

  BWS_ENV = { 'BWS_SANDBOX' => '1' }.freeze

  def test_bump_rejects_bubblewrap_environment
    out, status = Open3.capture2e(BWS_ENV, BUMP_BIN)
    refute status.success?
    assert_equal 1, status.exitstatus
    assert_includes out, 'Cannot bump version: running inside a Bubblewrap environment'
    assert_includes out, 'Please run ./tools/bump directly on the host machine'
  end

  def test_bump_dry_run_also_rejects_bubblewrap_environment
    out, status = Open3.capture2e(BWS_ENV, BUMP_BIN, '--dry-run')
    refute status.success?
    assert_equal 1, status.exitstatus
    assert_includes out, 'Cannot bump version: running inside a Bubblewrap environment'
  end

  def test_bump_help_still_works_inside_bubblewrap
    out, status = Open3.capture2e(BWS_ENV, BUMP_BIN, '--help')
    assert status.success?
    assert_includes out, 'Usage: ./tools/bump [options]'
    assert_includes out, '--dry-run'
  end
end
