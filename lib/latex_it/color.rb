# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/color.rb
#
# Terminal color output abstraction, TrueColor support, and theme presets.
# ==============================================================================

module LatexColor
  THEMES = {
    'blush' => {
      name: 'Soft Blush',
      red: '#ffcccc',
      yellow: '#ffe0b2',
      cyan: '#b3e5fc',
      green: '#c8e6c9',
      desc: 'Soft pastel blush with high luminance'
    },
    'catppuccin' => {
      name: 'Catppuccin Mocha',
      red: '#f38ba8',
      yellow: '#fab387',
      cyan: '#89dceb',
      green: '#a6e3a1',
      desc: 'Warm soothing pastels'
    },
    'tokyo-night' => {
      name: 'Tokyo Night',
      red: '#f7768e',
      yellow: '#ff9e64',
      cyan: '#7dcfff',
      green: '#9ece6a',
      desc: 'Cyberpunk rose pastel'
    },
    'dracula' => {
      name: 'Dracula',
      red: '#ff5555',
      yellow: '#ffb86c',
      cyan: '#8be9fd',
      green: '#50fa7b',
      desc: 'High-contrast vibrant coral'
    },
    'nord' => {
      name: 'Nord',
      red: '#bf616a',
      yellow: '#d08770',
      cyan: '#88c0d0',
      green: '#a3be8c',
      desc: 'Calm arctic muted brick'
    },
    'ansi' => {
      name: 'ANSI 16-Color',
      red: nil,
      yellow: nil,
      cyan: nil,
      green: nil,
      desc: 'Classic terminal 16-color ANSI'
    }
  }.freeze

  ORDERED_THEMES = %w[blush catppuccin tokyo-night dracula nord ansi].freeze
  DEFAULT_THEME = 'blush'

  @active_theme = DEFAULT_THEME

  class << self
    attr_reader :active_theme

    def active_theme=(theme_name)
      @active_theme = normalize_theme(theme_name)
    end

    def custom_hex?(str)
      !str.nil? && (str =~ /^#?[0-9a-f]{6}$/i)
    end

    def normalize_theme(name)
      return DEFAULT_THEME if name.nil? || name.to_s.strip.empty?

      str = name.to_s.strip.downcase
      return str if THEMES.key?(str) || custom_hex?(str)

      DEFAULT_THEME
    end

    def theme_colors
      if custom_hex?(@active_theme)
        hex = @active_theme.start_with?('#') ? @active_theme : "##{@active_theme}"
        return { red: hex }
      end
      THEMES[@active_theme] || THEMES[DEFAULT_THEME]
    end

    def theme_description(name)
      norm = normalize_theme(name)
      THEMES.dig(norm, :desc) || "Custom hex (#{norm})"
    end

    def cycle_theme(current_name, step = 1)
      norm = normalize_theme(current_name)
      idx = ORDERED_THEMES.index(norm) || 0
      next_idx = (idx + step) % ORDERED_THEMES.size
      ORDERED_THEMES[next_idx]
    end

    def format_theme_list
      lines = ["Available diagnostic color themes:\n"]
      ORDERED_THEMES.each do |key|
        meta = THEMES[key]
        marker = (key == @active_theme) ? '* ' : '  '
        swatch = meta[:red] ? " (#{meta[:red]})" : ''
        current_tag = (key == @active_theme) ? '  [current]' : ''
        lines << format('%s%-12s - %-32s%s%s', marker, key, meta[:desc], swatch, current_tag)
      end
      lines << "\nCycle through themes with: l --theme +1"
      lines.join("\n")
    end
  end
end

begin
  require 'rainbow'

  # Enable TrueColor 24-bit output for Rainbow RGB colors
  class Rainbow::Color::RGB < Rainbow::Color::Indexed
    def codes
      [ground == :foreground ? 38 : 48, 2, r, g, b]
    end
  end

  module RainbowThemeOverride
    def build(ground, values)
      if values.size == 1 && values.first.is_a?(Symbol)
        colors = LatexColor.theme_colors
        hex = colors[values.first]
        return Rainbow::Color::RGB.new(ground, *parse_hex_color(hex)) if hex
      end
      super
    end
  end
  Rainbow::Color.singleton_class.prepend(RainbowThemeOverride)

  # Fallback for ANSI theme: remap standard red (ANSI 31) to bright red (ANSI 91)
  if defined?(Rainbow::Color::Named::NAMES)
    bright_names = Rainbow::Color::Named::NAMES.dup.merge(red: 61)
    Rainbow::Color::Named.send(:remove_const, :NAMES)
    Rainbow::Color::Named.const_set(:NAMES, bright_names.freeze)
  end
rescue LoadError
  module Rainbow
    class NullString < String
      def method_missing(*)
        self
      end

      def respond_to_missing?(*)
        true
      end
    end

    def self.call(obj)
      NullString.new(obj.to_s)
    end

    def self.enabled=(val)
      @enabled = val
    end

    def self.enabled
      false
    end
  end

  def Rainbow(obj)
    Rainbow.call(obj)
  end
end
