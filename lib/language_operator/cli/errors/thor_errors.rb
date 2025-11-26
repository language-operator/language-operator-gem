# frozen_string_literal: true

require 'thor'

module LanguageOperator
  module CLI
    module Errors
      # Base error class that integrates properly with Thor's error handling
      # while providing specific exit codes for different error types
      class ThorCompatibleError < Thor::Error
        attr_reader :exit_code

        def initialize(message = nil, exit_code = 1)
          super(message)
          @exit_code = exit_code
        end
      end

      # Resource not found error (exit code 2)
      class NotFoundError < ThorCompatibleError
        def initialize(message = nil)
          super(message, 2)
        end
      end

      # Validation or configuration error (exit code 3)
      class ValidationError < ThorCompatibleError
        def initialize(message = nil)
          super(message, 3)
        end
      end

      # Network or connectivity error (exit code 4)
      class NetworkError < ThorCompatibleError
        def initialize(message = nil)
          super(message, 4)
        end
      end

      # Authentication or authorization error (exit code 5)
      class AuthError < ThorCompatibleError
        def initialize(message = nil)
          super(message, 5)
        end
      end

      # Synthesis or code generation error (exit code 6)
      class SynthesisError < ThorCompatibleError
        def initialize(message = nil)
          super(message, 6)
        end
      end
    end
  end
end
