# frozen_string_literal: true

module LanguageOperator
  module Ux
    module Concerns
      # Mixin for consistent heading and banner formatting in UX flows
      #
      # Provides helpers for creating section headers, step indicators,
      # welcome banners, and separator lines.
      #
      # @example
      #   class MyFlow < Base
      #     include Concerns::Headings
      #
      #     def execute
      #       heading('Welcome to My Flow', emoji: '🎉')
      #       step_heading(1, 5, 'First Step')
      #       # ... flow logic
      #     end
      #   end
      module Headings
        def title(text)
          puts
          puts pastel.bold.green("LANGUAGE OPERATOR v#{LanguageOperator::VERSION}")
          puts pastel.dim("↪ #{text}")
        end

        # Display a prominent heading with optional emoji
        #
        # @param text [String] The heading text
        # @param emoji [String, nil] Optional emoji to display
        # @param width [Integer] Width of the banner (default: 50)
        def heading(text, emoji: nil, width: 50)
          border = "╭#{'─' * (width - 2)}╮"
          bottom = "╰#{'─' * (width - 2)}╯"

          display_text = emoji ? "#{text} #{emoji}" : text
          padding = width - display_text.length - 4

          puts
          puts pastel.cyan(border)
          puts "#{pastel.cyan('│')}  #{display_text}#{' ' * padding}#{pastel.cyan('│')}"
          puts pastel.cyan(bottom)
          puts
        end

        # Display a step heading with step number
        #
        # @param current [Integer] Current step number
        # @param total [Integer] Total number of steps
        # @param title [String] Step title
        # @param width [Integer] Width of the separator line (default: 50)
        def step_heading(current, total, title, width: 50)
          puts
          puts '─' * width
          puts pastel.cyan("Step #{current}/#{total}: #{title}")
          puts '─' * width
          puts
        end

        # Display a simple subheading
        #
        # @param text [String] The subheading text
        def subheading(text)
          puts
          puts pastel.bold(text)
        end

        # Display a separator line
        #
        # @param width [Integer] Width of the line (default: 50)
        # @param char [String] Character to use for the line (default: '─')
        def separator(width: 50, char: '─')
          puts char * width
        end

        # Display a section header with description
        #
        # @param title [String] Section title
        # @param description [String, nil] Optional description
        def section(title, description: nil)
          puts
          puts pastel.cyan.bold(title)
          puts pastel.dim(description) if description
          puts
        end
      end
    end
  end
end
