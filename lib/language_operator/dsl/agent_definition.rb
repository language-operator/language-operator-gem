# frozen_string_literal: true

require_relative 'main_definition'
require_relative 'task_definition'
require_relative 'webhook_definition'
require_relative 'mcp_server_definition'
require_relative 'chat_endpoint_definition'
require_relative '../logger'
require_relative '../loggable'

module LanguageOperator
  module Dsl
    # Agent definition for autonomous agents
    #
    # Defines an agent with objectives, tasks, main execution block, schedule, and constraints.
    # Used within the DSL to create agents that can be executed standalone
    # or deployed to Kubernetes.
    #
    # @example Define a simple scheduled agent
    #   agent "news-summarizer" do
    #     description "Daily news summarization agent"
    #
    #     schedule "0 12 * * *"
    #
    #     task :search,
    #       instructions: "search for latest news",
    #       inputs: {},
    #       outputs: { results: 'array' }
    #
    #     main do |inputs|
    #       results = execute_task(:search)
    #       results
    #     end
    #   end
    #
    # @example Define a webhook agent
    #   agent "github-webhook" do
    #     description "Handle GitHub webhooks"
    #     mode :reactive
    #
    #     webhook "/github/pr-opened" do
    #       method :post
    #       on_request do |context|
    #         # Process webhook
    #       end
    #     end
    #   end
    class AgentDefinition
      include LanguageOperator::Loggable

      attr_reader :name, :description, :persona, :schedule, :objectives, :main, :tasks,
                  :constraints, :output_config, :execution_mode, :webhooks, :mcp_server, :chat_endpoint

      def initialize(name)
        @name = name
        @description = nil
        @persona = nil
        @schedule = nil
        @objectives = []
        @main = nil
        @tasks = {}
        @constraints = {}
        @output_config = nil
        @execution_mode = :autonomous
        @webhooks = []
        @mcp_server = nil
        @chat_endpoint = nil

        logger.debug('Agent definition initialized',
                     name: name,
                     mode: @execution_mode)
      end

      # Set or get description
      #
      # @param val [String, nil] Description text
      # @return [String] Current description
      def description(val = nil)
        return @description if val.nil?

        @description = val
      end

      # Set persona/system prompt
      #
      # @param text [String] Persona text or system prompt
      # @return [String] Current persona
      def persona(text = nil)
        return @persona if text.nil?

        @persona = text
      end

      # Set schedule (cron expression)
      #
      # @param cron [String] Cron expression
      # @return [String] Current schedule
      def schedule(cron = nil)
        return @schedule if cron.nil?

        @schedule = cron
        @execution_mode = :scheduled
      end

      # Set objectives (list of goals)
      #
      # @param list [Array<String>] List of objectives
      # @return [Array<String>] Current objectives
      def objectives(list = nil)
        return @objectives if list.nil?

        @objectives = list
      end

      # Define a single objective
      #
      # @param text [String] Objective text
      # @return [void]
      def objective(text)
        @objectives << text
      end

      # Define main execution block (DSL v1)
      #
      # The main block is the imperative entry point for agent execution.
      # It receives agent inputs and returns agent outputs. Use execute_task()
      # to call organic functions (tasks) defined with the task directive.
      #
      # @yield Main execution block
      # @return [MainDefinition] Current main definition
      # @example
      #   main do |inputs|
      #     result = execute_task(:fetch_data, inputs: inputs)
      #     execute_task(:process_data, inputs: result)
      #   end
      def main(&block)
        return @main if block.nil?

        @main = MainDefinition.new
        @main.execute(&block) if block
        @main
      end

      # Define a task (organic function) - DSL v1
      #
      # Tasks are the core primitive of DSL v1, representing organic functions with
      # stable input/output contracts. Tasks can be neural (instructions-based),
      # symbolic (code-based), or hybrid (both).
      #
      # @param name [Symbol] Task name
      # @param options [Hash] Task configuration
      # @option options [Hash] :inputs Input schema (param => type)
      # @option options [Hash] :outputs Output schema (field => type)
      # @option options [String] :instructions Natural language instructions (neural)
      # @yield [inputs] Symbolic implementation block (optional)
      # @yieldparam inputs [Hash] Validated input parameters
      # @yieldreturn [Hash] Output matching outputs schema
      # @return [TaskDefinition] The task definition
      #
      # @example Neural task
      #   task :analyze_data,
      #     instructions: "Analyze the data for anomalies",
      #     inputs: { data: 'array' },
      #     outputs: { issues: 'array', summary: 'string' }
      #
      # @example Symbolic task
      #   task :calculate_total,
      #     inputs: { items: 'array' },
      #     outputs: { total: 'number' }
      #   do |inputs|
      #     { total: inputs[:items].sum { |i| i['amount'] } }
      #   end
      #
      # @example Hybrid task
      #   task :fetch_user,
      #     instructions: "Fetch user from database",
      #     inputs: { user_id: 'integer' },
      #     outputs: { user: 'hash' }
      #   do |inputs|
      #     execute_tool('database', 'get_user', id: inputs[:user_id])
      #   end
      def task(name, **options, &block)
        # Create task definition
        task_def = TaskDefinition.new(name)

        # Configure from options (keyword arguments)
        task_def.inputs(options[:inputs]) if options[:inputs]
        task_def.outputs(options[:outputs]) if options[:outputs]
        task_def.instructions(options[:instructions]) if options[:instructions]

        # Symbolic implementation (if block provided)
        task_def.execute(&block) if block

        # Store in tasks collection
        @tasks[name] = task_def

        task_type = if task_def.neural? && task_def.symbolic?
                      'hybrid'
                    elsif task_def.neural?
                      'neural'
                    else
                      'symbolic'
                    end

        logger.debug('Task defined',
                     name: name,
                     type: task_type,
                     inputs: options[:inputs]&.keys || [],
                     outputs: options[:outputs]&.keys || [])

        task_def
      end

      # Define constraints (max_iterations, timeout, etc.)
      #
      # @yield Constraints block
      # @return [Hash] Current constraints
      def constraints(&block)
        return @constraints if block.nil?

        constraint_builder = ConstraintBuilder.new
        constraint_builder.instance_eval(&block) if block
        @constraints = constraint_builder.to_h
      end

      # Define output handler (DSL v1)
      #
      # The output block receives the final outputs from the main execution
      # and handles them (logging, saving to workspace, notifications, etc.)
      #
      # @yield [outputs] Output handler block
      # @yieldparam outputs [Hash] The outputs returned from main execution
      # @return [Proc] Current output handler
      # @example
      #   output do |outputs|
      #     puts "Agent completed: #{outputs.inspect}"
      #     File.write("/workspace/result.json", outputs.to_json)
      #   end
      def output(&block)
        return @output_config if block.nil?

        @output_config = block
      end

      # Set execution mode
      #
      # @param mode [Symbol] Execution mode (:autonomous, :scheduled, :reactive)
      # @return [Symbol] Current execution mode
      def mode(mode = nil)
        return @execution_mode if mode.nil?

        @execution_mode = mode
      end

      # Define a webhook endpoint
      #
      # @param path [String] URL path for the webhook
      # @yield Webhook configuration block
      # @return [WebhookDefinition] The webhook definition
      def webhook(path, &block)
        webhook_def = WebhookDefinition.new(path)
        webhook_def.instance_eval(&block) if block
        @webhooks << webhook_def
        @execution_mode = :reactive if @execution_mode == :autonomous
        webhook_def
      end

      # Define MCP server capabilities
      #
      # Allows this agent to expose tools via MCP protocol.
      # Other agents or MCP clients can discover and call these tools.
      #
      # @yield MCP server configuration block
      # @return [McpServerDefinition] The MCP server definition
      def as_mcp_server(&block)
        @mcp_server = McpServerDefinition.new(@name)
        @mcp_server.instance_eval(&block) if block
        @execution_mode = :reactive if @execution_mode == :autonomous
        @mcp_server
      end

      # Define chat endpoint capabilities
      #
      # Allows this agent to respond to OpenAI-compatible chat completion requests.
      # Other systems can treat this agent as a language model.
      #
      # @yield Chat endpoint configuration block
      # @return [ChatEndpointDefinition] The chat endpoint definition
      def as_chat_endpoint(&block)
        @chat_endpoint ||= ChatEndpointDefinition.new(@name)
        @chat_endpoint.instance_eval(&block) if block
        @execution_mode = :reactive if @execution_mode == :autonomous
        @chat_endpoint
      end

      # Execute the agent
      #
      # @return [void]
      def run!
        logger.info('Starting agent',
                    name: @name,
                    mode: @execution_mode,
                    objectives_count: @objectives.size,
                    has_main: !@main.nil?)

        case @execution_mode
        when :scheduled
          run_scheduled
        when :autonomous
          run_autonomous
        when :reactive
          run_reactive
        else
          logger.error('Unknown execution mode', mode: @execution_mode)
          raise "Unknown execution mode: #{@execution_mode}"
        end
      end

      private

      def logger_component
        "Agent:#{@name}"
      end

      def run_scheduled
        require 'rufus-scheduler'

        scheduler = Rufus::Scheduler.new

        logger.info('Scheduling agent',
                    name: @name,
                    cron: @schedule)

        scheduler.cron(@schedule) do
          logger.timed('Scheduled execution') do
            execute_objectives
          end
        end

        scheduler.join
      end

      def run_autonomous
        logger.info('Running agent in autonomous mode', name: @name)
        execute_objectives
      end

      def run_reactive
        logger.info('Running agent in reactive mode',
                    name: @name,
                    webhooks: @webhooks.size,
                    mcp_tools: @mcp_server&.tools&.size || 0,
                    chat_endpoint: !@chat_endpoint.nil?)

        # Create an Agent::Base instance with this definition
        require_relative '../agent/base'
        require_relative '../agent/web_server'

        # Build agent config
        agent_config = build_agent_config

        # Create agent instance
        agent = LanguageOperator::Agent::Base.new(agent_config)
        agent.instance_variable_set(:@mode, 'reactive')

        # Create web server
        web_server = LanguageOperator::Agent::WebServer.new(agent)

        # Register webhooks
        @webhooks.each do |webhook_def|
          webhook_def.register(web_server)
        end

        # Register MCP tools
        web_server.register_mcp_tools(@mcp_server) if @mcp_server&.tools?

        # Register chat endpoint
        web_server.register_chat_endpoint(@chat_endpoint, agent) if @chat_endpoint

        # Start the server
        web_server.start
      end

      # Build agent configuration hash
      #
      # @return [Hash] Agent configuration
      def build_agent_config
        {
          'agent' => {
            'name' => @name,
            'instructions' => @description || "Process incoming requests for #{@name}",
            'persona' => @persona
          },
          'llm' => {
            'provider' => ENV['LLM_PROVIDER'] || 'anthropic',
            'model' => ENV['LLM_MODEL'] || 'claude-3-5-sonnet-20241022',
            'api_key' => ENV.fetch('ANTHROPIC_API_KEY', nil)
          },
          'mcp' => {
            'servers' => {}
          }
        }
      end

      def execute_objectives
        logger.info('Executing objectives',
                    total: @objectives.size,
                    has_main: !@main.nil?)

        @objectives.each_with_index do |objective, index|
          logger.info('Executing objective',
                      index: index + 1,
                      total: @objectives.size,
                      objective: objective[0..100])

          # If main defined, execute it; otherwise just log
          if @main
            outputs = logger.timed('Objective main execution') do
              @main.call({ objective: objective })
            end

            # Call output handler if defined
            if @output_config.is_a?(Proc)
              logger.debug('Calling output handler', outputs: outputs)
              @output_config.call(outputs)
            end
          else
            logger.warn('No main block defined, skipping execution')
          end
        end

        logger.info('All objectives completed', total: @objectives.size)
      end
    end

    # Helper class for building constraints
    class ConstraintBuilder
      def initialize
        @constraints = {}
      end

      def max_iterations(value)
        @constraints[:max_iterations] = value
      end

      def timeout(value)
        @constraints[:timeout] = value
      end

      def max_retries(value)
        @constraints[:max_retries] = value
      end

      def memory(value)
        @constraints[:memory] = value
      end

      def rate_limit(value)
        @constraints[:rate_limit] = value
      end

      # Budget constraints
      def daily_budget(value)
        @constraints[:daily_budget] = value
      end

      def hourly_budget(value)
        @constraints[:hourly_budget] = value
      end

      def token_budget(value)
        @constraints[:token_budget] = value
      end

      # Rate limiting
      def requests_per_minute(value)
        @constraints[:requests_per_minute] = value
      end

      def requests_per_hour(value)
        @constraints[:requests_per_hour] = value
      end

      def requests_per_day(value)
        @constraints[:requests_per_day] = value
      end

      # Content filtering
      def blocked_patterns(patterns)
        @constraints[:blocked_patterns] = patterns
      end

      def blocked_topics(topics)
        @constraints[:blocked_topics] = topics
      end

      def to_h
        @constraints
      end
    end
  end
end
