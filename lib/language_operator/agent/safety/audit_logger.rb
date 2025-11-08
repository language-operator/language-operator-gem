# frozen_string_literal: true

require 'json'
require_relative '../../logger'
require_relative '../../loggable'

module LanguageOperator
  module Agent
    module Safety
      # Audit Logger for safety events
      #
      # Logs all safety-related events (blocked requests, budget exceeded, etc.)
      # for compliance and debugging.
      #
      # @example
      #   audit = AuditLogger.new
      #   audit.log_blocked_request(reason: 'Budget exceeded', details: {...})
      class AuditLogger
        include LanguageOperator::Loggable

        def initialize
          @audit_log_path = ENV['AUDIT_LOG_PATH'] || '/tmp/langop-audit.jsonl'
          logger.info('Audit logger initialized', log_path: @audit_log_path)
        end

        # Log a blocked request
        #
        # @param reason [String] Reason for blocking
        # @param details [Hash] Additional details
        def log_blocked_request(reason:, details: {})
          log_event(
            event_type: 'blocked_request',
            reason: reason,
            details: details
          )
        end

        # Log a budget event
        #
        # @param event [String] Event description
        # @param details [Hash] Budget details
        def log_budget_event(event:, details: {})
          log_event(
            event_type: 'budget_event',
            event: event,
            details: details
          )
        end

        # Log a rate limit event
        #
        # @param event [String] Event description
        # @param details [Hash] Rate limit details
        def log_rate_limit_event(event:, details: {})
          log_event(
            event_type: 'rate_limit_event',
            event: event,
            details: details
          )
        end

        # Log a content filter event
        #
        # @param event [String] Event description
        # @param details [Hash] Filter details
        def log_content_filter_event(event:, details: {})
          log_event(
            event_type: 'content_filter_event',
            event: event,
            details: details
          )
        end

        private

        def logger_component
          'Safety::AuditLogger'
        end

        def log_event(event_data)
          event = {
            timestamp: Time.now.utc.iso8601,
            agent_name: ENV['AGENT_NAME'] || 'unknown',
            **event_data
          }

          # Log to standard logger
          logger.info('Audit event', **event_data)

          # Append to audit log file
          begin
            File.open(@audit_log_path, 'a') do |f|
              f.puts(JSON.generate(event))
            end
          rescue StandardError => e
            logger.error('Failed to write audit log',
                         error: e.message,
                         log_path: @audit_log_path)
          end
        end
      end
    end
  end
end
