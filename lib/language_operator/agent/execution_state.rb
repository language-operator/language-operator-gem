# frozen_string_literal: true

module LanguageOperator
  module Agent
    # Execution State Manager
    #
    # Manages the execution state of agents to prevent concurrent executions.
    # Thread-safe implementation ensures only one execution runs at a time.
    #
    # @example Check if execution is running
    #   state = ExecutionState.new
    #   state.running? # => false
    #
    # @example Start an execution
    #   state.start_execution('exec-123')
    #   state.running? # => true
    class ExecutionState
      attr_reader :current_execution_id, :started_at, :status

      # Initialize a new execution state
      def initialize
        @mutex = Mutex.new
        @current_execution_id = nil
        @started_at = nil
        @status = :idle # :idle, :running, :completed, :failed
      end

      # Start a new execution
      #
      # @param execution_id [String] Unique identifier for the execution
      # @raise [ExecutionInProgressError] if an execution is already running
      # @return [void]
      def start_execution(execution_id)
        @mutex.synchronize do
          if @status == :running
            raise ExecutionInProgressError,
                  "Execution #{@current_execution_id} already running"
          end

          @current_execution_id = execution_id
          @started_at = Time.now
          @status = :running
        end
      end

      # Mark execution as completed
      #
      # @param result [Object] Optional execution result
      # @return [Object] The result passed in
      def complete_execution(result = nil)
        @mutex.synchronize do
          @status = :completed
          result
        end
      end

      # Mark execution as failed
      #
      # @param error [StandardError] The error that caused the failure
      # @return [void]
      def fail_execution(error)
        @mutex.synchronize do
          @status = :failed
          @last_error = error
        end
      end

      # Check if an execution is currently running
      #
      # @return [Boolean] true if execution is in progress
      def running?
        @mutex.synchronize { @status == :running }
      end

      # Get current execution information
      #
      # @return [Hash] Current execution state details
      def current_info
        @mutex.synchronize do
          {
            status: @status,
            execution_id: @current_execution_id,
            started_at: @started_at
          }
        end
      end
    end

    # Error raised when attempting to start an execution while one is already running
    class ExecutionInProgressError < StandardError; end
  end
end
