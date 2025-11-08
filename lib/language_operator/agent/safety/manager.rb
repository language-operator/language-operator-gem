# frozen_string_literal: true

require_relative 'budget_tracker'
require_relative 'rate_limiter'
require_relative 'content_filter'
require_relative 'audit_logger'
require_relative '../../logger'
require_relative '../../loggable'

module LanguageOperator
  module Agent
    module Safety
      # Safety Manager
      #
      # Coordinates all safety components (budget tracking, rate limiting,
      # content filtering, audit logging) and provides a unified interface.
      #
      # @example
      #   safety = Manager.new(
      #     daily_budget: 10.0,
      #     requests_per_minute: 10,
      #     blocked_patterns: ['password']
      #   )
      #   safety.check_request!(message: "Hello", estimated_cost: 0.01)
      class Manager
        include LanguageOperator::Loggable

        attr_reader :budget_tracker, :rate_limiter, :content_filter, :audit_logger

        def initialize(config = {})
          @config = config
          @enabled = config.fetch(:enabled, true)

          # Initialize components based on configuration
          @budget_tracker = if budget_config_present?
                              BudgetTracker.new(
                                daily_budget: config[:daily_budget],
                                hourly_budget: config[:hourly_budget],
                                token_budget: config[:token_budget]
                              )
                            end

          @rate_limiter = if rate_limit_config_present?
                            RateLimiter.new(
                              requests_per_minute: config[:requests_per_minute],
                              requests_per_hour: config[:requests_per_hour],
                              requests_per_day: config[:requests_per_day]
                            )
                          end

          @content_filter = if content_filter_config_present?
                              ContentFilter.new(
                                blocked_patterns: config[:blocked_patterns] || [],
                                blocked_topics: config[:blocked_topics] || [],
                                case_sensitive: config[:case_sensitive] || false
                              )
                            end

          @audit_logger = (AuditLogger.new if config.fetch(:audit_logging, true))

          logger.info('Safety manager initialized',
                      enabled: @enabled,
                      budget_tracking: !@budget_tracker.nil?,
                      rate_limiting: !@rate_limiter.nil?,
                      content_filtering: !@content_filter.nil?,
                      audit_logging: !@audit_logger.nil?)
        end

        # Check if safety checks are enabled
        #
        # @return [Boolean]
        def enabled?
          @enabled
        end

        # Perform all pre-request safety checks
        #
        # @param message [String] The message being sent
        # @param estimated_cost [Float] Estimated cost of the request
        # @param estimated_tokens [Integer] Estimated token count
        # @raise [BudgetTracker::BudgetExceededError] If budget exceeded
        # @raise [RateLimiter::RateLimitExceededError] If rate limit exceeded
        # @raise [ContentFilter::ContentBlockedError] If content blocked
        def check_request!(message:, estimated_cost: 0.0, estimated_tokens: 0)
          return unless @enabled

          begin
            # Check content filter (input)
            if @content_filter
              @content_filter.check_content!(message, direction: :input)
              logger.debug('Input content check passed')
            end

            # Check budget
            if @budget_tracker
              @budget_tracker.check_budget!(
                estimated_cost: estimated_cost,
                estimated_tokens: estimated_tokens
              )
              logger.debug('Budget check passed')
            end

            # Check rate limit
            if @rate_limiter
              @rate_limiter.check_rate_limit!
              logger.debug('Rate limit check passed')
            end

            logger.debug('All safety checks passed')
          rescue BudgetTracker::BudgetExceededError,
                 RateLimiter::RateLimitExceededError,
                 ContentFilter::ContentBlockedError => e
            # Log to audit
            @audit_logger&.log_blocked_request(
              reason: e.class.name,
              details: {
                message: e.message,
                message_preview: message[0..100],
                estimated_cost: estimated_cost,
                estimated_tokens: estimated_tokens
              }
            )
            raise
          end
        end

        # Check response content
        #
        # @param response [String] The LLM response
        # @raise [ContentFilter::ContentBlockedError] If content blocked
        def check_response!(response)
          return unless @enabled
          return unless @content_filter

          begin
            @content_filter.check_content!(response, direction: :output)
            logger.debug('Output content check passed')
          rescue ContentFilter::ContentBlockedError => e
            @audit_logger&.log_content_filter_event(
              event: 'output_blocked',
              details: {
                message: e.message,
                response_preview: response[0..100]
              }
            )
            raise
          end
        end

        # Record successful request
        #
        # @param cost [Float] Actual cost
        # @param tokens [Integer] Actual token count
        def record_request(cost:, tokens:)
          return unless @enabled

          @budget_tracker&.record_spending(cost: cost, tokens: tokens)
          @rate_limiter&.record_request

          @audit_logger&.log_budget_event(
            event: 'request_completed',
            details: {
              cost: cost.round(4),
              tokens: tokens,
              budget_status: @budget_tracker&.status
            }
          )
        end

        # Get current safety status
        #
        # @return [Hash] Safety status information
        def status
          {
            enabled: @enabled,
            budget: @budget_tracker&.status,
            rate_limits: @rate_limiter&.status,
            content_filter: {
              enabled: !@content_filter.nil?,
              patterns: @config[:blocked_patterns]&.length || 0,
              topics: @config[:blocked_topics]&.length || 0
            }
          }
        end

        private

        def logger_component
          'Safety::Manager'
        end

        def budget_config_present?
          @config[:daily_budget] || @config[:hourly_budget] || @config[:token_budget]
        end

        def rate_limit_config_present?
          @config[:requests_per_minute] || @config[:requests_per_hour] || @config[:requests_per_day]
        end

        def content_filter_config_present?
          @config[:blocked_patterns]&.any? ||
            @config[:blocked_topics]&.any?
        end
      end
    end
  end
end
