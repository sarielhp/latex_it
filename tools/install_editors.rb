#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# tools/install_editors.rb
#
# Automated installation helper for popular LaTeX GUI editors on Debian/Kali:
# - TeXstudio: Cross-platform open-source LaTeX IDE
# - Sublime Text: Fast GUI text editor
#
# Usage:
#   tools/install_editors.rb              # Installs both TeXstudio & Sublime Text
#   tools/install_editors.rb --texstudio  # Installs TeXstudio only
#   tools/install_editors.rb --sublime    # Installs Sublime Text only
#   tools/install_editors.rb --dry-run    # Preview commands without executing
# ==============================================================================

require 'optparse'

module EditorInstaller
  GREEN  = "\e[32m"
  YELLOW = "\e[33m"
  RED    = "\e[31m"
  CYAN   = "\e[36m"
  BOLD   = "\e[1m"
  RESET  = "\e[0m"

  SUBLIME_GPG_URL = 'https://download.sublimetext.com/sublimehq-pub.gpg'
  SUBLIME_KEY_PATH = '/etc/apt/trusted.gpg.d/sublimehq-archive.gpg'
  SUBLIME_REPO_PATH = '/etc/apt/sources.list.d/sublime-text.list'
  SUBLIME_REPO_LINE = 'deb https://download.sublimetext.com/ apt/stable/'

  def self.command_available?(cmd)
    ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, cmd))
    end
  end

  def self.sudo_prefix
    Process.uid.zero? ? '' : 'sudo '
  end

  def self.exec_cmd!(cmd, dry_run: false)
    puts "  #{CYAN}$#{RESET} #{cmd}"
    return true if dry_run

    system(cmd) || abort_cmd!(cmd)
  end

  def self.abort_cmd!(cmd)
    warn "#{RED}❌ Command failed:#{RESET} #{cmd}"
    exit 1
  end

  def self.install_texstudio!(dry_run: false)
    puts "\n#{BOLD}==> Installing TeXstudio...#{RESET}"
    if command_available?('texstudio') && !dry_run
      puts "  #{GREEN}✔ TeXstudio is already installed:#{RESET} #{`which texstudio`.strip}"
      return
    end

    exec_cmd!("#{sudo_prefix}apt-get update", dry_run: dry_run)
    exec_cmd!("#{sudo_prefix}apt-get install -y texstudio", dry_run: dry_run)
    puts "  #{GREEN}✔ TeXstudio installation completed.#{RESET}" unless dry_run
  end

  def self.setup_sublime_repo!(dry_run: false)
    unless File.file?(SUBLIME_KEY_PATH) && !dry_run
      gpg_cmd = "curl -fsSL #{SUBLIME_GPG_URL} | gpg --dearmor | #{sudo_prefix}tee #{SUBLIME_KEY_PATH} > /dev/null"
      exec_cmd!(gpg_cmd, dry_run: dry_run)
    end

    return if File.file?(SUBLIME_REPO_PATH) && !dry_run

    repo_cmd = "echo '#{SUBLIME_REPO_LINE}' | #{sudo_prefix}tee #{SUBLIME_REPO_PATH} > /dev/null"
    exec_cmd!(repo_cmd, dry_run: dry_run)
  end

  def self.install_sublime!(dry_run: false)
    puts "\n#{BOLD}==> Installing Sublime Text...#{RESET}"
    if (command_available?('subl') || command_available?('sublime_text')) && !dry_run
      which_subl = `which subl 2>/dev/null || which sublime_text 2>/dev/null`.strip
      puts "  #{GREEN}✔ Sublime Text is already installed:#{RESET} #{which_subl}"
      return
    end

    exec_cmd!("#{sudo_prefix}apt-get install -y apt-transport-https ca-certificates curl gnupg", dry_run: dry_run)
    setup_sublime_repo!(dry_run: dry_run)
    exec_cmd!("#{sudo_prefix}apt-get update", dry_run: dry_run)
    exec_cmd!("#{sudo_prefix}apt-get install -y sublime-text", dry_run: dry_run)
    puts "  #{GREEN}✔ Sublime Text installation completed.#{RESET}" unless dry_run
  end

  def self.report_summary
    puts "\n#{BOLD}==> Installed Editor Summary:#{RESET}"
    [
      ['TeXstudio', 'texstudio', '--version'],
      ['Sublime Text', 'subl', '-v']
    ].each do |label, cmd, ver_flag|
      if command_available?(cmd)
        ver = `#{cmd} #{ver_flag} 2>&1`.lines.first.to_s.strip
        puts "  #{GREEN}✔#{RESET} #{BOLD}#{label}#{RESET}: #{ver}"
      else
        puts "  #{YELLOW}○#{RESET} #{label}: not installed"
      end
    end
  end

  def self.parse_options(args)
    options = { texstudio: false, sublime: false, dry_run: false }
    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: tools/install_editors.rb [options]'
      opts.separator ''
      opts.on('--all', 'Install both TeXstudio and Sublime Text (default)') do
        options[:texstudio] = true
        options[:sublime] = true
      end
      opts.on('--texstudio', 'Install TeXstudio only') { options[:texstudio] = true }
      opts.on('--sublime', 'Install Sublime Text only') { options[:sublime] = true }
      opts.on('-n', '--dry-run', 'Print shell commands without executing them') { options[:dry_run] = true }
      opts.on('-h', '--help', 'Show this help message') do
        puts opts
        exit 0
      end
    end
    parser.parse!(args)

    if !options[:texstudio] && !options[:sublime]
      options[:texstudio] = true
      options[:sublime] = true
    end
    options
  end

  def self.run(args = ARGV)
    options = parse_options(args)
    dry = options[:dry_run]

    puts "#{BOLD}==> LaTeX Editor Installer#{RESET}"
    puts "#{CYAN}[Dry Run Mode] Commands will only be displayed.#{RESET}" if dry

    install_texstudio!(dry_run: dry) if options[:texstudio]
    install_sublime!(dry_run: dry) if options[:sublime]

    report_summary unless dry
    0
  end
end

exit EditorInstaller.run if $PROGRAM_NAME == __FILE__
