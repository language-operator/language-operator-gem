# frozen_string_literal: true

module LanguageOperator
  # Shared constants used across the Language Operator gem
  module Constants
    # Agent execution modes with their aliases
    # Primary modes are the canonical forms used in CRD schemas
    # Aliases are accepted for backwards compatibility and convenience
    EXECUTION_MODES = {
      autonomous: %w[autonomous interactive].freeze,
      scheduled: %w[scheduled event-driven].freeze,
      reactive: %w[reactive http webhook].freeze
    }.freeze

    # Primary (canonical) execution modes for schema definitions
    PRIMARY_MODES = %w[autonomous scheduled reactive].freeze

    # All valid mode strings (primary + aliases)
    ALL_MODE_ALIASES = EXECUTION_MODES.values.flatten.freeze

    # Normalizes a mode string to its primary canonical form
    #
    # @param mode_string [String] The mode string to normalize
    # @return [String] The canonical primary mode
    # @raise [ArgumentError] if the mode string is not recognized
    #
    # @example
    #   Constants.normalize_mode('interactive') # => 'autonomous'
    #   Constants.normalize_mode('webhook')     # => 'reactive'
    #   Constants.normalize_mode('scheduled')   # => 'scheduled'
    def self.normalize_mode(mode_string)
      return nil if mode_string.nil?

      mode_string = mode_string.to_s.downcase.strip

      # Handle empty/whitespace mode strings with specific error message
      if mode_string.empty?
        raise ArgumentError, 'AGENT_MODE environment variable is required but is unset or empty. ' \
                             "Please set AGENT_MODE to one of: #{ALL_MODE_ALIASES.join(', ')}"
      end

      EXECUTION_MODES.each do |primary, aliases|
        return primary.to_s if aliases.include?(mode_string)
      end

      raise ArgumentError, "Unknown execution mode: #{mode_string}. " \
                           "Valid modes: #{ALL_MODE_ALIASES.join(', ')}"
    end

    # Validates that a mode string is recognized
    #
    # @param mode_string [String] The mode string to validate
    # @return [Boolean] true if valid, false otherwise
    def self.valid_mode?(mode_string)
      return false if mode_string.nil?

      ALL_MODE_ALIASES.include?(mode_string.to_s.downcase.strip)
    end

    # Kubernetes Custom Resource Definitions (CRD) kinds
    # These replace magic strings scattered across CLI commands
    RESOURCE_AGENT = 'LanguageAgent'
    RESOURCE_AGENT_VERSION = 'LanguageAgentVersion'
    RESOURCE_MODEL = 'LanguageModel'
    RESOURCE_TOOL = 'LanguageTool'
    RESOURCE_PERSONA = 'LanguagePersona'
  end
end
