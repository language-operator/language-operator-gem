# frozen_string_literal: true

require_relative '../helpers/pastel_helper'

module LanguageOperator
  module CLI
    module Formatters
      # Unified formatter for status indicators across all commands
      #
      # Provides consistent colored status dots (●) for resource states
      class StatusFormatter
        extend Helpers::PastelHelper

        # Format a status string with colored indicator
        #
        # @param status [String, Symbol] The status to format
        # @return [String] Formatted status with colored dot
        def self.format(status)
          status_str = status.to_s

          case status_str.downcase
          when 'ready', 'running', 'active'
            "#{pastel.green('●')} #{status_str}"
          when 'pending', 'creating', 'synthesizing'
            "#{pastel.yellow('●')} #{status_str}"
          when 'failed', 'error'
            "#{pastel.red('●')} #{status_str}"
          when 'paused', 'stopped', 'suspended'
            "#{pastel.dim('●')} #{status_str}"
          else
            "#{pastel.dim('●')} #{status_str}"
          end
        end
      end
    end
  end
end
