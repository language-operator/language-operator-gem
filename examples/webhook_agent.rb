#!/usr/bin/env ruby
# frozen_string_literal: true

# Example webhook agent that demonstrates the reactive/HTTP server capability
#
# Usage:
#   PORT=8080 ruby examples/webhook_agent.rb
#
# Test with curl:
#   curl -X POST http://localhost:8080/webhook -H "Content-Type: application/json" -d '{"event": "test"}'
#   curl http://localhost:8080/health

require 'bundler/setup'
require 'language_operator'
require 'language_operator/dsl'

# Define a webhook agent using the DSL
LanguageOperator::Dsl.define do
  agent 'example-webhook-handler' do
    description 'Example agent that handles HTTP webhooks'
    mode :reactive

    # Health check endpoint (already provided by default)
    # GET /health

    # Custom webhook endpoint
    webhook '/webhook' do
      method :post
      on_request do |context|
        puts "\n=== Received Webhook ==="
        puts "Method: #{context[:method]}"
        puts "Path: #{context[:path]}"
        puts "Body: #{context[:body]}"
        puts "Params: #{context[:params].inspect}"
        puts "========================\n"

        {
          status: 'received',
          message: 'Webhook processed successfully',
          received_data: context[:params]
        }
      end
    end

    # GitHub-style webhook endpoint
    webhook '/github/pr' do
      method :post
      on_request do |context|
        puts "\n=== GitHub PR Webhook ==="
        puts "Simulating PR review..."
        puts "============================\n"

        {
          status: 'pr_reviewed',
          message: 'Pull request review queued'
        }
      end
    end
  end
end

# Get the agent definition and run it
agent_def = LanguageOperator::Dsl.agent_registry.get('example-webhook-handler')

if agent_def
  puts "Starting webhook agent on port #{ENV.fetch('PORT', '8080')}"
  puts "Available endpoints:"
  puts "  GET  /health        - Health check"
  puts "  GET  /ready         - Readiness check"
  puts "  POST /webhook       - Generic webhook"
  puts "  POST /github/pr     - GitHub PR webhook"
  puts "\nPress Ctrl+C to stop\n\n"

  agent_def.run!
else
  puts "Error: Agent definition not found"
  exit 1
end
