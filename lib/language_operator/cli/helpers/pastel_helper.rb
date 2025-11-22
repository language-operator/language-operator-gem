# frozen_string_literal: true

require_relative 'ux_helper'

module LanguageOperator
  module CLI
    module Helpers
      # @deprecated Use {UxHelper} instead.
      #   PastelHelper is deprecated and will be removed in v0.2.0.
      #   Use UxHelper which provides both pastel and prompt methods.
      #
      # @example Migration
      #   # Before:
      #   include PastelHelper
      #   puts pastel.green("Success!")
      #
      #   # After:
      #   include UxHelper
      #   puts pastel.green("Success!")
      #   answer = prompt.ask("Name?")
      #
      # @see UxHelper
      module PastelHelper
        include UxHelper

        def self.included(base)
          warn "[DEPRECATION] PastelHelper is deprecated. Use UxHelper instead (included in #{base})"
          super
        end

        def self.extended(base)
          warn "[DEPRECATION] PastelHelper is deprecated. Use UxHelper instead (extended in #{base})"
          super
        end
      end
    end
  end
end
