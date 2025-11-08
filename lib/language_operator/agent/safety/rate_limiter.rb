# frozen_string_literal: true

require_relative '../../logger'
require_relative '../../loggable'

module LanguageOperator
  module Agent
    module Safety
      # Rate Limiter for enforcing request limits
      #
      # Enforces per-agent rate limiting to prevent runaway requests.
      #
      # @example
      #   limiter = RateLimiter.new(requests_per_minute: 10, requests_per_hour: 100)
      #   limiter.check_rate_limit!
      class RateLimiter
        include LanguageOperator::Loggable

        class RateLimitExceededError < StandardError; end

        def initialize(requests_per_minute: nil, requests_per_hour: nil, requests_per_day: nil)
          @requests_per_minute = requests_per_minute&.to_i
          @requests_per_hour = requests_per_hour&.to_i
          @requests_per_day = requests_per_day&.to_i

          @minute_requests = []
          @hour_requests = []
          @day_requests = []

          logger.info('Rate limiter initialized',
                      per_minute: @requests_per_minute,
                      per_hour: @requests_per_hour,
                      per_day: @requests_per_day)
        end

        # Check if a request would exceed rate limits
        #
        # @raise [RateLimitExceededError] If rate limit would be exceeded
        def check_rate_limit!
          now = Time.now

          # Clean up old requests
          cleanup_old_requests(now)

          # Check per-minute limit
          if @requests_per_minute && @minute_requests.length >= @requests_per_minute
            oldest = @minute_requests.first
            wait_time = 60 - (now - oldest)
            logger.error('Per-minute rate limit exceeded',
                         current: @minute_requests.length,
                         limit: @requests_per_minute,
                         wait_time: wait_time.round(1))
            raise RateLimitExceededError,
                  "Per-minute rate limit exceeded: #{@minute_requests.length}/#{@requests_per_minute} " \
                  "(retry in #{wait_time.round(1)}s)"
          end

          # Check per-hour limit
          if @requests_per_hour && @hour_requests.length >= @requests_per_hour
            oldest = @hour_requests.first
            wait_time = 3600 - (now - oldest)
            logger.error('Per-hour rate limit exceeded',
                         current: @hour_requests.length,
                         limit: @requests_per_hour,
                         wait_time: (wait_time / 60).round(1))
            raise RateLimitExceededError,
                  "Per-hour rate limit exceeded: #{@hour_requests.length}/#{@requests_per_hour} " \
                  "(retry in #{(wait_time / 60).round(1)}m)"
          end

          # Check per-day limit
          if @requests_per_day && @day_requests.length >= @requests_per_day
            oldest = @day_requests.first
            wait_time = 86_400 - (now - oldest)
            logger.error('Per-day rate limit exceeded',
                         current: @day_requests.length,
                         limit: @requests_per_day,
                         wait_time: (wait_time / 3600).round(1))
            raise RateLimitExceededError,
                  "Per-day rate limit exceeded: #{@day_requests.length}/#{@requests_per_day} " \
                  "(retry in #{(wait_time / 3600).round(1)}h)"
          end

          logger.debug('Rate limit check passed',
                       minute_requests: @minute_requests.length,
                       hour_requests: @hour_requests.length,
                       day_requests: @day_requests.length)
        end

        # Record a request
        def record_request
          now = Time.now
          cleanup_old_requests(now)

          @minute_requests << now
          @hour_requests << now
          @day_requests << now

          logger.debug('Request recorded',
                       minute_count: @minute_requests.length,
                       hour_count: @hour_requests.length,
                       day_count: @day_requests.length)
        end

        # Get current rate limit status
        #
        # @return [Hash] Rate limit status information
        def status
          now = Time.now
          cleanup_old_requests(now)

          {
            per_minute: {
              requests: @minute_requests.length,
              limit: @requests_per_minute,
              remaining: @requests_per_minute ? (@requests_per_minute - @minute_requests.length) : nil
            },
            per_hour: {
              requests: @hour_requests.length,
              limit: @requests_per_hour,
              remaining: @requests_per_hour ? (@requests_per_hour - @hour_requests.length) : nil
            },
            per_day: {
              requests: @day_requests.length,
              limit: @requests_per_day,
              remaining: @requests_per_day ? (@requests_per_day - @day_requests.length) : nil
            }
          }
        end

        private

        def logger_component
          'Safety::RateLimiter'
        end

        def cleanup_old_requests(now)
          # Remove requests older than 1 minute
          @minute_requests.reject! { |t| (now - t) > 60 }

          # Remove requests older than 1 hour
          @hour_requests.reject! { |t| (now - t) > 3600 }

          # Remove requests older than 1 day
          @day_requests.reject! { |t| (now - t) > 86_400 }
        end
      end
    end
  end
end
