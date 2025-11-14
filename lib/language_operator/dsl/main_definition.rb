# frozen_string_literal: true

require_relative '../loggable'

module LanguageOperator
  module Dsl
    # Main execution block for agents (DSL v1)
    #
    # Defines the imperative entry point for agent execution. The main block receives
    # agent inputs and returns agent outputs. Within the block, agents can call tasks
    # using execute_task(), use standard Ruby control flow (if/else, loops), and handle
    # errors with standard Ruby exceptions.
    #
    # This replaces the declarative workflow/step model with an imperative programming
    # model centered on organic functions (tasks).
    #
    # @example Simple main block
    #   main do |inputs|
    #     result = execute_task(:fetch_data, inputs: inputs)
    #     execute_task(:process_data, inputs: result)
    #   end
    #
    # @example Main block with control flow
    #   main do |inputs|
    #     data = execute_task(:fetch_data, inputs: inputs)
    #
    #     if data[:count] > 100
    #       execute_task(:send_alert, inputs: { count: data[:count] })
    #     end
    #
    #     execute_task(:save_results, inputs: data)
    #   end
    #
    # @example Main block with error handling
    #   main do |inputs|
    #     begin
    #       result = execute_task(:risky_operation, inputs: inputs)
    #       { success: true, result: result }
    #     rescue => e
    #       logger.error("Operation failed: #{e.message}")
    #       { success: false, error: e.message }
    #     end
    #   end
    class MainDefinition
      include LanguageOperator::Loggable

      attr_reader :execute_block

      # Initialize a new main definition
      def initialize
        @execute_block = nil
      end

      # Define the main execution block
      #
      # @yield [inputs] Block that receives agent inputs and returns agent outputs
      # @yieldparam inputs [Hash] Agent input parameters
      # @yieldreturn [Object] Agent output (typically a Hash)
      # @return [void]
      # @example
      #   execute do |inputs|
      #     result = execute_task(:my_task, inputs: inputs)
      #     result
      #   end
      def execute(&block)
        raise ArgumentError, 'Main block is required' unless block

        @execute_block = block
        logger.debug('Main block defined', arity: block.arity)
      end

      # Execute the main block with given inputs
      #
      # @param inputs [Hash] Agent input parameters
      # @param context [Object] Execution context that provides execute_task method
      # @return [Object] Result from main block
      # @raise [RuntimeError] If main block is not defined
      # @raise [ArgumentError] If inputs is not a Hash
      def call(inputs, context)
        raise 'Main block not defined. Use execute { |inputs| ... } to define it.' unless @execute_block
        raise ArgumentError, "inputs must be a Hash, got #{inputs.class}" unless inputs.is_a?(Hash)

        logger.info('Executing main block', inputs_keys: inputs.keys)

        result = logger.timed('Main execution') do
          # Execute block in context to provide access to execute_task
          context.instance_exec(inputs, &@execute_block)
        end

        logger.info('Main block completed')
        result
      rescue StandardError => e
        logger.error('Main block execution failed',
                     error: e.class.name,
                     message: e.message,
                     backtrace: e.backtrace&.first(5))
        raise
      end

      # Check if main block is defined
      #
      # @return [Boolean] True if execute block is set
      def defined?
        !@execute_block.nil?
      end

      private

      def logger_component
        'Main'
      end
    end
  end
end
