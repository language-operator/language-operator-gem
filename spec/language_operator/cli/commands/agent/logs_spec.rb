# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/commands/agent/base'

RSpec.describe LanguageOperator::CLI::Commands::Agent::Base do
  let(:command) { described_class.new }

  describe '#logs' do
    let(:mock_agent) do
      {
        'metadata' => {
          'name' => 'test-agent',
          'namespace' => 'default'
        },
        'spec' => {
          'mode' => 'autonomous'
        }
      }
    end

    let(:mock_context) do
      double('ClusterContext',
             kubectl_prefix: 'kubectl --kubeconfig=/tmp/test --context=test --namespace=default')
    end

    before do
      allow(LanguageOperator::CLI::Helpers::ClusterContext).to receive(:from_options).and_return(mock_context)
      allow(command).to receive(:get_resource_or_exit).with(LanguageOperator::Constants::RESOURCE_AGENT, 'test-agent').and_return(mock_agent)
      allow(LanguageOperator::CLI::Formatters::ProgressFormatter).to receive(:info)
      # Set default options
      command.instance_variable_set(:@options, { tail: 100, follow: false })
    end

    context 'normal operation' do
      let(:mock_stdin) { double('stdin') }
      let(:mock_stdout) { double('stdout') }
      let(:mock_stderr) { double('stderr') }
      let(:mock_wait_thr) { double('wait_thr') }
      let(:mock_status) { double('status', success?: true) }

      before do
        allow(mock_stdin).to receive(:close)
        allow(mock_stdout).to receive(:each_line).and_yield("log line 1\n").and_yield("log line 2\n")
        allow(mock_stderr).to receive(:each_line).and_yield("error line 1\n")
        allow(mock_wait_thr).to receive(:value).and_return(mock_status)

        allow(Open3).to receive(:popen3).and_yield(mock_stdin, mock_stdout, mock_stderr, mock_wait_thr)
      end

      it 'streams logs successfully' do
        expect { command.logs('test-agent') }.not_to raise_error
      end

      it 'closes stdin immediately' do
        expect(mock_stdin).to receive(:close)
        command.logs('test-agent')
      end

      it 'handles stdout and stderr streams' do
        expect(mock_stdout).to receive(:each_line)
        expect(mock_stderr).to receive(:each_line)
        command.logs('test-agent')
      end

      it 'builds correct kubectl command' do
        expected_cmd = 'kubectl --kubeconfig=/tmp/test --context=test --namespace=default logs -l app.kubernetes.io/name=test-agent --tail=100  --all-containers'

        expect(Open3).to receive(:popen3).with(expected_cmd)
        command.logs('test-agent')
      end

      context 'with follow option' do
        it 'includes -f flag in kubectl command' do
          command.instance_variable_set(:@options, { follow: true, tail: 100 })
          expected_cmd = 'kubectl --kubeconfig=/tmp/test --context=test --namespace=default logs -l app.kubernetes.io/name=test-agent --tail=100 -f --all-containers'

          expect(Open3).to receive(:popen3).with(expected_cmd)
          command.logs('test-agent')
        end
      end
    end

    context 'resource cleanup and interruption handling' do
      let(:mock_stdin) { double('stdin') }
      let(:mock_stdout) { double('stdout') }
      let(:mock_stderr) { double('stderr') }
      let(:mock_wait_thr) { double('wait_thr') }
      let(:stdout_thread) { double('Thread') }
      let(:stderr_thread) { double('Thread') }

      before do
        allow(mock_stdin).to receive(:close)
        allow(mock_stdout).to receive(:each_line)
        allow(mock_stderr).to receive(:each_line)
        allow(mock_wait_thr).to receive(:value).and_return(double('status', success?: true))
        allow(Open3).to receive(:popen3).and_yield(mock_stdin, mock_stdout, mock_stderr, mock_wait_thr)

        # Mock thread creation
        allow(Thread).to receive(:new).and_return(stdout_thread, stderr_thread)
        allow(stdout_thread).to receive(:join)
        allow(stderr_thread).to receive(:join)
        allow(stdout_thread).to receive(:terminate)
        allow(stderr_thread).to receive(:terminate)
      end

      it 'terminates threads in ensure block' do
        expect(stdout_thread).to receive(:terminate)
        expect(stderr_thread).to receive(:terminate)

        command.logs('test-agent')
      end

      it 'handles signal interruption gracefully' do
        # Mock signal trapping
        original_handler = proc {}
        allow(Signal).to receive(:trap).with('INT').and_return(original_handler)

        # Simulate interruption during execution
        allow(Thread).to receive(:new).and_raise(Interrupt)

        expect(Signal).to receive(:trap).with('INT', original_handler)
        expect { command.logs('test-agent') }.to raise_error(Interrupt)
      end

      it 'restores original signal handler' do
        original_handler = proc {}
        allow(Signal).to receive(:trap).with('INT').and_return(original_handler)

        expect(Signal).to receive(:trap).with('INT', original_handler)
        command.logs('test-agent')
      end
    end

    context 'IOError handling in threads' do
      let(:mock_stdin) { double('stdin') }
      let(:mock_stdout) { double('stdout') }
      let(:mock_stderr) { double('stderr') }
      let(:mock_wait_thr) { double('wait_thr') }

      before do
        allow(mock_stdin).to receive(:close)
        allow(mock_wait_thr).to receive(:value).and_return(double('status', success?: true))
        allow(Open3).to receive(:popen3).and_yield(mock_stdin, mock_stdout, mock_stderr, mock_wait_thr)
      end

      it 'handles IOError in stdout thread gracefully' do
        allow(mock_stdout).to receive(:each_line).and_raise(IOError, 'Stream closed')
        allow(mock_stderr).to receive(:each_line)

        expect { command.logs('test-agent') }.not_to raise_error
      end

      it 'handles IOError in stderr thread gracefully' do
        allow(mock_stdout).to receive(:each_line)
        allow(mock_stderr).to receive(:each_line).and_raise(IOError, 'Stream closed')

        expect { command.logs('test-agent') }.not_to raise_error
      end
    end

    context 'exit status handling' do
      let(:mock_stdin) { double('stdin') }
      let(:mock_stdout) { double('stdout') }
      let(:mock_stderr) { double('stderr') }
      let(:mock_wait_thr) { double('wait_thr') }

      before do
        allow(mock_stdin).to receive(:close)
        allow(mock_stdout).to receive(:each_line)
        allow(mock_stderr).to receive(:each_line)
        allow(Open3).to receive(:popen3).and_yield(mock_stdin, mock_stdout, mock_stderr, mock_wait_thr)
      end

      it 'exits with failure status when kubectl command fails' do
        mock_status = double('status', success?: false, exitstatus: 1)
        allow(mock_wait_thr).to receive(:value).and_return(mock_status)

        expect(command).to receive(:exit).with(1)
        command.logs('test-agent')
      end

      it 'does not exit when kubectl command succeeds' do
        mock_status = double('status', success?: true)
        allow(mock_wait_thr).to receive(:value).and_return(mock_status)

        expect(command).not_to receive(:exit)
        command.logs('test-agent')
      end
    end

    context 'scheduled agent mode' do
      let(:mock_scheduled_agent) do
        {
          'metadata' => { 'name' => 'test-scheduled', 'namespace' => 'default' },
          'spec' => { 'mode' => 'scheduled' }
        }
      end

      before do
        allow(command).to receive(:get_resource_or_exit).with(LanguageOperator::Constants::RESOURCE_AGENT, 'test-scheduled').and_return(mock_scheduled_agent)

        # Mock the Open3 call to prevent actual execution
        allow(Open3).to receive(:popen3) do |cmd|
          expect(cmd).to include('app.kubernetes.io/name=test-scheduled')
          double('result')
        end
      end

      it 'uses same label selector for scheduled agents' do
        expect(Open3).to receive(:popen3).with(include('app.kubernetes.io/name=test-scheduled'))
        command.logs('test-scheduled')
      end
    end
  end
end
