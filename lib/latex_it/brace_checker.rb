# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/brace_checker.rb
#
# Lexical brace, bracket, and environment validator for LaTeX documents.
# Identifies mismatched braces/brackets and unclosed environments.
# ==============================================================================

class LaTeXBraceChecker
  VERBATIM_ENVS = %w[verbatim verbatim* lstlisting minted filecontents filecontents* comment alltt].freeze
  FLOAT_ENVS = %w[figure figure* table table* algorithm listing subfigure subtable].freeze
  UNNUMBERED_MATH_ENVS = %w[equation* align* gather* multline* flalign*].freeze

  LABEL_TOKEN_PATTERN = /\\(?:begin\{(figure\*?|table\*?|algorithm|listing|subfigure|subtable|equation\*|align\*|gather\*|multline\*|flalign\*)\}|end\{(figure\*?|table\*?|algorithm|listing|subfigure|subtable|equation\*|align\*|gather\*|multline\*|flalign\*)\}|caption\b|subcaption\b|label\{([^}]+)\})/.freeze

  def self.check_file(path)
    return [] unless File.file?(path)

    content = LaTeXUtils.safe_read(path)
    new(path, content).scan
  end

  def self.check_inverted_labels(path)
    return [] unless File.file?(path)

    content = LaTeXUtils.safe_read(path)
    scan_inverted_labels(path, content)
  end

  def self.scan_inverted_labels(path, content)
    alerts = []
    float_stack = []

    content.each_line.with_index(1) do |raw_line, line_no|
      line = raw_line.sub(/(?<!\\)%.*\z/, '')
      next if line.strip.empty?

      scan_line_for_labels(line, line_no, path, float_stack, alerts)
    end
    alerts
  end

  def self.scan_line_for_labels(line, line_no, path, float_stack, alerts)
    line.scan(LABEL_TOKEN_PATTERN) do
      match = Regexp.last_match
      handle_label_token(match, line_no, path, float_stack, alerts)
    end
  end

  def self.handle_label_token(match, line_no, path, float_stack, alerts)
    full = match[0]
    if full.start_with?('\\begin')
      push_label_float(match[1], line_no, float_stack)
    elsif full.start_with?('\\end')
      pop_label_float(match[2], float_stack)
    elsif full.start_with?('\\caption') || full.start_with?('\\subcaption')
      float_stack.last[:has_caption] = true if float_stack.any?
    elsif full.start_with?('\\label') && float_stack.any?
      check_label_alert(path, line_no, match[3], float_stack.last, alerts)
    end
  end

  def self.push_label_float(env, line_no, float_stack)
    float_stack << { env: env, line: line_no, has_caption: false, unnumbered: UNNUMBERED_MATH_ENVS.include?(env) }
  end

  def self.pop_label_float(env, float_stack)
    float_stack.pop if float_stack.any? && float_stack.last[:env] == env
  end

  def self.check_label_alert(path, line_no, key, current_float, alerts)
    if current_float[:unnumbered]
      env = current_float[:env]
      msg = "\\label{#{key}} placed inside unnumbered #{env} environment"
      alerts << build_label_alert(path, line_no, msg, :unnumbered_label)
    elsif !current_float[:has_caption]
      env = current_float[:env]
      msg = "Inverted \\label{#{key}} before \\caption in #{env} environment"
      alerts << build_label_alert(path, line_no, msg, :inverted_label)
    end
  end

  def self.build_label_alert(path, line_no, msg, alert_type)
    {
      file: path,
      line: line_no,
      col: 1,
      line_str: line_no.to_s,
      text: msg,
      alert_type: alert_type,
      base_color: :red,
      index: 50000 + line_no
    }
  end

  def initialize(path, content)
    @path = path
    @lines = content.lines
    @env_stack = []
    @brace_stack = []
    @errors = []
    @in_verbatim = false
    @verbatim_end = nil
  end

  def scan
    @lines.each_with_index do |raw_line, idx|
      scan_line(raw_line, idx + 1)
    end

    check_eof_unclosed
    @errors
  end

  private

  def scan_line(raw_line, line_no)
    if @in_verbatim
      if raw_line =~ /\\end\{#{Regexp.escape(@verbatim_end)}\}/
        @in_verbatim = false
        @verbatim_end = nil
      end
      return
    end

    col = 0
    len = raw_line.length
    while col < len
      ch = raw_line[col]
      case ch
      when '\\'
        col = process_backslash(raw_line, line_no, col, len)
      when '%'
        break
      when '{'
        @brace_stack << { line: line_no, col: col + 1, env_depth: @env_stack.size, mismatch: nil }
        col += 1
      when '}'
        process_closing_brace(raw_line, line_no, col)
        col += 1
      when '['
        process_bracket_open
        col += 1
      when ']'
        process_bracket_close(line_no, col)
        col += 1
      else
        col += 1
      end
    end
  end

  def process_backslash(raw_line, line_no, col, len)
    bs_start = col
    col += 1 while col < len && raw_line[col] == '\\'
    bs_count = col - bs_start

    return col unless bs_count.odd?
    return col + 1 if col < len && '{}[%]'.include?(raw_line[col])

    rest = raw_line[bs_start..]
    match_env_or_macro(rest, line_no, bs_start) || col
  end

  def match_env_or_macro(rest, line_no, bs_start)
    if rest =~ /\A\\begin\{([a-zA-Z0-9_\*]+)\}/
      handle_begin_env(Regexp.last_match(1), line_no, bs_start, Regexp.last_match(0).length)
    elsif rest =~ /\A\\end\{([a-zA-Z0-9_\*]+)\}/
      process_env_end(Regexp.last_match(1), line_no)
      bs_start + Regexp.last_match(0).length
    elsif rest =~ /\A\\\[/
      @env_stack << { name: '\\[', line: line_no, col: bs_start + 1, brace_depth: @brace_stack.size }
      bs_start + 2
    elsif rest =~ /\A\\\]/
      process_env_end('\\[', line_no)
      bs_start + 2
    elsif rest =~ /\A\\verb([*|#+~\/!@^"'$])(.*?)\1/
      bs_start + Regexp.last_match(0).length
    end
  end

  def handle_begin_env(name, line_no, bs_start, match_len)
    if VERBATIM_ENVS.include?(name)
      @in_verbatim = true
      @verbatim_end = name
    else
      @env_stack << { name: name, line: line_no, col: bs_start + 1, brace_depth: @brace_stack.size }
    end
    bs_start + match_len
  end

  def process_bracket_open
    if @brace_stack.any?
      @brace_stack.last[:bracket_depth] = (@brace_stack.last[:bracket_depth] || 0) + 1
    end
  end

  def process_bracket_close(line_no, col)
    return unless @brace_stack.any?

    curr = @brace_stack.last
    depth = curr[:bracket_depth] || 0
    if depth > 0
      curr[:bracket_depth] = depth - 1
    else
      curr[:mismatch] ||= {
        line: line_no,
        col: col + 1,
        open_line: curr[:line],
        open_col: curr[:col]
      }
    end
  end

  def process_closing_brace(raw_line, line_no, col)
    if @brace_stack.empty?
      @errors << build_error(
        line_no, col + 1,
        "Extra closing brace '}' with no matching open brace",
        raw_line.chomp
      )
    else
      @brace_stack.pop
    end
  end

  def process_env_end(name, end_line)
    return if @env_stack.empty?

    matching_idx = @env_stack.rindex { |e| e[:name] == name }
    return unless matching_idx

    target_env = @env_stack[matching_idx]
    unclosed = @brace_stack.select { |b| b[:env_depth] >= matching_idx }
    if unclosed.any?
      culprit = unclosed.last
      alert_msg = nil
      if culprit[:mismatch]
        m = culprit[:mismatch]
        alert_msg = "Probable mistype at line #{m[:line]}:#{m[:col]} of '}' as ']'"
      end

      msg = "Unclosed open brace '{' (opened on line #{culprit[:line]}, col #{culprit[:col]}) inside environment '#{target_env[:name]}' (ended at line #{end_line})"
      line_text = @lines[culprit[:line] - 1].to_s.chomp

      @errors << build_error(culprit[:line], culprit[:col], msg, line_text, alert_msg: alert_msg)
      @brace_stack.reject! { |b| b[:env_depth] >= matching_idx }
    end

    @env_stack.slice!(matching_idx..-1)
  end

  def check_eof_unclosed
    @brace_stack.each do |unclosed|
      alert_msg = nil
      if unclosed[:mismatch]
        m = unclosed[:mismatch]
        alert_msg = "Probable mistype at line #{m[:line]}:#{m[:col]} of '}' as ']'"
      end

      msg = "Unclosed open brace '{' (opened on line #{unclosed[:line]}, col #{unclosed[:col]}) reached end of file"
      line_text = @lines[unclosed[:line] - 1].to_s.chomp
      @errors << build_error(unclosed[:line], unclosed[:col], msg, line_text, alert_msg: alert_msg)
    end
  end

  def build_error(line_no, col_no, message, snippet, alert_msg: nil)
    err_block = ["! #{message}"]
    err_block << "  Alert: #{alert_msg}" if alert_msg
    err_block << "l.#{line_no} #{snippet}"

    {
      file: @path,
      line: line_no,
      col: col_no,
      line_str: line_no.to_s,
      text: err_block.join("\n"),
      err_block: err_block,
      base_color: :red,
      has_alert: !alert_msg.nil?,
      index: -1000
    }
  end
end
