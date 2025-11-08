# frozen_string_literal: true

require_relative '../../logger'
require_relative '../../loggable'

module LanguageOperator
  module Agent
    module Safety
      # Content Filter for pre-prompt and post-response filtering
      #
      # Supports pattern matching for blocked keywords and topics.
      # Can be extended to integrate with moderation APIs.
      #
      # @example
      #   filter = ContentFilter.new(blocked_patterns: ['password', 'secret'])
      #   filter.check_content!("Here is my password: 12345", direction: :input)
      class ContentFilter
        include LanguageOperator::Loggable

        class ContentBlockedError < StandardError; end

        def initialize(blocked_patterns: [], blocked_topics: [], case_sensitive: false)
          @blocked_patterns = blocked_patterns || []
          @blocked_topics = blocked_topics || []
          @case_sensitive = case_sensitive

          logger.info('Content filter initialized',
                      patterns: @blocked_patterns.length,
                      topics: @blocked_topics.length,
                      case_sensitive: @case_sensitive)
        end

        # Check content for blocked patterns
        #
        # @param content [String] Content to check
        # @param direction [Symbol] :input or :output
        # @raise [ContentBlockedError] If content contains blocked patterns
        def check_content!(content, direction: :input)
          return if @blocked_patterns.empty? && @blocked_topics.empty?

          content_to_check = @case_sensitive ? content : content.downcase

          # Check blocked patterns
          @blocked_patterns.each do |pattern|
            pattern_to_match = @case_sensitive ? pattern : pattern.downcase
            next unless content_to_check.include?(pattern_to_match)

            logger.warn('Blocked pattern detected',
                        direction: direction,
                        pattern: pattern,
                        content_preview: content[0..100])
            raise ContentBlockedError,
                  "Content blocked: contains forbidden pattern '#{pattern}' in #{direction}"
          end

          # Check blocked topics (using regex patterns)
          @blocked_topics.each do |topic|
            pattern = @case_sensitive ? Regexp.new(topic) : Regexp.new(topic, Regexp::IGNORECASE)
            next unless content_to_check.match?(pattern)

            logger.warn('Blocked topic detected',
                        direction: direction,
                        topic: topic,
                        content_preview: content[0..100])
            raise ContentBlockedError,
                  "Content blocked: matches forbidden topic '#{topic}' in #{direction}"
          end

          logger.debug('Content check passed',
                       direction: direction,
                       content_length: content.length)
        end

        # Check if content would be blocked (without raising)
        #
        # @param content [String] Content to check
        # @return [Boolean] True if content would be blocked
        def blocked?(content)
          check_content!(content)
          false
        rescue ContentBlockedError
          true
        end

        private

        def logger_component
          'Safety::ContentFilter'
        end
      end
    end
  end
end
