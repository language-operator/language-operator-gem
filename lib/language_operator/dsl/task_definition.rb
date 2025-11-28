# frozen_string_literal: true

require_relative '../loggable'
require_relative '../type_coercion'
require_relative '../agent/task_executor'

module LanguageOperator
  module Dsl
    # Task definition for organic functions (DSL v1)
    #
    # Represents an organic function with a stable contract (inputs/outputs) where
    # the implementation can evolve from neural (instructions-based) to symbolic
    # (explicit code) without breaking callers.
    #
    # @example Neural task (LLM-based)
    #   task :analyze_data,
    #     instructions: "Analyze the data for anomalies",
    #     inputs: { data: 'array' },
    #     outputs: { issues: 'array', summary: 'string' }
    #
    # @example Symbolic task (explicit code)
    #   task :calculate_total,
    #     inputs: { items: 'array' },
    #     outputs: { total: 'number' }
    #   do |inputs|
    #     { total: inputs[:items].sum { |i| i['amount'] } }
    #   end
    #
    # @example Hybrid task (both instructions and code)
    #   task :fetch_user,
    #     instructions: "Fetch user data from database",
    #     inputs: { user_id: 'integer' },
    #     outputs: { user: 'hash', preferences: 'hash' }
    #   do |inputs|
    #     execute_tool('database', 'get_user', id: inputs[:user_id])
    #   end
    class TaskDefinition
      include LanguageOperator::Loggable

      attr_reader :name, :inputs_schema, :outputs_schema, :instructions_text, :execute_block

      # Supported types for input/output validation
      SUPPORTED_TYPES = %w[string integer number boolean array hash any].freeze

      # Initialize a new task definition
      #
      # @param name [Symbol] Task name
      def initialize(name)
        @name = name
        @inputs_schema = {}
        @outputs_schema = {}
        @instructions_text = nil
        @execute_block = nil
      end

      # Define or retrieve the input contract
      #
      # @param schema [Hash, nil] Input schema (param_name => type_string)
      # @return [Hash] Current input schema
      # @example
      #   inputs { user_id: 'integer', filter: 'string' }
      def inputs(schema = nil)
        return @inputs_schema if schema.nil?

        validate_schema!(schema, 'inputs')
        @inputs_schema = schema
      end

      # Define or retrieve the output contract
      #
      # @param schema [Hash, nil] Output schema (field_name => type_string)
      # @return [Hash] Current output schema
      # @example
      #   outputs { user: 'hash', success: 'boolean' }
      def outputs(schema = nil)
        return @outputs_schema if schema.nil?

        validate_schema!(schema, 'outputs')
        @outputs_schema = schema
      end

      # Define or retrieve the instructions (neural implementation)
      #
      # @param text [String, nil] Natural language instructions
      # @return [String, nil] Current instructions
      # @example
      #   instructions "Fetch user data from the database"
      def instructions(text = nil)
        return @instructions_text if text.nil?

        @instructions_text = text
      end

      # Define the symbolic implementation
      #
      # @yield [inputs] Block that receives validated inputs and returns outputs
      # @yieldparam inputs [Hash] Validated and coerced input parameters
      # @yieldreturn [Hash] Output values matching the outputs schema
      # @example
      #   execute do |inputs|
      #     { total: inputs[:items].sum { |i| i['amount'] } }
      #   end
      def execute(&block)
        @execute_block = block if block
      end

      # Check if this is a neural task (instructions-based)
      #
      # @return [Boolean] True if instructions are defined
      def neural?
        !@instructions_text.nil?
      end

      # Check if this is a symbolic task (code-based)
      #
      # @return [Boolean] True if execute block is defined
      def symbolic?
        !@execute_block.nil?
      end

      # Execute the task with given inputs
      #
      # @param input_params [Hash] Input parameters
      # @param context [Object, nil] Execution context (optional)
      # @return [Hash] Validated output matching outputs schema
      # @raise [ArgumentError] If inputs or outputs don't match schema
      def call(input_params, context = nil)
        # Validate and coerce inputs
        validated_inputs = validate_inputs(input_params)

        # Execute based on implementation type
        result = if symbolic?
                   # Symbolic execution (explicit code)
                   logger.debug('Executing symbolic task', task: @name)
                   execute_symbolic(validated_inputs, context)
                 elsif neural?
                   # Neural execution (LLM-based)
                   logger.debug('Executing neural task', task: @name, instructions: @instructions_text)
                   execute_neural(validated_inputs, context)
                 else
                   raise "Task #{@name} has no implementation (neither neural nor symbolic)"
                 end

        # Validate outputs
        validate_outputs(result)
      end

      # Validate input parameters against schema
      #
      # @param params [Hash] Input parameters
      # @return [Hash] Validated and coerced parameters
      # @raise [ArgumentError] If validation fails
      def validate_inputs(params)
        params = params.transform_keys(&:to_sym)
        validated = {}

        @inputs_schema.each do |key, type|
          key_sym = key.to_sym
          value = params[key_sym]

          raise ArgumentError, "Missing required input parameter: #{key}" if value.nil?

          validated[key_sym] = coerce_value(value, type, "input parameter '#{key}'")
        end

        # Check for unexpected parameters
        extra_keys = params.keys - @inputs_schema.keys.map(&:to_sym)
        logger.warn('Unexpected input parameters', task: @name, extra: extra_keys) unless extra_keys.empty?

        validated
      end

      # Validate output values against schema
      #
      # @param result [Hash] Output values
      # @return [Hash] Validated and coerced outputs
      # @raise [ArgumentError] If validation fails
      def validate_outputs(result)
        return result if @outputs_schema.empty? # No schema = no validation

        result = result.transform_keys(&:to_sym)
        validated = {}

        @outputs_schema.each do |key, type|
          key_sym = key.to_sym
          value = result[key_sym]

          raise ArgumentError, "Missing required output field: #{key}" if value.nil?

          validated[key_sym] = coerce_value(value, type, "output field '#{key}'")
        end

        validated
      end

      # Export task as JSON schema
      #
      # @return [Hash] JSON Schema representation
      def to_schema
        {
          'name' => @name.to_s,
          'type' => implementation_type,
          'instructions' => @instructions_text,
          'inputs' => schema_to_json(@inputs_schema),
          'outputs' => schema_to_json(@outputs_schema)
        }
      end

      private

      def logger_component
        "Task:#{@name}"
      end

      # Determine implementation type
      #
      # @return [String] 'neural', 'symbolic', or 'hybrid'
      def implementation_type
        if neural? && symbolic?
          'hybrid'
        elsif neural?
          'neural'
        elsif symbolic?
          'symbolic'
        else
          'undefined'
        end
      end

      # Execute symbolic implementation
      #
      # @param inputs [Hash] Validated inputs
      # @param context [Object, nil] Execution context (TaskExecutor)
      # @return [Hash] Result from execute block
      def execute_symbolic(inputs, context)
        if context
          # Execute block in context's scope to make helper methods available
          # (execute_tool, execute_task, execute_llm, etc.)
          context.instance_exec(inputs, &@execute_block)
        else
          # Fallback for standalone execution without context
          @execute_block.call(inputs)
        end
      end

      # Execute neural implementation (stub for now)
      #
      # @param inputs [Hash] Validated inputs
      # @param context [Object, nil] Execution context
      # @return [Hash] Result from LLM
      # @note This is a placeholder - actual neural execution happens in agent runtime
      def execute_neural(inputs, context)
        raise NotImplementedError, 'Neural task execution requires agent runtime context. ' \
                                   "Task #{@name} should be executed via execute_task() in agent main block."
      end

      # Validate a schema hash
      #
      # @param schema [Hash] Schema to validate
      # @param name [String] Schema name (for error messages)
      # @raise [ArgumentError] If schema is invalid
      def validate_schema!(schema, name)
        raise ArgumentError, "#{name} schema must be a Hash, got #{schema.class}" unless schema.is_a?(Hash)

        schema.each do |key, type|
          unless type.is_a?(String) && SUPPORTED_TYPES.include?(type)
            raise ArgumentError, "#{name} schema type for '#{key}' must be one of #{SUPPORTED_TYPES.join(', ')}, " \
                                 "got '#{type}'"
          end
        end
      end

      # Coerce a value to the specified type
      #
      # @param value [Object] Value to coerce
      # @param type [String] Target type
      # @param context [String] Context for error messages
      # @return [Object] Coerced value
      # @raise [LanguageOperator::Agent::TaskValidationError] If coercion fails
      def coerce_value(value, type, context)
        TypeCoercion.coerce(value, type)
      rescue ArgumentError => e
        # Re-raise as TaskValidationError with context added
        raise LanguageOperator::Agent::TaskValidationError.new(@name, "#{e.message} for #{context}", e)
      end

      # Convert schema hash to JSON Schema format
      #
      # @param schema [Hash] Type schema
      # @return [Hash] JSON Schema
      def schema_to_json(schema)
        {
          'type' => 'object',
          'properties' => schema.transform_values { |type| { 'type' => map_type_to_json_schema(type) } },
          'required' => schema.keys.map(&:to_s)
        }
      end

      # Map internal type to JSON Schema type
      #
      # @param type [String] Internal type name
      # @return [String] JSON Schema type
      def map_type_to_json_schema(type)
        case type
        when 'integer' then 'integer'
        when 'number' then 'number'
        when 'string' then 'string'
        when 'boolean' then 'boolean'
        when 'array' then 'array'
        when 'hash' then 'object'
        when 'any' then 'any'
        else type
        end
      end
    end
  end
end
