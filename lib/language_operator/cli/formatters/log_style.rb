# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Formatters
      # Centralized configuration for log level icons and colors
      #
      # Single source of truth for all logging/notification output across the codebase.
      # This ensures consistent styling and makes it easy to customize icons and colors
      # for all log levels in one place.
      #
      # @example Using LogStyle with Pastel
      #   pastel = Pastel.new
      #   puts LogStyle.format(:success, "Operation completed", pastel)
      #   # => "\e[32m✔ Operation completed\e[0m"
      #
      # @example Getting icon and color separately
      #   icon = LogStyle.icon(:error)    # => "✗"
      #   color = LogStyle.color(:error)  # => :red
      #
      class LogStyle
        # Style configuration for each log level
        # @return [Hash] Mapping of log levels to icon and color
        STYLES = {
          debug: { icon: '☢', color: :dim },
          info: { icon: '⚬', color: :cyan },
          success: { icon: '✔', color: :green },
          warn: { icon: '⚠', color: :yellow },
          error: { icon: '✗', color: :red }
        }.freeze

        class << self
          # Format a message with icon and color for the given log level
          #
          # @param level [Symbol] Log level (:debug, :info, :success, :warn, :error)
          # @param message [String] Message to format
          # @param pastel [Pastel] Pastel instance for applying colors
          # @return [String] Formatted message with icon and color
          def format(level, message, pastel)
            style = STYLES[level] || STYLES[:info]
            icon = style[:icon]
            color = style[:color]

            pastel.send(color, "#{icon} #{message}")
          end

          # Get the icon for a log level
          #
          # @param level [Symbol] Log level
          # @return [String] Icon character
          def icon(level)
            STYLES.dig(level, :icon) || STYLES[:info][:icon]
          end

          # Get the color for a log level
          #
          # @param level [Symbol] Log level
          # @return [Symbol] Color name (e.g., :red, :green)
          def color(level)
            STYLES.dig(level, :color) || STYLES[:info][:color]
          end

          # Get a styled icon with ANSI color codes embedded
          #
          # @param level [Symbol] Log level
          # @param pastel [Pastel] Pastel instance for applying colors
          # @return [String] Colored icon with ANSI escape codes
          def styled_icon(level, pastel)
            style = STYLES[level] || STYLES[:info]
            pastel.send(style[:color], style[:icon])
          end

          # Detect log level from message content
          #
          # Useful for inferring log level from message text when not explicitly provided.
          #
          # @param message [String] Message text to analyze
          # @return [Symbol] Detected log level
          def detect_level_from_message(message)
            case message
            when /error|fail|✗|❌/i
              :error
            when /warn|⚠/i
              :warn
            when /completed|finished|success|✔|✅/i
              :success
            when /debug|☢/i
              :debug
            else
              :info
            end
          end

          # Convert emoji to log level symbol
          #
          # @param emoji [String] Emoji character
          # @return [Symbol] Log level symbol
          def emoji_to_level(emoji)
            case emoji
            when /[☰ℹ]/
              :info
            when /[☢🔍]/
              :debug
            when /⚠/
              :warn
            when /[✗❌]/
              :error
            when /[✔✅]/
              :success
            else
              :info
            end
          end

          # Get ANSI color code for a level (for Logger compatibility)
          #
          # @param level [Symbol, String] Log level
          # @return [String] ANSI escape code with icon and color
          def ansi_icon(level)
            level_sym = level.to_s.downcase.to_sym
            style = STYLES[level_sym] || STYLES[:info]
            icon = style[:icon]
            color_code = ansi_color_code(style[:color])

            "#{color_code}#{icon}\e[0m"
          end

          private

          # Get ANSI color code for a color name
          def ansi_color_code(color)
            case color
            when :dim
              "\e[1;90m"
            when :cyan
              "\e[1;36m"
            when :green
              "\e[1;32m"
            when :yellow
              "\e[1;33m"
            when :red
              "\e[1;31m"
            else
              "\e[0m"
            end
          end
        end
      end
    end
  end
end
