# frozen_string_literal: true

require 'thor'
require_relative '../formatters/progress_formatter'
require_relative '../wizards/quickstart_wizard'

module LanguageOperator
  module CLI
    module Commands
      # Quickstart wizard for first-time users
      class Quickstart < Thor
        desc 'run', 'Interactive setup wizard for first-time users'
        def run
          wizard = Wizards::QuickstartWizard.new
          wizard.run
        end

        default_task :run
      end
    end
  end
end
