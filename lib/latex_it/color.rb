# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/color.rb
#
# Terminal color output abstraction with fallback to plain strings.
# ==============================================================================

begin
  require 'rainbow'
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
