# frozen_string_literal: true

require 'uri'

module LanguageOperator
  # Common parameter validation utilities
  #
  # Provides reusable validators for common parameter validation patterns
  # across tools. All validators follow the same convention:
  # - Return `nil` if the value is valid
  # - Return an error string if the value is invalid
  #
  # This allows for consistent usage in tools:
  #   error = LanguageOperator::Validators.http_url(params['url'])
  #   next error if error
  #
  # @example URL validation
  #   error = Validators.http_url('https://example.com')
  #   # => nil (valid)
  #
  #   error = Validators.http_url('ftp://example.com')
  #   # => "Error: Invalid URL. Must start with http:// or https://"
  #
  # @example Enum validation
  #   error = Validators.one_of('GET', %w[GET POST PUT DELETE], 'HTTP method')
  #   # => nil (valid)
  #
  #   error = Validators.one_of('INVALID', %w[GET POST PUT DELETE], 'HTTP method')
  #   # => "Error: Invalid HTTP method 'INVALID'. Expected: one of: GET, POST, PUT, DELETE"
  module Validators
    # Validate HTTP/HTTPS URL format
    #
    # @param url [String] URL to validate
    # @return [String, nil] Error message if invalid, nil if valid
    #
    # @example Valid URLs
    #   Validators.http_url('http://example.com')  # => nil
    #   Validators.http_url('https://api.example.com/v1')  # => nil
    #
    # @example Invalid URLs
    #   Validators.http_url('')  # => "Error: URL cannot be empty"
    #   Validators.http_url('ftp://example.com')  # => "Error: Invalid URL..."
    def self.http_url(url)
      return 'Error: URL cannot be empty' if url.nil? || url.strip.empty?
      return nil if url =~ %r{^https?://.+}

      'Error: Invalid URL. Must start with http:// or https://'
    end

    # Validate that a value is not nil or empty
    #
    # @param value [Object] Value to check
    # @param field_name [String] Name of the field for error message
    # @return [String, nil] Error message if invalid, nil if valid
    #
    # @example Valid values
    #   Validators.not_empty('value', 'Name')  # => nil
    #   Validators.not_empty('  text  ', 'Name')  # => nil (has content after strip)
    #
    # @example Invalid values
    #   Validators.not_empty(nil, 'Name')  # => "Error: Name cannot be empty"
    #   Validators.not_empty('', 'Name')  # => "Error: Name cannot be empty"
    #   Validators.not_empty('   ', 'Name')  # => "Error: Name cannot be empty"
    def self.not_empty(value, field_name)
      return nil if value && !value.to_s.strip.empty?

      LanguageOperator::Errors.empty_field(field_name)
    end

    # Validate that a value is one of the allowed options
    #
    # @param value [String] Value to validate
    # @param allowed [Array<String>] Allowed values
    # @param field_name [String] Field name for error message
    # @return [String, nil] Error message if invalid, nil if valid
    #
    # @example Valid choice
    #   Validators.one_of('GET', %w[GET POST PUT], 'method')  # => nil
    #
    # @example Invalid choice
    #   Validators.one_of('DELETE', %w[GET POST PUT], 'method')
    #   # => "Error: Invalid method 'DELETE'. Expected: one of: GET, POST, PUT"
    def self.one_of(value, allowed, field_name)
      return nil if allowed.include?(value)

      LanguageOperator::Errors.invalid_parameter(
        field_name,
        value,
        "one of: #{allowed.join(', ')}"
      )
    end

    # Validate numeric range
    #
    # @param value [Numeric] Value to validate
    # @param min [Numeric, nil] Minimum value (inclusive)
    # @param max [Numeric, nil] Maximum value (inclusive)
    # @param field_name [String] Field name for error message
    # @return [String, nil] Error message if invalid, nil if valid
    #
    # @example Valid ranges
    #   Validators.numeric_range(5, min: 1, max: 10)  # => nil
    #   Validators.numeric_range(100, min: 50)  # => nil
    #   Validators.numeric_range(5, max: 10)  # => nil
    #
    # @example Invalid ranges
    #   Validators.numeric_range('foo', min: 1)  # => "Error: value must be a number"
    #   Validators.numeric_range(0, min: 1)  # => "Error: value must be at least 1"
    #   Validators.numeric_range(100, max: 50)  # => "Error: value must be at most 50"
    def self.numeric_range(value, min: nil, max: nil, field_name: 'value')
      return "Error: #{field_name} must be a number" unless value.is_a?(Numeric)

      return "Error: #{field_name} must be at least #{min}" if min && value < min

      return "Error: #{field_name} must be at most #{max}" if max && value > max

      nil
    end

    # Validate email address format (basic)
    #
    # Note: This is a basic format check, not full RFC 5322 validation.
    # It checks for: something@domain.tld
    #
    # @param email [String] Email address to validate
    # @return [String, nil] Error message if invalid, nil if valid
    #
    # @example Valid emails
    #   Validators.email('user@example.com')  # => nil
    #   Validators.email('test.user+tag@domain.co.uk')  # => nil
    #
    # @example Invalid emails
    #   Validators.email('')  # => "Error: Email address cannot be empty"
    #   Validators.email('invalid')  # => "Error: Invalid email address format"
    #   Validators.email('@example.com')  # => "Error: Invalid email address format"
    def self.email(email)
      return 'Error: Email address cannot be empty' if email.nil? || email.strip.empty?
      return nil if email =~ /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      'Error: Invalid email address format'
    end

    # Validate that a path doesn't contain directory traversal attempts
    #
    # Checks for:
    # - Parent directory references (..)
    # - Null bytes (\0)
    #
    # Note: This is a basic safety check. Tool-specific path validation
    # (like workspace sandboxing) should still be implemented in the tools.
    #
    # @param path [String] Path to validate
    # @return [String, nil] Error message if invalid, nil if valid
    #
    # @example Valid paths
    #   Validators.safe_path('/absolute/path')  # => nil
    #   Validators.safe_path('relative/path.txt')  # => nil
    #
    # @example Invalid paths
    #   Validators.safe_path('')  # => "Error: Path cannot be empty"
    #   Validators.safe_path('../../../etc/passwd')  # => "Error: Path contains..."
    #   Validators.safe_path('%2e%2e%2fetc%2fpasswd')  # => "Error: Path contains..."
    #   Validators.safe_path("file\0name")  # => "Error: Path contains..."
    def self.safe_path(path)
      return 'Error: Path cannot be empty' if path.nil? || path.strip.empty?

      # Check for null bytes first (before any decoding)
      return 'Error: Path contains invalid characters or directory traversal' if path.include?("\0")

      begin
        # Decode URL-encoded paths to catch encoded traversal attempts
        # Handle multiple layers of encoding by repeatedly decoding
        decoded_path = path
        3.times do # Limit to prevent infinite loops
          new_decoded = URI::DEFAULT_PARSER.unescape(decoded_path)
          break if new_decoded == decoded_path # No more changes

          decoded_path = new_decoded
        rescue ArgumentError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
          # Invalid byte sequence - treat as potential attack
          return 'Error: Path contains invalid characters or directory traversal'
        end

        # Check for directory traversal in both original and decoded paths
        [path, decoded_path].each do |check_path|
          # Check for obvious traversal patterns
          return 'Error: Path contains invalid characters or directory traversal' if check_path.include?('..')

          # Check for overlong UTF-8 sequences that decode to dangerous characters
          # These are common in directory traversal attacks
          if check_path.include?("\xC0\xAE") || check_path.include?("\xC0\xAF") ||
             check_path.bytes.each_cons(2).any? { |a, b| a == 0xC0 && (0x80..0xBF).cover?(b) }
            return 'Error: Path contains invalid characters or directory traversal'
          end

          # Canonicalize path to detect complex traversal attempts
          begin
            # Use current directory as base for relative paths
            canonical_path = File.expand_path(check_path, Dir.pwd)

            # For relative paths, ensure they don't escape current directory
            unless check_path.start_with?('/')
              current_dir_canonical = File.expand_path(Dir.pwd)
              return 'Error: Path contains invalid characters or directory traversal' unless canonical_path.start_with?(current_dir_canonical)
            end

            # Additional check: ensure canonical path doesn't contain dangerous patterns
            return 'Error: Path contains invalid characters or directory traversal' if canonical_path.include?('/../') || canonical_path.end_with?('/..')
          rescue ArgumentError, Errno::ENOENT
            # Path canonicalization failed, likely due to invalid characters
            return 'Error: Path contains invalid characters or directory traversal'
          end
        end
      rescue URI::InvalidURIError
        # URL decoding failed, path might contain invalid sequences
        return 'Error: Path contains invalid characters or directory traversal'
      end

      nil
    end
  end
end
