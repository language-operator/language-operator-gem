# frozen_string_literal: true

require_relative '../../../config/tool_registry'

module LanguageOperator
  module CLI
    module Commands
      module Tool
        # Tool search commands
        module Search
          def self.included(base)
            base.class_eval do
              desc 'search [PATTERN]', 'Search available tools in the registry'
              long_desc <<-DESC
                Search and list available tools from the registry.

                Without a pattern, lists all available tools.
                With a pattern, filters tools by name or description (case-insensitive).

                Examples:
                  aictl tool search              # List all tools
                  aictl tool search web          # Find tools matching "web"
                  aictl tool search email        # Find tools matching "email"
              DESC
              def search(pattern = nil)
                handle_command_error('search tools') do
                  # Load tool patterns registry
                  registry = Config::ToolRegistry.new
                  patterns = registry.fetch

                  # Filter out aliases and match pattern
                  tools = patterns.select do |key, config|
                    next false if config['alias'] # Skip aliases

                    if pattern
                      # Case-insensitive match on name or description
                      key.downcase.include?(pattern.downcase) ||
                        config['description']&.downcase&.include?(pattern.downcase)
                    else
                      true
                    end
                  end

                  if tools.empty?
                    if pattern
                      Formatters::ProgressFormatter.info("No tools found matching '#{pattern}'")
                    else
                      Formatters::ProgressFormatter.info('No tools found in registry')
                    end
                    return
                  end

                  # Display tools in a nice format
                  tools.each do |name, config|
                    description = config['description'] || 'No description'

                    # Bold the tool name (ANSI escape codes)
                    bold_name = "\e[1m#{name}\e[0m"
                    puts "#{bold_name} - #{description}"
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
