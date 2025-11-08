#!/usr/bin/env ruby
# frozen_string_literal: true

# Example agent that exposes tools via MCP protocol
#
# This demonstrates Phase 3: Agents as MCP Servers
# The agent exposes tools that other agents or MCP clients can call
#
# Usage:
#   PORT=8080 ruby examples/mcp_agent.rb
#
# Test MCP protocol:
#   curl -X POST http://localhost:8080/mcp \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
#
# Test webhook:
#   curl -X POST http://localhost:8080/webhook \
#     -H "Content-Type: application/json" \
#     -d '{"message": "test"}'

require 'bundler/setup'
require 'language_operator'
require 'language_operator/dsl'

# Define an agent that acts as both a webhook receiver and MCP server
# rubocop:disable Metrics/BlockLength
LanguageOperator::Dsl.define do
  agent 'data-processor-mcp' do
    description 'Data processing agent that exposes MCP tools'
    mode :reactive

    # Define tools this agent exposes via MCP
    as_mcp_server do
      # Tool 1: Process CSV data
      tool 'process_csv' do
        description 'Process CSV data and return summary statistics'

        parameter :csv_data do
          type :string
          required true
          description 'CSV data as string'
        end

        execute do |params|
          # Simple CSV processing example
          lines = params['csv_data'].split("\n")
          headers = lines.first&.split(',') || []
          data_rows = lines[1..]

          {
            total_rows: data_rows&.length || 0,
            total_columns: headers.length,
            headers: headers,
            sample: data_rows&.first || ''
          }.to_json
        end
      end

      # Tool 2: Calculate statistics
      tool 'calculate_stats' do
        description 'Calculate basic statistics for a list of numbers'

        parameter :numbers do
          type :array
          required true
          description 'Array of numbers'
        end

        execute do |params|
          nums = params['numbers']
          return { error: 'Empty array' }.to_json if nums.empty?

          sum = nums.sum
          mean = sum.to_f / nums.length
          sorted = nums.sort
          median = if nums.length.odd?
                     sorted[nums.length / 2]
                   else
                     (sorted[(nums.length / 2) - 1] + sorted[nums.length / 2]) / 2.0
                   end

          {
            count: nums.length,
            sum: sum,
            mean: mean,
            median: median,
            min: nums.min,
            max: nums.max
          }.to_json
        end
      end

      # Tool 3: Format data
      tool 'format_json' do
        description 'Format and validate JSON data'

        parameter :json_string do
          type :string
          required true
          description 'JSON string to format'
        end

        parameter :indent do
          type :number
          required false
          description 'Indentation spaces (default: 2)'
        end

        execute do |params|
          indent = params['indent'] || 2
          parsed = JSON.parse(params['json_string'])
          JSON.pretty_generate(parsed, indent: ' ' * indent.to_i)
        rescue JSON::ParserError => e
          { error: "Invalid JSON: #{e.message}" }.to_json
        end
      end
    end

    # Also expose a webhook endpoint
    webhook '/process' do
      method :post
      on_request do |_context|
        {
          status: 'processed',
          message: 'Data received for processing',
          tools_available: 3,
          mcp_endpoint: '/mcp'
        }
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength

# Get the agent definition and run it
agent_def = LanguageOperator::Dsl.agent_registry.get('data-processor-mcp')

if agent_def
  puts "Starting MCP agent on port #{ENV.fetch('PORT', '8080')}"
  puts 'Available endpoints:'
  puts '  GET  /health        - Health check'
  puts '  GET  /ready         - Readiness check'
  puts '  POST /webhook       - Webhook endpoint'
  puts '  POST /process       - Data processing endpoint'
  puts '  POST /mcp           - MCP protocol endpoint'
  puts
  puts 'MCP Tools:'
  puts '  - process_csv       - Process CSV data'
  puts '  - calculate_stats   - Calculate statistics'
  puts '  - format_json       - Format JSON data'
  puts "\nPress Ctrl+C to stop\n\n"

  agent_def.run!
else
  puts 'Error: Agent definition not found'
  exit 1
end
