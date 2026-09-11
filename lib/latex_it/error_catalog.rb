# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/error_catalog.rb
#
# Declarative catalog of known LaTeX/TeX compilation errors, pattern matching,
# token extraction, and actionable remediation hints.
# ==============================================================================

module LaTeXErrorCatalog
  PACKAGE_COMMANDS = {
    'toprule' => 'booktabs',
    'midrule' => 'booktabs',
    'bottomrule' => 'booktabs',
    'cmidrule' => 'booktabs',
    'specialrule' => 'booktabs',
    'mathbb' => 'amssymb',
    'mathfrak' => 'amssymb',
    'checkmark' => 'amssymb',
    'triangleq' => 'amssymb',
    'coloneqq' => 'mathtools',
    'DeclarePairedDelimiter' => 'mathtools',
    'bm' => 'bm',
    'url' => 'hyperref or url',
    'nolinkurl' => 'hyperref or url',
    'href' => 'hyperref',
    'hypersetup' => 'hyperref',
    'includegraphics' => 'graphicx',
    'graphicspath' => 'graphicx',
    'rotatebox' => 'graphicx',
    'resizebox' => 'graphicx',
    'color' => 'xcolor',
    'textcolor' => 'xcolor',
    'colorbox' => 'xcolor',
    'definecolor' => 'xcolor',
    'subcaption' => 'subcaption',
    'subfloat' => 'subcaption',
    'cancel' => 'cancel',
    'sout' => 'ulem',
    'hl' => 'soul',
    'lstinline' => 'listings',
    'lstinputlisting' => 'listings',
    'tikz' => 'tikz',
    'node' => 'tikz',
    'coordinate' => 'tikz',
    'microtypesetup' => 'microtype',
    'text' => 'amsmath',
    'eqref' => 'amsmath',
    'DeclareMathOperator' => 'amsmath',
    'boldsymbol' => 'amsmath',
    'intertext' => 'amsmath'
  }.freeze

  COMMON_COMMANDS = %w[
    documentclass usepackage begin end
    section subsection subsubsection paragraph subparagraph
    maketitle tableofcontents appendix bibliography bibliographystyle
    label ref pageref cite citep citet footnote item caption centering
    textbf textit texttt textsc textsf textsl underline emph
    normalsize large Large LARGE small footnotesize huge Huge
    newline newpage clearpage noindent bigskip medskip smallskip
    alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta
    iota kappa lambda mu nu xi pi rho sigma tau upsilon phi varphi chi psi omega
    Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega
    infty partial nabla times cdot sum prod int iint oint forall exists
    in notin subset subseteq supset supseteq cup cap setminus
    leq geq neq approx equiv sim simeq le ge ne
    to leftarrow rightarrow Leftarrow Rightarrow mapsto iff implies
    frac sqrt left right over atop lim min max sup inf det exp log ln sin cos tan
  ].freeze

  def self.suggest_command(raw_tok)
    return 'Undefined command; check spelling or \\usepackage' if raw_tok.nil? || raw_tok.empty?

    cmd = raw_tok.to_s.strip.sub(/\A\\/, '')
    return "Undefined command '\\#{cmd}'; check spelling or \\usepackage" if cmd.empty?

    pkg = PACKAGE_COMMANDS[cmd]
    return "Command '\\#{cmd}' requires \\usepackage{#{pkg}}" if pkg

    suggestion = find_closest_command(cmd)
    if suggestion
      sug_pkg = PACKAGE_COMMANDS[suggestion]
      sug_pkg ? "Did you mean '\\#{suggestion}'? (requires \\usepackage{#{sug_pkg}})" : "Did you mean '\\#{suggestion}'?"
    else
      "Undefined command '\\#{cmd}'; check spelling or \\usepackage"
    end
  end

  def self.find_closest_command(cmd)
    return nil if cmd.length < 3

    max_dist = cmd.length <= 4 ? 1 : 2
    candidates = (COMMON_COMMANDS + PACKAGE_COMMANDS.keys).uniq
    candidates.select! { |c| (c.length - cmd.length).abs <= max_dist }

    best = candidates.min_by do |c|
      dist = LaTeXUtils.edit_distance(cmd, c)
      [dist, c[0] == cmd[0] ? 0 : 1]
    end
    return nil unless best

    LaTeXUtils.edit_distance(cmd, best) <= max_dist ? best : nil
  end

  UNDEFINED_CS_EXTRACTOR = lambda do |_match, err_block|
    block_text = err_block.join("\n")
    if block_text =~ /<recently read>\s*(\\\S+)/
      Regexp.last_match(1)
    elsif block_text =~ /l\.\d+.*?(\\[a-zA-Z@]+)(?:\s|$|[^a-zA-Z@])/
      Regexp.last_match(1)
    end
  end

  CATALOG = [
    {
      id: :misplaced_alignment_tab,
      pattern: /Misplaced alignment tab character &/i,
      title: 'Misplaced Alignment Tab Character (&)',
      hint: "'&' outside align*/tabular; switch environment or escape as '\\&'",
      why: "An alignment tab '&' was encountered outside a table or align environment.",
      fix: "Use an environment that supports '&' (e.g., align*, tabular) or write '\\&'.",
      doc_slug: '01_misplaced_alignment_tab'
    },
    {
      id: :undefined_control_sequence,
      pattern: /Undefined control sequence/i,
      title: 'Undefined Control Sequence',
      token_extractor: UNDEFINED_CS_EXTRACTOR,
      hint: ->(tok) { suggest_command(tok) },
      why: 'LaTeX does not recognize this macro or command name.',
      fix: 'Check for typos or include the package defining this macro in preamble.',
      doc_slug: '02_undefined_control_sequence'
    },
    {
      id: :missing_item,
      pattern: /perhaps a missing \\item/i,
      title: "Something's wrong--perhaps a missing \\item",
      hint: 'Text inside list without \\item; add \\item before list entries',
      why: 'Text was typed directly inside an itemize, enumerate, or description environment before any \\item.',
      fix: 'Add \\item before the text or check if \\begin{itemize} is misplaced.',
      doc_slug: '03_missing_item'
    },
    {
      id: :missing_dollar,
      pattern: /Missing \$ inserted/i,
      title: 'Missing $ inserted',
      hint: 'Math symbol (like _ or ^) outside math mode; wrap in $...$',
      why: "A math-mode token (such as an underscore '_', superscript '^', or greek letter) was used in text mode.",
      fix: "Enclose in math delimiters ($...$) or escape literal characters (e.g., '\\_').",
      doc_slug: '04_missing_dollar'
    },
    {
      id: :extra_closing_brace,
      pattern: /(?:Too many }'s|Extra }, or forgotten \$)/i,
      title: "Too many }'s / Extra closing brace",
      hint: "Unmatched closing brace '}'; remove extra '}' or check balance",
      why: "A closing brace '}' was encountered without a matching opening brace '{'.",
      fix: "Remove the stray '}' or check brace nesting with 'latex_it --check-braces'.",
      doc_slug: '05_extra_closing_brace'
    },
    {
      id: :paragraph_ended_before_complete,
      pattern: /(?:Paragraph ended before \S+ was complete|Runaway argument\?)/i,
      title: 'Paragraph ended before macro was complete / Runaway argument',
      hint: 'Unclosed brace across paragraph or blank line inside short macro argument',
      why: 'A macro argument containing an unclosed brace encountered a blank line / paragraph break.',
      fix: "Close the unclosed brace '{' or ensure no blank lines are inside macro arguments.",
      doc_slug: '06_paragraph_ended_before_complete'
    },
    {
      id: :environment_undefined,
      pattern: /Environment (\S+) undefined/i,
      title: 'Environment undefined',
      hint: ->(tok) { tok ? "Undefined environment '#{tok}'; check spelling or \\usepackage" : 'Undefined environment; check spelling or \\usepackage' },
      why: 'The environment named in \\begin{...} is not defined by any loaded package.',
      fix: 'Check environment name spelling or load the package that provides it.',
      doc_slug: '07_environment_undefined'
    },
    {
      id: :no_line_here_to_end,
      pattern: /There's no line here to end/i,
      title: "There's no line here to end",
      hint: "Line break '\\\\' at start of paragraph or after section/math",
      why: "A line break '\\\\' or '\\newline' was issued when LaTeX was not in horizontal text mode.",
      fix: "Remove '\\\\' and use a blank line for paragraph separation, or \\vspace for vertical space.",
      doc_slug: '08_no_line_here_to_end'
    },
    {
      id: :file_not_found,
      pattern: /File `?([^']+)'? not found/i,
      title: 'File not found',
      hint: ->(tok) { tok ? "File '#{tok}' not found; check file path or spelling" : 'File not found; check file path or spelling' },
      why: 'An \\input{...}, \\include{...}, or \\usepackage{...} targeted a file that does not exist in TeX search path.',
      fix: 'Verify that the file exists and that the relative path is correct.',
      doc_slug: '09_file_not_found'
    },
    {
      id: :command_already_defined,
      pattern: /Command (\S+) already defined/i,
      title: 'Command already defined',
      hint: ->(tok) { tok ? "Command '#{tok}' already defined; use \\renewcommand or rename" : 'Command already defined; use \\renewcommand or rename' },
      why: '\\newcommand tried to define a macro that already exists in LaTeX or a loaded package.',
      fix: 'Use \\renewcommand instead of \\newcommand, or choose a different macro name.',
      doc_slug: '10_command_already_defined'
    },
    {
      id: :extra_alignment_tab,
      pattern: /Extra alignment tab has been changed to \\cr/i,
      title: 'Extra alignment tab has been changed to \\cr',
      hint: "Too many '&' columns in table row; check column specifier",
      why: "A table or matrix row contains more '&' separators than defined in the column specification.",
      fix: 'Add another column to the environment preamble (e.g., {c|c|c}) or remove the extra ampersand.',
      doc_slug: '11_extra_alignment_tab'
    },
    {
      id: :missing_number_treated_as_zero,
      pattern: /Missing number, treated as zero/i,
      title: 'Missing number, treated as zero',
      hint: 'Missing numeric value; provide a number before dimension unit',
      why: 'TeX expected a numeric constant or dimension value but found text or a unit without a leading number.',
      fix: 'Provide a numeric value before the unit (e.g. \\hspace{10pt} instead of \\hspace{pt}).',
      doc_slug: '12_missing_number_treated_as_zero'
    },
    {
      id: :illegal_unit_of_measure,
      pattern: /Illegal unit of measure \(pt inserted\)/i,
      title: 'Illegal unit of measure (pt inserted)',
      hint: 'Missing length unit; append pt, cm, mm, in, or em',
      why: 'A dimension had a numeric value but omitted the measurement unit.',
      fix: 'Specify a valid TeX unit after the number (e.g. \\vspace{10pt} or \\setlength{\\parindent}{1cm}).',
      doc_slug: '13_illegal_unit_of_measure'
    },
    {
      id: :double_subscript,
      pattern: /Double subscript/i,
      title: 'Double subscript',
      hint: "Consecutive '_' subscripts; wrap in braces like 'x_{a_b}'",
      why: "Multiple subscript operators '_' were applied directly to the same base.",
      fix: 'Group the subscripts with curly braces: $x_{a_b}$ or $x_{a,b}$.',
      doc_slug: '14_double_subscript'
    },
    {
      id: :double_superscript,
      pattern: /Double superscript/i,
      title: 'Double superscript',
      hint: "Consecutive '^' superscripts; wrap in braces like 'x^{a^b}'",
      why: "Multiple superscript operators '^' were applied directly to the same base.",
      fix: 'Group the superscripts with curly braces: $x^{a^b}$ or $x^{a,b}$.',
      doc_slug: '15_double_superscript'
    },
    {
      id: :option_clash_for_package,
      pattern: /Option clash for package ([a-zA-Z0-9_\-]+)/i,
      title: 'Option clash for package',
      hint: ->(tok) { tok ? "Conflicting options for package '#{tok}'; pass all options in first \\usepackage" : 'Conflicting package options; unify options in first \\usepackage' },
      why: 'A package was loaded multiple times with mutually conflicting options.',
      fix: 'Move all required package options to the first \\usepackage call or use \\PassOptionsToPackage.',
      doc_slug: '16_option_clash_for_package'
    },
    {
      id: :lonely_item,
      pattern: /Lonely \\item--perhaps a missing list environment/i,
      title: 'Lonely \\item--perhaps a missing list environment',
      hint: '\\item used outside list; wrap in \\begin{itemize} or \\begin{enumerate}',
      why: 'An \\item command was used outside any list environment.',
      fix: 'Enclose items within \\begin{itemize}...\\end{itemize} or \\begin{enumerate}...\\end{enumerate}.',
      doc_slug: '17_lonely_item'
    },
    {
      id: :cannot_determine_size_of_graphic,
      pattern: /Cannot determine size of graphic in (\S+)/i,
      title: 'Cannot determine size of graphic',
      hint: ->(tok) { tok ? "Invalid image format or missing BoundingBox for '#{tok}'" : 'Invalid image format or missing BoundingBox' },
      why: 'The graphics driver cannot read the image file format or find its bounding box dimensions.',
      fix: 'Ensure the file is a valid PDF, PNG, or JPG, or convert it to a supported format.',
      doc_slug: '18_cannot_determine_size_of_graphic'
    },
    {
      id: :not_in_outer_par_mode,
      pattern: /Not in outer par mode/i,
      title: 'Not in outer par mode',
      hint: 'Float (figure/table) inside a box or minipage; move float outside or use minipage',
      why: 'A floating environment (figure or table) was placed inside a box (\\mbox, \\fbox) or inside another float.',
      fix: 'Move the figure/table outside the box, or use a non-floating minipage with \\captionof.',
      doc_slug: '19_not_in_outer_par_mode'
    },
    {
      id: :missing_delimiter,
      pattern: /Missing delimiter \(\. inserted\)/i,
      title: 'Missing delimiter (. inserted)',
      hint: "\\left or \\right without delimiter; use '.' for empty delimiter (e.g. '\\right.')",
      why: 'A \\left or \\right command was not followed by a valid delimiter character.',
      fix: "Specify a delimiter after \\left or \\right. Use a period '.' if no visible delimiter is desired.",
      doc_slug: '20_missing_delimiter'
    },
    {
      id: :only_in_preamble,
      pattern: /Can be used only in preamble/i,
      title: 'Can be used only in preamble',
      hint: 'Preamble command (like \\usepackage) used after \\begin{document}; move before \\begin{document}',
      why: 'A configuration command that can only run in the document preamble was executed in the document body.',
      fix: 'Move \\usepackage and configuration declarations before \\begin{document}.',
      doc_slug: '21_only_in_preamble'
    },
    {
      id: :extra_right,
      pattern: /Extra \\right\b/i,
      title: 'Extra \\right',
      hint: '\\right without matching \\left; check delimiter balance',
      why: 'A \\right delimiter was closed without a corresponding \\left delimiter earlier in the formula.',
      fix: "Ensure every \\right has a corresponding \\left, or use '\\left.' for an invisible opening delimiter.",
      doc_slug: '22_extra_right'
    },
    {
      id: :missing_begin_document,
      pattern: /Missing \\begin\{document\}/i,
      title: 'Missing \\begin{document}',
      hint: 'Printable text in preamble; move text after \\begin{document}',
      why: 'Text, characters, or typesetting commands appeared in the preamble before \\begin{document}.',
      fix: 'Move body text after \\begin{document} or remove stray characters from preamble.',
      doc_slug: '23_missing_begin_document'
    },
    {
      id: :dimension_too_large,
      pattern: /Dimension too large/i,
      title: 'Dimension too large',
      hint: 'Coordinate or dimension exceeds TeX maximum (~5.75m / 16383pt); check scaling',
      why: "A length, coordinate, or calculation exceeded TeX's arithmetic limit (16383.99999pt).",
      fix: 'Scale down coordinates, font size, or TikZ graph dimensions.',
      doc_slug: '24_dimension_too_large'
    },
    {
      id: :misplaced_noalign,
      pattern: /(?:Misplaced \\noalign|Misplaced \\omit)/i,
      title: 'Misplaced \\noalign / \\omit',
      hint: "\\hline or \\cline placed after content; must follow '\\\\' immediately",
      why: "\\hline or \\cline was placed in a table row after table cells rather than immediately after a newline '\\\\'.",
      fix: "Place \\hline or \\cline directly after '\\\\' with no intervening text.",
      doc_slug: '25_misplaced_noalign'
    },
    {
      id: :bad_math_environment_delimiter,
      pattern: /Bad math environment delimiter/i,
      title: 'Bad math environment delimiter',
      hint: "Mismatched inline/display math delimiters; match '\\(' with '\\)' or '\\[ ' with '\\]'",
      why: 'A LaTeX math delimiter was closed with a mismatched counterpart (e.g. \\( ... \\]).',
      fix: 'Match opening and closing delimiters: \\( ... \\) or \\[ ... \\].',
      doc_slug: '26_bad_math_environment_delimiter'
    },
    {
      id: :counter_too_large,
      pattern: /Counter(?: (\S+))? too large/i,
      title: 'Counter too large',
      hint: ->(tok) { tok ? "Counter '#{tok}' exceeded limit (e.g. fnsymbol pool); reset or switch to numeric" : 'Counter exceeded limit (e.g. fnsymbol pool); reset or switch to numeric' },
      why: 'A counter representation (such as \\fnsymbol for footnotes) exceeded its fixed symbol pool.',
      fix: 'Reset the counter per page or switch to arabic numerals.',
      doc_slug: '27_counter_too_large'
    },
    {
      id: :amsmath_multiple_tag,
      pattern: /Multiple \\tag/i,
      title: 'Package amsmath: Multiple \\tag',
      hint: 'Multiple \\tag commands on same equation line; keep only one \\tag',
      why: 'More than one \\tag{...} was specified for a single equation.',
      fix: 'Remove the duplicate \\tag or use \\split / \\align for multi-line formulas.',
      doc_slug: '28_amsmath_multiple_tag'
    },
    {
      id: :undefined_color,
      pattern: /Undefined color `?([^']+)'?/i,
      title: 'Package xcolor: Undefined color',
      hint: ->(tok) { tok ? "Undefined color '#{tok}'; define with \\definecolor or load colornames" : 'Undefined color; define with \\definecolor or load colornames' },
      why: 'A color name was passed to \\textcolor or \\colorbox that has not been defined.',
      fix: 'Define the color using \\definecolor or load \\usepackage[dvipsnames]{xcolor}.',
      doc_slug: '29_undefined_color'
    },
    {
      id: :mismatched_environment,
      pattern: /\\begin\{([^\}]+)\} (?:on input line \d+ )?ended by \\end\{([^\}]+)\}/i,
      title: 'Mismatched \\begin and \\end environments',
      token_extractor: ->(match, _block) { "#{match[1]} vs #{match[2]}" },
      hint: ->(tok) { tok ? "Environment mismatch ('#{tok}'); ensure \\begin{foo} matches \\end{foo}" : 'Environment mismatch; ensure \\begin matches \\end' },
      why: 'An environment was opened with \\begin{foo} but closed with \\end{bar}.',
      fix: 'Ensure the environment name in \\end matches the opening \\begin.',
      doc_slug: '30_mismatched_environment'
    },
    {
      id: :missing_closing_brace,
      pattern: /Missing \} inserted/i,
      title: 'Missing } inserted',
      hint: "Unclosed math group or argument; insert matching '}'",
      why: 'A group or macro argument was opened with { but never closed before math mode or the line ended.',
      fix: 'Add the missing closing brace } before ending math or group.',
      doc_slug: '31_missing_closing_brace'
    },
    {
      id: :missing_endcsname,
      pattern: /Missing \\endcsname inserted/i,
      title: 'Missing \\endcsname inserted',
      hint: "Unclosed \\csname; terminate macro name with '\\endcsname'",
      why: 'A \\csname command was evaluated without finding a matching \\endcsname.',
      fix: 'Add \\endcsname to close the dynamic macro name.',
      doc_slug: '32_missing_endcsname'
    },
    {
      id: :cant_use_hrule_here,
      pattern: /You can't use `?\\hrule'? here/i,
      title: "You can't use \\hrule here except with leaders",
      hint: "\\hrule inside \\hbox; use '\\vrule' in horizontal boxes or move \\hrule outside",
      why: 'A horizontal rule \\hrule was placed inside a horizontal box (\\hbox).',
      fix: 'Use \\vrule for vertical rules in \\hbox, or place \\hrule in vertical mode.',
      doc_slug: '33_cant_use_hrule_here'
    },
    {
      id: :cant_use_spacefactor,
      pattern: /You can't use `?\\spacefactor'? in vertical mode/i,
      title: "You can't use \\spacefactor in vertical mode",
      hint: '\\spacefactor in vertical mode; set within paragraph or text mode',
      why: '\\spacefactor controls spacing between words and is only meaningful in horizontal mode.',
      fix: 'Ensure \\spacefactor is used within a paragraph.',
      doc_slug: '34_cant_use_spacefactor'
    },
    {
      id: :illegal_parameter_number,
      pattern: /Illegal parameter number in definition of (\S+)/i,
      title: 'Illegal parameter number in definition',
      hint: ->(tok) { tok ? "Macro '#{tok}' uses parameters (#1) without declaring argument count [n]" : 'Macro uses parameters without declaring argument count' },
      why: 'A macro definition referenced #1 or #2 but omitted the parameter count declaration.',
      fix: 'Declare the number of arguments: \\newcommand{\\cmd}[1]{...}.',
      doc_slug: '35_illegal_parameter_number'
    },
    {
      id: :two_documentclass_commands,
      pattern: /Two \\documentclass(?: or \\documentstyle)? commands/i,
      title: 'LaTeX Error: Two \\documentclass commands',
      hint: 'Multiple \\documentclass declarations; keep only one in preamble',
      why: 'A LaTeX document can only have exactly one \\documentclass command.',
      fix: 'Remove the redundant \\documentclass declaration.',
      doc_slug: '36_two_documentclass_commands'
    },
    {
      id: :verb_illegal_in_argument,
      pattern: /\\verb illegal in argument/i,
      title: 'LaTeX Error: \\verb illegal in argument',
      hint: "\\verb inside command argument; use '\\texttt' or 'cprotect' package",
      why: '\\verb changes character category codes and cannot be passed inside command arguments.',
      fix: 'Use \\texttt{...} instead of \\verb, or load the cprotect package.',
      doc_slug: '37_verb_illegal_in_argument'
    },
    {
      id: :caption_outside_float,
      pattern: /\\caption outside float/i,
      title: 'LaTeX Error: \\caption outside float',
      hint: "\\caption outside figure/table; place in float or use '\\captionof' from 'caption' package",
      why: '\\caption was placed in standard text outside a figure or table environment.',
      fix: 'Move inside \\begin{figure} / \\begin{table}, or use \\captionof{figure}{...}.',
      doc_slug: '38_caption_outside_float'
    },
    {
      id: :use_of_doesnt_match_definition,
      pattern: /Use of (\S+) doesn't match its definition/i,
      title: "Use of command doesn't match its definition",
      hint: ->(tok) { tok ? "Argument mismatch for delimited macro '#{tok}'; check delimiter syntax" : "Argument mismatch for delimited macro; check delimiter syntax" },
      why: 'A delimited macro was defined with custom argument syntax but invoked with different delimiters.',
      fix: 'Match the macro delimiter structure (e.g. \\cmd(arg) instead of \\cmd{arg}).',
      doc_slug: '39_use_of_doesnt_match_definition'
    },
    {
      id: :ambiguous_math_fractions,
      pattern: /Ambiguous; you need another \{ and \}/i,
      title: 'Ambiguous; you need another { and }',
      hint: "Multiple '\\over' in same group; add braces or use '\\frac{a}{b}'",
      why: 'Multiple \\over commands in the same math subformula created ambiguity.',
      fix: 'Enclose each fraction in braces: ${{a \\over b} \\over c}$ or use \\frac.',
      doc_slug: '40_ambiguous_math_fractions'
    },
    {
      id: :cant_use_eqno_in_math,
      pattern: /You can't use `?\\eqno'? in math mode/i,
      title: "You can't use \\eqno in math mode",
      hint: "\\eqno used in inline math; use display math '\\[ ... \\]' or '\\tag'",
      why: '\\eqno attaches an equation number and is only valid in display math ($$).',
      fix: 'Switch from inline math ($...$) to display math (\\[ ... \\] or equation).',
      doc_slug: '41_cant_use_eqno_in_math'
    },
    {
      id: :package_babel_unknown_language,
      pattern: /Package babel Error: Unknown (?:language|option) [`']([^`'.]+)['`]/i,
      title: 'Package babel Error: Unknown language',
      hint: ->(tok) { tok ? "Unknown babel language '#{tok}'; check spelling or texlive-lang" : 'Unknown babel language; check spelling or texlive-lang' },
      why: 'The language option passed to babel is not defined or installed.',
      fix: 'Verify language spelling (e.g. english, french, german) and install language packs.',
      doc_slug: '42_package_babel_unknown_language'
    },
    {
      id: :bad_register_code,
      pattern: /Bad register code/i,
      title: 'Bad register code',
      hint: 'Register number out of bounds; must be non-negative (use \\newcount)',
      why: 'A TeX register number was negative or exceeded the maximum register index.',
      fix: 'Use non-negative register numbers or allocate with \\newcount / \\newdimen.',
      doc_slug: '43_bad_register_code'
    },
    {
      id: :nested_include,
      pattern: /\\include cannot be nested/i,
      title: 'LaTeX Error: \\include cannot be nested',
      hint: "\\include called inside included file; replace secondary with '\\input'",
      why: '\\include manages page clears and aux files and cannot be called recursively.',
      fix: 'Use \\input{...} instead of \\include{...} inside secondary files.',
      doc_slug: '44_nested_include'
    },
    {
      id: :no_counter_defined,
      pattern: /No counter [`']([^`']+)['`] defined/i,
      title: 'LaTeX Error: No counter defined',
      hint: ->(tok) { tok ? "Counter '#{tok}' does not exist; declare with \\newcounter{#{tok}}" : 'Counter does not exist; declare with \\newcounter' },
      why: 'A counter operation was performed on an undeclared counter name.',
      fix: 'Declare the counter with \\newcounter{...} or check spelling.',
      doc_slug: '45_no_counter_defined'
    },
    {
      id: :command_undefined,
      pattern: /Command `?(\\?\S+?)'? undefined/i,
      title: 'LaTeX Error: Command undefined',
      hint: ->(tok) { tok ? "Command '#{tok}' is not defined; use \\newcommand instead of \\renewcommand" : 'Command is not defined; use \\newcommand instead of \\renewcommand' },
      why: '\\renewcommand was used on a macro that has not yet been declared.',
      fix: 'Use \\newcommand to define the command or check for typos in the name.',
      doc_slug: '46_command_undefined'
    },
    {
      id: :file_ended_while_scanning,
      pattern: /File ended while scanning (?:use|text) of (\\\S+?|\S+?)\.?$/i,
      title: 'File ended while scanning macro',
      hint: ->(tok) { tok ? "Unclosed brace in argument of '#{tok}'; add missing '}' before EOF" : "Unclosed brace before end of file; add missing '}'" },
      why: 'End of file was reached while TeX was still looking for a closing brace.',
      fix: 'Add the missing closing curly brace } to terminate the macro argument.',
      doc_slug: '47_file_ended_while_scanning'
    },
    {
      id: :package_amsmath_split_wont_work,
      pattern: /\\begin\{split\} won't work here/i,
      title: "Package amsmath Error: \\begin{split} won't work here",
      hint: "\\begin{split} outside display math; wrap inside '\\begin{equation}'",
      why: 'split environment is only allowed inside an existing math display (equation, gather).',
      fix: 'Wrap \\begin{split} ... \\end{split} inside \\begin{equation} ... \\end{equation}.',
      doc_slug: '48_package_amsmath_split_wont_work'
    },
    {
      id: :package_amsmath_invalid_intertext,
      pattern: /Invalid use of \\intertext/i,
      title: 'Package amsmath Error: Invalid use of \\intertext',
      hint: "\\intertext inside 'equation'; switch to '\\begin{align}' or move outside",
      why: '\\intertext can only be used inside multi-line alignment environments like align.',
      fix: 'Use align instead of equation, or place text outside the math environment.',
      doc_slug: '49_package_amsmath_invalid_intertext'
    },
    {
      id: :unknown_float_option,
      pattern: /Unknown float option [`']([^`']+)['`]/i,
      title: 'LaTeX Error: Unknown float option',
      hint: ->(tok) { tok == 'H' ? "Float option '[H]' requires '\\usepackage{float}'" : "Invalid float option '#{tok}'; use [!htbp]" },
      why: 'An unrecognized float placement specifier was provided.',
      fix: 'Load \\usepackage{float} for [H] placement, or use standard specifiers [!htbp].',
      doc_slug: '50_unknown_float_option'
    },
    {
      id: :package_tikz_missing_semicolon,
      pattern: /Giving up on this path\. Did you forget a semicolon\?/i,
      title: 'Package tikz Error: Missing semicolon',
      hint: "Missing semicolon ';' at end of TikZ path command; append ';'",
      why: 'A TikZ \\draw, \\node, or \\path command was not terminated with a semicolon.',
      fix: 'Append a semicolon ; to the end of the path statement.',
      doc_slug: '51_package_tikz_missing_semicolon'
    },
    {
      id: :package_pgfkeys_unknown_key,
      pattern: /Package pgfkeys Error: I do not know the key [`']([^`']+)['`]/i,
      title: 'Package pgfkeys Error: Unknown key',
      hint: ->(tok) { tok ? "Unknown pgfkeys option '#{tok}'; check spelling or load library" : 'Unknown pgfkeys option; check spelling or load library' },
      why: 'A key passed to a TikZ/PGF command is not recognized.',
      fix: 'Check the key spelling or load the required library (\\usetikzlibrary{...}).',
      doc_slug: '52_package_pgfkeys_unknown_key'
    },
    {
      id: :not_allowed_in_lr_mode,
      pattern: /Not allowed in LR mode/i,
      title: 'LaTeX Error: Not allowed in LR mode',
      hint: 'Block environment in LR mode; provide required arguments (e.g. \\begin{thebibliography}{99})',
      why: 'A paragraph-level or list environment was invoked inside horizontal LR mode.',
      fix: 'Check for missing mandatory arguments to environments or move outside LR box.',
      doc_slug: '53_not_allowed_in_lr_mode'
    },
    {
      id: :package_enumitem_key_undefined,
      pattern: /Package enumitem Error: (\S+) undefined/i,
      title: 'Package enumitem Error: Key undefined',
      hint: ->(tok) { tok ? "Undefined enumitem key '#{tok}'; check documentation (e.g. label, leftmargin)" : 'Undefined enumitem key; check documentation' },
      why: 'An invalid option key was passed to an enumitem list environment.',
      fix: 'Use valid enumitem options like label, leftmargin, itemsep, or topsep.',
      doc_slug: '54_package_enumitem_key_undefined'
    },
    {
      id: :package_kvsetkeys_undefined_key,
      pattern: /Package kvsetkeys Error: Undefined key `?([^']+)'?/i,
      title: 'Package kvsetkeys Error: Undefined key',
      hint: ->(tok) { tok ? "Undefined setup key '#{tok}'; check macro setup options" : 'Undefined setup key; check macro setup options' },
      why: 'An unknown key was passed to a package setup command (e.g. \\hypersetup).',
      fix: 'Verify option name spelling in the setup declaration.',
      doc_slug: '55_package_kvsetkeys_undefined_key'
    }
  ].freeze

  def self.classify(err_text, err_block = [])
    text = err_text.to_s
    CATALOG.each do |entry|
      match = entry[:pattern].match(text)
      next unless match

      token = extract_token(entry, match, err_block)
      hint = resolve_hint(entry[:hint], token)
      return {
        id: entry[:id],
        title: entry[:title],
        token: token,
        hint: hint,
        why: entry[:why],
        fix: entry[:fix],
        doc_slug: entry[:doc_slug]
      }
    end
    nil
  end

  def self.extract_token(entry, match, err_block)
    if entry[:token_extractor]
      entry[:token_extractor].call(match, err_block)
    elsif match && match.captures.any?
      match.captures.first
    end
  end

  def self.resolve_hint(hint, token)
    if hint.respond_to?(:call)
      hint.call(token)
    else
      hint.to_s
    end
  end

  WARNING_EXPLANATIONS = {
    multiply_defined_label: {
      title: 'Alert: Multiply-Defined Label',
      why: 'Two or more \\label{...} tags share the identical key; references will be ambiguous.',
      fix: 'Search your .tex sources for \\label{<key>} and rename or delete one.'
    },
    overfull_hbox_alert: {
      title: 'Alert: Severe Overfull \\hbox (≥24pt)',
      why: 'Content spills significantly (≥24pt / ~8.4mm) into the page margin.',
      fix: 'Reword text, insert discretionary hyphens \\-, break equations, or resize figures.'
    },
    overfull_hbox_warning: {
      title: 'Warning: Overfull \\hbox',
      why: 'Line exceeds column width; TeX could not hyphenate within standard tolerances.',
      fix: 'Reword sentence, insert \\-, or wrap code in \\sloppy / \\emergencystretch.'
    },
    overfull_hbox_whatever: {
      title: 'Whatever: Micro Overfull \\hbox (≤2.5pt)',
      why: 'Minor margin protrusion (≤2.5pt / ~0.88mm), often memoir TOC page numbers.',
      fix: 'Harmless typesetting quirk; safely ignored.'
    },
    underfull_box: {
      title: 'Warning: Underfull \\vbox or \\hbox',
      why: 'LaTeX could not stretch whitespace enough to fill the target dimension.',
      fix: 'Add \\raggedbottom to preamble, adjust figure heights, or reword text.'
    },
    undefined_reference: {
      title: 'Warning: Undefined Reference',
      why: 'A \\ref{...} or \\pageref{...} references a label that does not exist in any .aux.',
      fix: 'Check spelling of the key, ensure target chapter is included, and recompile.'
    },
    undefined_citation: {
      title: 'Warning: Undefined Citation',
      why: 'A \\cite{...} key was not found in the bibliography database (.bib).',
      fix: 'Verify key spelling, check \\bibliography / \\addbibresource, and run BibTeX/Biber.'
    },
    hyperref_token: {
      title: 'Whatever: Hyperref PDF Bookmark Token Sanitization',
      why: 'Math or formatting in a heading was stripped for plain-text PDF bookmarks.',
      fix: 'Harmless. Use \\texorpdfstring{$math$}{text} in headings to clean cleanly.'
    },
    float_specifier: {
      title: 'Whatever: Float Specifier Auto-Adjusted',
      why: "'!h' (strictly here) violated page layout rules, so LaTeX added 't' (top of page).",
      fix: "Harmless. Use '[!htbp]' to give LaTeX standard placement flexibility."
    },
    font_shape: {
      title: 'Whatever: Font Shape Substitution',
      why: 'Requested font weight/style combination was unavailable; fallback substituted.',
      fix: 'Harmless fallback. Check font declarations if unexpected styling appears.'
    },
    summary_warning: {
      title: 'Whatever: Redundant Summary Notice',
      why: 'Document-level summary emitted at end of LaTeX run.',
      fix: 'Harmless recap; individual items are already reported above.'
    },
    inverted_label: {
      title: 'Alert: Inverted \\label Before \\caption',
      why: '\\label{...} was placed before \\caption in a float. Cross-references (\\ref) will resolve to the Section number instead of the float number.',
      fix: 'Move \\label{...} after or inside \\caption{...}.'
    },
    unnumbered_label: {
      title: 'Alert: \\label Inside Unnumbered Math',
      why: '\\label was placed inside an unnumbered environment (e.g. equation* or align*). Cross-references will bind to the prior section or theorem.',
      fix: 'Remove \\label or switch to a numbered math environment (equation or align).'
    },
    type3_font: {
      title: 'Alert: Type 3 (Raster Bitmap) Font in PDF',
      why: 'PDF contains unscaled bitmapped fonts. IEEE, ACM, and arXiv submission portals will reject this document.',
      fix: 'Ensure scalable vector fonts are used (e.g. \\usepackage[T1]{fontenc} and \\usepackage{lmodern}), or replace bitmap EPS/figures.'
    }
  }.freeze

  def self.find_by_id(id)
    sym = id.to_sym
    CATALOG.find { |e| e[:id] == sym } || WARNING_EXPLANATIONS[sym]
  end
end
