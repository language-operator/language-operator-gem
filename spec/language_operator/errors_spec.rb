# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Errors do
  describe '.not_found' do
    it 'formats resource not found error' do
      result = described_class.not_found('Pod', 'my-pod')
      expect(result).to eq('Error: Pod not found - my-pod')
    end

    it 'handles different resource types' do
      result = described_class.not_found('LanguageAgent', 'test-agent')
      expect(result).to eq('Error: LanguageAgent not found - test-agent')
    end

    it 'handles complex identifiers' do
      result = described_class.not_found('Resource', 'namespace/name')
      expect(result).to eq('Error: Resource not found - namespace/name')
    end
  end

  describe '.access_denied' do
    it 'uses default context when not provided' do
      result = described_class.access_denied
      expect(result).to eq('Error: Access denied - check RBAC permissions')
    end

    it 'accepts custom context' do
      result = described_class.access_denied('insufficient privileges')
      expect(result).to eq('Error: Access denied - insufficient privileges')
    end

    it 'handles detailed context messages' do
      result = described_class.access_denied('check RBAC permissions for LanguageTool CRDs')
      expect(result).to eq('Error: Access denied - check RBAC permissions for LanguageTool CRDs')
    end
  end

  describe '.invalid_json' do
    it 'formats invalid JSON parameter error' do
      result = described_class.invalid_json('headers')
      expect(result).to eq('Error: Invalid JSON in headers parameter')
    end

    it 'handles different parameter names' do
      result = described_class.invalid_json('query_params')
      expect(result).to eq('Error: Invalid JSON in query_params parameter')
    end

    it 'handles data parameter' do
      result = described_class.invalid_json('data')
      expect(result).to eq('Error: Invalid JSON in data parameter')
    end
  end

  describe '.missing_config' do
    it 'formats single missing configuration variable' do
      result = described_class.missing_config('SMTP_HOST')
      expect(result).to eq('Error: Missing configuration: SMTP_HOST')
    end

    it 'formats multiple missing variables from array' do
      result = described_class.missing_config(%w[SMTP_HOST SMTP_USER SMTP_PASSWORD])
      expect(result).to eq('Error: Missing configuration: SMTP_HOST, SMTP_USER, SMTP_PASSWORD')
    end

    it 'handles empty array' do
      result = described_class.missing_config([])
      expect(result).to eq('Error: Missing configuration: ')
    end

    it 'converts single string to array internally' do
      result = described_class.missing_config('API_KEY')
      expect(result).to eq('Error: Missing configuration: API_KEY')
    end

    it 'handles mixed content in array' do
      result = described_class.missing_config(%w[VAR1 VAR2])
      expect(result).to eq('Error: Missing configuration: VAR1, VAR2')
    end
  end

  describe '.invalid_parameter' do
    it 'formats invalid parameter error with all details' do
      result = described_class.invalid_parameter('method', 'INVALID', 'one of: GET, POST, PUT, DELETE')
      expect(result).to eq("Error: Invalid method 'INVALID'. Expected: one of: GET, POST, PUT, DELETE")
    end

    it 'handles different parameter types' do
      result = described_class.invalid_parameter('port', '99999', 'value between 1 and 65535')
      expect(result).to eq("Error: Invalid port '99999'. Expected: value between 1 and 65535")
    end

    it 'handles URL validation' do
      result = described_class.invalid_parameter('url', 'not-a-url', 'http:// or https:// URL')
      expect(result).to eq("Error: Invalid url 'not-a-url'. Expected: http:// or https:// URL")
    end
  end

  describe '.operation_failed' do
    it 'formats operation failed error' do
      result = described_class.operation_failed('deployment', 'timeout waiting for pods')
      expect(result).to eq('Error: deployment failed - timeout waiting for pods')
    end

    it 'handles different operations' do
      result = described_class.operation_failed('SMTP connection', 'authentication failed')
      expect(result).to eq('Error: SMTP connection failed - authentication failed')
    end

    it 'handles complex failure reasons' do
      result = described_class.operation_failed('synthesis', 'invalid persona configuration')
      expect(result).to eq('Error: synthesis failed - invalid persona configuration')
    end
  end

  describe '.empty_field' do
    it 'formats empty field error' do
      result = described_class.empty_field('Path')
      expect(result).to eq('Error: Path cannot be empty')
    end

    it 'handles different field names' do
      result = described_class.empty_field('name')
      expect(result).to eq('Error: name cannot be empty')
    end

    it 'handles multi-word field names' do
      result = described_class.empty_field('Email address')
      expect(result).to eq('Error: Email address cannot be empty')
    end
  end

  describe '.file_not_found' do
    it 'returns a formatted error message with file path' do
      message = described_class.file_not_found('/path/to/missing.rb')
      
      expect(message).to include('File not found at')
      expect(message).to include('/path/to/missing.rb')
      expect(message).to include('Please check the file path exists')
    end

    it 'accepts custom context' do
      message = described_class.file_not_found('/path/to/agent.rb', 'agent definition')
      
      expect(message).to include('Agent definition not found at')
      expect(message).to include('/path/to/agent.rb')
    end
  end

  describe '.file_permission_denied' do
    it 'returns a formatted error message with file path' do
      message = described_class.file_permission_denied('/path/to/restricted.rb')
      
      expect(message).to include('Permission denied reading')
      expect(message).to include('/path/to/restricted.rb')
      expect(message).to include('check file permissions')
    end

    it 'accepts custom context' do
      message = described_class.file_permission_denied('/path/to/tool.rb', 'tool definition')
      
      expect(message).to include('Permission denied reading tool definition')
      expect(message).to include('/path/to/tool.rb')
    end
  end

  describe '.file_syntax_error' do
    it 'returns a formatted error message with file path and error' do
      original_error = 'unexpected end-of-input'
      message = described_class.file_syntax_error('/path/to/bad.rb', original_error)
      
      expect(message).to include('Syntax error in file')
      expect(message).to include('/path/to/bad.rb')
      expect(message).to include(original_error)
      expect(message).to include('check the file for valid Ruby syntax')
    end

    it 'accepts custom context' do
      original_error = 'missing end'
      message = described_class.file_syntax_error('/path/to/agent.rb', original_error, 'agent configuration')
      
      expect(message).to include('Syntax error in agent configuration')
      expect(message).to include('/path/to/agent.rb')
      expect(message).to include(original_error)
    end
  end

  describe 'consistency' do
    it 'all methods return strings starting with "Error: "' do
      expect(described_class.not_found('Type', 'id')).to start_with('Error: ')
      expect(described_class.access_denied).to start_with('Error: ')
      expect(described_class.invalid_json('param')).to start_with('Error: ')
      expect(described_class.missing_config('VAR')).to start_with('Error: ')
      expect(described_class.invalid_parameter('p', 'v', 'e')).to start_with('Error: ')
      expect(described_class.operation_failed('op', 'reason')).to start_with('Error: ')
      expect(described_class.empty_field('field')).to start_with('Error: ')
      expect(described_class.file_not_found('/path')).to start_with('Error: ')
      expect(described_class.file_permission_denied('/path')).to start_with('Error: ')
      expect(described_class.file_syntax_error('/path', 'error')).to start_with('Error: ')
    end

    it 'all methods return non-empty strings' do
      expect(described_class.not_found('Type', 'id')).not_to be_empty
      expect(described_class.access_denied).not_to be_empty
      expect(described_class.invalid_json('param')).not_to be_empty
      expect(described_class.missing_config('VAR')).not_to be_empty
      expect(described_class.invalid_parameter('p', 'v', 'e')).not_to be_empty
      expect(described_class.operation_failed('op', 'reason')).not_to be_empty
      expect(described_class.empty_field('field')).not_to be_empty
      expect(described_class.file_not_found('/path')).not_to be_empty
      expect(described_class.file_permission_denied('/path')).not_to be_empty
      expect(described_class.file_syntax_error('/path', 'error')).not_to be_empty
    end
  end
end

RSpec.describe 'LanguageOperator custom exceptions' do
  describe 'LanguageOperator::Error' do
    it 'is a StandardError' do
      expect(LanguageOperator::Error.new).to be_a(StandardError)
    end
  end

  describe 'LanguageOperator::FileLoadError' do
    it 'inherits from LanguageOperator::Error' do
      expect(LanguageOperator::FileLoadError.new).to be_a(LanguageOperator::Error)
    end
  end

  describe 'LanguageOperator::FileNotFoundError' do
    it 'inherits from FileLoadError' do
      expect(LanguageOperator::FileNotFoundError.new).to be_a(LanguageOperator::FileLoadError)
    end

    it 'can be caught as FileLoadError' do
      exception_caught = false
      
      begin
        raise LanguageOperator::FileNotFoundError, 'test'
      rescue LanguageOperator::FileLoadError
        exception_caught = true
      end
      
      expect(exception_caught).to be(true)
    end
  end

  describe 'LanguageOperator::FilePermissionError' do
    it 'inherits from FileLoadError' do
      expect(LanguageOperator::FilePermissionError.new).to be_a(LanguageOperator::FileLoadError)
    end
  end

  describe 'LanguageOperator::FileSyntaxError' do
    it 'inherits from FileLoadError' do
      expect(LanguageOperator::FileSyntaxError.new).to be_a(LanguageOperator::FileLoadError)
    end
  end
end
