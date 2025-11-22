# frozen_string_literal: true

require 'pastel'
require 'tty-prompt'

module LanguageOperator
  module CLI
    module Helpers
      # Provides unified access to TTY UI components across all CLI commands,
      # formatters, wizards, and error handlers.
      #
      # This module consolidates TTY initialization that was previously duplicated
      # across multiple files. It provides memoized instances to avoid unnecessary
      # object allocation.
      #
      # Available helpers:
      # - +pastel+ - Terminal colors and styles
      # - +prompt+ - Interactive user input
      # - +spinner+ - Loading/progress spinners
      # - +table+ - Formatted table display
      # - +box+ - Framed messages
      #
      # @example Using in a command
      #   class MyCommand < Thor
      #     include Helpers::UxHelper
      #
      #     def execute
      #       puts pastel.green("Success!")
      #       answer = prompt.ask("What's your name?")
      #
      #       spin = spinner("Loading...")
      #       spin.auto_spin
      #       # do work
      #       spin.success("Done!")
      #     end
      #   end
      #
      # @example Using in a formatter
      #   class MyFormatter
      #     include Helpers::UxHelper
      #
      #     def format(data)
      #       tbl = table(['Name', 'Status'], data)
      #       tbl.render(:unicode)
      #     end
      #   end
      module UxHelper
        # Returns a memoized Pastel instance for colorizing terminal output
        #
        # @return [Pastel] Colorization utility
        # @example
        #   puts pastel.green("Success")
        #   puts pastel.red.bold("Error!")
        def pastel
          @pastel ||= Pastel.new
        end

        # Returns a memoized TTY::Prompt instance for interactive input
        #
        # @return [TTY::Prompt] Interactive prompt utility
        # @example
        #   name = prompt.ask("Name?")
        #   confirmed = prompt.yes?("Continue?")
        #   choice = prompt.select("Pick:", %w[a b c])
        def prompt
          @prompt ||= TTY::Prompt.new
        end

        # Creates a new spinner for long-running operations
        #
        # @param message [String] The message to display next to the spinner
        # @param format [Symbol] Spinner format (:dots, :dots2, :line, :pipe, etc.)
        # @return [TTY::Spinner] Spinner instance
        # @example Basic usage
        #   spin = spinner("Loading...")
        #   spin.auto_spin
        #   # do work
        #   spin.success("Done!")
        # @example With custom format
        #   spin = spinner("Processing...", format: :dots2)
        #   spin.auto_spin
        def spinner(message, format: :dots)
          require 'tty-spinner'
          TTY::Spinner.new(
            "[:spinner] #{message}",
            format: format,
            success_mark: pastel.green('✓'),
            error_mark: pastel.red('✗')
          )
        end

        # Creates a formatted table for structured data display
        #
        # @param header [Array<String>] Column headers
        # @param rows [Array<Array>] Table rows
        # @param style [Symbol] Rendering style (:unicode, :ascii, :basic, etc.)
        # @return [TTY::Table] Table instance ready to render
        # @example Basic table
        #   tbl = table(['Name', 'Status'], [['agent1', 'running'], ['agent2', 'stopped']])
        #   puts tbl.render(:unicode)
        # @example With padding
        #   tbl = table(['ID', 'Value'], data)
        #   puts tbl.render(:unicode, padding: [0, 1])
        def table(header, rows, style: :unicode)
          require 'tty-table'
          tbl = TTY::Table.new(header, rows)
          tbl.render(style, padding: [0, 1])
        end

        # Creates a framed box around a message
        #
        # @param message [String] The message to frame
        # @param title [String, nil] Optional title for the box
        # @param style [Hash, Symbol] Box style or preset (:classic, :thick, :light)
        # @param padding [Integer, Array] Padding inside the box
        # @return [String] The framed message ready to print
        # @example Simple box
        #   puts box("Important message!")
        # @example With title and custom style
        #   puts box("Warning!", title: "Alert", border: :thick)
        # @example With custom styling
        #   puts box("Info", style: { border: { fg: :cyan } }, padding: 1)
        def box(message, title: nil, border: :light, padding: 1)
          require 'tty-box'

          options = {
            padding: padding,
            border: border
          }
          options[:title] = { top_left: " #{title} " } if title

          TTY::Box.frame(message, **options)
        end
      end
    end
  end
end
