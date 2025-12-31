# frozen_string_literal: true

require_relative '../base_command'
require_relative '../formatters/progress_formatter'
require_relative '../../kubernetes/client'
require_relative '../helpers/cluster_validator'

module LanguageOperator
  module CLI
    module Commands
      # UI command to open the Language Operator dashboard in browser
      class Ui < BaseCommand
        DEFAULT_PORT = 8080
        DEFAULT_SERVICE_NAME = 'language-operator-dashboard'
        DEFAULT_SERVICE_PORT = 3000

        desc 'ui', 'Open the Language Operator dashboard in your browser'
        long_desc <<-DESC
          Opens the Language Operator dashboard in your default browser.

          This command will:
          1. Set up a port forward to the dashboard service
          2. Open your default browser to the dashboard URL
          3. Keep the port forward running until you stop it (Ctrl+C)

          The dashboard provides a web interface for managing agents, tools, models, and monitoring
          the Language Operator cluster.

          Examples:
            # Open dashboard with default settings
            langop ui

            # Use a specific local port
            langop ui --port 9090

            # Connect to a specific service
            langop ui --service my-dashboard --service-port 8080
        DESC
        option :port, type: :numeric, default: DEFAULT_PORT, desc: "Local port to forward to (default: #{DEFAULT_PORT})"
        option :service, type: :string, default: DEFAULT_SERVICE_NAME, desc: "Service name to connect to (default: #{DEFAULT_SERVICE_NAME})"
        option :service_port, type: :numeric, default: DEFAULT_SERVICE_PORT, desc: "Service port to forward from (default: #{DEFAULT_SERVICE_PORT})"
        option :namespace, type: :string, default: 'language-operator', desc: 'Namespace to connect to (default: language-operator)'
        option :no_open, type: :boolean, default: false, desc: 'Do not automatically open browser'
        def ui
          handle_command_error('open dashboard') do

            logo(title: 'open dashboard')

            # Check if operator is installed and get service info
            validate_operator_installation

            port = options[:port]
            service_name = options[:service]
            service_port = options[:service_port]

            # Start port forward in background
            port_forward_pid = start_port_forward(service_name, service_port, port)

            # Wait a moment for port forward to establish
            sleep 2

            # Open browser unless --no-open
            open_browser("http://localhost:#{port}") unless options[:no_open]

            puts
            puts "Dashboard is now available at:"
            puts pastel.white.bold("http://localhost:#{port}")
            puts
            puts 'Press Ctrl+C to stop the port forward and exit'

            # Handle graceful shutdown
            trap('INT') do
              puts "\nStopping port forward..."
              stop_port_forward(port_forward_pid)
              puts 'Dashboard closed.'
              exit 0
            end

            # Keep the process running
            loop do
              sleep 1
            end
          end
        end

        private

        def validate_operator_installation
          namespace = options[:namespace]
          
          # Use current kubectl context directly
          k8s = Kubernetes::Client.new

          # Check if the operator namespace exists
          unless k8s.namespace_exists?(namespace)
            Formatters::ProgressFormatter.error("Namespace '#{namespace}' not found")
            puts
            puts 'The Language Operator does not appear to be installed.'
            puts 'Install it with: langop install'
            exit 1
          end

          # Check if the dashboard service exists
          begin
            k8s.get_resource('Service', options[:service], namespace)
          rescue StandardError
            Formatters::ProgressFormatter.error("Dashboard service '#{options[:service]}' not found")
            puts
            puts 'The dashboard service is not available. This may mean:'
            puts '  - The Language Operator is not fully deployed'
            puts '  - The dashboard is disabled in your installation'
            puts '  - You specified an incorrect service name'
            puts
            puts 'Check your installation with: langop status'
            exit 1
          end
        rescue StandardError => e
          Formatters::ProgressFormatter.error("Failed to validate installation: #{e.message}")
          exit 1
        end

        def start_port_forward(service_name, service_port, local_port)
          namespace = options[:namespace]
          # Forward directly to the dashboard pod using a specific label selector to avoid PostgreSQL pod
          cmd = "kubectl port-forward -n #{namespace} -l langop.io/kind=Dashboard #{local_port}:#{service_port}"

          Formatters::ProgressFormatter.with_spinner('Setting up port forward') do
            # Start kubectl port-forward in background
            pid = Process.spawn(cmd, out: '/dev/null', err: '/dev/null')
            Process.detach(pid)
            pid
          end
        end

        def stop_port_forward(pid)
          Process.kill('TERM', pid)
          # Give it a moment to clean up
          sleep 1
          # Force kill if still running
          Process.kill('KILL', pid) if process_running?(pid)
        rescue Errno::ESRCH
          # Process already dead, that's fine
        end

        def process_running?(pid)
          Process.getpgid(pid)
          true
        rescue Errno::ESRCH
          false
        end

        def open_browser(url)
          Formatters::ProgressFormatter.with_spinner('Opening browser') do
            # Detect platform and open browser accordingly
            case RbConfig::CONFIG['host_os']
            when /mswin|mingw|cygwin/
              system("start #{url}")
            when /darwin/
              system("open #{url}")
            when /linux|bsd/
              # Try common Linux browsers
              browsers = %w[xdg-open google-chrome firefox chromium-browser]
              browser_found = browsers.any? do |browser|
                system("which #{browser} > /dev/null 2>&1") && system("#{browser} #{url} > /dev/null 2>&1 &")
              end

              puts "Could not detect a browser to open. Please manually visit: #{url}" unless browser_found
            else
              puts "Unknown platform. Please manually visit: #{url}"
            end
          end
        end
      end
    end
  end
end
