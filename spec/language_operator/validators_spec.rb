# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Validators do
  describe '.http_url' do
    it 'returns nil for valid HTTP URL' do
      result = described_class.http_url('http://example.com')
      expect(result).to be_nil
    end

    it 'returns nil for valid HTTPS URL' do
      result = described_class.http_url('https://api.example.com/v1/users')
      expect(result).to be_nil
    end

    it 'returns nil for URL with query parameters' do
      result = described_class.http_url('https://example.com?foo=bar&baz=qux')
      expect(result).to be_nil
    end

    it 'returns error for empty URL' do
      result = described_class.http_url('')
      expect(result).to eq('Error: URL cannot be empty')
    end

    it 'returns error for nil URL' do
      result = described_class.http_url(nil)
      expect(result).to eq('Error: URL cannot be empty')
    end

    it 'returns error for whitespace-only URL' do
      result = described_class.http_url('   ')
      expect(result).to eq('Error: URL cannot be empty')
    end

    it 'returns error for FTP URL' do
      result = described_class.http_url('ftp://example.com')
      expect(result).to eq('Error: Invalid URL. Must start with http:// or https://')
    end

    it 'returns error for URL without protocol' do
      result = described_class.http_url('example.com')
      expect(result).to eq('Error: Invalid URL. Must start with http:// or https://')
    end

    it 'returns error for malformed URL' do
      result = described_class.http_url('ht tp://example.com')
      expect(result).to eq('Error: Invalid URL. Must start with http:// or https://')
    end
  end

  describe '.not_empty' do
    it 'returns nil for non-empty string' do
      result = described_class.not_empty('value', 'Field')
      expect(result).to be_nil
    end

    it 'returns nil for string with whitespace but content' do
      result = described_class.not_empty('  text  ', 'Field')
      expect(result).to be_nil
    end

    it 'returns nil for non-string objects' do
      result = described_class.not_empty(123, 'Number')
      expect(result).to be_nil
    end

    it 'returns error for nil value' do
      result = described_class.not_empty(nil, 'Field')
      expect(result).to eq('Error: Field cannot be empty')
    end

    it 'returns error for empty string' do
      result = described_class.not_empty('', 'Field')
      expect(result).to eq('Error: Field cannot be empty')
    end

    it 'returns error for whitespace-only string' do
      result = described_class.not_empty('   ', 'Field')
      expect(result).to eq('Error: Field cannot be empty')
    end

    it 'uses custom field name in error message' do
      result = described_class.not_empty('', 'Username')
      expect(result).to eq('Error: Username cannot be empty')
    end

    it 'integrates with Errors.empty_field' do
      result = described_class.not_empty(nil, 'Path')
      expect(result).to eq(LanguageOperator::Errors.empty_field('Path'))
    end
  end

  describe '.one_of' do
    it 'returns nil for valid choice' do
      result = described_class.one_of('GET', %w[GET POST PUT DELETE], 'method')
      expect(result).to be_nil
    end

    it 'returns nil for any allowed value' do
      expect(described_class.one_of('POST', %w[GET POST PUT], 'method')).to be_nil
      expect(described_class.one_of('PUT', %w[GET POST PUT], 'method')).to be_nil
    end

    it 'returns error for invalid choice' do
      result = described_class.one_of('INVALID', %w[GET POST PUT], 'method')
      expect(result).to include('Error: Invalid method')
      expect(result).to include('INVALID')
      expect(result).to include('GET, POST, PUT')
    end

    it 'is case sensitive' do
      result = described_class.one_of('get', %w[GET POST PUT], 'method')
      expect(result).to include('Error: Invalid method')
    end

    it 'uses custom field name in error message' do
      result = described_class.one_of('red', %w[blue green yellow], 'color')
      expect(result).to include('color')
      expect(result).to include('red')
    end

    it 'integrates with Errors.invalid_parameter' do
      result = described_class.one_of('X', %w[A B C], 'option')
      expected = LanguageOperator::Errors.invalid_parameter('option', 'X', 'one of: A, B, C')
      expect(result).to eq(expected)
    end
  end

  describe '.numeric_range' do
    describe 'type validation' do
      it 'returns nil for valid numeric value' do
        result = described_class.numeric_range(5)
        expect(result).to be_nil
      end

      it 'returns error for non-numeric value' do
        result = described_class.numeric_range('not a number')
        expect(result).to eq('Error: value must be a number')
      end

      it 'uses custom field name for type error' do
        result = described_class.numeric_range('foo', field_name: 'port')
        expect(result).to eq('Error: port must be a number')
      end
    end

    describe 'minimum validation' do
      it 'returns nil when value equals min' do
        result = described_class.numeric_range(10, min: 10)
        expect(result).to be_nil
      end

      it 'returns nil when value is above min' do
        result = described_class.numeric_range(15, min: 10)
        expect(result).to be_nil
      end

      it 'returns error when value is below min' do
        result = described_class.numeric_range(5, min: 10)
        expect(result).to eq('Error: value must be at least 10')
      end

      it 'uses custom field name for min error' do
        result = described_class.numeric_range(0, min: 1, field_name: 'interval')
        expect(result).to eq('Error: interval must be at least 1')
      end
    end

    describe 'maximum validation' do
      it 'returns nil when value equals max' do
        result = described_class.numeric_range(100, max: 100)
        expect(result).to be_nil
      end

      it 'returns nil when value is below max' do
        result = described_class.numeric_range(50, max: 100)
        expect(result).to be_nil
      end

      it 'returns error when value is above max' do
        result = described_class.numeric_range(150, max: 100)
        expect(result).to eq('Error: value must be at most 100')
      end

      it 'uses custom field name for max error' do
        result = described_class.numeric_range(100, max: 59, field_name: 'interval')
        expect(result).to eq('Error: interval must be at most 59')
      end
    end

    describe 'min and max validation' do
      it 'returns nil when value is within range' do
        result = described_class.numeric_range(50, min: 1, max: 100)
        expect(result).to be_nil
      end

      it 'returns nil when value equals min boundary' do
        result = described_class.numeric_range(1, min: 1, max: 100)
        expect(result).to be_nil
      end

      it 'returns nil when value equals max boundary' do
        result = described_class.numeric_range(100, min: 1, max: 100)
        expect(result).to be_nil
      end

      it 'returns error when below min' do
        result = described_class.numeric_range(0, min: 1, max: 100)
        expect(result).to include('at least 1')
      end

      it 'returns error when above max' do
        result = described_class.numeric_range(101, min: 1, max: 100)
        expect(result).to include('at most 100')
      end
    end

    describe 'floating point numbers' do
      it 'validates float ranges' do
        expect(described_class.numeric_range(3.14, min: 0.0, max: 10.0)).to be_nil
        expect(described_class.numeric_range(-1.5, min: 0.0)).to include('at least 0.0')
      end
    end

    describe 'negative numbers' do
      it 'validates negative ranges' do
        expect(described_class.numeric_range(-5, min: -10, max: 0)).to be_nil
        expect(described_class.numeric_range(-15, min: -10)).to include('at least -10')
      end
    end
  end

  describe '.email' do
    it 'returns nil for valid email address' do
      result = described_class.email('user@example.com')
      expect(result).to be_nil
    end

    it 'returns nil for email with subdomains' do
      result = described_class.email('user@mail.example.com')
      expect(result).to be_nil
    end

    it 'returns nil for email with plus sign' do
      result = described_class.email('user+tag@example.com')
      expect(result).to be_nil
    end

    it 'returns nil for email with dots' do
      result = described_class.email('first.last@example.co.uk')
      expect(result).to be_nil
    end

    it 'returns nil for email with numbers' do
      result = described_class.email('user123@example.com')
      expect(result).to be_nil
    end

    it 'returns error for empty email' do
      result = described_class.email('')
      expect(result).to eq('Error: Email address cannot be empty')
    end

    it 'returns error for nil email' do
      result = described_class.email(nil)
      expect(result).to eq('Error: Email address cannot be empty')
    end

    it 'returns error for whitespace-only email' do
      result = described_class.email('   ')
      expect(result).to eq('Error: Email address cannot be empty')
    end

    it 'returns error for email without @' do
      result = described_class.email('userexample.com')
      expect(result).to eq('Error: Invalid email address format')
    end

    it 'returns error for email without domain' do
      result = described_class.email('user@')
      expect(result).to eq('Error: Invalid email address format')
    end

    it 'returns error for email without local part' do
      result = described_class.email('@example.com')
      expect(result).to eq('Error: Invalid email address format')
    end

    it 'returns error for email without TLD' do
      result = described_class.email('user@example')
      expect(result).to eq('Error: Invalid email address format')
    end

    it 'returns error for email with spaces' do
      result = described_class.email('user name@example.com')
      expect(result).to eq('Error: Invalid email address format')
    end
  end

  describe '.safe_path' do
    it 'returns nil for absolute path' do
      result = described_class.safe_path('/absolute/path/to/file.txt')
      expect(result).to be_nil
    end

    it 'returns nil for relative path' do
      result = described_class.safe_path('relative/path/to/file.txt')
      expect(result).to be_nil
    end

    it 'returns nil for path with dots in filename' do
      result = described_class.safe_path('path/to/file.name.txt')
      expect(result).to be_nil
    end

    it 'returns nil for current directory reference' do
      result = described_class.safe_path('./file.txt')
      expect(result).to be_nil
    end

    it 'returns error for empty path' do
      result = described_class.safe_path('')
      expect(result).to eq('Error: Path cannot be empty')
    end

    it 'returns error for nil path' do
      result = described_class.safe_path(nil)
      expect(result).to eq('Error: Path cannot be empty')
    end

    it 'returns error for whitespace-only path' do
      result = described_class.safe_path('   ')
      expect(result).to eq('Error: Path cannot be empty')
    end

    it 'returns error for parent directory traversal' do
      result = described_class.safe_path('../etc/passwd')
      expect(result).to eq('Error: Path contains invalid characters or directory traversal')
    end

    it 'returns error for multiple parent directory traversals' do
      result = described_class.safe_path('../../../../../../etc/passwd')
      expect(result).to eq('Error: Path contains invalid characters or directory traversal')
    end

    it 'returns error for parent directory in middle of path' do
      result = described_class.safe_path('/safe/path/../../../etc/passwd')
      expect(result).to eq('Error: Path contains invalid characters or directory traversal')
    end

    it 'returns error for null byte in path' do
      result = described_class.safe_path("file\0name")
      expect(result).to eq('Error: Path contains invalid characters or directory traversal')
    end
  end

  describe 'real-world usage patterns' do
    it 'validates web tool HTTP method' do
      error = described_class.one_of('GET', %w[GET POST PUT DELETE HEAD], 'HTTP method')
      expect(error).to be_nil

      error = described_class.one_of('INVALID', %w[GET POST PUT DELETE HEAD], 'HTTP method')
      expect(error).to include('Invalid HTTP method')
    end

    it 'validates cron tool interval range' do
      error = described_class.numeric_range(30, min: 1, max: 59, field_name: 'interval')
      expect(error).to be_nil

      error = described_class.numeric_range(0, min: 1, max: 59, field_name: 'interval')
      expect(error).to eq('Error: interval must be at least 1')

      error = described_class.numeric_range(60, min: 1, max: 59, field_name: 'interval')
      expect(error).to eq('Error: interval must be at most 59')
    end

    it 'validates filesystem tool path' do
      error = described_class.not_empty('/valid/path', 'Path')
      expect(error).to be_nil

      error = described_class.safe_path('/valid/path')
      expect(error).to be_nil

      error = described_class.safe_path('../../../etc/passwd')
      expect(error).to include('directory traversal')
    end

    it 'validates email tool addresses' do
      error = described_class.email('user@example.com')
      expect(error).to be_nil

      error = described_class.email('invalid-email')
      expect(error).to eq('Error: Invalid email address format')
    end
  end
end
