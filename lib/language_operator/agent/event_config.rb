# frozen_string_literal: true

require_relative '../config'

module LanguageOperator
  module Agent
    # Event emission configuration for agent runtime
    #
    # Manages configuration for Kubernetes event emission including:
    # - Event filtering and batching options
    # - Error handling preferences
    # - Performance tuning settings
    #
    # @example Load event configuration
    #   config = EventConfig.load
    #   puts "Events enabled: #{config[:enabled]}"
    #   puts "Max events per minute: #{config[:rate_limit]}"
    module EventConfig
      # Load event emission configuration from environment variables
      #
      # @return [Hash] Event configuration hash
      def self.load
        Config.from_env(
          {
            # Core event emission settings
            enabled: 'ENABLE_K8S_EVENTS',
            disabled: 'DISABLE_K8S_EVENTS',

            # Event filtering
            emit_success_events: 'EMIT_SUCCESS_EVENTS',
            emit_failure_events: 'EMIT_FAILURE_EVENTS',
            emit_validation_events: 'EMIT_VALIDATION_EVENTS',

            # Performance and rate limiting
            rate_limit_per_minute: 'EVENT_RATE_LIMIT_PER_MINUTE',
            batch_size: 'EVENT_BATCH_SIZE',
            batch_timeout_ms: 'EVENT_BATCH_TIMEOUT_MS',

            # Error handling
            retry_failed_events: 'RETRY_FAILED_EVENTS',
            max_event_retries: 'MAX_EVENT_RETRIES',
            retry_delay_ms: 'EVENT_RETRY_DELAY_MS',

            # Event content control
            include_task_metadata: 'INCLUDE_TASK_METADATA',
            include_error_details: 'INCLUDE_ERROR_DETAILS',
            truncate_long_messages: 'TRUNCATE_LONG_MESSAGES',
            max_message_length: 'MAX_EVENT_MESSAGE_LENGTH'
          },
          defaults: {
            enabled: 'true',
            disabled: 'false',
            emit_success_events: 'true',
            emit_failure_events: 'true',
            emit_validation_events: 'true',
            rate_limit_per_minute: '60',
            batch_size: '1',
            batch_timeout_ms: '1000',
            retry_failed_events: 'true',
            max_event_retries: '3',
            retry_delay_ms: '1000',
            include_task_metadata: 'true',
            include_error_details: 'true',
            truncate_long_messages: 'true',
            max_message_length: '1000'
          },
          types: {
            enabled: :boolean,
            disabled: :boolean,
            emit_success_events: :boolean,
            emit_failure_events: :boolean,
            emit_validation_events: :boolean,
            rate_limit_per_minute: :integer,
            batch_size: :integer,
            batch_timeout_ms: :integer,
            retry_failed_events: :boolean,
            max_event_retries: :integer,
            retry_delay_ms: :integer,
            include_task_metadata: :boolean,
            include_error_details: :boolean,
            truncate_long_messages: :boolean,
            max_message_length: :integer
          }
        )
      end

      # Check if event emission is enabled overall
      #
      # Events are enabled if:
      # - Running in Kubernetes (KUBERNETES_SERVICE_HOST set)
      # - Not explicitly disabled (DISABLE_K8S_EVENTS != 'true')
      # - Explicitly enabled (ENABLE_K8S_EVENTS != 'false')
      #
      # @param config [Hash] Configuration hash from load
      # @return [Boolean] True if events should be emitted
      def self.enabled?(config = nil)
        config ||= load

        # Must be in Kubernetes environment
        return false unless ENV.fetch('KUBERNETES_SERVICE_HOST', nil)

        # Respect explicit disable flag (legacy)
        return false if config[:disabled]

        # Check enable flag
        config[:enabled]
      end

      # Check if specific event type should be emitted
      #
      # @param event_type [Symbol] Event type (:success, :failure, :validation)
      # @param config [Hash] Configuration hash from load
      # @return [Boolean] True if this event type should be emitted
      def self.should_emit?(event_type, config = nil)
        return false unless enabled?(config)

        config ||= load

        case event_type
        when :success
          config[:emit_success_events]
        when :failure
          config[:emit_failure_events]
        when :validation
          config[:emit_validation_events]
        else
          false
        end
      end

      # Get rate limiting configuration
      #
      # @param config [Hash] Configuration hash from load
      # @return [Hash] Rate limiting settings
      def self.rate_limit_config(config = nil)
        config ||= load
        {
          per_minute: config[:rate_limit_per_minute],
          batch_size: config[:batch_size],
          batch_timeout_ms: config[:batch_timeout_ms]
        }
      end

      # Get retry configuration for failed events
      #
      # @param config [Hash] Configuration hash from load
      # @return [Hash] Retry settings
      def self.retry_config(config = nil)
        config ||= load
        {
          enabled: config[:retry_failed_events],
          max_retries: config[:max_event_retries],
          delay_ms: config[:retry_delay_ms]
        }
      end

      # Get content configuration for event messages
      #
      # @param config [Hash] Configuration hash from load
      # @return [Hash] Content settings
      def self.content_config(config = nil)
        config ||= load
        {
          include_task_metadata: config[:include_task_metadata],
          include_error_details: config[:include_error_details],
          truncate_long_messages: config[:truncate_long_messages],
          max_message_length: config[:max_message_length]
        }
      end
    end
  end
end
