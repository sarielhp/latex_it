# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/flattener.rb
#
# Recursive LaTeX document flattener. Inlines \\input and \\include directives,
# strips comments, and cleans machine-specific styles.
# ==============================================================================

module LaTeXFlattener
  LITERAL_TEX = /\\begin\{(verbatim\*?|Verbatim|BVerbatim|LVerbatim|lstlisting|minted)\}.*?\\end\{\1\}|\\verb\*?([^\s]).*?\2/m.freeze

  def self.transform_tex(content)
    output = +''
    offset = 0
    content.to_enum(:scan, LITERAL_TEX).each do
      literal = Regexp.last_match
      output << yield(content[offset...literal.begin(0)])
      output << literal[0]
      offset = literal.end(0)
    end
    output << yield(content[offset..])
  end

  def self.flatten(main_tex, base_dir = '.', strip_patterns = nil)
    inlined = inline_file(main_tex, base_dir, [])
    cleaned = clean_host_specific(inlined, strip_patterns)
    strip_comments(cleaned)
  end

  def self.inline_file(filepath, base_dir, stack)
    real_path = File.expand_path(filepath, base_dir)
    if stack.include?(real_path)
      chain = (stack + [real_path]).map { |path| File.basename(path) }.join(' -> ')
      raise "Cyclic LaTeX input detected: #{chain}"
    end

    return '' unless File.file?(real_path)

    stack << real_path
    entered = true
    content = LaTeXUtils.safe_read(real_path)
    file_dir = File.dirname(real_path)

    transform_tex(content) do |chunk|
      chunk.lines.map { |line| inline_line(line, file_dir, stack) }.join
    end
  ensure
    stack.pop if entered
  end

  def self.inline_line(line, file_dir, stack)
    match = line.match(/^\s*\\(?:input|include)\{([^}]+)\}(.*)$/)
    return line unless match

    target, rest = match.captures
    target = target.strip
    target += '.tex' unless target.end_with?('.tex')
    candidate = File.expand_path(target, file_dir)
    return line unless File.file?(candidate)

    inlined = inline_file(candidate, file_dir, stack)
    return inlined if rest.strip.empty?

    inlined + rest + (line.end_with?("\n") ? "\n" : '')
  end

  def self.clean_host_specific(content, patterns = nil)
    tokens = patterns || LaTeXUtils::DEFAULT_STRIP_HOST_PATTERNS
    return content if tokens.empty?

    re_str = tokens.map { |t| Regexp.escape(t) }.join('|')
    transform_tex(content) do |chunk|
      chunk.gsub(/\\IfFileExists\{[^}]*(?:#{re_str})[^}]*\}\{[^}]*\}\{[^}]*\}/m, '')
           .gsub(/\\IfFileExists\{[^}]*(?:#{re_str})[^}]*\}\{[^}]*\}/m, '')
    end
  end

  def self.strip_comments(content)
    transform_tex(content) { |chunk| strip_comment_chunk(chunk) }
  end

  def self.strip_comment_chunk(content)
    output = +''
    content.each_line do |raw_line|
      line = raw_line.chomp
      if line =~ /^%!TEX\s+TS-program/i
        output << line << "\n"
        next
      end

      comment_idx = inline_comment_index(line)
      clean_line = comment_idx ? line[0...comment_idx] : line
      next if clean_line.nil?

      output << clean_line
      output << '%' if comment_idx
      output << "\n" if raw_line.end_with?("\n")
    end

    output
  end

  def self.strip_inline_comment(line)
    idx = inline_comment_index(line)
    idx ? line[0...idx] : line
  end

  def self.preceding_backslash_count(line, idx)
    count = 0
    k = idx - 1
    while k >= 0 && line[k] == '\\'
      count += 1
      k -= 1
    end
    count
  end

  def self.inline_comment_index(line)
    in_url = false
    i = 0
    len = line.length
    while i < len
      c = line[i]
      if line[i..].start_with?('\\url{', '\\href{')
        in_url = true
      elsif in_url && c == '}'
        in_url = false
      elsif c == '%' && !in_url
        return i if preceding_backslash_count(line, i).even?
      end
      i += 1
    end
    nil
  end
end
