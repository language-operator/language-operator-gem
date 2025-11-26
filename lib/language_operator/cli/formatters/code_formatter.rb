# frozen_string_literal: true

require_relative '../helpers/ux_helper'

module LanguageOperator
  module CLI
    module Formatters
      # Formatter for displaying syntax-highlighted code in the terminal
      class CodeFormatter
        class << self
          include Helpers::UxHelper

          # Display Ruby code with syntax highlighting
          #
          # @param code_content [String] The Ruby code to display
          # @param title [String, nil] Optional title to display above the code
          # @param max_lines [Integer, nil] Maximum number of lines to display (nil for all)
          def display_ruby_code(code_content, title: nil, max_lines: nil)
            # Truncate if max_lines specified
            lines = code_content.lines
            truncated = false
            if max_lines && lines.length > max_lines
              code_to_display = lines[0...max_lines].join
              truncated = true
              remaining_lines = lines.length - max_lines
            else
              code_to_display = code_content
            end

            # Highlight and print the code
            highlighted = highlight_ruby_code(code_to_display)
            puts highlighted

            # Show truncation notice if applicable
            return unless truncated

            puts
            puts pastel.dim("... #{remaining_lines} more lines ...")
          end

          # Display a code snippet with context
          #
          # @param code_content [String] The Ruby code
          # @param description [String] Description of what the code does
          def display_snippet(code_content, description: nil)
            puts
            puts pastel.cyan('Generated Code Preview:') if description.nil?
            puts pastel.dim(description) if description
            puts

            highlighted = highlight_ruby_code(code_content)

            puts highlighted
            puts
          end
        end
      end
    end
  end
end
