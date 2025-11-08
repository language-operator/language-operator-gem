# frozen_string_literal: true

module LanguageOperator
  # Retry utilities with exponential backoff for handling transient failures
  module Retry
    # Default retry configuration
    DEFAULT_MAX_RETRIES = 3
    DEFAULT_BASE_DELAY = 1.0
    DEFAULT_MAX_DELAY = 10.0
    DEFAULT_JITTER_FACTOR = 0.1

    # Common retryable HTTP status codes (transient errors)
    RETRYABLE_HTTP_CODES = [429, 500, 502, 503, 504].freeze

    # Execute a block with exponential backoff retry logic
    # @param max_retries [Integer] Maximum number of retry attempts (default: 3)
    # @param base_delay [Float] Initial delay in seconds (default: 1.0)
    # @param max_delay [Float] Maximum delay cap in seconds (default: 10.0)
    # @param jitter_factor [Float] Jitter randomization factor (default: 0.1)
    # @param on_retry [Proc] Optional callback called before each retry (receives attempt number and exception)
    # @yield Block to execute with retry logic
    # @return [Object] Return value of the block
    # @raise [StandardError] Re-raises the exception if all retries are exhausted
    #
    # @example Basic usage
    #   LanguageOperator::Retry.with_backoff(max_retries: 5) do
    #     client.get_resource(name)
    #   end
    #
    # @example With callback
    #   LanguageOperator::Retry.with_backoff(on_retry: ->(attempt, e) {
    #     puts "Retry attempt #{attempt} after error: #{e.message}"
    #   }) do
    #     api_call
    #   end
    def self.with_backoff(max_retries: DEFAULT_MAX_RETRIES,
                          base_delay: DEFAULT_BASE_DELAY,
                          max_delay: DEFAULT_MAX_DELAY,
                          jitter_factor: DEFAULT_JITTER_FACTOR,
                          on_retry: nil)
      attempt = 0
      begin
        yield
      rescue StandardError => e
        if attempt < max_retries
          attempt += 1
          delay = calculate_backoff(attempt, base_delay, max_delay, jitter_factor)
          on_retry&.call(attempt, e)
          sleep delay
          retry
        end
        raise e
      end
    end

    # Execute a block with retry for specific exception types
    # @param exception_types [Array<Class>] Exception types to retry on
    # @param max_retries [Integer] Maximum number of retry attempts
    # @param base_delay [Float] Initial delay in seconds
    # @param max_delay [Float] Maximum delay cap in seconds
    # @param jitter_factor [Float] Jitter randomization factor
    # @yield Block to execute
    # @return [Object] Return value of the block
    # @raise [StandardError] Re-raises the exception if all retries are exhausted
    #
    # @example
    #   LanguageOperator::Retry.on_exceptions([Net::OpenTimeout, Errno::ECONNREFUSED]) do
    #     smtp.connect
    #   end
    def self.on_exceptions(exception_types, max_retries: DEFAULT_MAX_RETRIES,
                           base_delay: DEFAULT_BASE_DELAY,
                           max_delay: DEFAULT_MAX_DELAY,
                           jitter_factor: DEFAULT_JITTER_FACTOR)
      attempt = 0
      begin
        yield
      rescue *exception_types => e
        if attempt < max_retries
          attempt += 1
          delay = calculate_backoff(attempt, base_delay, max_delay, jitter_factor)
          sleep delay
          retry
        end
        raise e
      end
    end

    # Check if an HTTP status code is retryable (transient error)
    # @param status [Integer] HTTP status code
    # @return [Boolean] True if status code indicates a transient error
    #
    # @example
    #   LanguageOperator::Retry.retryable_http_code?(503) # => true
    #   LanguageOperator::Retry.retryable_http_code?(404) # => false
    def self.retryable_http_code?(status)
      RETRYABLE_HTTP_CODES.include?(status)
    end

    # Calculate exponential backoff delay with jitter
    # @param attempt [Integer] Retry attempt number (1-based)
    # @param base_delay [Float] Initial delay in seconds
    # @param max_delay [Float] Maximum delay cap in seconds
    # @param jitter_factor [Float] Jitter randomization factor (0.0 to 1.0)
    # @return [Float] Delay in seconds
    #
    # @example
    #   LanguageOperator::Retry.calculate_backoff(1) # => ~1.0 seconds
    #   LanguageOperator::Retry.calculate_backoff(2) # => ~2.0 seconds
    #   LanguageOperator::Retry.calculate_backoff(3) # => ~4.0 seconds
    def self.calculate_backoff(attempt,
                               base_delay = DEFAULT_BASE_DELAY,
                               max_delay = DEFAULT_MAX_DELAY,
                               jitter_factor = DEFAULT_JITTER_FACTOR)
      # Exponential: base * 2^(attempt-1)
      exponential = base_delay * (2**(attempt - 1))
      # Cap at max
      capped = [exponential, max_delay].min
      # Add jitter: ±(delay * jitter_factor * random)
      jitter = capped * jitter_factor * (rand - 0.5) * 2
      capped + jitter
    end
  end
end
