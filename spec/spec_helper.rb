# frozen_string_literal: true

require 'bundler/setup'
require 'language_operator'
require 'webmock/rspec'
require 'tmpdir'
require 'tempfile'

# Disable external HTTP requests
WebMock.disable_net_connect!(allow_localhost: false)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Suppress STDOUT/STDERR during tests unless VERBOSE=1 or DEBUG_INIT=1
  config.around(:each) do |example|
    if ENV['VERBOSE'] || ENV['DEBUG_INIT']
      example.run
    else
      original_stdout = $stdout
      original_stderr = $stderr
      begin
        $stdout = StringIO.new
        $stderr = StringIO.new
        example.run
      ensure
        $stdout = original_stdout
        $stderr = original_stderr
      end
    end
  end

  # NOTE: Registry cleanup not needed as each test creates its own tool classes

  # Mock RubyLLM and RubyLLM::MCP configuration to avoid real API calls
  config.before(:each) do |example|
    allow(RubyLLM).to receive(:configure).and_yield(double(
                                                      anthropic_api_key: nil,
                                                      openai_api_key: nil,
                                                      request_timeout: nil,
                                                      respond_to?: true
                                                    ))

    allow(RubyLLM::MCP).to receive(:configure).and_yield(double(
                                                           request_timeout: nil,
                                                           respond_to?: true
                                                         ))

    # Suppress telemetry OTEL configuration errors in test environment
    # Don't mock for tests that specifically test telemetry warnings
    current_test_file = example.metadata[:absolute_file_path] || ''
    is_telemetry_test = current_test_file.include?('telemetry_spec.rb') || 
                        current_test_file.include?('config_spec.rb')
    
    unless is_telemetry_test
      allow(LanguageOperator::Agent::Telemetry).to receive(:configure).and_return(nil)
      
      # Suppress stderr warnings to prevent parallel_tests process issues
      unless ENV['VERBOSE']
        original_warn = method(:warn)
        allow(Kernel).to receive(:warn) do |message|
          # Only suppress telemetry warnings, allow other warnings through
          unless message.to_s.include?('AGENT_NAME') || message.to_s.include?('learning status tracking')
            original_warn.call(message)
          end
        end
      end
    end
  end

  # Clean up environment variables after each test
  config.after(:each) do
    %w[
      WORKSPACE_PATH
      AGENT_MODE
      AGENT_INSTRUCTIONS
      TEST_VAR
      SHOW_FULL_RESPONSES
      LOG_LEVEL
      LOG_FORMAT
    ].each { |var| ENV.delete(var) }
  end
end
