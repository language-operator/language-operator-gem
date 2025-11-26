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

      it 'raises error for invalid integer strings' do
        expect { described_class.convert_type('abc', :integer) }
          .to raise_error(ArgumentError, /invalid value for Integer/)
      end

      it 'raises error for mixed numeric strings' do
        expect { described_class.convert_type('123abc', :integer) }
          .to raise_error(ArgumentError, /invalid value for Integer/)
      end

      it 'raises error for empty strings' do
        expect { described_class.convert_type('', :integer) }
          .to raise_error(ArgumentError, /invalid value for Integer/)
      end

      it 'handles strings with leading/trailing whitespace' do
        result = described_class.convert_type('  42  ', :integer)
        expect(result).to eq(42)
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

      it 'raises error for invalid float strings' do
        expect { described_class.convert_type('xyz', :float) }
          .to raise_error(ArgumentError, /invalid value for Float/)
      end

      it 'raises error for multiple decimal points' do
        expect { described_class.convert_type('12.34.56', :float) }
          .to raise_error(ArgumentError, /invalid value for Float/)
      end

      it 'raises error for empty strings' do
        expect { described_class.convert_type('', :float) }
          .to raise_error(ArgumentError, /invalid value for Float/)
      end

      it 'handles strings with leading/trailing whitespace' do
        result = described_class.convert_type('  3.14  ', :float)
        expect(result).to eq(3.14)
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
        defaults: { kubeconfig: '/safe/default/kube/config' }
      )

      expect(config[:kubeconfig]).to eq('/custom/path/config')

      ENV.delete('KUBECONFIG')
    end

    it 'uses default kubeconfig when env var not set' do
      config = described_class.from_env(
        { kubeconfig: 'KUBECONFIG' },
        defaults: { kubeconfig: '/safe/default/kube/config' }
      )

      expect(config[:kubeconfig]).to eq('/safe/default/kube/config')
    end
  end

  describe '.get_int' do
    it 'converts valid integer strings' do
      ENV['TEST_PORT'] = '8080'
      result = described_class.get_int('TEST_PORT')
      expect(result).to eq(8080)
      ENV.delete('TEST_PORT')
    end

    it 'handles negative integers' do
      ENV['TEST_NUM'] = '-42'
      result = described_class.get_int('TEST_NUM')
      expect(result).to eq(-42)
      ENV.delete('TEST_NUM')
    end

    it 'handles zero' do
      ENV['TEST_ZERO'] = '0'
      result = described_class.get_int('TEST_ZERO')
      expect(result).to eq(0)
      ENV.delete('TEST_ZERO')
    end

    it 'handles strings with leading/trailing whitespace' do
      ENV['TEST_SPACE'] = '  123  '
      result = described_class.get_int('TEST_SPACE')
      expect(result).to eq(123)
      ENV.delete('TEST_SPACE')
    end

    it 'returns default when environment variable is nil' do
      result = described_class.get_int('NONEXISTENT_VAR', default: 42)
      expect(result).to eq(42)
    end

    it 'raises error when no default provided and env var missing' do
      expect { described_class.get_int('NONEXISTENT_VAR') }
        .to raise_error(ArgumentError, /Missing required integer configuration/)
    end

    it 'raises error for invalid integer strings' do
      ENV['TEST_INVALID'] = 'abc'
      expect { described_class.get_int('TEST_INVALID') }
        .to raise_error(ArgumentError, /Invalid integer value 'abc' in environment variable 'TEST_INVALID'/)
      ENV.delete('TEST_INVALID')
    end

    it 'raises error for mixed numeric strings' do
      ENV['TEST_MIXED'] = '123abc'
      expect { described_class.get_int('TEST_MIXED') }
        .to raise_error(ArgumentError, /Invalid integer value '123abc' in environment variable 'TEST_MIXED'/)
      ENV.delete('TEST_MIXED')
    end

    it 'raises error for empty strings' do
      ENV['TEST_EMPTY'] = ''
      expect { described_class.get_int('TEST_EMPTY') }
        .to raise_error(ArgumentError, /Invalid integer value '' in environment variable 'TEST_EMPTY'/)
      ENV.delete('TEST_EMPTY')
    end

    it 'raises error for whitespace-only strings' do
      ENV['TEST_WHITESPACE'] = '   '
      expect { described_class.get_int('TEST_WHITESPACE') }
        .to raise_error(ArgumentError, /Invalid integer value '   ' in environment variable 'TEST_WHITESPACE'/)
      ENV.delete('TEST_WHITESPACE')
    end

    it 'includes all key names in error message when multiple keys provided' do
      ENV['KEY1'] = 'invalid'
      expect { described_class.get_int('KEY1', 'KEY2', 'KEY3') }
        .to raise_error(ArgumentError, /Invalid integer value 'invalid' in environment variable 'KEY1'/)
      ENV.delete('KEY1')
    end

    it 'provides helpful error message with specific variable name and suggestion' do
      ENV['MAX_WORKERS'] = 'auto'
      expect { described_class.get_int('MAX_WORKERS') }
        .to raise_error(ArgumentError, /Invalid integer value 'auto' in environment variable 'MAX_WORKERS'.*Please set MAX_WORKERS to a valid integer/)
      ENV.delete('MAX_WORKERS')
    end

    it 'identifies correct variable when first fallback fails' do
      ENV['PRIMARY'] = 'invalid'
      expect { described_class.get_int('PRIMARY', 'SECONDARY') }
        .to raise_error(ArgumentError, /environment variable 'PRIMARY'.*Please set PRIMARY to a valid integer/)
      ENV.delete('PRIMARY')
    end

    it 'identifies correct variable when second fallback fails' do
      ENV['SECONDARY'] = 'invalid'
      expect { described_class.get_int('PRIMARY', 'SECONDARY') }
        .to raise_error(ArgumentError, /environment variable 'SECONDARY'.*Please set SECONDARY to a valid integer/)
      ENV.delete('SECONDARY')
    end

    it 'provides helpful error message when no variables are set and no default' do
      expect { described_class.get_int('MISSING1', 'MISSING2', 'MISSING3') }
        .to raise_error(ArgumentError, /Missing required integer configuration.*Checked environment variables: MISSING1, MISSING2, MISSING3/)
    end

    it 'uses first valid variable and ignores later invalid ones' do
      ENV['FIRST'] = '42'
      ENV['SECOND'] = 'invalid'
      result = described_class.get_int('FIRST', 'SECOND')
      expect(result).to eq(42)
      ENV.delete('FIRST')
      ENV.delete('SECOND')
    end
  end

  describe '.get_bool' do
    it 'converts "true" to true' do
      ENV['TEST_BOOL'] = 'true'
      result = described_class.get_bool('TEST_BOOL')
      expect(result).to be true
      ENV.delete('TEST_BOOL')
    end

    it 'converts "1" to true' do
      ENV['TEST_BOOL'] = '1'
      result = described_class.get_bool('TEST_BOOL')
      expect(result).to be true
      ENV.delete('TEST_BOOL')
    end

    it 'converts "yes" to true' do
      ENV['TEST_BOOL'] = 'yes'
      result = described_class.get_bool('TEST_BOOL')
      expect(result).to be true
      ENV.delete('TEST_BOOL')
    end

    it 'converts "on" to true' do
      ENV['TEST_BOOL'] = 'on'
      result = described_class.get_bool('TEST_BOOL')
      expect(result).to be true
      ENV.delete('TEST_BOOL')
    end

    it 'is case insensitive for true values' do
      ENV['TEST_BOOL_UPPER'] = 'TRUE'
      expect(described_class.get_bool('TEST_BOOL_UPPER')).to be true
      ENV.delete('TEST_BOOL_UPPER')

      ENV['TEST_BOOL_MIXED'] = 'Yes'
      expect(described_class.get_bool('TEST_BOOL_MIXED')).to be true
      ENV.delete('TEST_BOOL_MIXED')
    end

    it 'converts "false" and other values to false' do
      ENV['TEST_BOOL_FALSE'] = 'false'
      expect(described_class.get_bool('TEST_BOOL_FALSE')).to be false
      ENV.delete('TEST_BOOL_FALSE')

      ENV['TEST_BOOL_OTHER'] = 'random'
      expect(described_class.get_bool('TEST_BOOL_OTHER')).to be false
      ENV.delete('TEST_BOOL_OTHER')
    end

    it 'returns default when environment variable is nil' do
      result = described_class.get_bool('NONEXISTENT_VAR', default: true)
      expect(result).to be true
    end

    it 'returns false when no default provided and env var missing' do
      result = described_class.get_bool('NONEXISTENT_VAR')
      expect(result).to be false
    end
  end

  describe '.get_array' do
    it 'splits comma-separated values' do
      ENV['TEST_ARRAY'] = 'a,b,c'
      result = described_class.get_array('TEST_ARRAY')
      expect(result).to eq(%w[a b c])
      ENV.delete('TEST_ARRAY')
    end

    it 'strips whitespace from values' do
      ENV['TEST_ARRAY_SPACE'] = ' a , b , c '
      result = described_class.get_array('TEST_ARRAY_SPACE')
      expect(result).to eq(%w[a b c])
      ENV.delete('TEST_ARRAY_SPACE')
    end

    it 'removes empty values' do
      ENV['TEST_ARRAY_EMPTY'] = 'a,,b,  ,c'
      result = described_class.get_array('TEST_ARRAY_EMPTY')
      expect(result).to eq(%w[a b c])
      ENV.delete('TEST_ARRAY_EMPTY')
    end

    it 'supports custom separator' do
      ENV['TEST_ARRAY_PIPE'] = 'a|b|c'
      result = described_class.get_array('TEST_ARRAY_PIPE', separator: '|')
      expect(result).to eq(%w[a b c])
      ENV.delete('TEST_ARRAY_PIPE')
    end

    it 'returns empty array for empty string' do
      ENV['TEST_ARRAY_EMPTY_STR'] = ''
      result = described_class.get_array('TEST_ARRAY_EMPTY_STR')
      expect(result).to eq([])
      ENV.delete('TEST_ARRAY_EMPTY_STR')
    end

    it 'returns default when environment variable is nil' do
      result = described_class.get_array('NONEXISTENT_VAR', default: %w[x y z])
      expect(result).to eq(%w[x y z])
    end

    it 'returns empty array when no default provided and env var missing' do
      result = described_class.get_array('NONEXISTENT_VAR')
      expect(result).to eq([])
    end
  end
end
