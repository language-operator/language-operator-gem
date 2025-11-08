# frozen_string_literal: true

require 'thor'
require_relative '../formatters/progress_formatter'
require_relative '../wizards/quickstart_wizard'

module LanguageOperator
  module CLI
    module Commands
      # Quickstart wizard for first-time users
      class Quickstart < Thor
        desc 'start', 'Interactive setup wizard for first-time users'
        def start
          wizard = Wizards::QuickstartWizard.new
          wizard.run
        end

        default_task :start
      end
    end
  end
end
