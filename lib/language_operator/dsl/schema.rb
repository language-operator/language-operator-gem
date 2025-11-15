# frozen_string_literal: true

require_relative '../version'

module LanguageOperator
  module Dsl
    # JSON Schema generator for the Agent DSL
    #
    # Generates a JSON Schema v7 representation of the Language Operator Agent DSL.
    # This schema documents all available DSL methods, their parameters, validation
    # patterns, and structure.
    #
    # Used for:
    # - Template validation
    # - Documentation generation
    # - IDE autocomplete/IntelliSense
    # - CLI introspection commands
    #
    # @example Generate schema
    #   schema = LanguageOperator::Dsl::Schema.to_json_schema
    #   File.write('schema.json', JSON.pretty_generate(schema))
    # rubocop:disable Metrics/ClassLength
    class Schema
      # Generate complete JSON Schema v7 representation
      #
      # @return [Hash] JSON Schema draft-07 compliant schema
      def self.to_json_schema
        {
          '$schema': 'http://json-schema.org/draft-07/schema#',
          '$id': 'https://github.com/language-operator/language-operator-gem/schema/agent-dsl.json',
          title: 'Language Operator Agent DSL',
          description: 'Schema for defining autonomous AI agents using the Language Operator DSL',
          version: LanguageOperator::VERSION,
          type: 'object',
          properties: agent_properties,
          required: %w[name],
          definitions: all_definitions
        }
      end

      # Generate OpenAPI 3.0 specification for agent HTTP endpoints
      #
      # Generates an OpenAPI 3.0.3 spec documenting the HTTP API exposed by
      # reactive agents. This includes chat endpoints, webhooks, and health checks.
      #
      # @return [Hash] OpenAPI 3.0.3 compliant specification
      # @example Generate OpenAPI spec
      #   spec = LanguageOperator::Dsl::Schema.to_openapi
      #   File.write('openapi.json', JSON.pretty_generate(spec))
      def self.to_openapi
        {
          openapi: '3.0.3',
          info: openapi_info,
          servers: openapi_servers,
          paths: openapi_paths,
          components: openapi_components
        }
      end

      # Returns the schema version
      #
      # The schema version is directly linked to the gem version and follows semantic
      # versioning. Schema changes follow these rules:
      # - MAJOR: Breaking changes to DSL structure or behavior
      # - MINOR: New features, backward-compatible additions
      # - PATCH: Bug fixes, documentation improvements
      #
      # @return [String] Current schema version (e.g., "0.1.30")
      # @example
      #   LanguageOperator::Dsl::Schema.version
      #   # => "0.1.30"
      def self.version
        LanguageOperator::VERSION
      end

      # Returns array of safe agent DSL methods allowed in agent definitions
      #
      # Reads from Agent::Safety::ASTValidator::SAFE_AGENT_METHODS constant.
      # These methods are validated as safe for use in synthesized agent code.
      #
      # Includes methods for:
      # - Agent metadata (description, persona, objectives)
      # - Execution modes (mode, schedule)
      # - Workflows (workflow, step, depends_on, prompt)
      # - Constraints (budget, max_requests, rate_limit, content_filter)
      # - Output destinations (output)
      # - Endpoints (webhook, as_mcp_server, as_chat_endpoint)
      #
      # @return [Array<String>] Sorted array of safe agent method names
      # @example
      #   LanguageOperator::Dsl::Schema.safe_agent_methods
      #   # => ["agent", "as_chat_endpoint", "as_mcp_server", "budget", ...]
      def self.safe_agent_methods
        require_relative '../agent/safety/ast_validator'
        Agent::Safety::ASTValidator::SAFE_AGENT_METHODS.sort
      end

      # Returns array of safe tool DSL methods allowed in tool definitions
      #
      # Reads from Agent::Safety::ASTValidator::SAFE_TOOL_METHODS constant.
      # These methods are validated as safe for use in synthesized tool code.
      #
      # Includes methods for:
      # - Tool definition (tool, description)
      # - Parameters (parameter, type, required, default)
      # - Execution (execute)
      #
      # @return [Array<String>] Sorted array of safe tool method names
      # @example
      #   LanguageOperator::Dsl::Schema.safe_tool_methods
      #   # => ["default", "description", "execute", "parameter", "required", "tool", "type"]
      def self.safe_tool_methods
        require_relative '../agent/safety/ast_validator'
        Agent::Safety::ASTValidator::SAFE_TOOL_METHODS.sort
      end

      # Returns array of safe helper methods available in execute blocks
      #
      # Reads from Agent::Safety::ASTValidator::SAFE_HELPER_METHODS constant.
      # These helper methods are validated as safe for use in tool execute blocks.
      #
      # Includes helpers for:
      # - HTTP requests (HTTP.*)
      # - Shell commands (Shell.run)
      # - Validation (validate_url, validate_phone, validate_email)
      # - Environment variables (env_required, env_get)
      # - Utilities (truncate, parse_csv)
      # - Response formatting (error, success)
      #
      # @return [Array<String>] Sorted array of safe helper method names
      # @example
      #   LanguageOperator::Dsl::Schema.safe_helper_methods
      #   # => ["HTTP", "Shell", "env_get", "env_required", "error", ...]
      def self.safe_helper_methods
        require_relative '../agent/safety/ast_validator'
        Agent::Safety::ASTValidator::SAFE_HELPER_METHODS.sort
      end

      # Agent top-level properties
      #
      # @return [Hash] Schema properties for agent definition
      def self.agent_properties
        {
          name: {
            type: 'string',
            description: 'Unique agent identifier (lowercase, alphanumeric, hyphens)',
            pattern: '^[a-z0-9-]+$',
            minLength: 1,
            maxLength: 63
          },
          description: {
            type: 'string',
            description: 'Human-readable description of agent purpose'
          },
          persona: {
            type: 'string',
            description: 'System prompt or persona defining agent behavior and expertise'
          },
          schedule: {
            type: 'string',
            description: 'Cron expression for scheduled execution (sets mode to :scheduled)',
            pattern: '^\s*(\S+\s+){4}\S+\s*$'
          },
          mode: {
            type: 'string',
            description: 'Execution mode for the agent',
            enum: %w[autonomous scheduled reactive]
          },
          objectives: {
            type: 'array',
            description: 'List of goals the agent should achieve',
            items: {
              type: 'string'
            },
            minItems: 0
          },
          # DSL v1 (task/main model)
          tasks: {
            type: 'array',
            description: 'Task definitions (organic functions with stable contracts)',
            items: {
              '$ref': '#/definitions/TaskDefinition'
            }
          },
          main: {
            '$ref': '#/definitions/MainDefinition',
            description: 'Main execution block (imperative entry point)'
          },
          # DSL v0 (workflow/step model - deprecated)
          workflow: {
            '$ref': '#/definitions/WorkflowDefinition',
            description: 'Multi-step workflow (deprecated - use tasks and main instead)'
          },
          # Common properties
          constraints: {
            '$ref': '#/definitions/ConstraintsDefinition'
          },
          output: {
            '$ref': '#/definitions/OutputDefinition'
          },
          webhooks: {
            type: 'array',
            description: 'Webhook endpoints for reactive agents',
            items: {
              '$ref': '#/definitions/WebhookDefinition'
            }
          },
          mcp_server: {
            '$ref': '#/definitions/McpServerDefinition'
          },
          chat_endpoint: {
            '$ref': '#/definitions/ChatEndpointDefinition'
          }
        }
      end

      # All nested definition schemas
      #
      # @return [Hash] Schema definitions for nested types
      def self.all_definitions
        {
          # DSL v1 (task/main model)
          TaskDefinition: task_definition_schema,
          MainDefinition: main_definition_schema,
          TypeSchema: type_schema_definition,
          # DSL v0 (workflow/step model - deprecated but kept for migration)
          WorkflowDefinition: workflow_definition_schema,
          StepDefinition: step_definition_schema,
          # Common definitions
          ConstraintsDefinition: constraints_definition_schema,
          OutputDefinition: output_definition_schema,
          WebhookDefinition: webhook_definition_schema,
          WebhookAuthentication: webhook_authentication_schema,
          McpServerDefinition: mcp_server_definition_schema,
          ChatEndpointDefinition: chat_endpoint_definition_schema,
          ToolDefinition: tool_definition_schema,
          ParameterDefinition: parameter_definition_schema
        }
      end

      # Workflow definition schema
      #
      # @return [Hash] Schema for workflow definitions
      def self.workflow_definition_schema
        {
          type: 'object',
          description: 'Multi-step workflow with dependencies',
          properties: {
            steps: {
              type: 'array',
              description: 'Ordered list of workflow steps',
              items: {
                '$ref': '#/definitions/StepDefinition'
              }
            }
          }
        }
      end

      # Step definition schema (DSL v0 - deprecated)
      #
      # @return [Hash] Schema for workflow steps
      def self.step_definition_schema
        {
          type: 'object',
          description: 'Individual workflow step (deprecated - use TaskDefinition instead)',
          properties: {
            name: {
              type: 'string',
              description: 'Step identifier (symbol or string)'
            },
            tool: {
              type: 'string',
              description: 'Tool name to execute in this step'
            },
            params: {
              type: 'object',
              description: 'Parameters to pass to the tool',
              additionalProperties: true
            },
            depends_on: {
              oneOf: [
                { type: 'string' },
                {
                  type: 'array',
                  items: { type: 'string' }
                }
              ],
              description: 'Step dependencies (must complete before this step)'
            },
            prompt: {
              type: 'string',
              description: 'LLM prompt template for this step'
            }
          },
          required: %w[name]
        }
      end

      # Task definition schema (DSL v1)
      #
      # @return [Hash] Schema for task definitions (organic functions)
      def self.task_definition_schema
        {
          type: 'object',
          description: 'Organic function with stable contract (inputs/outputs) and evolving implementation',
          properties: {
            name: {
              type: 'string',
              description: 'Task identifier (symbol)',
              pattern: '^[a-z_][a-z0-9_]*$'
            },
            inputs: {
              '$ref': '#/definitions/TypeSchema',
              description: 'Input contract (parameter types)'
            },
            outputs: {
              '$ref': '#/definitions/TypeSchema',
              description: 'Output contract (return value types)'
            },
            instructions: {
              type: 'string',
              description: 'Natural language instructions for neural implementation (optional)'
            },
            implementation_type: {
              type: 'string',
              description: 'Implementation approach',
              enum: %w[neural symbolic hybrid undefined]
            }
          },
          required: %w[name inputs outputs]
        }
      end

      # Main definition schema (DSL v1)
      #
      # @return [Hash] Schema for main execution block
      def self.main_definition_schema
        {
          type: 'object',
          description: 'Imperative entry point for agent execution',
          properties: {
            type: {
              type: 'string',
              description: 'Block type',
              enum: ['main']
            },
            description: {
              type: 'string',
              description: 'Main block executes tasks using execute_task() with Ruby control flow'
            }
          },
          additionalProperties: false
        }
      end

      # Type schema definition (DSL v1)
      #
      # @return [Hash] Schema for type schemas used in task inputs/outputs
      def self.type_schema_definition
        {
          type: 'object',
          description: 'Type schema for task contract validation',
          patternProperties: {
            '^[a-z_][a-z0-9_]*$': {
              type: 'string',
              description: 'Parameter type',
              enum: %w[string integer number boolean array hash any]
            }
          },
          additionalProperties: false,
          examples: [
            {
              user_id: 'integer',
              name: 'string',
              active: 'boolean'
            },
            {
              data: 'array',
              metadata: 'hash'
            }
          ]
        }
      end

      # Constraints definition schema
      #
      # @return [Hash] Schema for constraint definitions
      def self.constraints_definition_schema
        {
          type: 'object',
          description: 'Execution constraints and limits',
          properties: {
            max_iterations: {
              type: 'integer',
              description: 'Maximum number of execution iterations',
              minimum: 1
            },
            timeout: {
              type: 'string',
              description: 'Execution timeout (e.g., "30s", "5m", "1h")',
              pattern: '^\d+[smh]$'
            },
            memory: {
              type: 'string',
              description: 'Memory limit (e.g., "512Mi", "1Gi")'
            },
            rate_limit: {
              type: 'integer',
              description: 'Maximum requests per time period',
              minimum: 1
            },
            daily_budget: {
              type: 'number',
              description: 'Maximum daily cost in USD',
              minimum: 0
            },
            hourly_budget: {
              type: 'number',
              description: 'Maximum hourly cost in USD',
              minimum: 0
            },
            token_budget: {
              type: 'integer',
              description: 'Maximum total tokens allowed',
              minimum: 1
            },
            requests_per_minute: {
              type: 'integer',
              description: 'Maximum requests per minute',
              minimum: 1
            },
            requests_per_hour: {
              type: 'integer',
              description: 'Maximum requests per hour',
              minimum: 1
            },
            requests_per_day: {
              type: 'integer',
              description: 'Maximum requests per day',
              minimum: 1
            },
            blocked_patterns: {
              type: 'array',
              description: 'Content patterns to block',
              items: { type: 'string' }
            },
            blocked_topics: {
              type: 'array',
              description: 'Topics to avoid',
              items: { type: 'string' }
            }
          }
        }
      end

      # Output definition schema
      #
      # @return [Hash] Schema for output configuration
      def self.output_definition_schema
        {
          type: 'object',
          description: 'Output destination configuration',
          properties: {
            workspace: {
              type: 'string',
              description: 'Workspace directory path for file outputs'
            },
            slack: {
              type: 'object',
              description: 'Slack integration configuration',
              properties: {
                channel: {
                  type: 'string',
                  description: 'Slack channel name or ID'
                }
              },
              required: %w[channel]
            },
            email: {
              type: 'object',
              description: 'Email notification configuration',
              properties: {
                to: {
                  type: 'string',
                  description: 'Email recipient address',
                  format: 'email'
                }
              },
              required: %w[to]
            }
          }
        }
      end

      # Webhook definition schema
      #
      # @return [Hash] Schema for webhook definitions
      def self.webhook_definition_schema
        {
          type: 'object',
          description: 'Webhook endpoint configuration',
          properties: {
            path: {
              type: 'string',
              description: 'URL path for webhook endpoint',
              pattern: '^/'
            },
            method: {
              type: 'string',
              description: 'HTTP method',
              enum: %w[get post put delete patch],
              default: 'post'
            },
            authentication: {
              '$ref': '#/definitions/WebhookAuthentication'
            },
            validations: {
              type: 'array',
              description: 'Request validation rules',
              items: {
                type: 'object',
                properties: {
                  type: {
                    type: 'string',
                    enum: %w[headers content_type custom]
                  }
                }
              }
            }
          },
          required: %w[path]
        }
      end

      # Webhook authentication schema
      #
      # @return [Hash] Schema for webhook authentication
      def self.webhook_authentication_schema
        {
          type: 'object',
          description: 'Webhook authentication configuration',
          properties: {
            type: {
              type: 'string',
              description: 'Authentication type',
              enum: %w[hmac api_key bearer custom]
            },
            secret: {
              type: 'string',
              description: 'Secret key for authentication'
            },
            header: {
              type: 'string',
              description: 'Header name containing signature/token'
            },
            algorithm: {
              type: 'string',
              description: 'HMAC algorithm',
              enum: %w[sha1 sha256 sha512]
            },
            prefix: {
              type: 'string',
              description: 'Signature prefix (e.g., "sha256=")'
            }
          }
        }
      end

      # MCP server definition schema
      #
      # @return [Hash] Schema for MCP server definitions
      def self.mcp_server_definition_schema
        {
          type: 'object',
          description: 'MCP (Model Context Protocol) server configuration',
          properties: {
            name: {
              type: 'string',
              description: 'MCP server name'
            },
            tools: {
              type: 'object',
              description: 'Tools exposed via MCP',
              additionalProperties: {
                '$ref': '#/definitions/ToolDefinition'
              }
            }
          }
        }
      end

      # Chat endpoint definition schema
      #
      # @return [Hash] Schema for chat endpoint definitions
      def self.chat_endpoint_definition_schema
        {
          type: 'object',
          description: 'OpenAI-compatible chat endpoint configuration',
          properties: {
            system_prompt: {
              type: 'string',
              description: 'System prompt for chat mode'
            },
            temperature: {
              type: 'number',
              description: 'Sampling temperature (0.0-2.0)',
              minimum: 0.0,
              maximum: 2.0,
              default: 0.7
            },
            max_tokens: {
              type: 'integer',
              description: 'Maximum tokens in response',
              minimum: 1,
              default: 2000
            },
            model_name: {
              type: 'string',
              description: 'Model name exposed in API'
            },
            top_p: {
              type: 'number',
              description: 'Nucleus sampling parameter (0.0-1.0)',
              minimum: 0.0,
              maximum: 1.0,
              default: 1.0
            },
            frequency_penalty: {
              type: 'number',
              description: 'Frequency penalty (-2.0 to 2.0)',
              minimum: -2.0,
              maximum: 2.0,
              default: 0.0
            },
            presence_penalty: {
              type: 'number',
              description: 'Presence penalty (-2.0 to 2.0)',
              minimum: -2.0,
              maximum: 2.0,
              default: 0.0
            },
            stop_sequences: {
              type: 'array',
              description: 'Sequences that stop generation',
              items: { type: 'string' }
            }
          }
        }
      end

      # Tool definition schema
      #
      # @return [Hash] Schema for tool definitions
      def self.tool_definition_schema
        {
          type: 'object',
          description: 'MCP tool definition',
          properties: {
            name: {
              type: 'string',
              description: 'Tool name (lowercase, alphanumeric, underscores)',
              pattern: '^[a-z0-9_]+$'
            },
            description: {
              type: 'string',
              description: 'Human-readable tool description'
            },
            parameters: {
              type: 'object',
              description: 'Tool parameters',
              additionalProperties: {
                '$ref': '#/definitions/ParameterDefinition'
              }
            }
          },
          required: %w[name description]
        }
      end

      # Parameter definition schema
      #
      # @return [Hash] Schema for parameter definitions
      def self.parameter_definition_schema
        {
          type: 'object',
          description: 'Tool parameter definition',
          properties: {
            type: {
              type: 'string',
              description: 'Parameter type',
              enum: %w[string number integer boolean array object]
            },
            description: {
              type: 'string',
              description: 'Parameter description'
            },
            required: {
              type: 'boolean',
              description: 'Whether parameter is required',
              default: false
            },
            default: {
              description: 'Default value if not provided'
            },
            enum: {
              type: 'array',
              description: 'Allowed values',
              items: {}
            }
          },
          required: %w[type]
        }
      end

      # OpenAPI info section
      #
      # @return [Hash] OpenAPI info object
      def self.openapi_info
        {
          title: 'Language Operator Agent API',
          version: LanguageOperator::VERSION,
          description: 'HTTP API endpoints exposed by Language Operator reactive agents',
          contact: {
            name: 'Language Operator',
            url: 'https://github.com/language-operator/language-operator-gem'
          },
          license: {
            name: 'FSL-1.1-Apache-2.0',
            url: 'https://github.com/language-operator/language-operator-gem/blob/main/LICENSE'
          }
        }
      end

      # OpenAPI servers section
      #
      # @return [Array<Hash>] OpenAPI server objects
      def self.openapi_servers
        [
          {
            url: 'http://localhost:8080',
            description: 'Local development server'
          }
        ]
      end

      # OpenAPI paths section - documents all HTTP endpoints
      #
      # @return [Hash] OpenAPI paths object
      def self.openapi_paths
        {
          '/health' => health_endpoint_spec,
          '/ready' => ready_endpoint_spec,
          '/v1/chat/completions' => chat_completions_endpoint_spec,
          '/v1/models' => models_endpoint_spec
        }
      end

      # OpenAPI components section - reusable schemas
      #
      # @return [Hash] OpenAPI components object
      def self.openapi_components
        {
          schemas: {
            ChatCompletionRequest: chat_completion_request_schema,
            ChatCompletionResponse: chat_completion_response_schema,
            ChatMessage: chat_message_schema,
            ChatChoice: chat_choice_schema,
            ChatUsage: chat_usage_schema,
            ModelList: model_list_schema,
            Model: model_schema,
            HealthResponse: health_response_schema,
            ErrorResponse: error_response_schema
          }
        }
      end

      # Health check endpoint spec
      #
      # @return [Hash] OpenAPI path item
      def self.health_endpoint_spec
        {
          get: {
            summary: 'Health check',
            description: 'Returns the health status of the agent',
            operationId: 'getHealth',
            tags: ['Health'],
            responses: {
              '200': {
                description: 'Agent is healthy',
                content: {
                  'application/json': {
                    schema: {
                      '$ref': '#/components/schemas/HealthResponse'
                    }
                  }
                }
              }
            }
          }
        }
      end

      # Readiness check endpoint spec
      #
      # @return [Hash] OpenAPI path item
      def self.ready_endpoint_spec
        {
          get: {
            summary: 'Readiness check',
            description: 'Returns whether the agent is ready to accept requests',
            operationId: 'getReady',
            tags: ['Health'],
            responses: {
              '200': {
                description: 'Agent is ready',
                content: {
                  'application/json': {
                    schema: {
                      '$ref': '#/components/schemas/HealthResponse'
                    }
                  }
                }
              },
              '503': {
                description: 'Agent is not ready',
                content: {
                  'application/json': {
                    schema: {
                      '$ref': '#/components/schemas/ErrorResponse'
                    }
                  }
                }
              }
            }
          }
        }
      end

      # Chat completions endpoint spec (OpenAI-compatible)
      #
      # @return [Hash] OpenAPI path item
      def self.chat_completions_endpoint_spec
        {
          post: {
            summary: 'Create chat completion',
            description: 'Creates a chat completion response (OpenAI-compatible endpoint)',
            operationId: 'createChatCompletion',
            tags: ['Chat'],
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    '$ref': '#/components/schemas/ChatCompletionRequest'
                  }
                }
              }
            },
            responses: {
              '200': {
                description: 'Successful chat completion response',
                content: {
                  'application/json': {
                    schema: {
                      '$ref': '#/components/schemas/ChatCompletionResponse'
                    }
                  },
                  'text/event-stream': {
                    description: 'Server-sent events stream (when stream=true)',
                    schema: {
                      type: 'string'
                    }
                  }
                }
              },
              '400': {
                description: 'Invalid request',
                content: {
                  'application/json': {
                    schema: {
                      '$ref': '#/components/schemas/ErrorResponse'
                    }
                  }
                }
              }
            }
          }
        }
      end

      # Models list endpoint spec (OpenAI-compatible)
      #
      # @return [Hash] OpenAPI path item
      def self.models_endpoint_spec
        {
          get: {
            summary: 'List models',
            description: 'Lists available models (OpenAI-compatible endpoint)',
            operationId: 'listModels',
            tags: ['Models'],
            responses: {
              '200': {
                description: 'List of available models',
                content: {
                  'application/json': {
                    schema: {
                      '$ref': '#/components/schemas/ModelList'
                    }
                  }
                }
              }
            }
          }
        }
      end

      # Chat completion request schema
      #
      # @return [Hash] OpenAPI schema object
      def self.chat_completion_request_schema
        {
          type: 'object',
          required: %w[model messages],
          properties: {
            model: {
              type: 'string',
              description: 'Model name to use for completion'
            },
            messages: {
              type: 'array',
              description: 'List of messages in the conversation',
              items: {
                '$ref': '#/components/schemas/ChatMessage'
              }
            },
            temperature: {
              type: 'number',
              description: 'Sampling temperature (0.0-2.0)',
              minimum: 0.0,
              maximum: 2.0,
              default: 0.7
            },
            max_tokens: {
              type: 'integer',
              description: 'Maximum tokens in response',
              minimum: 1,
              default: 2000
            },
            stream: {
              type: 'boolean',
              description: 'Stream responses as server-sent events',
              default: false
            },
            top_p: {
              type: 'number',
              description: 'Nucleus sampling parameter',
              minimum: 0.0,
              maximum: 1.0,
              default: 1.0
            },
            frequency_penalty: {
              type: 'number',
              description: 'Frequency penalty (-2.0 to 2.0)',
              minimum: -2.0,
              maximum: 2.0,
              default: 0.0
            },
            presence_penalty: {
              type: 'number',
              description: 'Presence penalty (-2.0 to 2.0)',
              minimum: -2.0,
              maximum: 2.0,
              default: 0.0
            },
            stop: {
              oneOf: [
                { type: 'string' },
                {
                  type: 'array',
                  items: { type: 'string' }
                }
              ],
              description: 'Stop sequences for generation'
            }
          }
        }
      end

      # Chat completion response schema
      #
      # @return [Hash] OpenAPI schema object
      def self.chat_completion_response_schema
        {
          type: 'object',
          required: %w[id object created model choices],
          properties: {
            id: {
              type: 'string',
              description: 'Unique identifier for the completion'
            },
            object: {
              type: 'string',
              description: 'Object type (always "chat.completion")',
              enum: ['chat.completion']
            },
            created: {
              type: 'integer',
              description: 'Unix timestamp of creation'
            },
            model: {
              type: 'string',
              description: 'Model used for completion'
            },
            choices: {
              type: 'array',
              description: 'List of completion choices',
              items: {
                '$ref': '#/components/schemas/ChatChoice'
              }
            },
            usage: {
              '$ref': '#/components/schemas/ChatUsage'
            }
          }
        }
      end

      # Chat message schema
      #
      # @return [Hash] OpenAPI schema object
      def self.chat_message_schema
        {
          type: 'object',
          required: %w[role content],
          properties: {
            role: {
              type: 'string',
              description: 'Message role',
              enum: %w[system user assistant]
            },
            content: {
              type: 'string',
              description: 'Message content'
            },
            name: {
              type: 'string',
              description: 'Optional name of the message author'
            }
          }
        }
      end

      # Chat choice schema
      #
      # @return [Hash] OpenAPI schema object
      def self.chat_choice_schema
        {
          type: 'object',
          required: %w[index message finish_reason],
          properties: {
            index: {
              type: 'integer',
              description: 'Choice index'
            },
            message: {
              '$ref': '#/components/schemas/ChatMessage'
            },
            finish_reason: {
              type: 'string',
              description: 'Reason for completion finish',
              enum: %w[stop length content_filter null]
            }
          }
        }
      end

      # Chat usage schema
      #
      # @return [Hash] OpenAPI schema object
      def self.chat_usage_schema
        {
          type: 'object',
          required: %w[prompt_tokens completion_tokens total_tokens],
          properties: {
            prompt_tokens: {
              type: 'integer',
              description: 'Tokens in the prompt'
            },
            completion_tokens: {
              type: 'integer',
              description: 'Tokens in the completion'
            },
            total_tokens: {
              type: 'integer',
              description: 'Total tokens used'
            }
          }
        }
      end

      # Model list schema
      #
      # @return [Hash] OpenAPI schema object
      def self.model_list_schema
        {
          type: 'object',
          required: %w[object data],
          properties: {
            object: {
              type: 'string',
              description: 'Object type (always "list")',
              enum: ['list']
            },
            data: {
              type: 'array',
              description: 'List of available models',
              items: {
                '$ref': '#/components/schemas/Model'
              }
            }
          }
        }
      end

      # Model schema
      #
      # @return [Hash] OpenAPI schema object
      def self.model_schema
        {
          type: 'object',
          required: %w[id object],
          properties: {
            id: {
              type: 'string',
              description: 'Model identifier'
            },
            object: {
              type: 'string',
              description: 'Object type (always "model")',
              enum: ['model']
            },
            created: {
              type: 'integer',
              description: 'Unix timestamp of model creation'
            },
            owned_by: {
              type: 'string',
              description: 'Organization that owns the model'
            }
          }
        }
      end

      # Health response schema
      #
      # @return [Hash] OpenAPI schema object
      def self.health_response_schema
        {
          type: 'object',
          required: %w[status],
          properties: {
            status: {
              type: 'string',
              description: 'Health status',
              enum: %w[ok ready]
            },
            timestamp: {
              type: 'string',
              format: 'date-time',
              description: 'Timestamp of health check'
            }
          }
        }
      end

      # Error response schema
      #
      # @return [Hash] OpenAPI schema object
      def self.error_response_schema
        {
          type: 'object',
          required: %w[error],
          properties: {
            error: {
              type: 'object',
              required: %w[message type],
              properties: {
                message: {
                  type: 'string',
                  description: 'Error message'
                },
                type: {
                  type: 'string',
                  description: 'Error type'
                },
                code: {
                  type: 'string',
                  description: 'Error code'
                }
              }
            }
          }
        }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
