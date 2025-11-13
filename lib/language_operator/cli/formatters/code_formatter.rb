# frozen_string_literal: true

require 'rouge'
require_relative '../helpers/pastel_helper'

module LanguageOperator
  module CLI
    module Formatters
      # Formatter for displaying syntax-highlighted code in the terminal
      class CodeFormatter
        class << self
          include Helpers::PastelHelper

          # Display Ruby code with syntax highlighting
          #
          # @param code_content [String] The Ruby code to display
          # @param title [String, nil] Optional title to display above the code
          # @param max_lines [Integer, nil] Maximum number of lines to display (nil for all)
          def display_ruby_code(code_content, title: nil, max_lines: nil)
            # Use Rouge to highlight the code
            formatter = Rouge::Formatters::Terminal256.new
            lexer = Rouge::Lexers::Ruby.new

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

            # Print header
            puts
            puts pastel.cyan(title) if title
            puts pastel.dim('─' * 80)
            puts

            # Highlight and print the code
            highlighted = formatter.format(lexer.lex(code_to_display))
            puts highlighted

            # Show truncation notice if applicable
            if truncated
              puts
              puts pastel.dim("... #{remaining_lines} more lines ...")
            end

            # Print footer
            puts
            puts pastel.dim('─' * 80)
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

            formatter = Rouge::Formatters::Terminal256.new
            lexer = Rouge::Lexers::Ruby.new
            highlighted = formatter.format(lexer.lex(code_content))

            puts highlighted
            puts
          end
        end
      end
    end
  end
end
