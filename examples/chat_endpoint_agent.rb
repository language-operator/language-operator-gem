#!/usr/bin/env ruby
# frozen_string_literal: true

# Chat Endpoint Agent Example
#
# This example demonstrates how to create an agent that exposes 
# an OpenAI-compatible chat completion endpoint.
#
# Usage:
#   ruby examples/chat_endpoint_agent.rb
#
# Then test with curl:
#   curl -X POST http://localhost:8080/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "github-expert-v1",
#       "messages": [
#         {"role": "user", "content": "How do I create a pull request?"}
#       ]
#     }'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'language_operator'

# Define an agent with chat endpoint capabilities
LanguageOperator::Dsl.define do
  agent "github-expert" do
    description "You are a GitHub expert assistant with deep knowledge of GitHub API, workflows, pull requests, issues, code review, GitHub Actions, CI/CD, and repository management best practices"
    mode :reactive

    # Chat endpoint is automatic! No configuration needed.
    # Every agent automatically gets:
    # - OpenAI-compatible chat endpoint at /v1/chat/completions
    # - Identity-aware responses with agent context
    # - Operational state awareness (uptime, cluster, etc.)
    # - Professional, contextual conversation style

    # Optional: Add constraints for safety and cost management
    constraints do
      timeout '30s'
      requests_per_minute 30
      daily_budget 1000  # $10/day
    end
  end
end

# Start the agent
if __FILE__ == $PROGRAM_NAME
  puts "Starting GitHub Expert Chat Endpoint Agent..."
  puts "Server will be available at http://localhost:8080"
  puts ""
  puts "Endpoints available:"
  puts "  POST /v1/chat/completions - Chat completion (OpenAI-compatible)"
  puts "  GET  /v1/models          - List available models"
  puts "  GET  /health             - Health check"
  puts "  GET  /ready              - Readiness check"
  puts ""
  puts "Test with curl:"
  puts '  curl -X POST http://localhost:8080/v1/chat/completions \\'
  puts '    -H "Content-Type: application/json" \\'
  puts '    -d \'{"model": "github-expert-v1", "messages": [{"role": "user", "content": "How do I create a pull request?"}]}\''
  puts ""
  
  LanguageOperator::Agent.run
end