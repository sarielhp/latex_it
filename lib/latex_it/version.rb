# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/version.rb
#
# Canonical version and executable path resolution for latex_it.
# ==============================================================================

module LatexIt
  VERSION_FILE = File.expand_path('../../VERSION', __dir__)
  VERSION = (File.file?(VERSION_FILE) ? File.read(VERSION_FILE).strip : '0.20.0').freeze
  EXECUTABLE = File.expand_path('../../latex_it', __dir__).freeze
end

VERSION = LatexIt::VERSION
LATEX_IT_EXECUTABLE = LatexIt::EXECUTABLE
