# frozen_string_literal: true

module LanguageOperator
  module Ux
    module Concerns
      # Mixin for common input validation and prompting patterns
      #
      # Provides helpers for common validation scenarios like URLs, emails,
      # Kubernetes resource names, and other frequently validated inputs.
      #
      # @example
      #   class MyFlow < Base
      #     include Concerns::InputValidation
      #
      #     def execute
      #       url = ask_url('Enter endpoint URL:')
      #       name = ask_k8s_name('Resource name:')
      #     end
      #   end
      module InputValidation
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

        # Ask for an email address with validation
        #
        # @param question [String] The prompt question
        # @param default [String, nil] Default value
        # @return [String, nil] The validated email or nil if cancelled
        def ask_email(question, default: nil)
          prompt.ask(question, default: default) do |q|
            q.required true
            q.validate(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i)
            q.messages[:valid?] = 'Please enter a valid email address'
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

        # Ask for a port number with validation
        #
        # @param question [String] The prompt question
        # @param default [Integer, nil] Default value
        # @return [Integer, nil] The validated port or nil if cancelled
        def ask_port(question, default: nil)
          prompt.ask(question, default: default, convert: :int) do |q|
            q.required true
            q.validate(->(v) { v.to_i.between?(1, 65_535) })
            q.messages[:valid?] = 'Must be a valid port number (1-65535)'
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

        # Validate and coerce a Kubernetes resource name
        #
        # @param name [String] The name to validate
        # @return [String] The validated and normalized name
        # @raise [ArgumentError] If name is invalid
        def validate_k8s_name(name)
          normalized = name.to_s.downcase.strip
          raise ArgumentError, "Invalid Kubernetes name: #{name}" unless normalized.match?(/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/)

          normalized
        end

        # Validate a URL
        #
        # @param url [String] The URL to validate
        # @return [String] The validated URL
        # @raise [ArgumentError] If URL is invalid
        def validate_url(url)
          uri = URI.parse(url)
          raise ArgumentError, "Invalid URL: #{url}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          url
        rescue URI::InvalidURIError => e
          raise ArgumentError, "Invalid URL: #{e.message}"
        end
      end
    end
  end
end
