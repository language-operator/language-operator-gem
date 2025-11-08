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
            final_message = if success_msg
                              "#{message}... #{success_msg}"
                            else
                              "#{message}... done"
                            end

            spinner.success(final_message)
            result
          rescue StandardError => e
            error_msg = e.message
            spinner.error("#{message}... #{error_msg}")
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
