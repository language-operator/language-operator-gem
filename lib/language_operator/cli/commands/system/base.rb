# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative '../../base_command'
require_relative '../../formatters/progress_formatter'
require_relative '../../../dsl/schema'

# Include all system subcommand modules
require_relative 'schema'
require_relative 'validate_template'
require_relative 'synthesize'
require_relative 'exec'
require_relative 'synthesis_template'

# Include helper modules
require_relative 'helpers/template_loader'
require_relative 'helpers/template_validator'
require_relative 'helpers/llm_synthesis'
require_relative 'helpers/pod_manager'

module LanguageOperator
  module CLI
    module Commands
      module System
        # Base system command class
        class Base < BaseCommand
          # Include all helper modules
          include Helpers::TemplateLoader
          include Helpers::TemplateValidator
          include Helpers::LlmSynthesis
          include Helpers::PodManager

          # Include all subcommand modules
          include Schema
          include ValidateTemplate
          include Synthesize
          include Exec
          include SynthesisTemplate
        end
      end
    end
  end
end
