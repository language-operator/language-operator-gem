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

        def logo(title: nil, sparkle: false)
          puts

          if sparkle
            animate_sparkle_logo
          else
            puts "#{pastel.bold.green('LANGUAGE OPERATOR')} v#{pastel.bold(LanguageOperator::VERSION)}"
          end

          puts pastel.dim("#{pastel.bold('↪')} #{title}") if title
          puts
        end

        private

        def animate_sparkle_logo
          text = 'LANGUAGE OPERATOR'
          frames = 8
          duration = 0.05 # seconds per frame

          # Move cursor up to overwrite the same line
          print "\e[?25l" # Hide cursor

          frames.times do |frame|
            # Build the colored string
            colored_text = text.chars.map.with_index do |char, idx|
              # Calculate distance from the wave position
              wave_position = (text.length.to_f / frames) * frame
              distance = (idx - wave_position).abs

              # Create a gradient effect based on distance
              if distance < 2
                pastel.bold.bright_green(char) # Bright sparkle
              elsif distance < 4
                pastel.bold.green(char) # Medium green
              else
                pastel.green(char) # Base green
              end
            end.join

            # Print the frame
            print "\r#{colored_text} v#{pastel.bold(LanguageOperator::VERSION)}"
            $stdout.flush
            sleep duration
          end

          # Final state - full bright
          print "\r#{pastel.bold.bright_green(text)} v#{pastel.bold(LanguageOperator::VERSION)}"
          puts
          print "\e[?25h" # Show cursor
        end

        # Creates a highlighted box with a colored title bar and content rows
        #
        # @param title [String] The title for the box
        # @param rows [Hash] Content rows where key is the label and value is the content
        # @param title_char [String] Character to use for the title bar (default: '❚')
        # @param color [Symbol] Color for the title and character (default: :yellow)
        # @return [String] The formatted box output
        # @example Simple usage
        #   highlighted_box(
        #     title: 'Model Details',
        #     rows: {
        #       'Name' => 'gpt-4',
        #       'Provider' => 'OpenAI',
        #       'Status' => 'active'
        #     }
        #   )
        #   # Output:
        #   # ❚ Model Details:
        #   # ❚ Name:     gpt-4
        #   # ❚ Provider: OpenAI
        #   # ❚ Status:   active
        #
        # @example With custom color
        #   highlighted_box(
        #     title: 'Error Details',
        #     rows: { 'Code' => '500', 'Message' => 'Server error' },
        #     color: :red
        #   )
        def highlighted_box(title:, rows:, title_char: '❚', color: :yellow)
          output = []
          output << pastel.bold.public_send(color, "#{title_char} #{title}")

          # Find max label width for alignment
          max_label_width = rows.keys.map(&:length).max || 0

          rows.each do |label, value|
            next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

            padded_label = label.ljust(max_label_width)
            output << "#{pastel.dim.public_send(color, title_char)} #{padded_label}: #{value}"
          end

          puts output.join("\n")
        end

        # Displays a formatted list with various styles
        #
        # @param title [String] The title/header for the list
        # @param items [Array, Hash] The items to display
        # @param empty_message [String] Message to show when list is empty (default: '(none)')
        # @param style [Symbol] Display style (:simple, :detailed, :conditions, :key_value)
        # @param bullet [String] Bullet character for list items (default: '-')
        # @return [void]
        # @example Simple list
        #   list_box(
        #     title: 'Models',
        #     items: ['gpt-4', 'claude-3']
        #   )
        #   # Output:
        #   # Models (2):
        #   #   - gpt-4
        #   #   - claude-3
        #
        # @example Simple list with custom bullet
        #   list_box(
        #     title: 'Models',
        #     items: ['gpt-4', 'claude-3'],
        #     bullet: '•'
        #   )
        #   # Output:
        #   # Models (2):
        #   #   • gpt-4
        #   #   • claude-3
        #
        # @example Detailed list with metadata
        #   list_box(
        #     title: 'Agents',
        #     items: [
        #       { name: 'bash', status: 'Running' },
        #       { name: 'web', status: 'Stopped' }
        #     ],
        #     style: :detailed
        #   )
        #   # Output:
        #   # Agents (2):
        #   #   - bash (Running)
        #   #   - web (Stopped)
        #
        # @example Conditions list
        #   list_box(
        #     title: 'Conditions',
        #     items: [
        #       { type: 'Ready', status: 'True', message: 'Agent is ready' },
        #       { type: 'Validated', status: 'False', message: 'Validation failed' }
        #     ],
        #     style: :conditions
        #   )
        #   # Output:
        #   # Conditions (2):
        #   #   ✓ Ready: Agent is ready
        #   #   ✗ Validated: Validation failed
        #
        # @example Key-value pairs
        #   list_box(
        #     title: 'Labels',
        #     items: { 'app' => 'web', 'env' => 'prod' },
        #     style: :key_value
        #   )
        #   # Output:
        #   # Labels:
        #   #   app: web
        #   #   env: prod
        def list_box(title:, items:, empty_message: 'none', style: :simple, bullet: '•')
          # Convert K8s::Resource or hash-like objects to plain Hash/Array
          # Only call to_h if it's not already an Array (Arrays respond to to_h but it behaves differently)
          items_normalized = if items.is_a?(Array)
                               items
                             else
                               (items.respond_to?(:to_h) ? items.to_h : items)
                             end

          # Convert items to array if it's a hash (for key_value style)
          items_array = items_normalized.is_a?(Hash) ? items_normalized.to_a : items_normalized
          count = items_array.length

          # Print title with count
          puts "#{pastel.white.bold(title)} #{pastel.dim("(#{count})")}"

          # Handle empty lists
          if items_array.empty?
            puts pastel.dim(empty_message)
            return
          end

          # Render based on style
          case style
          when :simple
            items_array.each do |item|
              puts "#{bullet} #{item}"
            end
          when :detailed
            items_array.each do |item|
              name = item[:name] || item['name']
              meta = item[:meta] || item['meta'] || item[:status] || item['status']
              if meta
                puts "#{bullet} #{name} (#{meta})"
              else
                puts "#{bullet} #{name}"
              end
            end
          when :conditions
            items_array.each do |condition|
              status = condition[:status] || condition['status']
              type = condition[:type] || condition['type']
              message = condition[:message] || condition['message'] || condition[:reason] || condition['reason']
              icon = status == 'True' ? pastel.green('✓') : pastel.red('✗')
              puts "#{icon} #{type}: #{message}"
            end
          when :key_value
            items_array.each do |key, value|
              puts "#{key}: #{value}"
            end
          end
        end

        # Confirm deletion with user in a clean, simple format
        #
        # @param resource_type [String] Type of resource being deleted (e.g., 'agent', 'model')
        # @param name [String] Resource name
        # @param cluster [String] Cluster name
        # @return [Boolean] True if user confirms, false otherwise
        # @example
        #   confirm_deletion('agent', 'bash', 'production')
        #   # Output: Are you sure you want to delete agent bash from cluster production? (y/N)
        def confirm_deletion(resource_type, name, cluster)
          message = "Are you sure you want to delete #{resource_type} #{pastel.red.bold(name)} " \
                    "from cluster #{pastel.red.bold(cluster)}?"
          prompt.yes?(message)
        end
      end
    end
  end
end
