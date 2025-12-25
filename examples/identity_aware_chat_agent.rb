#!/usr/bin/env ruby
# frozen_string_literal: true

# Identity-Aware Chat Agent Example
#
# This example demonstrates automatic persona-driven system prompts that provide
# ALL agents with awareness of their identity, role, environment, and operational context.
#
# Key Features (AUTOMATIC):
# - Agent knows its name, role, and purpose
# - Operational context (uptime, cluster, status) awareness  
# - Environment information (namespace, tools available)
# - Professional, contextual conversation style
#
# Usage:
#   ruby examples/identity_aware_chat_agent.rb
#
# Test with:
#   curl -X POST http://localhost:8080/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "say-something-v2", "messages": [{"role": "user", "content": "hello"}]}'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'language_operator'

# Define an identity-aware agent
LanguageOperator::Dsl.define do
  agent "say-something" do
    description "A helpful assistant that specializes in creating engaging, concise messages and interactions. You excel at understanding context and providing meaningful responses that fit the conversation."
    mode :reactive

    # Identity-aware chat endpoint is automatic! 
    # No configuration needed - every agent gets it by default.

    # Add some constraints for safety
    constraints do
      timeout '30s'
      requests_per_minute 20
      daily_budget 500  # $5/day
    end
  end
end

# Start the agent
if __FILE__ == $PROGRAM_NAME
  puts "🚀 Starting Identity-Aware Say-Something Agent..."
  puts ""
  puts "ALL agents automatically include persona-driven system prompts with:"
  puts "  ✓ Agent identity awareness (name, role, purpose)"
  puts "  ✓ Operational context (uptime, status, environment)"  
  puts "  ✓ Dynamic prompt generation based on current state"
  puts "  ✓ Professional, contextual conversation style"
  puts ""
  puts "Server will be available at http://localhost:8080"
  puts ""
  puts "📝 Example conversation:"
  puts "  User: 'hello'"
  puts "  Agent: 'Hello! I'm say-something, running in the code-games cluster."
  puts "         I've been active for 15m now, helping log interesting messages"
  puts "         and interactions. How can I assist you today?'"
  puts ""
  puts "🔧 Endpoints:"
  puts "  POST /v1/chat/completions - Chat completion (OpenAI-compatible)"
  puts "  GET  /v1/models          - List available models"
  puts "  GET  /health             - Health check"
  puts "  GET  /ready              - Readiness check"
  puts ""
  puts "🧪 Test command:"
  puts "  curl -X POST http://localhost:8080/v1/chat/completions \\"
  puts "    -H 'Content-Type: application/json' \\"
  puts '    -d \'{"model": "say-something-v2", "messages": [{"role": "user", "content": "hello"}]}\''
  puts ""
  puts "💡 Try different questions to see automatic identity awareness:"
  puts "  - 'hello' or 'hi there' for context-aware introductions"
  puts "  - 'what are you?' or 'tell me about yourself'"
  puts "  - 'how long have you been running?'"
  puts "  - 'what can you do?' or 'what tools do you have?'"
  puts "  - 'what cluster are you in?'"
  puts ""
  
  LanguageOperator::Agent.run
end