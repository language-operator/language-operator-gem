# frozen_string_literal: true

require_relative '../helpers/ux_helper'
require_relative 'log_style'

module LanguageOperator
  module CLI
    module Formatters
      # Beautiful progress output for CLI operations
      class ProgressFormatter
        class << self
          include Helpers::UxHelper

          def with_spinner(message, success_msg: nil, &block)
            spin = spinner("#{message}...")
            spin.auto_spin

            result = block.call

            # Determine what to show after spinner completes
            final_status = success_msg || 'done'

            spin.success(final_status)
            result
          rescue StandardError => e
            spin.error(e.message)
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
            puts "#{LogStyle.styled_icon(:warn, pastel)} #{pastel.bold(message)}"
          end
        end
      end
    end
  end
end
