# frozen_string_literal: true

require 'tty-spinner'
require 'pastel'

module LanguageOperator
  module CLI
    module Formatters
      # Beautiful progress output for CLI operations
      class ProgressFormatter
        class << self
          def with_spinner(message, success_msg: nil, &block)
            spinner = TTY::Spinner.new("[:spinner] #{message}...", format: :dots)
            spinner.auto_spin

            result = block.call

            # Determine what to show after spinner completes
            final_status = success_msg || 'done'

            spinner.success(final_status)
            result
          rescue StandardError => e
            spinner.error(e.message)
            raise
          end

          def success(message)
            puts "[#{pastel.green('✓')}] #{message}"
          end

          def error(message)
            puts "[#{pastel.red('✗')}] #{message}"
          end

          def info(message)
            puts pastel.dim(message)
          end

          def warn(message)
            puts "[#{pastel.yellow('⚠')}] #{message}"
          end

          private

          def pastel
            @pastel ||= Pastel.new
          end
        end
      end
    end
  end
end
