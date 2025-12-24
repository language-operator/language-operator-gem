#!/usr/bin/env ruby
# frozen_string_literal: true

# Hybrid Agent Example
#
# This demonstrates an agent that runs BOTH:
# 1. Continuous autonomous work (background monitoring)
# 2. Chat endpoint for interactive queries
#
# The agent will:
# - Monitor system status every 30 seconds (autonomous mode)
# - Expose chat endpoint at /v1/chat/completions (web server)
# - Handle webhooks for alerts (reactive features)
#
# Usage:
#   ruby examples/hybrid_agent.rb
#
# Test chat endpoint:
#   curl -X POST http://localhost:8080/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "system-monitor-v1",
#       "messages": [
#         {"role": "user", "content": "What is the current system status?"}
#       ]
#     }'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'language_operator'

# Define a hybrid agent
LanguageOperator::Dsl.define do
  agent "system-monitor" do
    description "Autonomous system monitor with chat interface"
    
    # This agent runs in autonomous mode (continuous loop)
    mode :autonomous
    
    # Define the main autonomous work
    task :check_system_status,
      instructions: "Check current system status (CPU, memory, disk, network)",
      inputs: {},
      outputs: { 
        status: 'string',
        cpu_usage: 'number',
        memory_usage: 'number',
        disk_usage: 'number',
        timestamp: 'string'
      }

    task :analyze_trends,
      instructions: "Analyze system trends and identify potential issues",
      inputs: { 
        status: 'string',
        cpu_usage: 'number',
        memory_usage: 'number',
        disk_usage: 'number'
      },
      outputs: { 
        analysis: 'string',
        alerts: 'array'
      }

    task :log_status,
      instructions: "Log the system status and analysis",
      inputs: {
        status: 'string',
        analysis: 'string',
        alerts: 'array',
        timestamp: 'string'
      },
      outputs: { logged: 'boolean' }

    # Main autonomous loop - runs continuously
    main do |inputs|
      puts "🔄 Running system monitoring cycle..."
      
      # Check system status
      status_data = execute_task(:check_system_status)
      puts "📊 System status: #{status_data[:status]} (CPU: #{status_data[:cpu_usage]}%)"
      
      # Analyze trends
      analysis_data = execute_task(:analyze_trends, inputs: status_data)
      
      # Log results
      execute_task(:log_status, inputs: status_data.merge(analysis_data))
      
      if analysis_data[:alerts].any?
        puts "⚠️  Alerts: #{analysis_data[:alerts].join(', ')}"
      end
      
      puts "😴 Sleeping for 30 seconds..."
      sleep 30
      
      # Return data for next cycle
      status_data.merge(analysis_data)
    end

    # Chat endpoint for interactive queries
    as_chat_endpoint do
      system_prompt <<~PROMPT
        You are a system monitoring assistant with real-time access to system metrics.
        
        You can help with:
        - Current system status and performance metrics
        - Historical trends and analysis
        - Performance optimization recommendations
        - Alert investigation and troubleshooting
        - System health assessments
        
        Provide clear, actionable insights about system performance.
        Use technical terminology appropriately but explain complex concepts.
      PROMPT

      model "system-monitor-v1"
      temperature 0.3  # More factual for system data
      max_tokens 1500
    end

    # Webhook for external alerts
    webhook "/alert" do
      method :post
      
      on_request do |context|
        alert_data = JSON.parse(context[:body])
        puts "🚨 Received alert: #{alert_data['message']}"
        
        # Could trigger immediate system check or escalation
        {
          status: 'received',
          alert_id: alert_data['id'],
          processed_at: Time.now.iso8601
        }
      end
    rescue JSON::ParserError => e
      {
        error: 'Invalid JSON in alert payload',
        message: e.message
      }
    end

    # MCP tools for system operations
    as_mcp_server do
      tool "get_current_metrics" do
        description "Get real-time system metrics"
        
        execute do |params|
          # Simulate system metrics collection
          {
            cpu_percent: rand(0.0..100.0).round(1),
            memory_percent: rand(0.0..100.0).round(1), 
            disk_percent: rand(0.0..100.0).round(1),
            load_average: [rand(0.0..4.0), rand(0.0..4.0), rand(0.0..4.0)].map { |x| x.round(2) },
            uptime_seconds: rand(3600..2_592_000),
            timestamp: Time.now.iso8601
          }
        end
      end

      tool "restart_service" do
        description "Restart a system service"
        parameter "service_name", type: :string, required: true, description: "Name of service to restart"
        
        execute do |params|
          service_name = params["service_name"]
          puts "🔄 Restarting service: #{service_name}"
          
          # Simulate service restart
          success = rand > 0.1  # 90% success rate
          
          {
            service: service_name,
            action: 'restart',
            success: success,
            message: success ? "Service restarted successfully" : "Failed to restart service",
            timestamp: Time.now.iso8601
          }
        end
      end
    end

    # Constraints for safety and resource management
    constraints do
      timeout '60s'
      max_iterations 999999  # Run indefinitely
      requests_per_minute 60  # For chat/webhook endpoints
      daily_budget 2000      # $20/day
    end
  end
end

# Start the hybrid agent
if __FILE__ == $PROGRAM_NAME
  puts "🚀 Starting Hybrid System Monitor Agent"
  puts ""
  puts "This agent will:"
  puts "  ✅ Run autonomous system monitoring every 30 seconds"
  puts "  ✅ Expose chat endpoint at http://localhost:8080/v1/chat/completions"
  puts "  ✅ Handle alerts via POST /alert webhook"
  puts "  ✅ Provide MCP tools for system operations"
  puts ""
  puts "Available endpoints:"
  puts "  POST /v1/chat/completions - Chat with the monitoring assistant"
  puts "  GET  /v1/models          - List available models"
  puts "  POST /alert              - Receive system alerts"
  puts "  POST /mcp                - MCP protocol endpoint"
  puts "  GET  /health             - Health check"
  puts "  GET  /ready              - Readiness check"
  puts ""
  puts "Test commands:"
  puts ""
  puts "# Chat with the agent"
  puts "curl -X POST http://localhost:8080/v1/chat/completions \\"
  puts '  -H "Content-Type: application/json" \\'
  puts '  -d \'{"model": "system-monitor-v1", "messages": [{"role": "user", "content": "What is the system status?"}]}\''
  puts ""
  puts "# Send an alert"  
  puts "curl -X POST http://localhost:8080/alert \\"
  puts '  -H "Content-Type: application/json" \\'
  puts '  -d \'{"id": "alert-001", "message": "High CPU usage detected", "severity": "warning"}\''
  puts ""
  puts "Press Ctrl+C to stop"
  puts "=" * 80
  
  LanguageOperator::Agent.run
end