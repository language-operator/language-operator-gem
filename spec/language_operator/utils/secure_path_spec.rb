# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/utils/secure_path'

RSpec.describe LanguageOperator::Utils::SecurePath do
  describe '.expand_home_path' do
    context 'with safe HOME directory' do
      it 'expands paths relative to HOME' do
        original_home = ENV['HOME']
        ENV['HOME'] = '/home/testuser'

        # Mock the file system checks
        allow(File).to receive(:directory?).with('/home/testuser').and_return(true)
        allow(File).to receive(:readable?).with('/home/testuser').and_return(true)

        result = described_class.expand_home_path('.kube/config')
        expect(result).to eq('/home/testuser/.kube/config')

        ENV['HOME'] = original_home
      end

      it 'handles nested paths' do
        original_home = ENV['HOME']
        ENV['HOME'] = '/home/testuser'

        # Mock the file system checks
        allow(File).to receive(:directory?).with('/home/testuser').and_return(true)
        allow(File).to receive(:readable?).with('/home/testuser').and_return(true)

        result = described_class.expand_home_path('.config/app/settings.yaml')
        expect(result).to eq('/home/testuser/.config/app/settings.yaml')

        ENV['HOME'] = original_home
      end
    end

    context 'with path traversal attacks in HOME' do
      let(:attack_scenarios) do
        [
          '../../../etc',           # Basic traversal
          '/etc/../../../proc',     # Traversal with absolute path
          '/home/../etc',           # Traversal to system directory
          '/var/../../../etc',      # Complex traversal
          'some/../../etc',         # Relative with traversal
          '/tmp/../etc'             # Simple traversal
        ]
      end

      it 'falls back to safe directory for all traversal attacks' do
        attack_scenarios.each do |malicious_home|
          original_home = ENV['HOME']
          ENV['HOME'] = malicious_home

          result = described_class.expand_home_path('.kube/config')
          expect(result).to eq('/tmp/.kube/config'),
                            "Failed to block traversal attack: HOME=#{malicious_home}"

          ENV['HOME'] = original_home
        end
      end
    end

    context 'with dangerous system directories in HOME' do
      let(:dangerous_homes) do
        [
          '/etc',        # System configuration
          '/proc',       # Process info
          '/sys',        # System info
          '/dev',        # Device files
          '/boot',       # Boot files
          '/root',       # Root home
          '/etc/passwd', # System file
          '/proc/1',     # Process directory
          '/dev/null'    # Device file
        ]
      end

      it 'blocks access to system directories' do
        dangerous_homes.each do |dangerous_home|
          original_home = ENV['HOME']
          ENV['HOME'] = dangerous_home

          result = described_class.expand_home_path('.kube/config')
          expect(result).to eq('/tmp/.kube/config'),
                            "Failed to block dangerous HOME: #{dangerous_home}"

          ENV['HOME'] = original_home
        end
      end
    end

    context 'with relative paths in HOME' do
      it 'blocks relative HOME paths' do
        relative_homes = ['user', 'home/user', '../user', './user']

        relative_homes.each do |relative_home|
          original_home = ENV['HOME']
          ENV['HOME'] = relative_home

          result = described_class.expand_home_path('.kube/config')
          expect(result).to eq('/tmp/.kube/config'),
                            "Failed to block relative HOME: #{relative_home}"

          ENV['HOME'] = original_home
        end
      end
    end

    context 'with invalid HOME directories' do
      it 'falls back for nil HOME' do
        original_home = ENV.delete('HOME')

        result = described_class.expand_home_path('.kube/config')
        expect(result).to eq('/tmp/.kube/config')

        ENV['HOME'] = original_home if original_home
      end

      it 'falls back for empty HOME' do
        original_home = ENV['HOME']
        ENV['HOME'] = ''

        result = described_class.expand_home_path('.kube/config')
        expect(result).to eq('/tmp/.kube/config')

        ENV['HOME'] = original_home
      end
    end
  end

  describe '.secure_home_directory' do
    it 'returns validated home directory' do
      original_home = ENV['HOME']
      ENV['HOME'] = '/home/testuser'

      # Mock the file system checks
      allow(File).to receive(:directory?).with('/home/testuser').and_return(true)
      allow(File).to receive(:readable?).with('/home/testuser').and_return(true)

      result = described_class.secure_home_directory
      expect(result).to eq('/home/testuser')

      ENV['HOME'] = original_home
    end

    it 'returns fallback for unsafe directories' do
      original_home = ENV['HOME']
      ENV['HOME'] = '/etc'

      result = described_class.secure_home_directory
      expect(result).to eq('/tmp')

      ENV['HOME'] = original_home
    end
  end

  describe 'security boundary testing' do
    it 'blocks HOME with embedded traversal sequences' do
      tricky_homes = [
        '/home/user/../../etc',
        '/valid/path/../../../proc',
        '/tmp/../../boot'
      ]

      tricky_homes.each do |tricky_home|
        original_home = ENV['HOME']
        ENV['HOME'] = tricky_home

        result = described_class.expand_home_path('.config/app.conf')
        expect(result).to eq('/tmp/.config/app.conf'),
                          "Failed to block tricky HOME: #{tricky_home}"

        ENV['HOME'] = original_home
      end
    end

    it 'blocks paths with null bytes' do
      original_home = ENV['HOME']
      malicious_path = "/home/user\x00/../../etc"

      # Mock ENV.fetch instead of setting the actual environment variable
      allow(ENV).to receive(:fetch).with('HOME', '/tmp').and_return(malicious_path)

      result = described_class.expand_home_path('.kube/config')
      expect(result).to eq('/tmp/.kube/config')

      ENV['HOME'] = original_home
    end
  end
end