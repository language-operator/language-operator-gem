# frozen_string_literal: true

module LanguageOperator
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
  end
end
