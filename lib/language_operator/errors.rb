# frozen_string_literal: true

module LanguageOperator
  # Base exception class for all Language Operator errors
  class Error < StandardError; end

  # File loading related errors
  class FileLoadError < Error; end
  class FileNotFoundError < FileLoadError; end
  class FilePermissionError < FileLoadError; end
  class FileSyntaxError < FileLoadError; end
  
  # Security related errors
  class SecurityError < Error; end
  class PathTraversalError < SecurityError; end

  # Standardized error formatting module for consistent error messages across tools
  module Errors
    # Resource not found error
    # @param resource_type [String] Type of resource (e.g., "Pod", "LanguageAgent")
    # @param identifier [String] Resource identifier (name, ID, etc.)
    # @return [String] Formatted error message
    def self.not_found(resource_type, identifier)
      "Error: #{resource_type} not found - #{identifier}"
    end

    # Access denied error
    # @param context [String] Additional context (default: "check RBAC permissions")
    # @return [String] Formatted error message
    def self.access_denied(context = 'check RBAC permissions')
      "Error: Access denied - #{context}"
    end

    # Invalid JSON parameter error
    # @param param_name [String] Name of the parameter
    # @return [String] Formatted error message
    def self.invalid_json(param_name)
      "Error: Invalid JSON in #{param_name} parameter"
    end

    # Missing configuration error
    # @param missing_vars [String, Array<String>] Missing variable(s)
    # @return [String] Formatted error message
    def self.missing_config(missing_vars)
      vars = Array(missing_vars).join(', ')
      "Error: Missing configuration: #{vars}"
    end

    # Invalid parameter value error
    # @param param_name [String] Parameter name
    # @param value [String] Invalid value
    # @param expected [String] Expected format/value
    # @return [String] Formatted error message
    def self.invalid_parameter(param_name, value, expected)
      "Error: Invalid #{param_name} '#{value}'. Expected: #{expected}"
    end

    # Generic operation failed error
    # @param operation [String] Operation that failed
    # @param reason [String] Reason for failure
    # @return [String] Formatted error message
    def self.operation_failed(operation, reason)
      "Error: #{operation} failed - #{reason}"
    end

    # Empty/missing required field error
    # @param field_name [String] Name of the field
    # @return [String] Formatted error message
    def self.empty_field(field_name)
      "Error: #{field_name} cannot be empty"
    end

    # File not found error
    # @param file_path [String] Path to the file that wasn't found
    # @param context [String] Additional context about what the file is for
    # @return [String] Formatted error message
    def self.file_not_found(file_path, context = "file")
      "Error: #{context.capitalize} not found at '#{file_path}'. " \
      "Please check the file path exists and is accessible."
    end

    # File permission error
    # @param file_path [String] Path to the file with permission issues
    # @param context [String] Additional context about what the file is for
    # @return [String] Formatted error message
    def self.file_permission_denied(file_path, context = "file")
      "Error: Permission denied reading #{context} '#{file_path}'. " \
      "Please check file permissions or run with appropriate access rights."
    end

    # File syntax error
    # @param file_path [String] Path to the file with syntax errors
    # @param original_error [String] Original error message from parser
    # @param context [String] Additional context about what the file is for
    # @return [String] Formatted error message
    def self.file_syntax_error(file_path, original_error, context = "file")
      "Error: Syntax error in #{context} '#{file_path}': #{original_error}. " \
      "Please check the file for valid Ruby syntax."
    end

    # Path traversal security error
    # @param context [String] Context about what operation was attempted
    # @return [String] Formatted error message
    def self.path_traversal_blocked(context = "file operation")
      "Error: Path traversal attempt blocked during #{context}. " \
      "File path must be within allowed directories. " \
      "Use relative paths or configure LANGOP_ALLOWED_PATHS if needed."
    end
  end
end
