# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Commands
      module System
        module Helpers
          # Template loading utilities
          module TemplateLoader
            # Load template from bundled gem or operator ConfigMap
            def load_template(type)
              # Try to fetch from operator ConfigMap first (if kubectl available)
              template = fetch_from_operator(type)
              return template if template

              # Fall back to bundled template
              load_bundled_template(type)
            end

            # Fetch template from operator ConfigMap via kubectl
            def fetch_from_operator(type)
              configmap_name = type == 'agent' ? 'agent-synthesis-template' : 'persona-distillation-template'
              result = `kubectl get configmap #{configmap_name} -n language-operator-system -o jsonpath='{.data.template}' 2>/dev/null`
              result.empty? ? nil : result
            rescue StandardError
              nil
            end

            # Load bundled template from gem
            def load_bundled_template(type)
              filename = type == 'agent' ? 'agent_synthesis.tmpl' : 'persona_distillation.tmpl'
              template_path = File.join(__dir__, '..', '..', '..', 'templates', filename)
              File.read(template_path)
            end

            # Render Go-style template ({{.Variable}})
            # Simplified implementation for basic variable substitution
            def render_go_template(template, data)
              result = template.dup

              # Handle {{if .ErrorContext}} - remove this section for test-synthesis
              result.gsub!(/{{if \.ErrorContext}}.*?{{else}}/m, '')
              result.gsub!(/{{end}}/, '')

              # Replace simple variables {{.Variable}}
              data.each do |key, value|
                result.gsub!("{{.#{key}}}", value.to_s)
              end

              result
            end
          end
        end
      end
    end
  end
end
