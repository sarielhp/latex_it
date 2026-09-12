# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/config.rb
#
# JSONC configuration loader and template generator for latex_it.
# Supports ~/.config/latex_it/config.jsonc and project-level .l.jsonc overrides.
# ==============================================================================

require 'fileutils'
require 'json'

module LaTeXConfig
  CONFIG_DIR = File.expand_path('~/.config/latex_it')
  GLOBAL_CONFIG_FILE = File.join(CONFIG_DIR, 'config.jsonc')
  LOCAL_CONFIG_CANDIDATES = ['.l.jsonc', '.latex_it.jsonc'].freeze

  DEFAULT_CONFIG_TEMPLATE = <<~JSONC
    {
      // =========================================================================
      // latex_it Global Configuration File
      // Location: ~/.config/latex_it/config.jsonc
      //
      // Project-level overrides can be placed in .l.jsonc (or .latex_it.jsonc).
      // CLI flags always override settings defined here.
      // =========================================================================

      // LaTeX engine: "xelatex" (default), "lualatex", or "pdflatex"
      "engine": "xelatex",

      // Fast incremental mode: reuse .aux and skip redundant passes
      "fast": false,

      // Maximum compilation passes (1-3, default: 3)
      "passes": 3,

      // Only update target PDF if extracted text content changed (requires pdftotext)
      "update_on_diff": false,

      // Display execution timing diagnostics per pass (-T / --time)
      "time": false,

      // Terminal color output: true (force), false (disable), or null (auto-detect)
      "color": null,

      // Lockfile concurrency protection
      "lock": true,

      // Treat compilation warnings as fatal errors (-W / --werror)
      "werror": false,

      // Legacy REVTeX 4.0 compatibility files. Installed files are used only
      // for compiler subprocesses; project sources are never modified.
      "revtex4": {
        "enabled": true,
        "texmf_dirs": []
      },

      // Format warnings/errors for Emacs AUCTeX integration
      "emacs": false,

      // Overfull \\hbox threshold (in pt) to promote to Alert (default: 24.0)
      "alert_overfull_pt": 24.0,

      // Overfull \\hbox threshold (in pt) to demote to Whatever (default: 2.5)
      "whatever_overfull_pt": 2.5,

      // Diagnostic tier suppression (by default only Whatevers are suppressed)
      "suppress_whatevers": true,
      "suppress_warnings": false,
      "suppress_alerts": false,

      // Filename patterns ignored when auto-detecting the main .tex document
      "exclude_main_tex": [
        "prefix*.tex",
        "prelim*.tex",
        "preamble*.tex",
        "*.num.tex",
        "pratenddefaultcategory.tex"
      ],

      // Patterns excluded from brace checking and diagnostic source scans
      "exclude_source_tex": [
        "styles/*",
        "macros/*",
        "pkg/*",
        "packages/*",
        "*prefix*.tex",
        "*preamble*.tex",
        "*macros*.tex",
        "*styles*.tex"
      ],

      // Directories searched for bibliography (.bib) files (in addition to root)
      "bib_dirs": ["refs", "bib", "bibliography"],

      // Automatically mirror project subdirectories into junk/ for nested inputs
      "auto_mirror_subdirs": true,

      // Additional subdirectories inside junk/ to pre-create
      "junk_subdirs": ["figs", "fragment"],

      // Portable Zip Bundling Settings (invoked via `l -z`)
      "zip": {
        // When true, harvested style files are placed in styles/ and \\input@path
        // is injected into the packaged .tex file.
        // When false (default), harvested styles sit in the archive root.
        "inject_styles": false,

        // Additional figure source file extensions to auto-discover
        "fig_sources": [".fig", ".ipe", ".svg", ".asy", ".gp", ".gnuplot", ".py", ".R"],

        // Supplementary files or glob patterns to always bundle in this project
        "include": []
      },

      // arXiv Submission Preparation Settings (invoked via `l --arxiv`)
      "arxiv": {
        // Automatically bundle local biblatex files to prevent version mismatch
        "bundle_biblatex": true,

        // Recursively inline all \\input and \\include statements into a single .tex file
        "flatten": true,

        // Strip private comments (% ...) from sources
        "strip_comments": true,

        // Verify package in isolated /tmp sandbox before completing
        "verify": true,

        // Render and compare every PDF page during arXiv verification
        "visual_verify": true,

        // Default comments string for submission (e.g. page count, conference details)
        "comments": null,

        // File patterns in \\IfFileExists{...} stripped during flattening
        "strip_host_patterns": ["computer", "local", "private"]
      }
    }
  JSONC

  def self.ensure_global_config_exists!
    return if File.exist?(GLOBAL_CONFIG_FILE)

    FileUtils.mkdir_p(CONFIG_DIR)
    File.write(GLOBAL_CONFIG_FILE, DEFAULT_CONFIG_TEMPLATE)
  rescue StandardError
    # Silently ignore if unable to create in restricted environments
  end

  def self.create_local_template!(dir = '.')
    local_path = File.join(dir, '.l.jsonc')
    if File.exist?(local_path)
      warn " -- Local config already exists: #{local_path}"
      return
    end

    File.write(local_path, DEFAULT_CONFIG_TEMPLATE)
    puts "Created local configuration file: #{local_path}"
  end

  def self.skip_comment(content, i, len)
    if content[i, 2] == '//'
      content.index("\n", i) || len
    elsif content[i, 2] == '/*'
      end_idx = content.index('*/', i + 2)
      end_idx ? end_idx + 2 : len
    end
  end

  # Removes comments and trailing commas in a single pass that tracks string
  # boundaries. Two defects lived here before:
  #
  #   * `escaped` was recomputed for the current character before the
  #     close-quote test, so when c == '"' the expression `!escaped && c ==
  #     '\\'` was always false and the `!escaped` guard was always true. An
  #     escaped \" therefore ended the string, and a following // or /* ate the
  #     rest of the file. Since a parse failure returns {}, a single \" in one
  #     value discarded the user's entire configuration. An even number of \"
  #     re-synchronised by accident, which made the failure look random.
  #
  #   * Trailing commas were removed afterwards with a gsub over the whole
  #     document, so a comma inside a string value that preceded } or ] was
  #     deleted too. arxiv.comments is free text that reaches the metadata file
  #     the user pastes into the arXiv form.
  def self.strip_comments(content)
    state = { in_string: false, escaped: false, pending_comma: nil }
    out = []
    i = 0
    len = content.length

    while i < len
      i = scan_jsonc_char(content, i, len, out, state)
    end
    out << ',' if state[:pending_comma]
    out.join
  end

  # Returns the index to continue scanning from.
  def self.scan_jsonc_char(content, i, len, out, state)
    c = content[i]
    if state[:in_string]
      scan_inside_string(c, out, state)
      return i + 1
    end

    skip_to = skip_comment(content, i, len)
    return skip_to if skip_to

    flush_pending_comma(c, out, state)
    scan_outside_string(c, out, state)
    i + 1
  end

  def self.scan_inside_string(c, out, state)
    out << c
    if state[:escaped]
      state[:escaped] = false
    elsif c == '\\'
      state[:escaped] = true
    elsif c == '"'
      state[:in_string] = false
    end
  end

  # A comma is held back until the next significant character is known: if that
  # turns out to be } or ] the comma was trailing and is dropped.
  def self.flush_pending_comma(c, out, state)
    return unless state[:pending_comma]
    return if c.match?(/\s/)

    out << ',' unless c == '}' || c == ']'
    state[:pending_comma] = nil
  end

  def self.scan_outside_string(c, out, state)
    if c == ','
      state[:pending_comma] = true
    elsif c == '"'
      state[:in_string] = true
      out << c
    else
      out << c
    end
  end

  def self.parse_jsonc(content)
    return {} if content.nil? || content.strip.empty?

    JSON.parse(strip_comments(content))
  rescue JSON::ParserError => e
    warn " -- Warning: Could not parse JSONC config (#{e.message}); using defaults."
    {}
  rescue StandardError
    {}
  end

  def self.load_merged_config(dir = '.')
    ensure_global_config_exists!

    base_cfg = parse_jsonc(DEFAULT_CONFIG_TEMPLATE)
    global_cfg = File.exist?(GLOBAL_CONFIG_FILE) ? parse_jsonc(File.read(GLOBAL_CONFIG_FILE)) : {}
    merged_global = deep_merge(base_cfg, global_cfg)

    local_cfg = {}
    LOCAL_CONFIG_CANDIDATES.each do |candidate|
      path = File.join(dir, candidate)
      if File.exist?(path)
        local_cfg = parse_jsonc(File.read(path))
        break
      end
    end

    deep_merge(merged_global, local_cfg)
  end

  def self.deep_merge(hash1, hash2)
    merged = hash1.dup
    hash2.each do |k, v|
      merged[k] = if v.is_a?(Hash) && merged[k].is_a?(Hash)
                    deep_merge(merged[k], v)
                  else
                    v
                  end
    end
    merged
  end
end
