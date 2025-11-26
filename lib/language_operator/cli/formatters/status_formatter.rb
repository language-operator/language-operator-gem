# frozen_string_literal: true

require_relative '../helpers/ux_helper'

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
          color = status_color(status_str)
          "#{pastel.send(color, '●')} #{status_str}"
        end

        # Format just the status indicator dot (without text)
        #
        # @param status [String, Symbol] The status to format
        # @return [String] Just the colored dot
        def self.dot(status)
          color = status_color(status.to_s)
          pastel.send(color, '●')
        end

        # Determine the appropriate color for a status
        #
        # @param status_str [String] The status string
        # @return [Symbol] Color method name for pastel
        def self.status_color(status_str)
          case status_str.downcase
          when 'ready', 'running', 'active'
            :green
          when 'pending', 'creating', 'synthesizing'
            :yellow
          when 'failed', 'error'
            :red
          when 'paused', 'stopped', 'suspended'
            :dim
          else
            :dim
          end
        end

        private_class_method :status_color
      end
    end
  end
end
