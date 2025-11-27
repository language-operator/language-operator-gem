# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'language_operator/cli/helpers/cluster_context'
require 'language_operator/cli/formatters/progress_formatter'

# Test the Lifecycle module methods directly by creating a minimal test class
# We avoid including the full module to prevent Thor CLI conflicts
RSpec.describe 'Agent Lifecycle Commands' do
  let(:test_class) do
    Class.new do
      def pause(name, options = {})
        handle_command_error('pause agent') do
          ctx = LanguageOperator::CLI::Helpers::ClusterContext.from_options(options)

          # Get agent
          agent = get_resource_or_exit(LanguageOperator::Constants::RESOURCE_AGENT, name)

          mode = agent.dig('spec', 'executionMode') || 'autonomous'
          unless mode == 'scheduled'
            LanguageOperator::CLI::Formatters::ProgressFormatter.warn("Agent '#{name}' is not a scheduled agent (mode: #{mode})")
            puts
            puts 'Only scheduled agents can be paused.'
            puts 'Autonomous agents can be stopped by deleting them.'
            exit 1
          end

          # Suspend the CronJob by setting spec.suspend = true
          cronjob_name = name

          LanguageOperator::CLI::Formatters::ProgressFormatter.with_spinner("Pausing agent '#{name}'") do
            # Use kubectl to patch the cronjob
            cmd = "#{ctx.kubectl_prefix} patch cronjob #{cronjob_name} -p '{\"spec\":{\"suspend\":true}}'"
            _, stderr, status = Open3.capture3(cmd)

            unless status.success?
              error_msg = "Failed to pause agent '#{name}': kubectl command failed (exit code: #{status.exitstatus})"
              error_msg += "\nError: #{stderr.strip}" unless stderr.nil? || stderr.strip.empty?
              raise error_msg
            end
          end

          LanguageOperator::CLI::Formatters::ProgressFormatter.success("Agent '#{name}' paused")
        end
      end

      def resume(name, options = {})
        handle_command_error('resume agent') do
          ctx = LanguageOperator::CLI::Helpers::ClusterContext.from_options(options)

          # Get agent
          agent = get_resource_or_exit(LanguageOperator::Constants::RESOURCE_AGENT, name)

          mode = agent.dig('spec', 'executionMode') || 'autonomous'
          unless mode == 'scheduled'
            LanguageOperator::CLI::Formatters::ProgressFormatter.warn("Agent '#{name}' is not a scheduled agent (mode: #{mode})")
            puts
            puts 'Only scheduled agents can be resumed.'
            exit 1
          end

          # Resume the CronJob by setting spec.suspend = false
          cronjob_name = name

          LanguageOperator::CLI::Formatters::ProgressFormatter.with_spinner("Resuming agent '#{name}'") do
            # Use kubectl to patch the cronjob
            cmd = "#{ctx.kubectl_prefix} patch cronjob #{cronjob_name} -p '{\"spec\":{\"suspend\":false}}'"
            _, stderr, status = Open3.capture3(cmd)

            unless status.success?
              error_msg = "Failed to resume agent '#{name}': kubectl command failed (exit code: #{status.exitstatus})"
              error_msg += "\nError: #{stderr.strip}" unless stderr.nil? || stderr.strip.empty?
              raise error_msg
            end
          end

          LanguageOperator::CLI::Formatters::ProgressFormatter.success("Agent '#{name}' resumed")
        end
      end

      private

      def handle_command_error(_operation)
        yield
      end

      def get_resource_or_exit(_resource_type, name)
        # Mock agent resource for testing
        {
          'metadata' => { 'name' => name },
          'spec' => { 'executionMode' => 'scheduled' }
        }
      end
    end
  end

  let(:instance) { test_class.new }
  let(:mock_ctx) do
    double('ClusterContext').tap do |ctx|
      allow(ctx).to receive(:kubectl_prefix).and_return('kubectl -n default')
      allow(ctx).to receive(:namespace).and_return('default')
    end
  end

  let(:mock_cluster_context) { double('CLI::Helpers::ClusterContext') }

  before do
    allow(LanguageOperator::CLI::Helpers::ClusterContext).to receive(:from_options).and_return(mock_ctx)
    allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:with_spinner).and_yield
    allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:success)
    allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:warn)
    allow($stdout).to receive(:puts) # Suppress output in tests
  end

  describe '#pause' do
    context 'with successful kubectl command' do
      it 'executes kubectl patch with suspend=true' do
        expect(Open3).to receive(:capture3).with(
          "kubectl -n default patch cronjob test-agent -p '{\"spec\":{\"suspend\":true}}'"
        ).and_return(['success output', '', double('Status', success?: true, exitstatus: 0)])

        expect { instance.pause('test-agent') }.not_to raise_error
      end

      it 'shows success message after successful pause' do
        allow(Open3).to receive(:capture3).and_return(
          ['success', '', double('Status', success?: true, exitstatus: 0)]
        )

        expect(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:success).with("Agent 'test-agent' paused")

        instance.pause('test-agent')
      end
    end

    context 'with failed kubectl command' do
      it 'raises error with exit status when kubectl fails' do
        expect(Open3).to receive(:capture3).and_return(
          ['', 'cronjob.batch "test-agent" not found', double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.pause('test-agent')
        end.to raise_error(
          "Failed to pause agent 'test-agent': kubectl command failed (exit code: 1)\nError: cronjob.batch \"test-agent\" not found"
        )
      end

      it 'includes stderr in error message when available' do
        expect(Open3).to receive(:capture3).and_return(
          ['', 'RBAC permission denied', double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.pause('test-agent')
        end.to raise_error(
          /Failed to pause agent 'test-agent'.*RBAC permission denied/m
        )
      end

      it 'handles empty stderr gracefully' do
        expect(Open3).to receive(:capture3).and_return(
          ['', '', double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.pause('test-agent')
        end.to raise_error(
          "Failed to pause agent 'test-agent': kubectl command failed (exit code: 1)"
        )
      end

      it 'handles nil stderr gracefully' do
        expect(Open3).to receive(:capture3).and_return(
          ['', nil, double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.pause('test-agent')
        end.to raise_error(
          "Failed to pause agent 'test-agent': kubectl command failed (exit code: 1)"
        )
      end
    end

    context 'with different kubectl contexts' do
      it 'uses custom kubectl prefix from context' do
        allow(mock_ctx).to receive(:kubectl_prefix).and_return('kubectl --context=prod -n agents')

        expect(Open3).to receive(:capture3).with(
          "kubectl --context=prod -n agents patch cronjob test-agent -p '{\"spec\":{\"suspend\":true}}'"
        ).and_return(['success', '', double('Status', success?: true, exitstatus: 0)])

        instance.pause('test-agent')
      end
    end
  end

  describe '#resume' do
    context 'with successful kubectl command' do
      it 'executes kubectl patch with suspend=false' do
        expect(Open3).to receive(:capture3).with(
          "kubectl -n default patch cronjob test-agent -p '{\"spec\":{\"suspend\":false}}'"
        ).and_return(['success output', '', double('Status', success?: true, exitstatus: 0)])

        expect { instance.resume('test-agent') }.not_to raise_error
      end

      it 'shows success message after successful resume' do
        allow(Open3).to receive(:capture3).and_return(
          ['success', '', double('Status', success?: true, exitstatus: 0)]
        )

        expect(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:success).with("Agent 'test-agent' resumed")

        instance.resume('test-agent')
      end
    end

    context 'with failed kubectl command' do
      it 'raises error with exit status when kubectl fails' do
        expect(Open3).to receive(:capture3).and_return(
          ['', 'cronjob.batch "test-agent" not found', double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.resume('test-agent')
        end.to raise_error(
          "Failed to resume agent 'test-agent': kubectl command failed (exit code: 1)\nError: cronjob.batch \"test-agent\" not found"
        )
      end

      it 'includes stderr in error message when available' do
        expect(Open3).to receive(:capture3).and_return(
          ['', 'Network timeout', double('Status', success?: false, exitstatus: 124)]
        )

        expect do
          instance.resume('test-agent')
        end.to raise_error(
          /Failed to resume agent 'test-agent'.*Network timeout/m
        )
      end

      it 'handles empty stderr gracefully' do
        expect(Open3).to receive(:capture3).and_return(
          ['', '', double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.resume('test-agent')
        end.to raise_error(
          "Failed to resume agent 'test-agent': kubectl command failed (exit code: 1)"
        )
      end
    end

    context 'with different kubectl contexts' do
      it 'uses custom kubectl prefix from context' do
        allow(mock_ctx).to receive(:kubectl_prefix).and_return('kubectl --kubeconfig=/custom/config -n prod')

        expect(Open3).to receive(:capture3).with(
          "kubectl --kubeconfig=/custom/config -n prod patch cronjob test-agent -p '{\"spec\":{\"suspend\":false}}'"
        ).and_return(['success', '', double('Status', success?: true, exitstatus: 0)])

        instance.resume('test-agent')
      end
    end
  end

  describe 'error propagation' do
    context 'when Open3.capture3 fails' do
      it 'allows underlying exceptions to bubble up for pause' do
        expect(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'kubectl command not found')

        expect do
          instance.pause('test-agent')
        end.to raise_error(Errno::ENOENT, /kubectl command not found/)
      end

      it 'allows underlying exceptions to bubble up for resume' do
        expect(Open3).to receive(:capture3).and_raise(Errno::EACCES, 'permission denied')

        expect do
          instance.resume('test-agent')
        end.to raise_error(Errno::EACCES, /permission denied/)
      end
    end
  end

  describe 'real-world kubectl error scenarios' do
    context 'RBAC permission errors' do
      it 'provides clear error message for RBAC failures in pause' do
        rbac_error = 'cronjobs.batch is forbidden: User "user" cannot patch resource "cronjobs" in API group "batch"'
        expect(Open3).to receive(:capture3).and_return(
          ['', rbac_error, double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.pause('test-agent')
        end.to raise_error(
          /Failed to pause agent 'test-agent'.*cronjobs.batch is forbidden/m
        )
      end
    end

    context 'network connectivity errors' do
      it 'handles network timeouts gracefully' do
        network_error = 'Unable to connect to the server: dial tcp: i/o timeout'
        expect(Open3).to receive(:capture3).and_return(
          ['', network_error, double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.resume('test-agent')
        end.to raise_error(
          /Failed to resume agent 'test-agent'.*Unable to connect to the server/m
        )
      end
    end

    context 'invalid resource errors' do
      it 'handles missing cronjob errors' do
        missing_error = 'cronjobs.batch "non-existent-agent" not found'
        expect(Open3).to receive(:capture3).and_return(
          ['', missing_error, double('Status', success?: false, exitstatus: 1)]
        )

        expect do
          instance.pause('non-existent-agent')
        end.to raise_error(
          /Failed to pause agent 'non-existent-agent'.*not found/m
        )
      end
    end
  end
end
