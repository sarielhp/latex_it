# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/utils.rb
#
# Core utility functions for LaTeX engine detection, main document resolution,
# noise filtering, environment sanitization, and cleanup.
# ==============================================================================

require 'fileutils'

module LaTeXUtils
  # `figs/bak` is deliberately absent: the packager treats it as a user-owned
  # backup directory to exclude from bundles, so cleaning must not delete it.
  JUNK_BUILD_DIRS = %w[junk styles/junk figs/junk refs/junk].freeze

  # Every scratch file this tool writes lives under `junk/`, which is removed
  # wholesale via JUNK_BUILD_DIRS. These patterns therefore only ever run over
  # the project root, where a match can only be a TeX-generated artifact or a
  # file the user wrote by hand. Patterns that cannot distinguish the two --
  # `log.txt`, `err_*`, `*.err*` -- were removed for that reason; the tool's own
  # copies of those are `junk/log.txt`, `junk/log.txt.1` and `junk/err_<engine>`.
  JUNK_PATTERNS = [
    '*.{aux,bbl,bbl.bak,blg,bcf,run.xml}',
    '*.{log,out,toc,lof,lot,thm,idx,ind,ilg}',
    '*.{nav,snm,vrb,synctex.gz,synctex,dvi,ps}',
    '*.{fls,fdb_latexmk,rel,vtc,axp,dpth,md5,soc,build_state.json}',
    '.build_state.json',
    'texput.log', 'missfont.log', 'mfput.log',
    'flycheck_*.tex',
    'arxiv_*_meta.txt'
  ].freeze

  TEX_ENV_VARS = %w[
    BIBINPUTS BSTINPUTS TEXINPUTS PDFTEXINPUTS XETEXINPUTS LUATEXINPUTS
    LUAINPUTS BBLINPUTS TEXMFOUTPUT TEXFORMATS TEXFONTS TFMFONTS T1FONTS
    OFMFONTS AFMFONTS TTFONTS OPENTYPEFONTS MFINPUTS MPINPUTS TEXPICTS
    TEXDOCS TEXSOURCES TEXPOOL INDEXSTYLE BIBTEX_PREFIX TEXMFHOME TEXMFVAR
    TEXMFCONFIG TEXMFLOCAL TEXMFSYSCONFIG TEXMFSYSVAR TEXMFCNF TEXMF
    TEXMFDBS TEXMFCACHE
  ].freeze

  DEFAULT_EXCLUDE_MAIN_PATTERNS = [
    'prefix*.tex', 'prelim*.tex', 'preamble*.tex',
    '*.num.tex', 'pratenddefaultcategory.tex'
  ].freeze

  DEFAULT_EXCLUDE_SOURCE_PATTERNS = [
    'styles/*', 'macros/*', 'pkg/*', 'packages/*',
    '*prefix*.tex', '*preamble*.tex', '*macros*.tex', '*styles*.tex'
  ].freeze

  DEFAULT_BIB_DIRS = %w[refs bib bibliography].freeze
  DEFAULT_JUNK_SUBDIRS = %w[figs fragment].freeze
  DEFAULT_STRIP_HOST_PATTERNS = %w[computer local private].freeze

  # Engines this tool is willing to execute. The engine name reaches here from a
  # project-local .l.jsonc, from a `% !TEX program =` magic comment, and from
  # PDFBIN/LATEX_ENGINE -- all of which travel inside a repository or an
  # environment the user may not control. Anything outside this list is refused
  # rather than passed through to Open3 as a program name.
  KNOWN_ENGINES = %w[xelatex lualatex pdflatex latex tectonic].freeze

  def self.normalize_engine(engine)
    return 'xelatex' if engine.nil? || engine.to_s.strip.empty?

    eng = engine.to_s.strip.downcase
    first_token = eng.split.first || ''
    base = File.basename(first_token, '.*')
    case base
    when 'lua', 'lualatex', 'luatex'
      'lualatex'
    when 'xe', 'xelatex', 'xetex'
      'xelatex'
    when 'pdf', 'pdflatex', 'pdftex'
      'pdflatex'
    when *KNOWN_ENGINES
      base
    else
      warn " -- Warning: unknown LaTeX engine #{base.inspect}; using xelatex."
      'xelatex'
    end
  end

  def self.detect_engine_from_file(path)
    return nil unless path && File.file?(path)

    content = safe_read(path)
    return nil if content.empty?

    # 1. Magic comments in header
    header_lines = content.lines.first(50) || []
    header_lines.each do |line|
      if line =~ /^\s*%\s*!T[eE]X\s+(?:TS-)?(?:program|engine)\s*=\s*(\S+)/i
        return normalize_engine(Regexp.last_match(1).strip)
      end
    end

    # 2. AUCTeX local variables at footer
    tail_lines = content.lines.last(40) || []
    tail_lines.each do |line|
      if line =~ /TeX-engine:\s*([a-zA-Z0-9_-]+)/i
        return normalize_engine(Regexp.last_match(1).strip)
      end
    end

    # 3. Lua-specific packages
    if content =~ /\\usepackage(?:\[.*?\])?\{luacode\}/ ||
       content =~ /\\usepackage(?:\[.*?\])?\{luamplib\}/ ||
       content =~ /\\usepackage(?:\[.*?\])?\{luatex85\}/ ||
       content.include?('\\directlua')
      return 'lualatex'
    end

    if content =~ /\\(?:usepackage|RequirePackage)\s*(?:\[[^\]]*\])?\s*\{\s*inputenc\s*\}/i
      return 'pdflatex'
    end

    nil
  end

  def self.source_requires_pdflatex?(path)
    !source_pdflatex_reasons(path).empty?
  end

  def self.source_pdflatex_reasons(path)
    return [] unless path && File.file?(path)

    content = strip_latex_comments(safe_read(path))
    reasons = []
    if content.match?(/\\(?:usepackage|RequirePackage)\s*(?:\[[^\]]*\])?\s*\{\s*inputenc\s*\}/i)
      reasons << 'inputenc'
    end
    if content.match?(/\\includegraphics\s*(?:\[[^\]]*\])?\s*\{[^}\n]*\.eps(?:\s*\})/i) ||
       content.match?(/\\epsfig\s*\{[^}\n]*\bfile\s*=\s*[^,}\n]*\.eps(?:\s*[,}])/i)
      reasons << 'EPS graphics'
    end
    reasons
  end

  def self.strip_latex_comments(content)
    content.lines.map { |line| line.sub(/(?<!\\)%.*$/, '') }.join
  end

  def self.compatible_engine(engine, path)
    normalized = normalize_engine(engine)
    return 'pdflatex' if %w[xelatex lualatex].include?(normalized) && source_requires_pdflatex?(path)

    normalized
  end

  def self.edit_distance(left, right)
    return 0 if left == right
    return right.length if left.empty?
    return left.length if right.empty?

    previous = (0..right.length).to_a
    left.each_char.with_index(1) do |left_char, row|
      current = [row]
      right.each_char.with_index(1) do |right_char, col|
        cost = left_char == right_char ? 0 : 1
        current << [current[col - 1] + 1, previous[col] + 1, previous[col - 1] + cost].min
      end
      previous = current
    end
    previous.last
  end

  def self.safe_read(path)
    return '' unless path && File.file?(path)

    raw = File.read(path, mode: 'r:binary', invalid: :replace, undef: :replace)
    raw.force_encoding('UTF-8').scrub
  rescue StandardError
    ''
  end

  def self.filter_subcommand_noise(text)
    return '' if text.nil? || text.empty?

    text.gsub(/(?:kpathsea: Running mktex\S+|mktex\S+: Running mf).*?(?:failed to make \S+|Transcript written on mfput\.log\.)\n?/m, '')
  end

  def self.bbl_has_entries?(path)
    return false unless path && File.file?(path) && File.size(path) > 0

    content = safe_read(path)
    content.include?('\bibitem') || content.include?('\entry{')
  end

  def self.command_available?(cmd)
    ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |dir|
      bin = File.join(dir, cmd.to_s)
      File.file?(bin) && File.executable?(bin)
    end
  end

  def self.check_program(cmd)
    return if command_available?(cmd)

    warn "ERROR: #{cmd} could not be found in PATH"
    exit 1
  end

  def self.candidate_tex_files(dir, exclude_patterns = nil)
    patterns = exclude_patterns || DEFAULT_EXCLUDE_MAIN_PATTERNS
    search_path = (dir == '.' ? '*.tex' : File.join(dir, '*.tex'))
    Dir[search_path].map { |f| File.basename(f) }.reject do |f|
      f.start_with?('flycheck_', '.') || f.end_with?('~', '.bak') ||
        patterns.any? { |pat| File.fnmatch?(pat, f, File::FNM_CASEFOLD | File::FNM_EXTGLOB) }
    end
  end

  def self.find_main_latex_file(dir = '.', exclude_patterns = nil)
    mainfile = File.join(dir, '.mainfile')
    if File.exist?(mainfile)
      mf = File.read(mainfile).strip
      return mf unless mf.empty?
    end

    candidates = candidate_tex_files(dir, exclude_patterns)
    if candidates.empty?
      warn "Error: No LaTeX (.tex) files found in directory '#{File.expand_path(dir)}'."
      exit 1
    end
    return candidates.first if candidates.size == 1

    dir_match = "#{File.basename(File.expand_path(dir))}.tex"
    return dir_match if candidates.include?(dir_match)

    with_doc = candidates.select do |f|
      c = safe_read(File.join(dir, f))
      c.include?('\begin{document}') || c.include?('\documentclass')
    end
    return with_doc.first if with_doc.size == 1

    with_pdf = candidates.select do |f|
      base = File.basename(f, '.tex')
      File.exist?(File.join(dir, "#{base}.pdf")) || File.exist?(File.join(dir, 'junk', "#{base}.pdf"))
    end
    return with_pdf.first if with_pdf.size == 1

    warn 'Error: Multiple candidate .tex files found. Please specify which file to compile, or'
    warn '       create a .mainfile containing the name of the main LaTeX file:'
    candidates.each { |f| warn "  #{f}" }
    exit 1
  end

  def self.clean_directory(dir = '.', verbose = true)
    target_dir = File.expand_path(dir)
    return unless File.directory?(target_dir)

    puts "Cleaning LaTeX auxiliary files in #{target_dir}..." if verbose

    Dir.chdir(target_dir) do
      JUNK_BUILD_DIRS.each { |d| FileUtils.rm_rf(d) if File.exist?(d) }
      JUNK_PATTERNS.each do |pat|
        Dir.glob(pat).each { |f| FileUtils.rm_f(f) if File.file?(f) }
      end
    end
  end

  def self.reset_latex_environment!
    TEX_ENV_VARS.each { |var| ENV.delete(var) }
    ENV.keys.each do |key|
      ENV.delete(key) if key =~ /\A(?:TEX|BIB|BST|LUA|MF|MP)INPUTS/i
    end
  end

  def self.detailed_examples(banner = nil)
    lines = []
    lines << banner if banner && !banner.empty?
    lines << '' if banner && !banner.empty?
    lines << 'Detailed Examples & Common Workflows:'
    lines << ''
    lines << '  1. Standard Compilation:'
    lines << '     l                              Auto-detect main .tex and compile using xelatex'
    lines << '     l paper.tex                    Compile specified paper.tex'
    lines << '     l -1                           Force first pass (skip up-to-date check), continuing if needed'
    lines << '     l -u                           Fast single pass only (no BibTeX/Biber, no extra passes)'
    lines << '     lw (or l --fast)               Incremental fast mode reusing cached aux/bbl'
    lines << ''
    lines << '  2. Compiler Engines:'
    lines << '     l --lua paper.tex              Compile using LuaLaTeX'
    lines << '     l --pdflatex paper.tex         Compile using pdfLaTeX'
    lines << '     l --xe paper.tex               Explicitly compile using XeLaTeX (default)'
    lines << ''
    lines << '  3. Diagnostics & Error Handling:'
    lines << '     l -e                           Display plain-English diagnostic explanations & fixes'
    lines << '     l -a                           Show all diagnostics (including suppressed Whatevers)'
    lines << '     l -c                           Clean build artifacts (junk/, .aux, .bbl) before building'
    lines << '     l -C                           Clean directory artifacts and exit without building'
    lines << '     l -s                           Quiet score mode (prints error/alert/warning counts)'
    lines << '     l -W                           Treat compilation warnings as fatal errors'
    lines << ''
    lines << '  4. Output Protection & Diffing:'
    lines << '     l -d                           Only replace PDF if rendered text layout changed'
    lines << ''
    lines << '  5. Portable Paper Bundling & Verification:'
    lines << '     l -z                           Bundle paper, active styles, and figures into paper.zip'
    lines << '     l -z -t                        Bundle paper into zip and verify build in /tmp sandbox'
    lines << '     l -z -- figs/extra.png         Include extra supplemental files in the portable bundle'
    lines << ''
    lines << '  6. arXiv Submission Preparation:'
    lines << '     l --arxiv                      Flatten inputs, strip comments, and bundle arXiv package'
    lines << '     l --meta                       Extract title, authors, abstract, and comments metadata'
    lines << ''
    lines << '  7. Configuration & Utilities:'
    lines << '     l -m                           Print detected main LaTeX file and exit'
    lines << '     l --init-config                Generate a starter .l.jsonc configuration file'
    lines.join("\n")
  end

  def self.pdf_page_count(pdf_path)
    return 1 unless command_available?('pdfinfo') && File.file?(pdf_path)

    out, status = Open3.capture2e('pdfinfo', pdf_path)
    return 1 unless status.success?

    out =~ /Pages:\s+(\d+)/ ? Regexp.last_match(1).to_i : 1
  rescue StandardError
    1
  end

  def self.check_type3_fonts(pdf_path)
    return nil unless command_available?('pdffonts') && File.file?(pdf_path) && File.size(pdf_path) > 0

    stdout, status = Open3.capture2e('pdffonts', pdf_path)
    return nil unless status.success? && stdout.include?('Type 3')

    names = extract_type3_font_names(stdout)
    return nil if names.empty?

    pages = find_type3_font_pages(pdf_path)
    { fonts: names, pages: pages }
  rescue StandardError
    nil
  end

  def self.extract_type3_font_names(stdout)
    names = []
    stdout.each_line do |line|
      next if line.start_with?('name ', '---')
      next unless line =~ /\s+Type 3\s+/

      parts = line.split
      names << (parts[0] || '[none]')
    end
    names.uniq
  end

  def self.find_type3_font_pages(pdf_path)
    total_pages = pdf_page_count(pdf_path)
    return [] if total_pages > 100

    pages = []
    (1..total_pages).each do |p|
      out, status = Open3.capture2e('pdffonts', '-f', p.to_s, '-l', p.to_s, pdf_path)
      pages << p if status.success? && out.include?('Type 3')
    end
    pages
  rescue StandardError
    []
  end
end
