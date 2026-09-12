# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/diagnostics.rb
#
# LaTeX compilation log diagnostic analysis, AUCTeX error extraction,
# 4-tier categorization (Errors, Alerts, Warnings, Whatevers), and scoring.
# ==============================================================================

require_relative 'error_catalog'

module LaTeXDiagnostics
  DIAGNOSTIC_EXPLANATIONS = LaTeXErrorCatalog::WARNING_EXPLANATIONS

  LOG_FILE_EXTENSIONS = %w[
    tex sty cls aux bbl bib dtx def ldf cfg clo toc lof lot png pdf jpg eps fd fontspec out idx code\.tex
  ].join('|').freeze

  LOG_FILE_PATTERN = %r{\A\((?:"([^"]+)"?|((?:\.{1,2}[\\/][^\s()]+|[a-zA-Z0-9_\-./]+?\.(?:#{LOG_FILE_EXTENSIONS}))\b))}.freeze

  # One canonical recogniser for a LaTeX/package/class warning header. Five
  # near-but-not-equal variants of this used to be spelled out inline, and the
  # two that mattered most used a package-name class of [-A-Za-z0-9], which
  # excludes '.'. That made `Package pdftex.def Warning:` neither a warning
  # start nor a block boundary, so it was appended to the preceding warning's
  # text -- and when that predecessor was a Whatever, a real warning vanished
  # into a tier suppressed by default. luatex.def, xetex.def, dvips.def and
  # epstopdf-base all shared the fate.
  WARNING_LINE_PATTERN = /^(?:LaTeX|Class|Package|\*)(?:\s+[-\w.@*]+)*\s+[Ww]arning:/.freeze

  # Every pattern here must be anchored. TeX echoes the offending paragraph
  # after each Overfull \hbox, so the document's own prose reaches this log
  # verbatim: an unanchored `include?('Error:')` made a paper that discusses
  # error messages fail its own successful build, and the abort happens before
  # the PDF is copied out of junk/, so the user got no output and no
  # explanation. 'WARN - ' was dropped entirely -- that is biber's output
  # format, which never appears in a LaTeX terminal log.
  def count_errors_in_log(st, loga)
    raw = LaTeXUtils.safe_read(loga)
    content = LaTeXUtils.filter_subcommand_noise(raw)

    errcnt = content.each_line.count { |l| latex_error_line?(l) }
    errcnt + st
  end

  def latex_error_line?(line)
    line.match?(/^!\s+\S/) ||
      line.match?(/^Runaway argument\?/) ||
      line.match?(/^Error:\s/i) ||
      line.match?(/^.+?:\d+:\s+(?!warning\b)(?!\(see\b)\S/i)
  end

  def extract_error_line(err_text)
    clean = err_text.gsub(/\([a-zA-Z0-9_\-]+\)\s*/, '')
    if clean =~ /:(\d+):/ || clean =~ /\bl\.(\d+)\b/ || clean =~ /(?:at|on|in)?\s*(?:input\s+)?lines?\s*(\d+)/i
      Regexp.last_match(1).to_i
    else
      0
    end
  end

  def extract_box_severity(box_line)
    if box_line =~ /\(([\d\.]+)pt too (?:wide|high)\)/i || box_line =~ /\(badness (\d+)\)/i
      Regexp.last_match(1).to_f
    else
      0.0
    end
  end

  def colorize_line_num(str, base_color = nil)
    return str if @options[:emacs]

    base_color == :cyan ? Rainbow(str).blue.bright.to_s : Rainbow(str).cyan.bright.to_s
  end

  def highlight_line_numbers(text, base_color, bright: false)
    return text if @options[:emacs]

    pattern = /((?:input\s+)?lines?\s+)(\d+(?:--?\d+)?)|(\bl\.)(\d+)\b|(:)(\d+)(:)/i
    parts = []
    last_pos = 0

    apply_base = lambda do |str|
      r = Rainbow(str).send(base_color)
      bright ? r.bright.to_s : r.to_s
    end

    text.scan(pattern) do
      m = Regexp.last_match
      parts << apply_base.call(text[last_pos...m.begin(0)]) if m.begin(0) > last_pos

      if m[1]
        parts << apply_base.call(m[1]) << colorize_line_num(m[2], base_color)
      elsif m[3]
        parts << apply_base.call(m[3]) << colorize_line_num(m[4], base_color)
      elsif m[5]
        parts << apply_base.call(m[5]) << colorize_line_num(m[6], base_color) << apply_base.call(m[7])
      end
      last_pos = m.end(0)
    end

    parts << apply_base.call(text[last_pos..]) if last_pos < text.length
    parts.join
  end

  def format_diagnostic_line(line_str, message, base_color, width: 0, bright_sep: true)
    return message if @options[:emacs]

    str = line_str.to_s
    sep = Rainbow(': ').send(base_color)
    sep_str = bright_sep ? sep.bright.to_s : sep.to_s

    left_side = if str.empty?
                  "#{' ' * width}#{sep_str}"
                else
                  padding = ' ' * [width - str.length, 0].max
                  "#{padding}#{colorize_line_num(str, base_color)}#{sep_str}"
                end

    left_side + highlight_line_numbers(message, base_color)
  end

  def format_error_block(err_block, line_no, width: 0, catalog: nil)
    return err_block.join("\n") if @options[:emacs]

    str = line_no.to_s
    indent = ' ' * (width.positive? ? width + 2 : 2)

    lines = err_block.map.with_index do |l, idx|
      colored = highlight_line_numbers(l, :red, bright: true)
      if idx == 0
        format_first_error_line(l, colored, line_no, str, width)
      else
        "#{indent}#{colored}"
      end
    end

    append_error_hint(lines, catalog, indent)
    lines.join("\n")
  end

  def append_error_hint(lines, catalog, indent)
    return unless catalog && catalog[:hint]

    hint_text = "Hint: #{catalog[:hint]}"
    hint_colored = @options[:color] == false ? hint_text : Rainbow(hint_text).cyan
    arrow = @options[:color] == false ? '▸' : Rainbow('▸').cyan.bright
    lines << "#{indent}#{arrow} #{hint_colored}"
  end

  def format_first_error_line(l, colored, line_no, str, width)
    if line_no.positive? && !l.match?(/:#{line_no}:|^\s*#{line_no}:/)
      padding = ' ' * [width - str.length, 0].max
      "#{padding}#{colorize_line_num(str, :red)}#{Rainbow(': ').red.bright}#{colored}"
    elsif width.positive? && !l.match?(/:#{line_no}:|^\s*#{line_no}:/)
      "#{' ' * width}#{Rainbow(': ').red.bright}#{colored}"
    else
      colored
    end
  end

  def render_diagnostic_item(item, width: 0)
    return format_error_block(item[:err_block], item[:line] || 0, width: width, catalog: item[:catalog]) if item[:err_block]

    base_color = item[:base_color] || :yellow
    out = format_diagnostic_line(item[:line_str], item[:text], base_color, width: width)
    if @options[:verbose] && item[:extra_lines] && !item[:extra_lines].empty?
      indent = ' ' * (width.positive? ? width + 2 : 2)
      out += "\n" + item[:extra_lines].map do |el|
        @options[:emacs] ? el : "#{indent}#{highlight_line_numbers(el, base_color)}"
      end.join("\n")
    end
    out
  end

  def track_log_file(line, file_stack)
    return if line =~ WARNING_LINE_PATTERN ||
              line =~ /^(?:Overfull|Underfull)/ || line =~ /^!\s+/

    pos = 0
    len = line.length
    while pos < len
      ch = line[pos]
      if ch == '('
        sub = line[pos..]
        if (m = sub.match(LOG_FILE_PATTERN))
          file_stack.push(m[1] || m[2])
          pos += m[0].length
        else
          file_stack.push(nil)
          pos += 1
        end
      elsif ch == ')'
        file_stack.pop unless file_stack.empty?
        pos += 1
      else
        pos += 1
      end
    end
  end

  def current_log_file(file_stack)
    file_stack.reverse_each.find { |f| !f.nil? } || @filename
  end

  def diagnostic_boundary_line?(line)
    return true if line.strip.empty? ||
                   line =~ WARNING_LINE_PATTERN ||
                   line =~ /^(?:Overfull|Underfull)/ || line =~ /^\[\d+\]/ ||
                   line =~ /^!\s+/ || line =~ /^.+:\d+:/ ||
                   line =~ /^Runaway argument\?/ || line =~ /^\s*\)/ ||
                   line =~ /^\s*\((?:\.[\\\/]|[a-zA-Z0-9_\-\.\/]+?\.(?:tex|sty|cls|aux|bbl|bib))/

    false
  end

  def parse_package_warning(lines, i, file_stack)
    l = lines[i]
    return [nil, i + 1] if l.include?('multiply defined')

    warn_block = [l.strip]
    start_idx = i
    i += 1
    while i < lines.size && !diagnostic_boundary_line?(lines[i])
      warn_block << lines[i].strip
      i += 1
    end

    warn_text = condense_package_warning(warn_block.join(' '))
    file_name, line_no, line_str = extract_warning_location(warn_text, file_stack)

    formatted = format_diagnostic_line(line_str, warn_text, :yellow)
    item = { type: :warn, file: file_name, line: line_no, line_str: line_str, text: warn_text, base_color: :yellow, formatted: formatted, index: start_idx }
    [item, i]
  end

  def condense_package_warning(text)
    if text =~ /Package biblatex Warning: The following entr(?:y|ies) could not be found/i
      sub = text[/(?:in the database:)\s*(.*?)\s*(?:Please verify the spelling|$)/i, 1]
      if sub
        keys = sub.gsub(/\(biblatex\)/i, '').strip.gsub(/\s+/, ' ')
        return "Package biblatex Warning: Entry '#{keys}' not found in database."
      end
    end
    text
  end

  def extract_warning_location(warn_text, file_stack)
    clean = warn_text.gsub(/\([a-zA-Z0-9_\-]+\)\s*/, '').gsub(/line (\d+)\s+(\d+)\b/, 'line \1\2')
    file_name = current_log_file(file_stack)
    line_no = 0
    line_str = ''

    if clean =~ /^([^\s:]+):(\d+):/
      file_name = Regexp.last_match(1)
      line_no = Regexp.last_match(2).to_i
      line_str = Regexp.last_match(2)
    elsif clean =~ /(?:at|on|in)?\s*(?:input\s+)?lines?\s*(\d+)/i || clean =~ /:(\d+):/
      line_no = Regexp.last_match(1).to_i
      line_str = Regexp.last_match(1)
    end
    [file_name, line_no, line_str]
  end

  def parse_box_warning(lines, i, file_stack, verbose)
    l = lines[i]
    start_idx = i
    box_type = (l =~ /^(Overfull|Underfull) \\(hbox|vbox)/) ? "#{Regexp.last_match(1)} \\#{Regexp.last_match(2)}" : 'Overfull \\hbox'
    box_line = l.strip
    color_m = box_line.start_with?('Overfull') ? :magenta : :cyan
    i += 1
    extra_lines = []
    while i < lines.size && !diagnostic_boundary_line?(lines[i]) && lines[i] !~ /^l\.\d+/
      extra_lines << lines[i].strip
      i += 1
    end

    line_no, line_str = (box_line =~ /lines?\s+(\d+(?:--\d+)?)/i) ? [Regexp.last_match(1).split('--').first.to_i, Regexp.last_match(1)] : [0, '']
    file_name = current_log_file(file_stack)
    formatted = format_diagnostic_line(line_str, box_line, color_m)
    if verbose && !extra_lines.empty?
      formatted += "\n" + extra_lines.map { |line| @options[:emacs] ? line : highlight_line_numbers(line, color_m) }.join("\n")
    end

    severity = extract_box_severity(box_line)
    item = {
      type: box_type, file: file_name, line: line_no, line_str: line_str,
      text: box_line, base_color: color_m, extra_lines: extra_lines,
      severity: severity, formatted: formatted, index: start_idx
    }
    [item, i]
  end

  def deduplicate_box_warnings(raw_warnings)
    filtered_warnings = []
    box_groups = {}
    raw_warnings.each do |w|
      if w[:type].is_a?(String) && w[:type] =~ /^(Overfull|Underfull)/ && !w[:line_str].empty?
        key = [w[:file], w[:type], w[:line_str]]
        box_groups[key] ||= []
        box_groups[key] << w
      else
        filtered_warnings << w
      end
    end

    box_groups.each { |_key, items| filtered_warnings << items.max_by { |item| item[:severity] } }
    filtered_warnings
  end

  def extract_warnings(content, verbose = false)
    raw_warnings = []
    seen_warnings = {}
    lines = content.lines
    file_stack = [@filename]
    i = 0

    while i < lines.size
      l = lines[i]
      track_log_file(l, file_stack)

      if l =~ WARNING_LINE_PATTERN
        item, i = parse_package_warning(lines, i, file_stack)
        if item && !seen_warnings[item[:text]]
          seen_warnings[item[:text]] = true
          raw_warnings << item
        end
      elsif l =~ /^(?:Overfull|Underfull) \\(?:hbox|vbox)/
        item, i = parse_box_warning(lines, i, file_stack, verbose)
        raw_warnings << item if item
      else
        i += 1
      end
    end

    deduplicate_box_warnings(raw_warnings)
  end

  def error_line_match(line)
    if line =~ /^([^\s:]+):(\d+):\s+(?!warning\b)(?!\(see\b)\S+/i
      [true, Regexp.last_match(1)]
    elsif line =~ /^!\s+\S+/ || line =~ /^Runaway argument\?/ || line =~ /^Error:\s+/i
      [true, nil]
    else
      [false, nil]
    end
  end

  def collect_error_block(lines, start_idx)
    err_block = [lines[start_idx]]
    i = start_idx + 1
    while i < lines.size && err_block.size < 6
      curr = lines[i]
      break if curr =~ /^!\s*(?:==>\s*)?(?:Emergency stop|Fatal error occurred)/i ||
               curr =~ /^.+:\d+:\s+(?!warning\b)/i ||
               curr =~ /^!\s+\S+/ || curr =~ /^Runaway argument\?/ ||
               curr =~ WARNING_LINE_PATTERN ||
               curr =~ /^(?:Overfull|Underfull) \\(?:hbox|vbox)/ ||
               curr =~ /^\s*\)/ || curr =~ /^\s*\((?:\.[\\\/]|[a-zA-Z0-9_\-\.\/]+?\.(?:tex|sty|cls|aux|bbl|bib))/

      err_block << curr
      i += 1
      break if curr =~ /^l\.\d+/
    end
    [err_block, i]
  end

  def extract_errors(content)
    errors = []
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    lines = clean_content.lines
    file_stack = [@filename]
    i = 0

    while i < lines.size
      line = lines[i]
      track_log_file(line, file_stack)

      if line =~ /^!\s*(?:==>\s*)?(?:Emergency stop|Fatal error occurred)/i
        i += 1
        next
      end

      is_err, err_file = error_line_match(line)
      if is_err
        err_item, i = build_error_entry(lines, i, err_file, file_stack)
        errors << err_item
      else
        i += 1
      end
    end
    errors
  end

  def build_error_entry(lines, idx, err_file, file_stack)
    err_block, next_idx = collect_error_block(lines, idx)
    err_block = err_block.map(&:rstrip).reject(&:empty?)
    err_text = err_block.join("\n")
    line_no = extract_error_line(err_text)
    file_name = err_file || current_log_file(file_stack)
    classification = LaTeXErrorCatalog.classify(err_text, err_block, file: file_name, line: line_no)
    formatted = format_error_block(err_block, line_no, catalog: classification)
    cat_id = classification ? classification[:id] : :generic
    item = {
      file: file_name, line: line_no, line_str: (line_no > 0 ? line_no.to_s : ''),
      text: err_text, err_block: err_block, base_color: :red, formatted: formatted, index: next_idx,
      catalog: classification, catalog_id: cat_id
    }
    [item, next_idx]
  end

  def overfull_hbox?(item)
    t = item[:type].to_s
    txt = item[:text].to_s
    (t.include?('Overfull') && t.include?('hbox')) || txt =~ /\AOverfull\s+\\hbox/i
  end

  def sort_diagnostic_items(warnings, errors)
    overfull_warnings, other_warnings = warnings.partition { |w| overfull_hbox?(w) }

    sorted_other = other_warnings.sort_by { |w| [format_display_path(w[:file]), w[:line] || 0, w[:index] || 0] }
    sorted_overfull = overfull_warnings.sort_by do |w|
      sev = w[:severity] || extract_box_severity(w[:text].to_s)
      [format_display_path(w[:file]), sev.to_f, w[:line] || 0, w[:index] || 0]
    end
    sorted_errors = errors.sort_by { |e| [format_display_path(e[:file]), e[:line] || 0, e[:index] || 0] }

    all_items = sorted_other + sorted_overfull + sorted_errors
    all_sorted = all_items.sort_by do |item|
      idx = item[:index] || 0
      [idx.negative? ? 0 : 1, format_display_path(item[:file]), item[:line] || 0, idx]
    end

    [all_sorted, sorted_other.size + sorted_overfull.size, sorted_errors.size]
  end

  def print_diagnostics_body(warnings, errors, fallback_lines: [], tier_label: nil, io: $stdout)
    all_sorted, num_warnings, num_errors = sort_diagnostic_items(warnings, errors)
    max_width = all_sorted.map { |item| item[:line_str].to_s.length }.max || 0

    header_counts = count_items_by_header(all_sorted, tier_label)
    current_header = nil
    all_sorted.each do |item|
      current_header = render_diagnostic_entry(item, max_width, current_header, tier_label, header_counts, io: io)
    end

    render_diagnostic_fallback(all_sorted, fallback_lines, current_header, tier_label, io: io)
    [num_warnings, num_errors]
  end

  def count_items_by_header(all_sorted, tier_label)
    counts = Hash.new(0)
    all_sorted.each do |item|
      f = format_display_path(item[:file])
      lbl = tier_label_for(item, tier_label)
      counts[[f, lbl]] += 1
    end
    counts
  end

  def render_diagnostic_entry(item, max_width, current_header, tier_label = nil, header_counts = nil, io: $stdout)
    item_file = format_display_path(item[:file])
    lbl = tier_label_for(item, tier_label)
    header_key = @options[:emacs] ? item_file : [item_file, lbl]

    if header_key != current_header
      if @options[:emacs]
        io.puts ')' if current_header
        io.puts "(#{item_file}"
      else
        count = header_counts ? header_counts[header_key] : 1
        io.puts ''
        io.puts format_file_separator(item_file, lbl, count)
      end
      current_header = header_key
    end

    rendered = render_diagnostic_item(item, width: max_width).rstrip
    io.puts rendered unless rendered.empty?

    explain_diagnostic_item(item, io: io) if @options[:explain]
    current_header
  end

  def tier_label_for(item, tier_label)
    return tier_label if tier_label
    return 'errors' if item[:err_block]
    return 'alerts' if item[:base_color] == :red
    return 'whatevers' if item[:base_color] == :cyan

    'warnings'
  end

  def format_file_separator(item_file, tier_label, count)
    count_str = format_tier_count_label(count, tier_label)
    uncolored_prefix = "── #{item_file} (#{count_str}) "
    cols = terminal_columns
    dash_count = [cols - uncolored_prefix.length, 3].max
    dashes = '─' * dash_count

    color = tier_color(tier_label)
    lead = Rainbow('── ').send(color).bright
    file_part = Rainbow(item_file).bold
    count_part = " (#{count_str}) "
    tail = Rainbow(dashes).send(color).bright
    "#{lead}#{file_part}#{count_part}#{tail}"
  end

  def format_tier_count_label(count, tier_label)
    name = case tier_label.to_s
           when 'alerts' then count == 1 ? 'alert' : 'alerts'
           when 'warnings' then count == 1 ? 'warning' : 'warnings'
           when 'errors' then count == 1 ? 'error' : 'errors'
           when 'whatevers' then count == 1 ? 'whatever' : 'whatevers'
           else tier_label.to_s
           end
    "#{count} #{name}"
  end

  def tier_color(tier_label)
    case tier_label.to_s
    when 'alerts', 'errors' then :red
    when 'warnings' then :yellow
    when 'whatevers' then :cyan
    else :yellow
    end
  end

  def explain_diagnostic_item(item, io: $stdout)
    cat = diagnostic_category(item)
    return if !cat || cat == :generic || @explained_categories[cat]

    @explained_categories[cat] = true
    box = format_boxed_explanation(cat)
    io.puts box if box
  end

  def render_diagnostic_fallback(all_sorted, fallback_lines, current_header, tier_label = nil, io: $stdout)
    if all_sorted.empty? && !fallback_lines.empty?
      render_fallback_lines(fallback_lines, tier_label, io: io)
    elsif current_header && @options[:emacs]
      io.puts ')'
    end
  end

  def render_fallback_lines(fallback_lines, tier_label = nil, io: $stdout)
    disp = format_display_path(@filename)
    if @options[:emacs]
      io.puts "(#{disp}"
    else
      lbl = tier_label || 'errors'
      io.puts ''
      io.puts format_file_separator(disp, lbl, 1)
    end
    fallback_lines.each do |l|
      next if l.strip.empty?

      io.puts @options[:emacs] ? l.strip : highlight_line_numbers(l.strip, :red, bright: true)
    end
    io.puts ')' if @options[:emacs]
  end

  def format_display_path(file)
    path = (file || @filename).to_s
    path = @filename.to_s if path.empty? || path == '.'
    cwd_prefix = "#{Dir.pwd}/"
    path = path.delete_prefix(cwd_prefix) if path.start_with?(cwd_prefix)
    path = path.delete_prefix('./') if path.start_with?('./')
    path
  end

  def terminal_columns
    return 80 if @options[:emacs]

    w = begin
      IO.console&.winsize&.last rescue nil
    end
    (w && w > 40) ? [w, 80].min : 80
  end

  def wrap_box_field(prefix, text, inner_width)
    full_prefix = "#{prefix} "
    avail = inner_width - full_prefix.length
    words = text.split(/\s+/)
    lines = []
    curr = ''
    words.each do |wd|
      if curr.empty?
        curr = wd
      elsif curr.length + 1 + wd.length <= avail
        curr += " #{wd}"
      else
        lines << curr
        curr = wd
      end
    end
    lines << curr unless curr.empty?

    lines.each_with_index.map do |ln, idx|
      pfx = idx == 0 ? full_prefix : (' ' * full_prefix.length)
      "│ #{("#{pfx}#{ln}").ljust(inner_width)} │"
    end
  end

  def format_boxed_explanation(category)
    expl = DIAGNOSTIC_EXPLANATIONS[category] || LaTeXErrorCatalog.find_by_id(category)
    return nil unless expl

    cols = terminal_columns
    inner_width = cols - 4

    top_title = "─ Diagnostic Explanation: #{expl[:title]} "
    dash_count = [cols - 2 - top_title.length, 1].max
    box_lines = [
      "┌#{top_title}#{'─' * dash_count}┐",
      *wrap_box_field('Why:', expl[:why], inner_width),
      *wrap_box_field('Fix:', expl[:fix], inner_width),
      "└#{'─' * (cols - 2)}┘"
    ]

    render_colored_box(box_lines)
  end

  def render_colored_box(box_lines)
    return "\n#{box_lines.join("\n")}\n" if @options[:color] == false || @options[:emacs]

    colored = box_lines.map do |bl|
      if bl.start_with?('┌') || bl.start_with?('└')
        Rainbow(bl).cyan.bright
      else
        left_bar = Rainbow('│').cyan.bright
        right_bar = Rainbow('│').cyan.bright
        "#{left_bar} #{bl[2...-2]} #{right_bar}"
      end
    end
    "\n#{colored.join("\n")}\n"
  end

  def classify_overfull_category(item)
    sev = (item[:severity] || extract_box_severity(item[:text].to_s)).to_f
    if sev >= alert_overfull_pt
      :overfull_hbox_alert
    elsif sev > 0 && sev <= whatever_overfull_pt
      :overfull_hbox_whatever
    else
      :overfull_hbox_warning
    end
  end

  def reference_or_cite_category(txt)
    if (txt.include?('Reference `') || txt.include?('reference `')) && txt.include?('undefined')
      :undefined_reference
    elsif (txt.include?('Citation `') || txt.include?('citation `')) && txt.include?('undefined')
      :undefined_citation
    end
  end

  def diagnostic_category(item)
    return item[:catalog_id] if item[:catalog_id] && item[:catalog_id] != :generic
    return item[:alert_type] if item[:alert_type]

    txt = item[:text].to_s
    return :multiply_defined_label if txt.include?('multiply defined')
    return classify_overfull_category(item) if overfull_hbox?(item)
    ref_cat = reference_or_cite_category(txt)
    return ref_cat if ref_cat

    return :hyperref_token if txt.include?('Token not allowed in a PDF string')
    return :float_specifier if txt =~ /float specifier changed to/i
    return :font_shape if txt.include?('Some font shapes were not available') || txt =~ /Font shape .* undefined/i
    return :summary_warning if txt.include?('There were multiply-defined labels') || txt.include?('There were undefined references')

    :generic
  end

  def alert_overfull_pt
    (@options[:alert_overfull_pt] || 24.0).to_f
  end

  def whatever_overfull_pt
    (@options[:whatever_overfull_pt] || 2.5).to_f
  end

  def extract_label_alerts(content)
    alerts = []
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    lines = clean_content.lines
    file_stack = [@filename]
    lines.each_with_index do |line, i|
      track_log_file(line, file_stack)
      next unless line.include?('multiply defined') && line.include?('LaTeX Warning')

      text = line.strip
      file_name = current_log_file(file_stack)
      formatted = format_diagnostic_line('', text, :red)
      alerts << {
        file: file_name, line: 0, line_str: '', text: text,
        base_color: :red, formatted: formatted, index: i
      }
    end
    alerts
  end

  def extract_alerts(content, warn_items = nil)
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    warn_items ||= extract_warnings(clean_content, @options[:verbose])
    threshold = alert_overfull_pt
    alert_boxes = warn_items.select do |w|
      overfull_hbox?(w) && (w[:severity] || 0.0) >= threshold
    end
    alert_boxes.each do |ab|
      ab[:base_color] = :red
      ab[:formatted] = format_diagnostic_line(ab[:line_str], ab[:text], :red)
    end
    extract_label_alerts(clean_content) + alert_boxes + collect_source_label_alerts + collect_type3_font_alerts
  end

  def collect_source_label_alerts
    candidates = collect_source_candidates
    candidates.flat_map do |f|
      raw_alerts = LaTeXBraceChecker.check_inverted_labels(f)
      raw_alerts.map do |a|
        a[:formatted] = format_diagnostic_line(a[:line_str], a[:text], :red)
        a
      end
    end
  end

  def collect_source_candidates
    candidates = []
    candidates << @filename if @filename && File.file?(@filename)
    if @bfilename && File.exist?("junk/#{@bfilename}.fls") && respond_to?(:extract_fls_dependencies, true)
      candidates.concat(extract_fls_dependencies("junk/#{@bfilename}.fls").select { |f| f.end_with?('.tex') })
    end
    candidates.concat(Dir['*.tex', '*/*.tex'].select { |f| File.file?(f) })
    patterns = (@options && @options[:exclude_source_tex]) || LaTeXUtils::DEFAULT_EXCLUDE_SOURCE_PATTERNS
    candidates.uniq.reject do |f|
      patterns.any? { |pat| File.fnmatch?(pat, f, File::FNM_CASEFOLD | File::FNM_EXTGLOB) }
    end
  end

  def collect_type3_font_alerts
    target_pdf = resolve_target_pdf
    return [] unless target_pdf

    type3 = LaTeXUtils.check_type3_fonts(target_pdf)
    return [] unless type3

    fonts_str = type3[:fonts].join(', ')
    pages_str = type3[:pages].empty? ? '' : " on page #{type3[:pages].join(', ')}"
    msg = "Type 3 (raster bitmap) font detected: #{fonts_str}#{pages_str}"
    formatted = format_diagnostic_line('', msg, :red)
    [{
      file: target_pdf,
      line: 0,
      line_str: '',
      text: msg,
      formatted: formatted,
      alert_type: :type3_font,
      base_color: :red,
      index: 60000
    }]
  end

  def resolve_target_pdf
    return "#{@bfilename}.pdf" if @bfilename && File.file?("#{@bfilename}.pdf")
    return "junk/#{@bfilename}.pdf" if @bfilename && File.file?("junk/#{@bfilename}.pdf")

    nil
  end

  def whatever_diagnostic?(item)
    if overfull_hbox?(item)
      sev = (item[:severity] || extract_box_severity(item[:text].to_s)).to_f
      return true if sev > 0 && sev <= whatever_overfull_pt
    end

    txt = item[:text].to_s
    return true if txt.include?('Token not allowed in a PDF string') ||
                   txt =~ /float specifier changed to/i ||
                   txt.include?('There were multiply-defined labels') ||
                   txt.include?('There were undefined references') ||
                   txt.include?('Some font shapes were not available') ||
                   txt =~ /Font shape .* undefined using .* instead/i

    false
  end

  def partition_diagnostics(clean_content, warn_items)
    alert_items = extract_alerts(clean_content, warn_items)
    whatevers = []
    regular_warnings = []

    threshold = alert_overfull_pt
    warn_items.each do |w|
      next if overfull_hbox?(w) && ((w[:severity] || 0.0) >= threshold)

      if whatever_diagnostic?(w)
        whatevers << w
      else
        regular_warnings << w
      end
    end

    [alert_items, regular_warnings, whatevers]
  end

  def format_tier_count(label, count, color, suppressed)
    if count == 0
      Rainbow("#{label}: 0").green.bright
    else
      base = Rainbow("#{label}: #{count}").color(color).bright
      suppressed ? "#{base} #{Rainbow('(suppressed)').faint}" : base
    end
  end

  def print_summary_line(errors, alerts, warnings, whatevers,
                         suppressed_warnings: false, suppressed_whatevers: false, suppressed_alerts: false, io: nil)
    err_str = format_tier_count('Errors', errors, :red, false)
    alert_str = format_tier_count('Alerts', alerts, :red, suppressed_alerts)
    warn_str = format_tier_count('Warnings', warnings, :yellow, suppressed_warnings)
    what_str = format_tier_count('Whatevers', whatevers, :cyan, suppressed_whatevers)

    target_io = io || ((@options && @options[:score]) ? (@orig_stdout || $stdout) : $stdout)
    target_io.puts ''
    target_io.puts "#{err_str}, #{alert_str}, #{warn_str}, #{what_str}"
  end

  def throttle_errors(errors)
    return [errors, nil] if (@options && @options[:all]) || errors.size <= 1

    groups = errors.group_by { |e| format_display_path(e[:file]) }
    first_file, file_errors = groups.first
    return [errors, nil] if groups.size <= 1 && file_errors.size <= 10

    displayed = file_errors.first(10)
    other_files = groups.keys[1..] || []
    cascade_info = {
      first_file: first_file,
      remaining_in_first: file_errors.size - displayed.size,
      other_files: other_files,
      other_errors_count: other_files.sum { |f| groups[f].size }
    }
    [displayed, cascade_info]
  end

  def format_other_files_list(other_list)
    return other_list.join(', ') if other_list.size <= 4

    "#{other_list.first(3).join(', ')}, and #{other_list.size - 3} more files"
  end

  def print_cascade_notice(cascade_info, io: $stderr)
    io.puts Rainbow("\n═══════════════════════════════════════════════════════════════════════════════").yellow
    if cascade_info[:remaining_in_first] > 0
      io.puts Rainbow("▸ #{cascade_info[:remaining_in_first]} more errors in #{cascade_info[:first_file]} were truncated (likely cascades).").yellow
    end
    if cascade_info[:other_errors_count] > 0
      files_str = format_other_files_list(cascade_info[:other_files])
      io.puts Rainbow("▸ #{cascade_info[:other_errors_count]} more errors were detected across #{cascade_info[:other_files].size} other files (#{files_str}).").yellow
      io.puts Rainbow('  These may be cascades caused by the earlier error. Please resolve the issues above first.').yellow
    end
    io.puts Rainbow("  (Run with 'l -a' / '--all' to display all errors across all files).").yellow
    io.puts Rainbow('═══════════════════════════════════════════════════════════════════════════════').yellow
  end

  def report_errors(loga, io: $stderr)
    raw = LaTeXUtils.safe_read(loga)
    content = LaTeXUtils.filter_subcommand_noise(raw)

    io.puts Rainbow("\n===============================================================").red.bright
    io.puts Rainbow(' ERROR: LaTeX Compilation Failed!').red.bright
    io.puts Rainbow('===============================================================').red.bright

    brace_errors = check_source_braces
    errors = brace_errors + extract_errors(content)
    fallback = errors.empty? ? content.lines.last(15) : []
    displayed_errors, cascade_info = throttle_errors(errors)
    _num_warnings, _num_errors = print_diagnostics_body([], displayed_errors, fallback_lines: fallback, tier_label: 'errors', io: io)
    print_cascade_notice(cascade_info, io: io) if cascade_info

    io.puts Rainbow('===============================================================').red.bright
    io.puts "See #{loga} for full error details."
    report_error_summary(content, raw, brace_errors, errors.size, io: io)
    exit 1
  end

  def report_error_summary(content, raw, brace_errors, num_errors, io: $stdout)
    raw_warns = extract_warnings(content, false)
    alert_items, regular_warns, whatever_items = partition_diagnostics(content, raw_warns)

    brace_alerts_count = brace_errors.count { |e| e[:has_alert] }
    errors_count = [num_errors, count_latex_errors(raw, 1)].max
    alerts_count = alert_items.size + brace_alerts_count
    warnings_count = regular_warns.size
    whatevers_count = whatever_items.size
    print_summary_line(
      errors_count, alerts_count, warnings_count, whatevers_count,
      suppressed_alerts: alerts_count > 0,
      suppressed_warnings: warnings_count > 0,
      suppressed_whatevers: whatevers_count > 0,
      io: io
    )
  end

  def collect_diagnostic_counts(new_content)
    cnt_overfull = new_content.scan(/overfull/i).size
    cnt_underfull = new_content.scan(/underfull/i).size
    cnt_bib = count_bib_messages
    cnt_undef_cite, cnt_undef_ref, cnt_mult_def = count_reference_messages(new_content)

    cbib = cnt_bib[:warns] + cnt_bib[:errors]
    {
      overfull: cnt_overfull, underfull: cnt_underfull,
      cbib: cbib, biberr: cnt_bib[:errors],
      undef_cite: cnt_undef_cite, undef_ref: cnt_undef_ref, mult_def: cnt_mult_def,
      bib_warns: cnt_bib[:warns]
    }
  end

  # Match the tools' actual error grammar. A bare scan for /error/i counted the
  # word anywhere it appeared -- including inside a .bib path the tool prints
  # back, such as "Found BibTeX data source 'papers/error-bounds/refs.bib'".
  # One such line set counts[:biberr], and render_diagnostics_tiers then renders
  # only the errors tier, so every real alert and warning was hidden. The same
  # scan also missed bibtex's actual failure text, which never says "error".
  BIB_ERROR_PATTERN = Regexp.union(
    /^ERROR\s+-\s/i,
    /couldn't open \w+ file/i,
    /^\s*I couldn't open/i,
    /\(There (?:was|were) \d+ error message/i
  ).freeze

  BIB_WARNING_PATTERN = /^Warning--|^Repeated entry---|^WARN\s+-\s/i.freeze

  def count_bib_messages
    return { warns: 0, errors: 0 } unless @biberr && File.exist?(@biberr)

    bib_content = LaTeXUtils.safe_read(@biberr)
    warns = bib_content.each_line.count { |l| l =~ BIB_WARNING_PATTERN }
    errors = bib_content.each_line.count { |l| l =~ BIB_ERROR_PATTERN }
    { warns: warns, errors: errors }
  end

  UNDEF_CITE_PATTERN = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Citation\s+[`'"]?.*?['"]?\s+.*undefined/i.freeze
  UNDEF_REF_PATTERN  = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Reference\s+[`'"]?.*?['"]?\s+.*undefined/i.freeze
  MULT_DEF_PATTERN   = /^(?:LaTeX|Package\s+[-\w.@*]+)\s+Warning:\s+Label\s+[`'"]?.*?['"]?\s+multiply defined/i.freeze

  def count_reference_messages(new_content)
    content = LaTeXUtils.filter_subcommand_noise(new_content)
    undef_cite = content.scan(UNDEF_CITE_PATTERN).size
    undef_ref  = content.scan(UNDEF_REF_PATTERN).size
    mult_def   = content.scan(MULT_DEF_PATTERN).size
    [undef_cite, undef_ref, mult_def]
  end

  def print_diagnostic_banner(counts)
    puts ''
    overfull_s = counts[:overfull] > 0 ? Rainbow("Overfull: #{counts[:overfull]}").magenta : "Overfull: #{counts[:overfull]}"
    underfull_s = counts[:underfull] > 0 ? Rainbow("Underfull: #{counts[:underfull]}").cyan : "Underfull: #{counts[:underfull]}"
    bib_s = counts[:cbib] > 0 ? Rainbow("Bibtex warns/errors: #{counts[:cbib]}").yellow.bright : "Bibtex warns/errors: #{counts[:cbib]}"
    cite_s = counts[:undef_cite] > 0 ? Rainbow("Undef cite: #{counts[:undef_cite]}").red.bright : "Undef cite: #{counts[:undef_cite]}"
    refs_s = counts[:undef_ref] > 0 ? Rainbow("Undef refs: #{counts[:undef_ref]}").red.bright : "Undef refs: #{counts[:undef_ref]}"
    mult_s = counts[:mult_def] > 0 ? Rainbow("Lab multi-def: #{counts[:mult_def]}").red.bright : "Lab multi-def: #{counts[:mult_def]}"
    puts "#{overfull_s} | #{underfull_s} | #{bib_s} | #{cite_s} | #{refs_s} | #{mult_s}"
  end

  def append_bib_diagnostics!(warn_items, err_items)
    return unless @biberr && File.exist?(@biberr)

    LaTeXUtils.safe_read(@biberr).each_line.with_index do |bl, bidx|
      if bl =~ BIB_WARNING_PATTERN
        line_str = (bl =~ /line\s+(\d+)/i) ? Regexp.last_match(1) : ''
        formatted = format_diagnostic_line(line_str, bl.strip, :yellow)
        warn_items << { file: './bibliography', line: line_str.to_i, line_str: line_str, text: bl.strip, formatted: formatted, index: 100000 + bidx }
      elsif bl =~ BIB_ERROR_PATTERN
        formatted = @options[:emacs] ? bl.strip : highlight_line_numbers(bl.strip, :red, bright: true)
        err_items << { file: './bibliography', line: 0, text: bl.strip, formatted: formatted, index: 100000 + bidx }
      end
    end
  end

  def analyze_output
    pdferr = find_last_latex_log
    if @options[:score]
      output_score(pdferr, 0)
      return
    end

    new_content = LaTeXUtils.safe_read(pdferr)
    counts = collect_diagnostic_counts(new_content)
    clean_content = LaTeXUtils.filter_subcommand_noise(new_content)
    raw_warns = extract_warnings(clean_content, @options[:verbose])
    err_items = extract_errors(clean_content)
    append_bib_diagnostics!(raw_warns, err_items) if counts[:cbib] > 0

    alert_items, reg_warns, what_items = partition_diagnostics(clean_content, raw_warns)
    errors = count_latex_errors(new_content, 0) + counts[:biberr]

    display_analyzed_diagnostics(counts, err_items, alert_items, reg_warns, what_items, errors)
  end

  def display_analyzed_diagnostics(counts, err_items, alert_items, reg_warns, what_items, errors)
    total_diag = counts[:cbib] + counts[:undef_cite] + counts[:undef_ref] + counts[:mult_def] + counts[:overfull] + counts[:underfull]
    alerts = alert_items.size
    warnings = reg_warns.size
    whatevers = what_items.size

    if total_diag > 0 || errors > 0 || alerts > 0 || warnings > 0 || whatevers > 0
      print_diagnostic_banner(counts) if total_diag > 0 || errors > 0 || alerts > 0
      errors = render_diagnostics_tiers(err_items, alert_items, reg_warns, what_items, errors)
    end

    return unless errors > 0 || alerts > 0 || warnings > 0 || whatevers > 0

    summarize_and_check_werror(errors, alerts, warnings, whatevers)
  end

  def render_diagnostics_tiers(err_items, alert_items, reg_warns, what_items, errors)
    if errors > 0 || !err_items.empty?
      displayed_errors, cascade_info = throttle_errors(err_items)
      _num_warnings, _num_errors = print_diagnostics_body([], displayed_errors, tier_label: 'errors')
      print_cascade_notice(cascade_info, io: $stdout) if cascade_info
      [err_items.size, errors].max
    else
      render_non_error_tiers(alert_items, reg_warns, what_items)
      errors
    end
  end

  def render_non_error_tiers(alert_items, reg_warns, what_items)
    suppress_alerts = @options[:suppress_alerts] == true
    suppress_warnings = @options[:suppress_warnings] == true
    suppress_whatevers = @options[:suppress_whatevers] != false

    print_diagnostics_body([], alert_items, tier_label: 'alerts') if !suppress_alerts && !alert_items.empty?
    print_diagnostics_body(reg_warns, [], tier_label: 'warnings') if !suppress_warnings && !reg_warns.empty?
    render_whatevers_tier(what_items) if !suppress_whatevers && !what_items.empty?
  end

  def render_whatevers_tier(what_items)
    formatted = what_items.map do |wh|
      wh_copy = wh.dup
      wh_copy[:base_color] = :cyan
      wh_copy[:formatted] = format_diagnostic_line(wh[:line_str], wh[:text], :cyan)
      wh_copy
    end
    print_diagnostics_body(formatted, [], tier_label: 'whatevers')
  end

  def summarize_and_check_werror(errors, alerts, warnings, whatevers)
    suppressed_alt = (errors > 0) || (@options[:suppress_alerts] == true)
    suppressed_wrn = (errors > 0) || (@options[:suppress_warnings] == true)
    suppressed_wht = (errors > 0) || (@options[:suppress_whatevers] != false)

    print_summary_line(
      errors, alerts, warnings, whatevers,
      suppressed_alerts: suppressed_alt && alerts > 0,
      suppressed_warnings: suppressed_wrn && warnings > 0,
      suppressed_whatevers: suppressed_wht && whatevers > 0
    )

    fail_on_diagnostics(errors, alerts, warnings)
  end

  # The exit status has to agree with the summary line the user just read.
  # summarize_and_check_werror printed `errors` and then ignored it, so a run
  # that reported "Errors: 2" still exited 0 -- and -W only ever looked at
  # alerts and warnings, so even that flag could not make an error fatal.
  def fail_on_diagnostics(errors, alerts, warnings)
    if errors.positive?
      puts Rainbow("\n#{errors} error(s) reported; exiting with a non-zero status.").red.bright
      exit 1
    end
    return unless @options[:werror] && (alerts.positive? || warnings.positive?)

    puts Rainbow("\n[Werror] Warnings treated as fatal errors.").red.bright
    exit 1
  end

  def find_last_latex_log
    %w[_3 _2 _1].each do |s|
      candidate = "#{@pdferr}#{s}"
      return candidate if File.exist?(candidate)
    end
    @pdferr
  end

  def count_latex_errors(content, status = 0)
    errors = 0
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    clean_content.each_line do |line|
      next if line =~ /^!\s*(?:==>\s*)?(?:Emergency stop|Fatal error occurred)/i

      if line =~ /^!\s+\S+/ ||
         line =~ /^.+:\d+:\s+(?:(?:LaTeX|Package|Class)\s+Error:|Undefined control sequence|Error:|Runaway argument\?|Missing\s|Extra\s|You can't use)/i ||
         line =~ /^.+:\d+:\s+.*error/i || line =~ /^Error:\s+/i
        errors += 1
      end
    end
    errors = 1 if errors == 0 && status.to_i > 0
    errors
  end

  def count_latex_warnings(content)
    warnings = 0
    content.each_line do |line|
      next if line.include?('multiply defined') && line.include?('LaTeX Warning')

      if line =~ WARNING_LINE_PATTERN ||
         line =~ /^.+:\d+:\s+warning:/i || line =~ /^Warning:\s+/i ||
         line =~ /^(?:Overfull|Underfull) \\(?:hbox|vbox)/
        warnings += 1
      end
    end
    warnings
  end

  def output_score(last_log_path = nil, status = 0)
    last_log_path ||= find_last_latex_log
    content = LaTeXUtils.safe_read(last_log_path)
    clean_content = LaTeXUtils.filter_subcommand_noise(content)
    raw_warns = extract_warnings(clean_content, false)
    alert_items, regular_warns, whatever_items = partition_diagnostics(clean_content, raw_warns)

    errors = count_latex_errors(content, status)
    alerts = alert_items.size
    warnings = regular_warns.size
    whatevers = whatever_items.size
    suppress_alerts = @options[:suppress_alerts] == true
    suppress_warnings = @options[:suppress_warnings] == true
    suppress_whatevers = @options[:suppress_whatevers] != false

    print_summary_line(
      errors, alerts, warnings, whatevers,
      suppressed_alerts: suppress_alerts && alerts > 0,
      suppressed_warnings: suppress_warnings && warnings > 0,
      suppressed_whatevers: suppress_whatevers && whatevers > 0
    )

    # analyze_output returns early for :score, so without this `l -s -W` could
    # never fail -- the flag whose only purpose is a non-zero exit status was
    # silently disabled by the flag whose purpose is a quiet one.
    fail_on_diagnostics(errors, alerts, warnings)
  end
end
