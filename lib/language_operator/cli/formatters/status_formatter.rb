# frozen_string_literal: true

require_relative '../helpers/pastel_helper'

module LanguageOperator
  module CLI
    module Formatters
      # Unified formatter for status indicators across all commands
      #
      # Provides consistent colored status dots (●) for resource states
      class StatusFormatter
        extend Helpers::UxHelper

        # Format a status string with colored indicator
        #
        # @param status [String, Symbol] The status to format
        # @return [String] Formatted status with colored dot
        def self.format(status)
          status_str = status.to_s

          case status_str.downcase
          when 'ready', 'active'
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

        # Format just the status indicator dot (without text)
        #
        # @param status [String, Symbol] The status to format
        # @return [String] Just the colored dot
        def self.dot(status)
          status_str = status.to_s

          case status_str.downcase
          when 'ready', 'active'
            pastel.green('●')
          when 'pending', 'creating', 'synthesizing'
            pastel.yellow('●')
          when 'failed', 'error'
            pastel.red('●')
          when 'paused', 'stopped', 'suspended'
            pastel.dim('●')
          else
            pastel.dim('●')
          end
        end
      end
    end
  end
end
