# frozen_string_literal: true

module LanguageOperator
  module Agent
    module Safety
      # Executes Ruby code in a sandboxed context with method whitelisting
      # Wraps the execution context to prevent dangerous method calls at runtime
      class SafeExecutor
        class SecurityError < StandardError; end

        # Methods that are always safe to call
        ALWAYS_SAFE_METHODS = %i[
          nil? == != eql? equal? hash object_id class is_a? kind_of? instance_of?
          respond_to? send_to? methods public_methods private_methods
          instance_variables instance_variable_get instance_variable_set
          to_s to_str inspect to_a to_h to_i to_f to_sym
          freeze frozen? dup clone
        ].freeze

        def initialize(context, validator: nil)
          @context = context
          @validator = validator || ASTValidator.new
          @audit_log = []
        end

        # Execute code in the sandboxed context
        # @param code [String] Ruby code to execute
        # @param file_path [String] Path to file (for error reporting)
        # @return [Object] Result of code execution
        def eval(code, file_path = '(eval)')
          # Step 1: Validate code with AST analysis
          @validator.validate!(code, file_path)

          # Step 2: Execute in sandboxed context
          sandbox = SandboxProxy.new(@context, self)

          # Step 3: Execute using instance_eval
          # Note: We still use instance_eval but with validated code
          # and wrapped context
          sandbox.instance_eval(code, file_path)
        rescue ASTValidator::SecurityError => e
          # Re-raise validation errors as executor errors for clarity
          raise SecurityError, "Code validation failed: #{e.message}"
        end

        # Log method calls for auditing
        def log_call(receiver, method_name, args)
          @audit_log << {
            timestamp: Time.now,
            receiver: receiver.class.name,
            method: method_name,
            args: args.map(&:class).map(&:name)
          }
        end

        # Get audit log
        attr_reader :audit_log

        # Proxy class that wraps the context and intercepts method calls
        class SandboxProxy < BasicObject
          def initialize(context, executor)
            @__context__ = context
            @__executor__ = executor
          end

          # Delegate method calls to the underlying context
          # but check for dangerous methods first
          def method_missing(method_name, *args, &)
            # Log the call
            @__executor__.log_call(@__context__, method_name, args)

            # Special handling for require - allow only 'language_operator'
            if method_name == :require || method_name == :require_relative
              required_gem = args.first.to_s
              if required_gem == 'language_operator'
                # Allow require 'language_operator'
                return ::Kernel.require(required_gem)
              else
                ::Kernel.raise ::LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
                               "Require '#{required_gem}' is not allowed. Only 'require \"language_operator\"' is permitted."
              end
            end

            # Check if method is safe
            unless safe_method?(method_name)
              ::Kernel.raise ::LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
                             "Method '#{method_name}' is not allowed in sandboxed code"
            end

            # Delegate to underlying context
            @__context__.send(method_name, *args, &)
          end

          def respond_to_missing?(method_name, include_private = false)
            @__context__.respond_to?(method_name, include_private)
          end

          # Provide access to safe constants from the context
          def const_missing(name)
            # Allow access to HTTP and Shell helper classes
            if name == :HTTP
              return ::LanguageOperator::Dsl::HTTP
            elsif name == :Shell
              return ::LanguageOperator::Dsl::Shell
            end

            # Otherwise delegate to the context's module
            @__context__.class.const_get(name)
          rescue ::NameError
            ::Kernel.raise ::NameError, "uninitialized constant #{name}"
          end

          private

          def safe_method?(method_name)
            # Always allow safe basic methods
            return true if ::LanguageOperator::Agent::Safety::SafeExecutor::ALWAYS_SAFE_METHODS.include?(method_name)

            # Check if the underlying context responds to the method
            # (This allows DSL methods defined on the context)
            @__context__.respond_to?(method_name)
          end
        end
      end
    end
  end
end
