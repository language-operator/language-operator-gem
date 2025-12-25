#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic Agent with Default Chat Endpoint
#
# This example demonstrates that agents automatically expose chat endpoints
# without explicitly defining them via as_chat_endpoint.
#
# This agent:
# - Runs autonomous work (logging every 10 seconds)  
# - Automatically exposes chat endpoint at /v1/chat/completions
# - No explicit as_chat_endpoint block needed!
#
# Usage:
#   ruby examples/basic_agent_with_default_chat.rb
#
# Test default chat endpoint:
#   curl -X POST http://localhost:8080/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "basic-worker",
#       "messages": [
#         {"role": "user", "content": "What are you doing right now?"}
#       ]
#     }'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'language_operator'

# Define a basic agent - NO explicit chat endpoint!
agent "basic-worker" do
  description "Simple worker that performs basic tasks"
  mode :autonomous

  # Simple main loop - this is the autonomous work
  task :do_work,
    instructions: "Perform some basic work and log progress",
    inputs: {},
    outputs: { 
      work_done: 'boolean',
      message: 'string',
      timestamp: 'string'
    }

  main do |inputs|
    puts "🔨 Performing autonomous work..."
    
    # Execute the work task
    work_result = execute_task(:do_work)
    
    puts "✅ Work completed: #{work_result[:message]}"
    puts "😴 Sleeping for 10 seconds..."
    
    sleep 10
    
    work_result
  end

  # Basic constraints
  constraints do
    max_iterations 999999
    timeout '30s'
  end
end

# Start the agent
if __FILE__ == $PROGRAM_NAME
  puts "🚀 Starting Basic Agent with Default Chat Endpoint"
  puts ""
  puts "This agent demonstrates automatic chat endpoint creation:"
  puts "  ✅ Runs autonomous work every 10 seconds" 
  puts "  ✅ Automatically exposes chat at /v1/chat/completions"
  puts "  ✅ No explicit as_chat_endpoint block needed!"
  puts ""
  puts "Agent info:"
  puts "  Name: basic-worker"
  puts "  Description: Simple worker that performs basic tasks"
  puts "  Mode: autonomous"
  puts ""
  puts "Available endpoints (auto-generated):"
  puts "  POST /v1/chat/completions - Chat with basic-worker"
  puts "  GET  /v1/models          - Available models"
  puts "  GET  /health             - Health check"
  puts "  GET  /ready              - Readiness check"
  puts ""
  puts "Test command:"
  puts "curl -X POST http://localhost:8080/v1/chat/completions \\"
  puts '  -H "Content-Type: application/json" \\'
  puts '  -d \'{"model": "basic-worker", "messages": [{"role": "user", "content": "What are you doing?"}]}\''
  puts ""
  puts "Expected system prompt (auto-generated):"
  puts '"You are simple worker that performs basic tasks. Provide helpful assistance based on your capabilities."'
  puts ""
  puts "Press Ctrl+C to stop"
  puts "=" * 80
  
  LanguageOperator::Agent.run
end