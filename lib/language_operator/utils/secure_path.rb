# frozen_string_literal: true

require 'pathname'

module LanguageOperator
  module Utils
    # Secure path utilities to prevent path traversal attacks
    # when expanding user home directory paths
    class SecurePath
      # Default fallback directory for untrusted HOME environments
      DEFAULT_HOME = '/tmp'

      class << self
        # Securely expand a path relative to user home directory
        # Prevents path traversal attacks via malicious HOME environment variable
        #
        # @param relative_path [String] Path relative to home (e.g., '.kube/config')
        # @return [String] Safe absolute path
        def expand_home_path(relative_path)
          home_dir = secure_home_directory
          File.join(home_dir, relative_path)
        end

        # Get user home directory with security validation
        # Falls back to safe default if HOME environment variable is suspicious
        #
        # @return [String] Validated home directory path
        def secure_home_directory
          home = ENV.fetch('HOME', DEFAULT_HOME)

          # Validate HOME is safe to use
          return DEFAULT_HOME unless home_directory_safe?(home)

          home
        end

        private

        # Validate that a home directory path is safe to use
        # Prevents path traversal and access to sensitive system directories
        #
        # @param path [String] Home directory path to validate
        # @return [Boolean] true if safe to use
        def home_directory_safe?(path)
          # Basic safety checks
          return false if path.nil? || path.empty?
          return false if path.include?('../')  # Path traversal
          return false if path.include?('/..')  # Path traversal
          return false unless Pathname.new(path).absolute? # Must be absolute

          # Dangerous system paths
          dangerous_prefixes = [
            '/etc',        # System configuration
            '/proc',       # Process information
            '/sys',        # System information
            '/dev',        # Device files
            '/boot',       # Boot files
            '/root'        # Root user home (should use /root/.kube not accessible via ~)
          ]

          dangerous_prefixes.each do |prefix|
            return false if path.start_with?(prefix)
          end

          # Directory must exist and be readable
          File.directory?(path) && File.readable?(path)
        rescue SystemCallError
          # If we can't check the directory, assume it's unsafe
          false
        end
      end
    end
  end
end
