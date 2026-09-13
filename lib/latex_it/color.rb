# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/color.rb
#
# Terminal color output abstraction with fallback to plain strings.
# ==============================================================================

begin
  require 'rainbow'

  # Remap standard red (ANSI 31) to bright/high-intensity red (ANSI 91)
  # so error messages and diagnostics are clearly visible on dark/black terminal backgrounds.
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
