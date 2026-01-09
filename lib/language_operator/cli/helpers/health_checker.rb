# frozen_string_literal: true

require_relative '../formatters/progress_formatter'

module LanguageOperator
  module CLI
    module Helpers
      # Health checker for Language Operator components
      class HealthChecker
        attr_reader :k8s, :namespace, :cluster_name, :cluster_namespace

        def initialize(k8s_client, namespace, cluster_name = nil, cluster_namespace = nil)
          @k8s = k8s_client
          @namespace = namespace
          @cluster_name = cluster_name
          @cluster_namespace = cluster_namespace
        end

        # Check dashboard deployment health
        def check_dashboard_health
          deployment = @k8s.client.api('apps/v1')
                               .resource('deployments', namespace: @namespace)
                               .get('language-operator-dashboard')

          ready_replicas = deployment.dig('status', 'readyReplicas') || 0
          desired_replicas = deployment.dig('spec', 'replicas') || 0

          {
            healthy: ready_replicas == desired_replicas && desired_replicas > 0,
            ready_replicas: ready_replicas,
            desired_replicas: desired_replicas
          }
        rescue K8s::Error::NotFound
          { healthy: false, error: 'Dashboard deployment not found' }
        rescue StandardError => e
          { healthy: false, error: e.message }
        end

        # Check operator deployment health
        def check_operator_health
          deployment = @k8s.client.api('apps/v1')
                               .resource('deployments', namespace: @namespace)
                               .get('language-operator')

          ready_replicas = deployment.dig('status', 'readyReplicas') || 0
          desired_replicas = deployment.dig('spec', 'replicas') || 0

          {
            healthy: ready_replicas == desired_replicas && desired_replicas > 0,
            ready_replicas: ready_replicas,
            desired_replicas: desired_replicas
          }
        rescue K8s::Error::NotFound
          { healthy: false, error: 'Operator deployment not found' }
        rescue StandardError => e
          { healthy: false, error: e.message }
        end

        # Check ClickHouse health and authentication
        def check_clickhouse_health
          # First check if service exists
          begin
            @k8s.client.api('v1')
                       .resource('services', namespace: @namespace)
                       .get('language-operator-clickhouse')
          rescue K8s::Error::NotFound
            return { healthy: false, error: 'ClickHouse service not found' }
          end

          # Try to connect and authenticate using port-forward
          require 'net/http'
          require 'uri'
          require 'open3'

          port = find_available_port
          pf_pid = nil

          begin
            # Start port-forward in background
            pf_command = "kubectl port-forward -n #{@namespace} service/language-operator-clickhouse #{port}:8123"
            pf_stdin, pf_stdout, pf_stderr, pf_thread = Open3.popen3(pf_command)

            # Give port-forward time to establish
            sleep(2)

            # Test connection with credentials
            uri = URI("http://localhost:#{port}/ping")
            
            http = Net::HTTP.new(uri.host, uri.port)
            http.read_timeout = 5
            http.open_timeout = 5

            # Try with auth (default ClickHouse credentials for Language Operator)
            request = Net::HTTP::Get.new(uri)
            request.basic_auth('langop', 'langop')
            
            response = http.request(request)
            
            {
              healthy: response.code == '200',
              auth_works: response.code == '200',
              response_code: response.code
            }
          rescue StandardError => e
            { healthy: false, error: e.message }
          ensure
            # Clean up port-forward
            if pf_thread&.alive?
              Process.kill('TERM', pf_thread.pid) rescue nil
              pf_thread.join(1)
            end
          end
        end

        # Check PostgreSQL health and authentication  
        def check_postgres_health
          # First check if service exists
          begin
            @k8s.client.api('v1')
                       .resource('services', namespace: @namespace)
                       .get('language-operator-dashboard-postgresql')
          rescue K8s::Error::NotFound
            return { healthy: false, error: 'PostgreSQL service not found' }
          end

          # Try to connect and authenticate using port-forward and pg_isready
          require 'open3'

          port = find_available_port
          pf_pid = nil

          begin
            # Start port-forward in background
            pf_command = "kubectl port-forward -n #{@namespace} service/language-operator-dashboard-postgresql #{port}:5432"
            pf_stdin, pf_stdout, pf_stderr, pf_thread = Open3.popen3(pf_command)

            # Give port-forward time to establish
            sleep(2)

            # Test connection with pg_isready (if available) or simple TCP connection
            if system('which pg_isready > /dev/null 2>&1')
              # Use pg_isready for proper PostgreSQL health check
              test_output, test_status = Open3.capture2e("pg_isready -h localhost -p #{port} -U postgres -d langop_dashboard")
              {
                healthy: test_status.success?,
                auth_works: test_status.success?,
                output: test_output.strip
              }
            else
              # Fallback to basic TCP connection test
              require 'socket'
              begin
                socket = TCPSocket.new('localhost', port)
                socket.close
                { healthy: true, auth_works: false, note: 'pg_isready not available - basic TCP test only' }
              rescue StandardError => e
                { healthy: false, error: e.message }
              end
            end
          rescue StandardError => e
            { healthy: false, error: e.message }
          ensure
            # Clean up port-forward
            if pf_thread&.alive?
              Process.kill('TERM', pf_thread.pid) rescue nil
              pf_thread.join(1)
            end
          end
        end

        # Check if the selected cluster exists in Kubernetes
        def check_cluster_exists
          return { healthy: true, note: 'No cluster specified' } unless @cluster_name && @cluster_namespace

          cluster_resource = @k8s.get_resource('LanguageCluster', @cluster_name, @cluster_namespace)

          status = cluster_resource.dig('status', 'phase') || 'Unknown'
          {
            healthy: true,
            status: status,
            exists: true
          }
        rescue K8s::Error::NotFound
          { healthy: false, error: "Cluster '#{@cluster_name}' not found in namespace '#{@cluster_namespace}'" }
        rescue StandardError => e
          { healthy: false, error: e.message }
        end

        # Run all health checks with progress indicators
        def run_all_checks
          results = {}

          # Cluster existence check (first)
          if @cluster_name && @cluster_namespace
            begin
              results[:cluster] = Formatters::ProgressFormatter.with_spinner(
                "Verifying cluster '#{@cluster_name}' exists"
              ) { check_cluster_exists }
            rescue StandardError => e
              results[:cluster] = { healthy: false, error: e.message }
            end
          end

          # Dashboard health check
          begin
            results[:dashboard] = Formatters::ProgressFormatter.with_spinner(
              'Verifying language-operator-dashboard deployment'
            ) { check_dashboard_health }
          rescue StandardError => e
            results[:dashboard] = { healthy: false, error: e.message }
          end

          # Operator health check  
          begin
            results[:operator] = Formatters::ProgressFormatter.with_spinner(
              'Verifying language-operator deployment'
            ) { check_operator_health }
          rescue StandardError => e
            results[:operator] = { healthy: false, error: e.message }
          end

          # ClickHouse health check
          begin
            results[:clickhouse] = Formatters::ProgressFormatter.with_spinner(
              'Verifying ClickHouse health and authentication'
            ) { check_clickhouse_health }
          rescue StandardError => e
            results[:clickhouse] = { healthy: false, error: e.message }
          end

          # PostgreSQL health check
          begin
            results[:postgres] = Formatters::ProgressFormatter.with_spinner(
              'Verifying PostgreSQL health and authentication'
            ) { check_postgres_health }
          rescue StandardError => e
            results[:postgres] = { healthy: false, error: e.message }
          end

          results
        end

        private

        # Find an available port for port-forwarding
        def find_available_port
          require 'socket'
          port = 8080
          begin
            server = TCPServer.new('localhost', port)
            port = server.addr[1]
            server.close
            port
          rescue Errno::EADDRINUSE
            port += 1
            retry if port < 9000
            raise 'No available ports found'
          end
        end
      end
    end
  end
end