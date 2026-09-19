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

      // LaTeX engine: "xelatex" (default), "lualatex", or "pdflatex".
      // Left unset here on purpose. Engine precedence is:
      //   --engine / symlink personality  >  "% !TEX program =" magic comment
      //   >  this key  >  xelatex
      // Hardcoding it here made the magic comment unreachable.
      // "engine": "xelatex",

      // Accepted for compatibility and currently has no effect; incremental
      // rebuilds are automatic via junk/.build_state.json.
      "fast": false,

      // Maximum compilation passes (1-3, default: 3)
      "passes": 3,

      // Only update target PDF if extracted text content changed (requires pdftotext)
      "update_on_diff": false,

      // Display execution timing diagnostics per pass (-T / --time)
      "time": false,

      // Print exact external subprocess commands and environment overrides (--trace)
      "trace": false,

      // Terminal color output: true (force), false (disable), or null (auto-detect)
      "color": null,

      // Diagnostic color theme: "blush" (default), "catppuccin", "tokyo-night", "dracula", "nord", "ansi"
      "theme": "blush",

      // Help screen visual style: "plain" (default, standard Unix style) or "lines" (subdued horizontal dividers)
      "help_style": "plain",

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

        // Strip private comments (% ...) from the flattened source.
        // Inlining of \\input and \\include is not optional: the staging and
        // verification pipeline assumes a single self-contained .tex file.
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

  VSCODE_TASK_LABEL = 'Build LaTeX (latex_it)'
  VSCODE_TOOL_NAME = 'latex_it'

  def self.default_vscode_task
    {
      'label' => VSCODE_TASK_LABEL,
      'type' => 'shell',
      'command' => 'l',
      'args' => ['--compile'],
      'group' => {
        'kind' => 'build',
        'isDefault' => true
      },
      'presentation' => {
        'reveal' => 'silent',
        'panel' => 'shared'
      },
      'problemMatcher' => {
        'owner' => 'latex',
        'fileLocation' => ['relative', '${workspaceFolder}'],
        'pattern' => {
          'regexp' => '^([^:]+):(\\d+)(?::(\\d+))?:\\s+(error|warning|alert|note):\\s+(.*)$',
          'file' => 1,
          'line' => 2,
          'column' => 3,
          'severity' => 4,
          'message' => 5
        }
      }
    }
  end

  def self.write_vscode_tasks!(vscode_dir)
    tasks_file = File.join(vscode_dir, 'tasks.json')
    data = File.file?(tasks_file) ? parse_jsonc(File.read(tasks_file)) : {}
    data = {} unless data.is_a?(Hash)
    data['version'] ||= '2.0.0'
    raw_tasks = data['tasks'].is_a?(Array) ? data['tasks'] : []
    tasks = raw_tasks.reject { |t| t.is_a?(Hash) && t['label'] == VSCODE_TASK_LABEL }
    tasks << default_vscode_task
    data['tasks'] = tasks
    File.write(tasks_file, "#{JSON.pretty_generate(data)}\n")
    tasks_file
  end

  def self.merge_vscode_tool(tools)
    filtered = tools.reject { |t| t.is_a?(Hash) && t['name'] == VSCODE_TOOL_NAME }
    filtered << { 'name' => VSCODE_TOOL_NAME, 'command' => 'l', 'args' => ['%DOC%'], 'env' => {} }
  end

  def self.merge_vscode_recipe(recipes)
    filtered = recipes.reject { |r| r.is_a?(Hash) && r['name'] == VSCODE_TOOL_NAME }
    filtered << { 'name' => VSCODE_TOOL_NAME, 'tools' => [VSCODE_TOOL_NAME] }
  end

  def self.write_vscode_settings!(vscode_dir)
    settings_file = File.join(vscode_dir, 'settings.json')
    data = File.file?(settings_file) ? parse_jsonc(File.read(settings_file)) : {}
    data = {} unless data.is_a?(Hash)

    raw_tools = data['latex-workshop.latex.tools'].is_a?(Array) ? data['latex-workshop.latex.tools'] : []
    data['latex-workshop.latex.tools'] = merge_vscode_tool(raw_tools)

    raw_recipes = data['latex-workshop.latex.recipes'].is_a?(Array) ? data['latex-workshop.latex.recipes'] : []
    data['latex-workshop.latex.recipes'] = merge_vscode_recipe(raw_recipes)

    data['latex-workshop.latex.recipe.default'] = VSCODE_TOOL_NAME
    data['latex-workshop.latex.outDir'] = '%DIR%/junk'

    File.write(settings_file, "#{JSON.pretty_generate(data)}\n")
    settings_file
  end

  def self.create_vscode_template!(dir = '.')
    vscode_dir = File.join(dir, '.vscode')
    FileUtils.mkdir_p(vscode_dir)

    tasks_path = write_vscode_tasks!(vscode_dir)
    settings_path = write_vscode_settings!(vscode_dir)

    puts "Configured VS Code workspace in #{vscode_dir}:"
    puts "  - #{tasks_path} (Default build task: Ctrl+Shift+B / Cmd+Shift+B)"
    puts "  - #{settings_path} (LaTeX Workshop tool, recipe, and outDir)"
    [tasks_path, settings_path]
  end

  def self.save_global_theme!(new_theme, config_file = GLOBAL_CONFIG_FILE)
    ensure_global_config_exists! if config_file == GLOBAL_CONFIG_FILE
    return false unless File.exist?(config_file)

    content = File.read(config_file)
    updated = if content =~ /"theme"\s*:\s*"[^"]*"/
                content.sub(/"theme"\s*:\s*"[^"]*"/, "\"theme\": \"#{new_theme}\"")
              elsif content =~ /(["']?color["']?\s*:\s*[^,\n]+,)/
                content.sub(/(["']?color["']?\s*:\s*[^,\n]+,)/, "\\1\n\n  // Diagnostic color theme: \"blush\" (default), \"catppuccin\", \"tokyo-night\", \"dracula\", \"nord\", \"ansi\"\n  \"theme\": \"#{new_theme}\",")
              else
                content.sub(/\}\s*\z/, "  \"theme\": \"#{new_theme}\"\n}\n")
              end
    File.write(config_file, updated)
    true
  rescue StandardError => e
    warn " -- Warning: Could not persist theme to #{config_file}: #{e.message}"
    false
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

  def self.active_config_info(dir = '.')
    local_found = LOCAL_CONFIG_CANDIDATES.find { |c| File.file?(File.join(dir, c)) }
    local_path = local_found ? File.join(dir, local_found) : nil

    {
      global_file: GLOBAL_CONFIG_FILE,
      global_exists: File.file?(GLOBAL_CONFIG_FILE),
      local_file: local_path,
      merged_config: load_merged_config(dir)
    }
  end

  def self.format_active_config(dir = '.')
    info = active_config_info(dir)
    lines = [
      '# =========================================================================',
      '# Active latex_it Configuration',
      '# =========================================================================',
      format('# Global file: %s (%s)', info[:global_file], info[:global_exists] ? 'loaded' : 'not found'),
      format('#  Local file: %s', info[:local_file] ? "#{info[:local_file]} (loaded)" : 'none'),
      '',
      JSON.pretty_generate(info[:merged_config])
    ]
    lines.join("\n")
  end
end
