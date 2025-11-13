# frozen_string_literal: true

require 'pastel'

module LanguageOperator
  module CLI
    module Helpers
      # Shared module providing Pastel color functionality
      # to CLI commands, formatters, and helpers.
      #
      # Usage:
      #   include PastelHelper
      #   puts pastel.green("Success!")
      module PastelHelper
        # Returns a memoized Pastel instance for colorizing terminal output
        #
        # @return [Pastel] Pastel instance
        def pastel
          @pastel ||= Pastel.new
        end
      end
    end
  end
end
