# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Helpers
      # Helper module for user confirmation prompts and interactive input.
      # Consolidates the repeated confirmation pattern used throughout commands.
      module UserPrompts
        # Ask user for confirmation
        # @param message [String] The confirmation message
        # @param force [Boolean] Skip prompt if true (default: false)
        # @return [Boolean] true if confirmed, false otherwise
        # rubocop:disable Naming/PredicateMethod
        def self.confirm(message, force: false)
          return true if force

          print "#{message} (y/N): "
          response = $stdin.gets&.chomp || ''
          puts
          response.downcase == 'y'
        end
        # rubocop:enable Naming/PredicateMethod

        # Ask user for confirmation and exit if not confirmed
        # @param message [String] The confirmation message
        # @param force [Boolean] Skip prompt if true (default: false)
        # @param cancel_message [String] Message to display on cancellation
        # @return [void] Returns if confirmed, exits otherwise
        def self.confirm!(message, force: false, cancel_message: 'Operation cancelled')
          return if confirm(message, force: force)

          puts cancel_message
          exit 0
        end

        # Ask user for text input
        # @param prompt [String] The prompt message
        # @param default [String, nil] Default value if user enters nothing
        # @return [String] User input
        def self.ask(prompt, default: nil)
          prompt_text = default ? "#{prompt} [#{default}]" : prompt
          print "#{prompt_text}: "
          response = $stdin.gets&.chomp || ''
          response.empty? && default ? default : response
        end

        # Ask user to select from options
        # @param prompt [String] The prompt message
        # @param options [Array<String>] Available options
        # @return [String] Selected option
        def self.select(prompt, options)
          loop do
            puts prompt
            options.each_with_index do |option, index|
              puts "  #{index + 1}. #{option}"
            end
            print "\nSelect (1-#{options.length}): "

            input = $stdin.gets&.chomp || ''

            # Allow user to quit/cancel
            if input.downcase.match?(/^q(uit)?$/)
              puts 'Selection cancelled'
              exit 0
            end

            selection = input.to_i
            return options[selection - 1] if selection.between?(1, options.length)

            puts 'Invalid selection. Please try again.'
            puts
          end
        end
      end
    end
  end
end
