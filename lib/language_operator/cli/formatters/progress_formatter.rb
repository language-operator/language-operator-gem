# frozen_string_literal: true

require 'tty-spinner'
require_relative '../helpers/pastel_helper'
require_relative 'log_style'

module LanguageOperator
  module CLI
    module Formatters
      # Beautiful progress output for CLI operations
      class ProgressFormatter
        class << self
          include Helpers::PastelHelper

          def with_spinner(message, success_msg: nil, &block)
            success_icon = LogStyle.styled_icon(:success, pastel)
            spinner = TTY::Spinner.new(":spinner #{message}...", format: :dots, success_mark: success_icon)
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
            puts LogStyle.format(:success, message, pastel)
          end

          def error(message)
            puts LogStyle.format(:error, message, pastel)
          end

          def info(message)
            icon = LogStyle.styled_icon(:info, pastel)
            puts "#{icon} #{pastel.dim(message)}"
          end

          def debug(message)
            icon = LogStyle.styled_icon(:debug, pastel)
            puts "#{icon} #{pastel.dim(message)}"
          end

          def warn(message)
            puts "#{pastel.yellow.bold(LogStyle.icon(:warn))} #{message}"
          end
        end
      end
    end
  end
end
