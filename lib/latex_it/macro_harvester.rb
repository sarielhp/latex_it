# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/macro_harvester.rb
#
# Scans local project source files (.tex, .sty, .cls) to harvest custom macro
# declarations for fuzzy suggestions during diagnostic error reporting.
# ==============================================================================

module LaTeXMacroHarvester
  MACRO_DEF_PATTERN = %r{
    \\(?:
      (?:renew|new|provide)command|
      DeclareRobustCommand|
      (?:New|Renew|Provide|Declare)DocumentCommand|
      Declare(?:MathOperator|PairedDelimiter)
    )\*?\s*\{?\\([a-zA-Z@]+)
    |
    \\(?:[gex]?def|let)\s*\\([a-zA-Z@]+)
  }x.freeze

  EXCLUDED_DIRS = %w[junk .git .bws .gemini node_modules].freeze

  @cache = {}

  def self.harvest(file_path = nil)
    root = determine_project_root(file_path)
    return [] unless root

    @cache[root] ||= scan_project(root)
  end

  def self.clear_cache!
    @cache = {}
  end

  def self.determine_project_root(file_path)
    if file_path && !file_path.to_s.strip.empty?
      source = resolve_file(file_path)
      return resolve_source_root(source) if source
    end

    pwd = File.expand_path(Dir.pwd)
    root_indicator?(pwd) ? pwd : nil
  end

  def self.resolve_source_root(source)
    source_abs = File.expand_path(source)
    return source_abs if File.directory?(source_abs)

    pwd_abs = File.expand_path(Dir.pwd)
    return pwd_abs if source_abs.start_with?(pwd_abs) && root_indicator?(pwd_abs)

    find_project_root_ancestor(File.dirname(source_abs))
  end

  def self.root_indicator?(dir)
    return true if File.file?(File.join(dir, '.mainfile'))

    Dir.glob(File.join(dir, '*.tex')).any? do |f|
      File.file?(f) && File.size(f) <= 1_000_000 && File.read(f, 2048)&.include?('\\documentclass')
    rescue StandardError
      false
    end
  end

  def self.find_project_root_ancestor(start_dir)
    curr = start_dir
    4.times do
      return curr if root_indicator?(curr)

      parent = File.dirname(curr)
      break if parent == curr

      curr = parent
    end
    start_dir
  end

  def self.resolve_file(file_path)
    return nil if file_path.nil? || file_path.to_s.strip.empty?

    clean = file_path.to_s.strip.delete_prefix('"').delete_suffix('"')
    return clean if File.exist?(clean)

    base = File.basename(clean)
    File.exist?(base) ? base : nil
  end

  def self.scan_project(root)
    files = collect_source_files(root)
    macros = []
    files.each { |f| scan_file_for_macros(f, macros) }
    macros.uniq
  end

  def self.collect_source_files(root)
    candidates = Dir.glob(File.join(root, '**', '*.{tex,sty,cls}'))
    candidates.reject! do |path|
      excluded_dir?(path) || (File.file?(path) && File.size(path) > 1_000_000)
    end
    candidates[0...200]
  end

  def self.excluded_dir?(path)
    parts = path.split(File::SEPARATOR)
    (parts & EXCLUDED_DIRS).any?
  end

  def self.scan_file_for_macros(file_path, macros)
    return unless File.file?(file_path)

    File.foreach(file_path) do |line|
      clean = line.chomp.sub(/(?<!\\)%.*\z/, '')
      clean.scan(MACRO_DEF_PATTERN) do |c1, c2|
        cmd = c1 || c2
        macros << cmd if cmd && cmd.length >= 3
      end
    end
  rescue StandardError
    nil
  end
end
