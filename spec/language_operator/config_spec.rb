# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Config do
  describe '.from_env' do
    it 'loads environment variables based on mappings' do
      ENV['TEST_VAR'] = 'test_value'
      config = described_class.from_env({ test: 'TEST_VAR' })

      expect(config[:test]).to eq('test_value')

      ENV.delete('TEST_VAR')
    end

    it 'applies default values when env vars not set' do
      config = described_class.from_env(
        { missing: 'MISSING_VAR' },
        defaults: { missing: 'default_value' }
      )

      expect(config[:missing]).to eq('default_value')
    end

    it 'prefers env var over default value' do
      ENV['PRESENT_VAR'] = 'from_env'
      config = described_class.from_env(
        { key: 'PRESENT_VAR' },
        defaults: { key: 'from_default' }
      )

      expect(config[:key]).to eq('from_env')

      ENV.delete('PRESENT_VAR')
    end

    it 'supports prefix for env var names' do
      ENV['SMTP_HOST'] = 'smtp.example.com'
      config = described_class.from_env(
        { host: 'HOST' },
        prefix: 'SMTP'
      )

      expect(config[:host]).to eq('smtp.example.com')

      ENV.delete('SMTP_HOST')
    end

    it 'returns nil for missing env vars without defaults' do
      config = described_class.from_env({ missing: 'NONEXISTENT_VAR' })

      expect(config[:missing]).to be_nil
    end

    it 'handles multiple mappings' do
      ENV['VAR1'] = 'value1'
      ENV['VAR2'] = 'value2'
      config = described_class.from_env({
                                          first: 'VAR1',
                                          second: 'VAR2'
                                        })

      expect(config[:first]).to eq('value1')
      expect(config[:second]).to eq('value2')

      ENV.delete('VAR1')
      ENV.delete('VAR2')
    end
  end

  describe '.convert_type' do
    describe ':string type' do
      it 'converts to string' do
        result = described_class.convert_type('hello', :string)
        expect(result).to eq('hello')
      end

      it 'handles numeric strings' do
        result = described_class.convert_type('123', :string)
        expect(result).to eq('123')
      end
    end

    describe ':integer type' do
      it 'converts string to integer' do
        result = described_class.convert_type('42', :integer)
        expect(result).to eq(42)
      end

      it 'handles negative integers' do
        result = described_class.convert_type('-10', :integer)
        expect(result).to eq(-10)
      end

      it 'handles zero' do
        result = described_class.convert_type('0', :integer)
        expect(result).to eq(0)
      end
    end

    describe ':float type' do
      it 'converts string to float' do
        result = described_class.convert_type('3.14', :float)
        expect(result).to eq(3.14)
      end

      it 'handles negative floats' do
        result = described_class.convert_type('-2.5', :float)
        expect(result).to eq(-2.5)
      end

      it 'converts integers to float' do
        result = described_class.convert_type('42', :float)
        expect(result).to eq(42.0)
      end
    end

    describe ':boolean type' do
      it 'converts "true" to true' do
        result = described_class.convert_type('true', :boolean)
        expect(result).to be true
      end

      it 'converts "1" to true' do
        result = described_class.convert_type('1', :boolean)
        expect(result).to be true
      end

      it 'converts "yes" to true' do
        result = described_class.convert_type('yes', :boolean)
        expect(result).to be true
      end

      it 'converts "on" to true' do
        result = described_class.convert_type('on', :boolean)
        expect(result).to be true
      end

      it 'is case insensitive for true values' do
        expect(described_class.convert_type('TRUE', :boolean)).to be true
        expect(described_class.convert_type('Yes', :boolean)).to be true
        expect(described_class.convert_type('ON', :boolean)).to be true
      end

      it 'converts "false" to false' do
        result = described_class.convert_type('false', :boolean)
        expect(result).to be false
      end

      it 'converts "0" to false' do
        result = described_class.convert_type('0', :boolean)
        expect(result).to be false
      end

      it 'converts any other string to false' do
        expect(described_class.convert_type('no', :boolean)).to be false
        expect(described_class.convert_type('off', :boolean)).to be false
        expect(described_class.convert_type('random', :boolean)).to be false
      end
    end

    describe 'nil values' do
      it 'returns nil for nil input regardless of type' do
        expect(described_class.convert_type(nil, :string)).to be_nil
        expect(described_class.convert_type(nil, :integer)).to be_nil
        expect(described_class.convert_type(nil, :float)).to be_nil
        expect(described_class.convert_type(nil, :boolean)).to be_nil
      end
    end

    describe 'unknown types' do
      it 'returns value unchanged for unknown type' do
        result = described_class.convert_type('value', :unknown)
        expect(result).to eq('value')
      end
    end
  end

  describe '.from_env with type conversion' do
    it 'applies type conversion to env vars' do
      ENV['PORT'] = '587'
      ENV['TLS'] = 'true'

      config = described_class.from_env(
        { port: 'PORT', tls: 'TLS' },
        types: { port: :integer, tls: :boolean }
      )

      expect(config[:port]).to eq(587)
      expect(config[:port]).to be_a(Integer)
      expect(config[:tls]).to be true

      ENV.delete('PORT')
      ENV.delete('TLS')
    end

    it 'applies type conversion to default values' do
      config = described_class.from_env(
        { port: 'MISSING_PORT', enabled: 'MISSING_ENABLED' },
        defaults: { port: '8080', enabled: '1' },
        types: { port: :integer, enabled: :boolean }
      )

      expect(config[:port]).to eq(8080)
      expect(config[:enabled]).to be true
    end
  end

  describe '.validate_required!' do
    it 'raises no error when all required keys are present' do
      config = { host: 'localhost', port: 587 }

      expect do
        described_class.validate_required!(config, %i[host port])
      end.not_to raise_error
    end

    it 'raises error when required key is missing' do
      config = { host: 'localhost' }

      expect do
        described_class.validate_required!(config, %i[host password])
      end.to raise_error(RuntimeError, /PASSWORD/)
    end

    it 'raises error when required key is nil' do
      config = { host: 'localhost', password: nil }

      expect do
        described_class.validate_required!(config, %i[host password])
      end.to raise_error(RuntimeError, /PASSWORD/)
    end

    it 'raises error when required key is empty string' do
      config = { host: 'localhost', password: '' }

      expect do
        described_class.validate_required!(config, %i[host password])
      end.to raise_error(RuntimeError, /PASSWORD/)
    end

    it 'raises error when required key is whitespace only' do
      config = { host: 'localhost', password: '   ' }

      expect do
        described_class.validate_required!(config, %i[host password])
      end.to raise_error(RuntimeError, /PASSWORD/)
    end

    it 'includes all missing keys in error message' do
      config = { host: 'localhost' }

      expect do
        described_class.validate_required!(config, %i[user password])
      end.to raise_error(RuntimeError, /USER.*PASSWORD/)
    end

    it 'uses Errors.missing_config for consistent error formatting' do
      config = {}

      expect do
        described_class.validate_required!(config, [:api_key])
      end.to raise_error(RuntimeError, /Error: Missing configuration/)
    end
  end

  describe '.load' do
    it 'combines from_env and validate_required! in one call' do
      ENV['SMTP_HOST'] = 'smtp.example.com'
      ENV['SMTP_USER'] = 'user@example.com'
      ENV['SMTP_PASSWORD'] = 'secret'

      config = described_class.load(
        { host: 'HOST', port: 'PORT', user: 'USER', password: 'PASSWORD' },
        prefix: 'SMTP',
        required: %i[host user password],
        defaults: { port: '587' },
        types: { port: :integer }
      )

      expect(config[:host]).to eq('smtp.example.com')
      expect(config[:port]).to eq(587)
      expect(config[:user]).to eq('user@example.com')
      expect(config[:password]).to eq('secret')

      ENV.delete('SMTP_HOST')
      ENV.delete('SMTP_USER')
      ENV.delete('SMTP_PASSWORD')
    end

    it 'raises error if required keys are missing' do
      expect do
        described_class.load(
          { host: 'MISSING_HOST_VAR', user: 'MISSING_USER_VAR' },
          required: %i[host user]
        )
      end.to raise_error(RuntimeError, /HOST.*USER/)
    end

    it 'does not validate if required array is empty' do
      config = described_class.load(
        { optional: 'OPTIONAL_VAR' },
        required: []
      )

      expect(config[:optional]).to be_nil
    end

    it 'works without required parameter' do
      ENV['TEST_VAR'] = 'test'
      config = described_class.load({ test: 'TEST_VAR' })

      expect(config[:test]).to eq('test')

      ENV.delete('TEST_VAR')
    end
  end

  describe 'real-world usage examples' do
    it 'loads SMTP configuration like email tool' do
      ENV['SMTP_HOST'] = 'smtp.gmail.com'
      ENV['SMTP_PORT'] = '587'
      ENV['SMTP_USER'] = 'user@gmail.com'
      ENV['SMTP_PASSWORD'] = 'secret'
      ENV['SMTP_TLS'] = 'true'

      config = described_class.load(
        { host: 'HOST', port: 'PORT', user: 'USER', password: 'PASSWORD', tls: 'TLS' },
        prefix: 'SMTP',
        required: %i[host user password],
        defaults: { port: '587', tls: 'true' },
        types: { port: :integer, tls: :boolean }
      )

      expect(config).to eq({
                             host: 'smtp.gmail.com',
                             port: 587,
                             user: 'user@gmail.com',
                             password: 'secret',
                             tls: true
                           })

      ENV.delete('SMTP_HOST')
      ENV.delete('SMTP_PORT')
      ENV.delete('SMTP_USER')
      ENV.delete('SMTP_PASSWORD')
      ENV.delete('SMTP_TLS')
    end

    it 'loads kubeconfig path like k8s tool' do
      ENV['KUBECONFIG'] = '/custom/path/config'

      config = described_class.from_env(
        { kubeconfig: 'KUBECONFIG' },
        defaults: { kubeconfig: File.expand_path('~/.kube/config') }
      )

      expect(config[:kubeconfig]).to eq('/custom/path/config')

      ENV.delete('KUBECONFIG')
    end

    it 'uses default kubeconfig when env var not set' do
      config = described_class.from_env(
        { kubeconfig: 'KUBECONFIG' },
        defaults: { kubeconfig: File.expand_path('~/.kube/config') }
      )

      expect(config[:kubeconfig]).to eq(File.expand_path('~/.kube/config'))
    end
  end
end
