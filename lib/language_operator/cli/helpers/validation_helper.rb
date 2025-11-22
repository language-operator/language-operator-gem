# frozen_string_literal: true

require 'uri'

module LanguageOperator
  module CLI
    module Helpers
      # Common input validation patterns for CLI wizards
      #
      # Provides validation helpers for URLs, Kubernetes names, emails, ports, etc.
      # Uses UxHelper for prompt access.
      #
      # @example
      #   class MyWizard
      #     include Helpers::UxHelper
      #     include Helpers::ValidationHelper
      #
      #     def run
      #       url = ask_url('Enter endpoint:')
      #       name = ask_k8s_name('Resource name:')
      #     end
      #   end
      module ValidationHelper
        # Ask for a URL with validation
        #
        # @param question [String] The prompt question
        # @param default [String, nil] Default value
        # @param required [Boolean] Whether input is required
        # @return [String, nil] The validated URL or nil if cancelled
        def ask_url(question, default: nil, required: true)
          prompt.ask(question, default: default) do |q|
            q.required required
            q.validate(%r{^https?://})
            q.messages[:valid?] = 'Must be a valid HTTP(S) URL'
          end
        rescue TTY::Reader::InputInterrupt
          nil
        end

        # Ask for a Kubernetes-compatible resource name
        #
        # @param question [String] The prompt question
        # @param default [String, nil] Default value
        # @return [String, nil] The validated name or nil if cancelled
        def ask_k8s_name(question, default: nil)
          prompt.ask(question, default: default) do |q|
            q.required true
            q.validate(/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/, 'Must be lowercase alphanumeric with hyphens')
            q.modify :strip, :down
          end
        rescue TTY::Reader::InputInterrupt
          nil
        end

        # Ask for a masked input (like API keys or passwords)
        #
        # @param question [String] The prompt question
        # @param required [Boolean] Whether input is required
        # @return [String, nil] The input value or nil if cancelled
        def ask_secret(question, required: true)
          prompt.mask(question) do |q|
            q.required required
          end
        rescue TTY::Reader::InputInterrupt
          nil
        end

        # Ask a yes/no question
        #
        # @param question [String] The prompt question
        # @param default [Boolean] Default value
        # @return [Boolean, nil] The response or nil if cancelled
        def ask_yes_no(question, default: false)
          prompt.yes?(question, default: default)
        rescue TTY::Reader::InputInterrupt
          nil
        end

        # Ask for selection from a list
        #
        # @param question [String] The prompt question
        # @param choices [Array] Array of choices
        # @param per_page [Integer] Items per page for pagination
        # @return [Object, nil] The selected choice or nil if cancelled
        def ask_select(question, choices, per_page: 10)
          prompt.select(question, choices, per_page: per_page)
        rescue TTY::Reader::InputInterrupt
          nil
        end
      end
    end
  end
end
