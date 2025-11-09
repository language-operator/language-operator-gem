# frozen_string_literal: true

require 'shellwords'
require 'open3'
require 'timeout'

module LanguageOperator
  module Dsl
    # Safe shell command execution for MCP tools
    #
    # Provides methods for executing shell commands safely with automatic
    # argument escaping to prevent injection attacks. All methods are class methods.
    #
    # @example Basic usage
    #   result = Shell.run('ls', '-la', '/tmp')
    #   if result[:success]
    #     puts result[:output]
    #   end
    #
    # @example Safe user input
    #   # User input is automatically escaped
    #   result = Shell.run('grep', user_input, '/etc/hosts')
    module Shell
      # Run a shell command with properly escaped arguments
      #
      # This is safer than using backticks as it prevents shell injection.
      # Arguments are automatically escaped using Shellwords.
      #
      # @param cmd [String] Command to execute
      # @param args [Array<String>] Arguments (will be escaped)
      # @param env [Hash] Environment variables to set
      # @param chdir [String, nil] Working directory
      # @param timeout [Integer] Timeout in seconds (default: 30)
      # @return [Hash] Result with :success, :output, :error, :exitcode, :timeout keys
      def self.run(cmd, *args, env: {}, chdir: nil, timeout: 30)
        # Escape all arguments
        escaped_args = args.map { |arg| Shellwords.escape(arg.to_s) }
        full_cmd = "#{cmd} #{escaped_args.join(' ')}"

        # Execute with timeout
        stdout = nil
        stderr = nil
        status = nil

        begin
          Timeout.timeout(timeout) do
            stdout, stderr, status = Open3.capture3(env, full_cmd, chdir: chdir)
          end
        rescue Timeout::Error
          return {
            success: false,
            output: '',
            error: "Command timed out after #{timeout} seconds",
            exitcode: -1,
            timeout: true
          }
        rescue StandardError => e
          return {
            success: false,
            output: '',
            error: e.message,
            exitcode: -1
          }
        end

        {
          success: status.success?,
          output: stdout,
          error: stderr,
          exitcode: status.exitstatus,
          timeout: false
        }
      end

      # Run a command and return only stdout (like backticks)
      # Returns nil if the command fails
      def self.capture(cmd, *, **)
        result = run(cmd, *, **)
        result[:success] ? result[:output] : nil
      end

      # Run a command and return stdout, raising on failure
      def self.capture!(cmd, *, **)
        result = run(cmd, *, **)
        raise "Command failed (exit #{result[:exitcode]}): #{result[:error]}" unless result[:success]

        result[:output]
      end

      # Check if a command exists in PATH
      def self.command_exists?(cmd)
        result = run('which', cmd)
        result[:success]
      end

      # Run a command in the background and return immediately
      # @deprecated This method has been removed for security reasons
      # @raise [SecurityError] Always raises an error
      def self.spawn(_cmd, *_args, env: {}, chdir: nil)
        raise SecurityError, 'Shell.spawn has been removed for security reasons. Background process execution is not allowed in synthesized code.'
      end

      # Execute raw shell command (REMOVED FOR SECURITY)
      # This method has been removed as it allowed arbitrary shell execution
      # with pipes, redirects, etc. which is a security risk in synthesized code.
      # @deprecated This method has been removed for security reasons
      # @raise [SecurityError] Always raises an error
      def self.raw(_command, env: {}, chdir: nil, timeout: 30)
        raise SecurityError, 'Shell.raw has been removed for security reasons. Use Shell.run with explicit arguments instead.'
      end

      # Safely build a command string with escaped arguments
      # Useful when you need to construct a command but not execute it yet
      def self.build(cmd, *args)
        escaped_args = args.map { |arg| Shellwords.escape(arg.to_s) }
        "#{cmd} #{escaped_args.join(' ')}"
      end

      # Escape a single argument for shell usage
      def self.escape(arg)
        Shellwords.escape(arg.to_s)
      end
    end
  end
end
