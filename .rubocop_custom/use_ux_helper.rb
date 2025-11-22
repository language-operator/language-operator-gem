# frozen_string_literal: true

module RuboCop
  module Cop
    module LanguageOperator
      # Enforces the use of UxHelper instead of direct Pastel or TTY::Prompt instantiation
      #
      # @example
      #   # bad
      #   @pastel = Pastel.new
      #   pastel = Pastel.new
      #   @prompt = TTY::Prompt.new
      #   prompt = TTY::Prompt.new
      #
      #   # good
      #   include Helpers::UxHelper
      #   pastel.green("Success")
      #   prompt.ask("Name?")
      #
      class UseUxHelper < Base
        MSG_PASTEL = 'Avoid direct Pastel instantiation. Include `Helpers::UxHelper` and use the `pastel` method instead.'
        MSG_PROMPT = 'Avoid direct TTY::Prompt instantiation. Include `Helpers::UxHelper` and use the `prompt` method instead.'

        RESTRICT_ON_SEND = %i[new].freeze

        def_node_matcher :pastel_new?, <<~PATTERN
          (send (const nil? :Pastel) :new)
        PATTERN

        def_node_matcher :tty_prompt_new?, <<~PATTERN
          (send (const (const nil? :TTY) :Prompt) :new)
        PATTERN

        def on_send(node)
          if pastel_new?(node)
            add_offense(node, message: MSG_PASTEL)
          elsif tty_prompt_new?(node)
            add_offense(node, message: MSG_PROMPT)
          end
        end
      end
    end
  end
end
