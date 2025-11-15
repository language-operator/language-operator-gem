# frozen_string_literal: true

require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../../ux/quickstart'

module LanguageOperator
  module CLI
    module Commands
      # Quickstart wizard for first-time users
      class Quickstart < BaseCommand
        desc 'start', 'Interactive setup wizard for first-time users'
        def start
          Ux::Quickstart.execute
        end

        default_task :start
      end
    end
  end
end
