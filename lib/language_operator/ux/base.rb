# frozen_string_literal: true

require 'tty-prompt'
require 'pastel'
require_relative '../cli/formatters/progress_formatter'

module LanguageOperator
  module Ux
    # Base class for interactive user experience flows
    #
    # Provides common infrastructure for TTY-based interactive wizards
    # including cluster context validation and standard UI helpers.
    #
    # @example Creating a new UX flow
    #   class CreateModel < Base
    #     def execute
    #       show_welcome
    #       # ... flow logic
    #     end
    #   end
    #
    # @example Using a UX flow
    #   Ux::CreateModel.execute(ctx)
    #
    class Base
      attr_reader :prompt, :pastel, :ctx

      # Initialize the UX flow
      #
      # @param ctx [Object, nil] Cluster context (required unless overridden)
      def initialize(ctx = nil)
        @prompt = TTY::Prompt.new
        @pastel = Pastel.new
        @ctx = ctx

        validate_cluster_context! if requires_cluster?
      end

      # Execute the UX flow
      #
      # Subclasses must override this method to implement their flow logic.
      #
      # @raise [NotImplementedError] if not overridden by subclass
      def execute
        raise NotImplementedError, "#{self.class.name} must implement #execute"
      end

      # Execute the UX flow as a class method
      #
      # @param ctx [Object, nil] Cluster context
      # @return [Object] Result of execute method
      def self.execute(ctx = nil)
        new(ctx).execute
      end

      private

      # Whether this flow requires a cluster context
      #
      # Subclasses can override to disable cluster requirement (e.g., Quickstart).
      #
      # @return [Boolean] true if cluster is required
      def requires_cluster?
        true
      end

      # Validate that a cluster context is available
      #
      # Exits with error if cluster is required but not provided.
      def validate_cluster_context!
        return unless requires_cluster?
        return if ctx

        CLI::Formatters::ProgressFormatter.error(
          'No cluster selected. Run "aictl cluster add" first.'
        )
        exit 1
      end
    end
  end
end
