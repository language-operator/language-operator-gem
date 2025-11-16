# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../../dsl/schema'

module LanguageOperator
  module CLI
    module Commands
      # System commands for schema introspection and metadata
      class System < BaseCommand
        desc 'schema', 'Export the DSL schema in various formats'
        long_desc <<-DESC
          Export the Language Operator Agent DSL schema in various formats.

          The schema documents all available DSL methods, parameters, validation
          patterns, and structure. Useful for template validation, documentation
          generation, and IDE autocomplete.

          Examples:
            # Export JSON schema (default)
            aictl system schema

            # Export as YAML
            aictl system schema --format yaml

            # Export OpenAPI 3.0 specification
            aictl system schema --format openapi

            # Show schema version only
            aictl system schema --version

            # Save to file
            aictl system schema > schema.json
            aictl system schema --format openapi > openapi.json
        DESC
        option :format, type: :string, default: 'json', desc: 'Output format (json, yaml, openapi)'
        option :version, type: :boolean, default: false, desc: 'Show schema version only'
        def schema
          handle_command_error('generate schema') do
            # Handle version flag
            if options[:version]
              puts Dsl::Schema.version
              return
            end

            # Generate schema based on format
            format = options[:format].downcase
            case format
            when 'json'
              output_json_schema
            when 'yaml'
              output_yaml_schema
            when 'openapi'
              output_openapi_schema
            else
              Formatters::ProgressFormatter.error("Invalid format: #{format}")
              puts
              puts 'Supported formats: json, yaml, openapi'
              exit 1
            end
          end
        end

        no_commands do
          # Output JSON Schema v7
          def output_json_schema
            schema = Dsl::Schema.to_json_schema
            puts JSON.pretty_generate(schema)
          end

          # Output YAML Schema
          def output_yaml_schema
            schema = Dsl::Schema.to_json_schema
            puts YAML.dump(schema.transform_keys(&:to_s))
          end

          # Output OpenAPI 3.0 specification
          def output_openapi_schema
            spec = Dsl::Schema.to_openapi
            puts JSON.pretty_generate(spec)
          end
        end

        desc 'validate_template', 'Validate synthesis template against DSL schema'
        long_desc <<-DESC
          Validate a synthesis template file against the DSL schema.

          Extracts Ruby code examples from the template and validates each example
          against the Language Operator Agent DSL schema. Checks for dangerous
          methods, syntax errors, and compliance with safe coding practices.

          Examples:
            # Validate a custom template file
            aictl system validate_template --template /path/to/template.tmpl

            # Validate the bundled agent template (default)
            aictl system validate_template

            # Validate the bundled persona template
            aictl system validate_template --type persona

            # Verbose output with all violations
            aictl system validate_template --template mytemplate.tmpl --verbose
        DESC
        option :template, type: :string, desc: 'Path to template file (defaults to bundled template)'
        option :type, type: :string, default: 'agent', desc: 'Template type if using bundled template (agent, persona)'
        option :verbose, type: :boolean, default: false, desc: 'Show detailed violation information'
        def validate_template
          handle_command_error('validate template') do
            # Determine template source
            if options[:template]
              # Load custom template from file
              unless File.exist?(options[:template])
                Formatters::ProgressFormatter.error("Template file not found: #{options[:template]}")
                exit 1
              end
              template_content = File.read(options[:template])
              template_name = File.basename(options[:template])
            else
              # Load bundled template
              template_type = options[:type].downcase
              unless %w[agent persona].include?(template_type)
                Formatters::ProgressFormatter.error("Invalid template type: #{template_type}")
                puts
                puts 'Supported types: agent, persona'
                exit 1
              end
              template_content = load_bundled_template(template_type)
              template_name = "bundled #{template_type} template"
            end

            # Display header
            puts "Validating template: #{template_name}"
            puts '=' * 60
            puts

            # Extract code examples
            code_examples = extract_code_examples(template_content)

            if code_examples.empty?
              Formatters::ProgressFormatter.warn('No Ruby code examples found in template')
              puts
              puts 'Templates should contain Ruby code blocks like:'
              puts '```ruby'
              puts 'agent "my-agent" do'
              puts '  # ...'
              puts 'end'
              puts '```'
              exit 1
            end

            puts "Found #{code_examples.size} code example(s)"
            puts

            # Validate each example
            all_valid = true
            code_examples.each_with_index do |example, idx|
              puts "Example #{idx + 1} (starting at line #{example[:start_line]}):"
              puts '-' * 40

              result = validate_code_against_schema(example[:code])

              if result[:valid] && result[:warnings].empty?
                Formatters::ProgressFormatter.success('Valid - No issues found')
              elsif result[:valid]
                Formatters::ProgressFormatter.success('Valid - With warnings')
                result[:warnings].each do |warn|
                  line = example[:start_line] + (warn[:location] || 0)
                  puts "  ⚠  Line #{line}: #{warn[:message]}"
                end
              else
                Formatters::ProgressFormatter.error('Invalid - Violations detected')
                result[:errors].each do |err|
                  line = example[:start_line] + (err[:location] || 0)
                  puts "  ✗ Line #{line}: #{err[:message]}"
                  puts "    Type: #{err[:type]}" if options[:verbose]
                end
                all_valid = false
              end

              puts
            end

            # Final summary
            puts '=' * 60
            if all_valid
              Formatters::ProgressFormatter.success('All examples are valid')
              exit 0
            else
              Formatters::ProgressFormatter.error('Validation failed')
              puts
              puts 'Fix the violations above and run validation again.'
              exit 1
            end
          end
        end

        desc 'synthesize [INSTRUCTIONS]', 'Synthesize agent code from natural language instructions'
        long_desc <<-DESC
          Synthesize agent code by converting natural language instructions
          into Ruby DSL code without creating an actual agent.

          This command uses a LanguageModel resource from your cluster to generate
          agent code. If --model is not specified, the first available model will
          be auto-selected.

          Instructions can be provided either as a command argument or via STDIN.
          If no argument is provided, the command will read from STDIN.

          This command helps you validate your instructions and understand how the
          synthesis engine interprets them. Use --dry-run to see the prompt that
          would be sent to the LLM, or run without it to generate actual code.

          Examples:
            # Test with dry-run (show prompt only)
            aictl system synthesize "Monitor GitHub issues daily" --dry-run

            # Generate code from instructions (auto-selects first available model)
            aictl system synthesize "Send daily reports to Slack"

            # Use a specific cluster model
            aictl system synthesize "Process webhooks from GitHub" --model my-claude

            # Output raw code without formatting (useful for piping to files)
            aictl system synthesize "Monitor logs" --raw > agent.rb

            # Read instructions from STDIN
            cat instructions.txt | aictl system synthesize > agent.rb

            # Read from STDIN with pipe
            echo "Monitor GitHub issues" | aictl system synthesize --raw

            # Specify custom agent name and tools
            aictl system synthesize "Process webhooks from GitHub" \\
              --agent-name github-processor \\
              --tools github,slack \\
              --model my-gpt4
        DESC
        option :agent_name, type: :string, default: 'test-agent', desc: 'Name for the test agent'
        option :tools, type: :string, desc: 'Comma-separated list of available tools'
        option :models, type: :string, desc: 'Comma-separated list of available models (from cluster)'
        option :model, type: :string, desc: 'Model to use for synthesis (defaults to first available in cluster)'
        option :dry_run, type: :boolean, default: false, desc: 'Show prompt without calling LLM'
        option :raw, type: :boolean, default: false, desc: 'Output only the raw code without formatting'
        def synthesize(instructions = nil)
          handle_command_error('synthesize agent') do
            # Read instructions from STDIN if not provided as argument
            if instructions.nil? || instructions.strip.empty?
              if $stdin.tty?
                Formatters::ProgressFormatter.error('No instructions provided')
                puts
                puts 'Provide instructions either as an argument or via STDIN:'
                puts '  aictl system synthesize "Your instructions here"'
                puts '  cat instructions.txt | aictl system synthesize'
                exit 1
              else
                instructions = $stdin.read.strip
                if instructions.empty?
                  Formatters::ProgressFormatter.error('No instructions provided')
                  puts
                  puts 'Provide instructions either as an argument or via STDIN:'
                  puts '  aictl system synthesize "Your instructions here"'
                  puts '  cat instructions.txt | aictl system synthesize'
                  exit 1
                end
              end
            end
            # Select model to use for synthesis
            selected_model = select_synthesis_model

            # Load synthesis template
            template_content = load_bundled_template('agent')

            # Detect temporal intent from instructions
            temporal_intent = detect_temporal_intent(instructions)

            # Prepare template data
            template_data = {
              'Instructions' => instructions,
              'AgentName' => options[:agent_name],
              'ToolsList' => format_tools_list(options[:tools]),
              'ModelsList' => format_models_list(options[:models]),
              'TemporalIntent' => temporal_intent,
              'PersonaSection' => '',
              'ScheduleSection' => temporal_intent == 'scheduled' ? '  schedule "0 */1 * * *"  # Example hourly schedule' : '',
              'ScheduleRules' => temporal_intent == 'scheduled' ? "\n2. Include schedule with cron expression\n3. Set mode to :scheduled\n4. " : "\n2. ",
              'ConstraintsSection' => '',
              'ErrorContext' => nil
            }

            # Render template (Go-style template syntax)
            rendered_prompt = render_go_template(template_content, template_data)

            if options[:dry_run]
              # Show the prompt that would be sent
              puts 'Synthesis Prompt Preview'
              puts '=' * 80
              puts
              puts rendered_prompt
              puts
              puts '=' * 80
              Formatters::ProgressFormatter.success('Dry-run complete - prompt displayed above')
              return
            end

            # Call LLM to generate code (no output - just do it)
            llm_response = call_llm_for_synthesis(rendered_prompt, selected_model)

            # Extract Ruby code from response
            generated_code = extract_ruby_code(llm_response)

            if generated_code.nil?
              Formatters::ProgressFormatter.error('Failed to extract Ruby code from LLM response')
              puts
              puts 'LLM Response:'
              puts llm_response
              exit 1
            end

            # Handle raw output
            if options[:raw]
              puts generated_code
              return
            end

            # Display formatted code
            require 'rouge'
            formatter = Rouge::Formatters::Terminal256.new
            lexer = Rouge::Lexers::Ruby.new
            highlighted_code = formatter.format(lexer.lex(generated_code))

            puts highlighted_code
          end
        end

        desc 'exec [AGENT_FILE]', 'Execute an agent file in a test pod on the cluster'
        long_desc <<-DESC
          Deploy and execute an agent file in a temporary test pod on the Kubernetes cluster.

          This command creates a ConfigMap with the agent code, deploys a test pod,
          streams the logs until completion, and cleans up all resources.

          The agent code is mounted at /etc/agent/code/agent.rb as expected by the agent runtime.

          Agent code can be provided either as a file path or via STDIN.
          If no file path is provided, the command will read from STDIN.

          Examples:
            # Execute a synthesized agent file
            aictl system exec agent.rb

            # Execute with a custom agent name
            aictl system exec agent.rb --agent-name my-test

            # Keep the pod after execution for debugging
            aictl system exec agent.rb --keep-pod

            # Use a different agent image
            aictl system exec agent.rb --image ghcr.io/language-operator/agent:v0.1.0

            # Read agent code from STDIN
            cat agent.rb | aictl system exec

            # Pipe synthesized code directly to execution
            cat agent.txt | aictl system synthesize | aictl system exec
        DESC
        option :agent_name, type: :string, default: 'test-agent', desc: 'Name for the test agent pod'
        option :keep_pod, type: :boolean, default: false, desc: 'Keep the pod after execution (for debugging)'
        option :image, type: :string, default: 'ghcr.io/language-operator/agent:latest', desc: 'Agent container image'
        option :timeout, type: :numeric, default: 300, desc: 'Timeout in seconds for agent execution'
        def exec(agent_file = nil)
          handle_command_error('exec agent') do
            # Verify cluster is selected
            unless ctx.client
              Formatters::ProgressFormatter.error('No cluster context available')
              puts
              puts 'Please configure kubectl with a valid cluster context:'
              puts '  kubectl config get-contexts'
              puts '  kubectl config use-context <context-name>'
              exit 1
            end

            # Read agent code from file or STDIN
            agent_code = if agent_file && !agent_file.strip.empty?
                           # Read from file
                           unless File.exist?(agent_file)
                             Formatters::ProgressFormatter.error("Agent file not found: #{agent_file}")
                             exit 1
                           end
                           File.read(agent_file)
                         elsif $stdin.tty?
                           # Read from STDIN
                           Formatters::ProgressFormatter.error('No agent code provided')
                           puts
                           puts 'Provide agent code either as a file or via STDIN:'
                           puts '  aictl system exec agent.rb'
                           puts '  cat agent.rb | aictl system exec'
                           exit 1
                         else
                           code = $stdin.read.strip
                           if code.empty?
                             Formatters::ProgressFormatter.error('No agent code provided')
                             puts
                             puts 'Provide agent code either as a file or via STDIN:'
                             puts '  aictl system exec agent.rb'
                             puts '  cat agent.rb | aictl system exec'
                             exit 1
                           end
                           code
                         end

            # Generate unique names
            timestamp = Time.now.to_i
            configmap_name = "#{options[:agent_name]}-code-#{timestamp}"
            pod_name = "#{options[:agent_name]}-#{timestamp}"

            begin
              # Create ConfigMap with agent code
              Formatters::ProgressFormatter.with_spinner('Creating ConfigMap with agent code') do
                create_agent_configmap(configmap_name, agent_code)
              end

              # Create test pod
              Formatters::ProgressFormatter.with_spinner('Creating test pod') do
                create_test_pod(pod_name, configmap_name, options[:image])
              end

              # Wait for pod to be ready or running
              Formatters::ProgressFormatter.with_spinner('Waiting for pod to start') do
                wait_for_pod_start(pod_name, timeout: 60)
              end

              # Stream logs until pod completes
              stream_pod_logs(pod_name, timeout: options[:timeout])

              # Wait for pod to fully terminate and get final status
              exit_code = wait_for_pod_termination(pod_name)

              if exit_code&.zero?
                Formatters::ProgressFormatter.success('Agent completed successfully')
              elsif exit_code
                Formatters::ProgressFormatter.error("Agent failed with exit code: #{exit_code}")
              else
                Formatters::ProgressFormatter.warn('Unable to determine pod exit status')
              end
            ensure
              # Clean up resources unless --keep-pod
              puts
              puts
              if options[:keep_pod]
                Formatters::ProgressFormatter.info('Resources kept for debugging:')
                puts "  Pod: #{pod_name}"
                puts "  ConfigMap: #{configmap_name}"
                puts
                puts "To view logs: kubectl logs -n #{ctx.namespace} #{pod_name}"
                puts "To delete:    kubectl delete pod,configmap -n #{ctx.namespace} #{pod_name} #{configmap_name}"
              else
                Formatters::ProgressFormatter.with_spinner('Cleaning up resources') do
                  delete_pod(pod_name)
                  delete_configmap(configmap_name)
                end
              end
            end
          end
        end

        desc 'synthesis-template', 'Export synthesis templates for agent code generation'
        long_desc <<-DESC
          Export the synthesis templates used by the Language Operator to generate
          agent code from natural language instructions.

          These templates are used by the operator's synthesis engine to convert
          user instructions into executable Ruby DSL code.

          Examples:
            # Export agent synthesis template (default)
            aictl system synthesis-template

            # Export persona distillation template
            aictl system synthesis-template --type persona

            # Export as JSON with schema included
            aictl system synthesis-template --format json --with-schema

            # Export as YAML
            aictl system synthesis-template --format yaml

            # Validate template syntax
            aictl system synthesis-template --validate

            # Save to file
            aictl system synthesis-template > agent_synthesis.tmpl
        DESC
        option :format, type: :string, default: 'template', desc: 'Output format (template, json, yaml)'
        option :type, type: :string, default: 'agent', desc: 'Template type (agent, persona)'
        option :with_schema, type: :boolean, default: false, desc: 'Include DSL schema in output'
        option :validate, type: :boolean, default: false, desc: 'Validate template syntax'
        def synthesis_template
          handle_command_error('load template') do
            # Validate type
            template_type = options[:type].downcase
            unless %w[agent persona].include?(template_type)
              Formatters::ProgressFormatter.error("Invalid template type: #{template_type}")
              puts
              puts 'Supported types: agent, persona'
              exit 1
            end

            # Load template
            template_content = load_template(template_type)

            # Validate if requested
            if options[:validate]
              validation_result = validate_template_content(template_content, template_type)

              # Display warnings if any
              unless validation_result[:warnings].empty?
                Formatters::ProgressFormatter.warn('Template validation warnings:')
                validation_result[:warnings].each do |warning|
                  puts "  ⚠  #{warning}"
                end
                puts
              end

              # Display errors and exit if validation failed
              if validation_result[:valid]
                Formatters::ProgressFormatter.success('Template validation passed')
                return
              else
                Formatters::ProgressFormatter.error('Template validation failed:')
                validation_result[:errors].each do |error|
                  puts "  ✗ #{error}"
                end
                exit 1
              end
            end

            # Generate output based on format
            format = options[:format].downcase
            case format
            when 'template'
              output_template_format(template_content)
            when 'json'
              output_json_format(template_content, template_type)
            when 'yaml'
              output_yaml_format(template_content, template_type)
            else
              Formatters::ProgressFormatter.error("Invalid format: #{format}")
              puts
              puts 'Supported formats: template, json, yaml'
              exit 1
            end
          end
        end

        private

        # Render Go-style template ({{.Variable}})
        # Simplified implementation for basic variable substitution
        def render_go_template(template, data)
          result = template.dup

          # Handle {{if .ErrorContext}} - remove this section for test-synthesis
          result.gsub!(/{{if \.ErrorContext}}.*?{{else}}/m, '')
          result.gsub!(/{{end}}/, '')

          # Replace simple variables {{.Variable}}
          data.each do |key, value|
            result.gsub!("{{.#{key}}}", value.to_s)
          end

          result
        end

        # Detect temporal intent from instructions (scheduled vs autonomous)
        def detect_temporal_intent(instructions)
          temporal_keywords = {
            scheduled: %w[daily weekly hourly monthly schedule cron every day week hour minute],
            autonomous: %w[monitor watch continuously constantly always loop]
          }

          instructions_lower = instructions.downcase

          # Check for scheduled keywords
          scheduled_matches = temporal_keywords[:scheduled].count { |keyword| instructions_lower.include?(keyword) }
          autonomous_matches = temporal_keywords[:autonomous].count { |keyword| instructions_lower.include?(keyword) }

          scheduled_matches > autonomous_matches ? 'scheduled' : 'autonomous'
        end

        # Format tools list for template
        def format_tools_list(tools_str)
          return 'No tools specified' if tools_str.nil? || tools_str.strip.empty?

          tools = tools_str.split(',').map(&:strip)
          tools.map { |tool| "- #{tool}" }.join("\n")
        end

        # Format models list for template
        def format_models_list(models_str)
          # If not specified, try to detect from cluster
          if models_str.nil? || models_str.strip.empty?
            models = detect_available_models
            return models.map { |model| "- #{model}" }.join("\n") unless models.empty?

            return 'No models available (run: aictl model list)'
          end

          models = models_str.split(',').map(&:strip)
          models.map { |model| "- #{model}" }.join("\n")
        end

        # Detect available models from cluster
        def detect_available_models
          models = ctx.client.list_resources('LanguageModel', namespace: ctx.namespace)
          models.map { |m| m.dig('metadata', 'name') }
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to list models from cluster: #{e.message}")
          []
        end

        # Select model to use for synthesis
        def select_synthesis_model
          # If --model option specified, use it
          return options[:model] if options[:model]

          # Otherwise, auto-select from available cluster models
          available_models = detect_available_models

          if available_models.empty?
            Formatters::ProgressFormatter.error('No models available in cluster')
            puts
            puts 'Please create a model first:'
            puts '  aictl model create'
            puts
            puts 'Or list existing models:'
            puts '  aictl model list'
            exit 1
          end

          # Auto-select first available model (silently)
          available_models.first
        end

        # Get endpoint for a cluster model
        def get_model_endpoint(model_name)
          # For cluster models, we use the service endpoint
          # The service is typically named the same as the model and listens on port 4000
          "http://#{model_name}.#{ctx.namespace}.svc.cluster.local:4000/v1"
        end

        # Call LLM to generate code from synthesis prompt using cluster model
        def call_llm_for_synthesis(prompt, model_name)
          require 'json'
          require 'faraday'

          # Get model resource
          model = get_resource_or_exit('LanguageModel', model_name)
          model_id = model.dig('spec', 'modelName')

          # Get the model's pod
          pod = get_model_pod(model_name)
          pod_name = pod.dig('metadata', 'name')

          # Set up port-forward to access the model pod
          port_forward_pid = nil
          local_port = find_available_port

          begin
            # Start kubectl port-forward in background
            port_forward_pid = start_port_forward(pod_name, local_port, 4000)

            # Wait for port-forward to be ready
            wait_for_port(local_port)

            # Build the JSON payload for the chat completion request
            payload = {
              model: model_id,
              messages: [{ role: 'user', content: prompt }],
              max_tokens: 4000,
              temperature: 0.3
            }

            # Make HTTP request using Faraday
            conn = Faraday.new(url: "http://localhost:#{local_port}") do |f|
              f.request :json
              f.response :json
              f.adapter Faraday.default_adapter
              f.options.timeout = 120
              f.options.open_timeout = 10
            end

            response = conn.post('/v1/chat/completions', payload)

            # Parse response
            result = response.body

            if result['error']
              error_msg = result['error']['message'] || result['error']
              raise "Model error: #{error_msg}"
            elsif !result['choices'] || result['choices'].empty?
              raise "Unexpected response format: #{result.inspect}"
            end

            # Extract the content from the first choice
            result.dig('choices', 0, 'message', 'content')
          rescue Faraday::TimeoutError
            raise 'LLM request timed out after 120 seconds'
          rescue Faraday::ConnectionFailed => e
            raise "Failed to connect to model: #{e.message}"
          rescue StandardError => e
            Formatters::ProgressFormatter.error("LLM call failed: #{e.message}")
            puts
            puts "Make sure the model '#{model_name}' is running: kubectl get pods -n #{ctx.namespace}"
            exit 1
          ensure
            # Clean up port-forward process
            cleanup_port_forward(port_forward_pid) if port_forward_pid
          end
        end

        # Get the pod for a model
        def get_model_pod(model_name)
          # Get the deployment for the model
          deployment = ctx.client.get_resource('Deployment', model_name, ctx.namespace)
          labels = deployment.dig('spec', 'selector', 'matchLabels')

          raise "Deployment '#{model_name}' has no selector labels" if labels.nil?

          # Convert to hash if needed
          labels_hash = labels.respond_to?(:to_h) ? labels.to_h : labels
          raise "Deployment '#{model_name}' has empty selector labels" if labels_hash.empty?

          label_selector = labels_hash.map { |k, v| "#{k}=#{v}" }.join(',')

          # Find a running pod
          pods = ctx.client.list_resources('Pod', namespace: ctx.namespace, label_selector: label_selector)
          raise "No pods found for model '#{model_name}'" if pods.empty?

          running_pod = pods.find do |pod|
            pod.dig('status', 'phase') == 'Running' &&
              pod.dig('status', 'conditions')&.any? { |c| c['type'] == 'Ready' && c['status'] == 'True' }
          end

          if running_pod.nil?
            pod_phases = pods.map { |p| p.dig('status', 'phase') }.join(', ')
            raise "No running pods found. Pod phases: #{pod_phases}"
          end

          running_pod
        rescue K8s::Error::NotFound
          raise "Model deployment '#{model_name}' not found"
        end

        # Find an available local port for port-forwarding
        def find_available_port
          require 'socket'

          # Try ports in the range 14000-14999
          (14_000..14_999).each do |port|
            server = TCPServer.new('127.0.0.1', port)
            server.close
            return port
          rescue Errno::EADDRINUSE
            # Port in use, try next
            next
          end

          raise 'No available ports found in range 14000-14999'
        end

        # Start kubectl port-forward in background
        def start_port_forward(pod_name, local_port, remote_port)
          require 'English'

          cmd = "kubectl port-forward -n #{ctx.namespace} #{pod_name} #{local_port}:#{remote_port}"
          pid = spawn(cmd, out: '/dev/null', err: '/dev/null')

          # Detach so it runs in background
          Process.detach(pid)

          pid
        end

        # Wait for port-forward to be ready
        def wait_for_port(port, max_attempts: 30)
          require 'socket'

          max_attempts.times do
            socket = TCPSocket.new('127.0.0.1', port)
            socket.close
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            sleep 0.1
          end

          raise "Port-forward to localhost:#{port} failed to become ready after #{max_attempts} attempts"
        end

        # Clean up port-forward process
        def cleanup_port_forward(pid)
          return unless pid

          begin
            Process.kill('TERM', pid)
            Process.wait(pid, Process::WNOHANG)
          rescue Errno::ESRCH
            # Process already gone
          rescue Errno::ECHILD
            # Process already reaped
          end
        end

        # Extract Ruby code from LLM response
        # Looks for ```ruby ... ``` blocks
        def extract_ruby_code(response)
          # Match ```ruby ... ``` blocks
          match = response.match(/```ruby\n(.*?)```/m)
          return match[1].strip if match

          # Try without language specifier
          match = response.match(/```\n(.*?)```/m)
          return match[1].strip if match

          # If no code blocks, return nil
          nil
        end

        # Load template from bundled gem or operator ConfigMap
        def load_template(type)
          # Try to fetch from operator ConfigMap first (if kubectl available)
          template = fetch_from_operator(type)
          return template if template

          # Fall back to bundled template
          load_bundled_template(type)
        end

        # Fetch template from operator ConfigMap via kubectl
        def fetch_from_operator(type)
          configmap_name = type == 'agent' ? 'agent-synthesis-template' : 'persona-distillation-template'
          result = `kubectl get configmap #{configmap_name} -n language-operator-system -o jsonpath='{.data.template}' 2>/dev/null`
          result.empty? ? nil : result
        rescue StandardError
          nil
        end

        # Load bundled template from gem
        def load_bundled_template(type)
          filename = type == 'agent' ? 'agent_synthesis.tmpl' : 'persona_distillation.tmpl'
          template_path = File.join(__dir__, '..', '..', 'templates', filename)
          File.read(template_path)
        end

        # Validate template syntax and structure
        def validate_template_content(content, type)
          errors = []
          warnings = []

          # Check for required placeholders based on type
          required_placeholders = if type == 'agent'
                                    %w[
                                      Instructions ToolsList ModelsList AgentName TemporalIntent
                                    ]
                                  else
                                    %w[
                                      PersonaName PersonaDescription PersonaSystemPrompt
                                      AgentInstructions AgentTools
                                    ]
                                  end

          required_placeholders.each do |placeholder|
            errors << "Missing required placeholder: {{.#{placeholder}}}" unless content.include?("{{.#{placeholder}}}")
          end

          # Check for balanced braces
          open_braces = content.scan(/{{/).count
          close_braces = content.scan(/}}/).count
          errors << "Unbalanced template braces ({{ vs }}): #{open_braces} open, #{close_braces} close" if open_braces != close_braces

          # Extract and validate Ruby code blocks
          code_examples = extract_code_examples(content)
          code_examples.each do |example|
            code_result = validate_code_against_schema(example[:code])
            unless code_result[:valid]
              code_result[:errors].each do |err|
                # Adjust line numbers to be relative to template
                line = example[:start_line] + (err[:location] || 0)
                errors << "Line #{line}: #{err[:message]}"
              end
            end
            code_result[:warnings].each do |warn|
              line = example[:start_line] + (warn[:location] || 0)
              warnings << "Line #{line}: #{warn[:message]}"
            end
          end

          # Extract method calls and check if they're in the safe list
          method_calls = extract_method_calls(content)
          safe_methods = Dsl::Schema.safe_agent_methods +
                         Dsl::Schema.safe_tool_methods +
                         Dsl::Schema.safe_helper_methods
          method_calls.each do |method|
            next if safe_methods.include?(method)

            warnings << "Method '#{method}' not in safe methods list (may be valid Ruby builtin)"
          end

          {
            valid: errors.empty?,
            errors: errors,
            warnings: warnings
          }
        end

        # Extract Ruby code examples from template
        # Returns array of {code: String, start_line: Integer}
        def extract_code_examples(template)
          examples = []
          lines = template.split("\n")
          in_code_block = false
          current_code = []
          start_line = 0

          lines.each_with_index do |line, idx|
            if line.strip.start_with?('```ruby')
              in_code_block = true
              start_line = idx + 2 # idx is 0-based, we want line number (1-based) of first code line
              current_code = []
            elsif line.strip == '```' && in_code_block
              in_code_block = false
              examples << { code: current_code.join("\n"), start_line: start_line } unless current_code.empty?
            elsif in_code_block
              current_code << line
            end
          end

          examples
        end

        # Extract method calls from template code
        # Returns array of method name strings
        def extract_method_calls(template)
          require 'prism'

          method_calls = []
          code_examples = extract_code_examples(template)

          code_examples.each do |example|
            # Parse the code to find method calls
            result = Prism.parse(example[:code])

            # Walk the AST to find method calls
            extract_methods_from_ast(result.value, method_calls) if result.success?
          rescue Prism::ParseError
            # Skip code with syntax errors - they'll be caught by validate_code_against_schema
            next
          end

          method_calls.uniq
        end

        # Recursively extract method names from AST
        def extract_methods_from_ast(node, methods)
          return unless node

          methods << node.name.to_s if node.is_a?(Prism::CallNode)

          node.compact_child_nodes.each do |child|
            extract_methods_from_ast(child, methods)
          end
        end

        # Validate Ruby code against DSL schema
        # Returns {valid: Boolean, errors: Array<Hash>, warnings: Array<Hash>}
        def validate_code_against_schema(code)
          require 'language_operator/agent/safety/ast_validator'

          validator = LanguageOperator::Agent::Safety::ASTValidator.new
          violations = validator.validate(code, '(template)')

          errors = []
          warnings = []

          violations.each do |violation|
            case violation[:type]
            when :syntax_error
              errors << {
                type: :syntax_error,
                location: 0,
                message: violation[:message]
              }
            when :dangerous_method, :dangerous_constant, :dangerous_constant_access, :dangerous_global, :backtick_execution
              errors << {
                type: violation[:type],
                location: violation[:location],
                message: violation[:message]
              }
            else
              warnings << {
                type: violation[:type],
                location: violation[:location] || 0,
                message: violation[:message]
              }
            end
          end

          {
            valid: errors.empty?,
            errors: errors,
            warnings: warnings
          }
        end

        # Output raw template format
        def output_template_format(content)
          puts content
        end

        # Output JSON format with metadata
        def output_json_format(content, type)
          data = {
            version: Dsl::Schema.version,
            template_type: type,
            template: content
          }

          if options[:with_schema]
            data[:schema] = Dsl::Schema.to_json_schema
            data[:safe_agent_methods] = Dsl::Schema.safe_agent_methods
            data[:safe_tool_methods] = Dsl::Schema.safe_tool_methods
            data[:safe_helper_methods] = Dsl::Schema.safe_helper_methods
          end

          puts JSON.pretty_generate(data)
        end

        # Output YAML format with metadata
        def output_yaml_format(content, type)
          data = {
            'version' => Dsl::Schema.version,
            'template_type' => type,
            'template' => content
          }

          if options[:with_schema]
            data['schema'] = Dsl::Schema.to_json_schema.transform_keys(&:to_s)
            data['safe_agent_methods'] = Dsl::Schema.safe_agent_methods
            data['safe_tool_methods'] = Dsl::Schema.safe_tool_methods
            data['safe_helper_methods'] = Dsl::Schema.safe_helper_methods
          end

          puts YAML.dump(data)
        end

        # Create a ConfigMap with agent code
        def create_agent_configmap(name, code)
          configmap = {
            'apiVersion' => 'v1',
            'kind' => 'ConfigMap',
            'metadata' => {
              'name' => name,
              'namespace' => ctx.namespace
            },
            'data' => {
              'agent.rb' => code
            }
          }

          ctx.client.create_resource(configmap)
        end

        # Create a test pod for running the agent
        def create_test_pod(name, configmap_name, image)
          # Detect available models in the cluster
          model_env = detect_model_config

          env_vars = [
            { 'name' => 'AGENT_NAME', 'value' => name },
            { 'name' => 'AGENT_MODE', 'value' => 'autonomous' },
            { 'name' => 'AGENT_CODE_PATH', 'value' => '/etc/agent/code/agent.rb' },
            { 'name' => 'CONFIG_PATH', 'value' => '/nonexistent/config.yaml' }
          ]

          # Add model configuration if available
          env_vars += model_env if model_env

          pod = {
            'apiVersion' => 'v1',
            'kind' => 'Pod',
            'metadata' => {
              'name' => name,
              'namespace' => ctx.namespace,
              'labels' => {
                'app.kubernetes.io/name' => name,
                'app.kubernetes.io/component' => 'test-agent'
              }
            },
            'spec' => {
              'restartPolicy' => 'Never',
              'containers' => [
                {
                  'name' => 'agent',
                  'image' => image,
                  'imagePullPolicy' => 'Always',
                  'env' => env_vars,
                  'volumeMounts' => [
                    {
                      'name' => 'agent-code',
                      'mountPath' => '/etc/agent/code',
                      'readOnly' => true
                    }
                  ]
                }
              ],
              'volumes' => [
                {
                  'name' => 'agent-code',
                  'configMap' => {
                    'name' => configmap_name
                  }
                }
              ]
            }
          }

          ctx.client.create_resource(pod)
        end

        # Detect model configuration from the cluster
        def detect_model_config
          models = ctx.client.list_resources('LanguageModel', namespace: ctx.namespace)
          return nil if models.empty?

          # Use first available model
          model = models.first
          model_name = model.dig('metadata', 'name')
          model_id = model.dig('spec', 'modelName')

          # Build endpoint URL (port 8000 is the model service port)
          endpoint = "http://#{model_name}.#{ctx.namespace}.svc.cluster.local:8000"

          [
            { 'name' => 'MODEL_ENDPOINTS', 'value' => endpoint },
            { 'name' => 'LLM_MODEL', 'value' => model_id },
            { 'name' => 'OPENAI_API_KEY', 'value' => 'sk-dummy-key-for-local-proxy' }
          ]
        rescue StandardError
          # If we can't detect models, return nil and let the agent handle it
          nil
        end

        # Wait for pod to start (running or terminated)
        def wait_for_pod_start(name, timeout: 60)
          start_time = Time.now
          loop do
            pod = ctx.client.get_resource('Pod', name, ctx.namespace)
            phase = pod.dig('status', 'phase')

            return if %w[Running Succeeded Failed].include?(phase)

            raise "Pod #{name} did not start within #{timeout} seconds" if Time.now - start_time > timeout

            sleep 1
          end
        end

        # Stream pod logs until completion
        def stream_pod_logs(name, timeout: 300)
          require 'open3'

          cmd = "kubectl logs -f -n #{ctx.namespace} #{name} 2>&1"
          Open3.popen3(cmd) do |_stdin, stdout, _stderr, wait_thr|
            # Set up timeout
            start_time = Time.now

            # Stream logs
            stdout.each_line do |line|
              puts line

              # Check timeout
              if Time.now - start_time > timeout
                Process.kill('TERM', wait_thr.pid)
                raise "Log streaming timed out after #{timeout} seconds"
              end
            end

            # Wait for process to complete
            wait_thr.value
          end
        rescue Errno::EPIPE
          # Pod terminated, logs finished
        end

        # Wait for pod to terminate and get exit code
        def wait_for_pod_termination(name, timeout: 10)
          # Give the pod a moment to fully transition after logs complete
          sleep 2

          start_time = Time.now
          loop do
            pod = ctx.client.get_resource('Pod', name, ctx.namespace)
            phase = pod.dig('status', 'phase')
            container_status = pod.dig('status', 'containerStatuses', 0)

            # Pod completed successfully or failed
            if %w[Succeeded Failed].include?(phase) && container_status && (terminated = container_status.dig('state', 'terminated'))
              return terminated['exitCode']
            end

            # Check timeout
            if Time.now - start_time > timeout
              # Try one last time
              if container_status && (terminated = container_status.dig('state', 'terminated'))
                return terminated['exitCode']
              end

              return nil
            end

            sleep 0.5
          rescue K8s::Error::NotFound
            # Pod was deleted before we could get status
            return nil
          end
        end

        # Get pod status
        def get_pod_status(name)
          pod = ctx.client.get_resource('Pod', name, ctx.namespace)
          pod.to_h.fetch('status', {})
        end

        # Delete a pod
        def delete_pod(name)
          ctx.client.delete_resource('Pod', name, ctx.namespace)
        rescue K8s::Error::NotFound
          # Already deleted
        end

        # Delete a ConfigMap
        def delete_configmap(name)
          ctx.client.delete_resource('ConfigMap', name, ctx.namespace)
        rescue K8s::Error::NotFound
          # Already deleted
        end
      end
    end
  end
end
