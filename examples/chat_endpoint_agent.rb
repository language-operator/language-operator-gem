#!/usr/bin/env ruby
# frozen_string_literal: true

# Example agent that exposes an OpenAI-compatible chat completion endpoint
#
# This demonstrates Phase 4: Agents as Chat Completion Endpoints
# The agent can be used as a drop-in replacement for OpenAI's API
#
# Usage:
#   PORT=8080 ruby examples/chat_endpoint_agent.rb
#
# Test non-streaming:
#   curl -X POST http://localhost:8080/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "github-expert",
#       "messages": [{"role": "user", "content": "How do I create a PR?"}]
#     }'
#
# Test streaming:
#   curl -X POST http://localhost:8080/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "github-expert",
#       "messages": [{"role": "user", "content": "How do I create a PR?"}],
#       "stream": true
#     }'
#
# Test with OpenAI SDK:
#   require 'openai'
#   client = OpenAI::Client.new(
#     access_token: "not-needed",
#     uri_base: "http://localhost:8080/v1/"
#   )
#   response = client.chat(
#     parameters: {
#       model: "github-expert",
#       messages: [{role: "user", content: "How do I create a PR?"}]
#     }
#   )

require 'bundler/setup'
require 'language_operator'
require 'language_operator/dsl'

# Define an agent that acts as a GitHub expert LLM
LanguageOperator::Dsl.define do
  agent 'github-expert' do
    description 'GitHub API and workflow expert'
    mode :reactive

    # Configure as an OpenAI-compatible chat endpoint
    as_chat_endpoint do
      system_prompt <<~PROMPT
        You are a GitHub expert assistant with deep knowledge of:
        - GitHub API and workflows
        - Pull requests, issues, and code review
        - GitHub Actions and CI/CD
        - Repository management and best practices

        Provide helpful, accurate answers about GitHub topics.
        Keep responses concise but informative.
      PROMPT

      # Model parameters
      model 'github-expert-v1'
      temperature 0.7
      max_tokens 2000
    end

    # Optionally, also expose as webhook
    webhook '/github/webhook' do
      method :post
      on_request do |_context|
        {
          status: 'received',
          message: 'GitHub webhook processed',
          chat_endpoint: '/v1/chat/completions'
        }
      end
    end
  end
end
# Get the agent definition and run it
agent_def = LanguageOperator::Dsl.agent_registry.get('github-expert')

if agent_def
  puts "Starting GitHub Expert agent on port #{ENV.fetch('PORT', '8080')}"
  puts
  puts 'OpenAI-Compatible Endpoints:'
  puts '  POST /v1/chat/completions - Chat completion (streaming & non-streaming)'
  puts '  GET  /v1/models           - List available models'
  puts
  puts 'Additional Endpoints:'
  puts '  GET  /health              - Health check'
  puts '  GET  /ready               - Readiness check'
  puts '  POST /github/webhook      - GitHub webhook endpoint'
  puts
  puts 'Test with curl:'
  puts <<~CURL
    curl -X POST http://localhost:8080/v1/chat/completions \\
      -H "Content-Type: application/json" \\
      -d '{"model": "github-expert-v1", "messages": [{"role": "user", "content": "How do I create a PR?"}]}'
  CURL
  puts
  puts 'Test streaming:'
  puts <<~CURL
    curl -N -X POST http://localhost:8080/v1/chat/completions \\
      -H "Content-Type: application/json" \\
      -d '{"model": "github-expert-v1", "messages": [{"role": "user", "content": "Explain GitHub Actions"}], "stream": true}'
  CURL
  puts "\nPress Ctrl+C to stop\n\n"

  agent_def.run!
else
  puts 'Error: Agent definition not found'
  exit 1
end
