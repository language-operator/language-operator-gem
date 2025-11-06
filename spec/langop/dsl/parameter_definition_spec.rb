# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/dsl/parameter_definition'

RSpec.describe LanguageOperator::Dsl::ParameterDefinition do
  describe 'required flag behavior' do
    it 'defaults to false' do
      param = described_class.new(:test_param)
      expect(param.required?).to be false
    end

    it 'can be set to true' do
      param = described_class.new(:test_param)
      param.required true
      expect(param.required?).to be true
    end

    it 'can be set to false explicitly' do
      param = described_class.new(:test_param)
      param.required false
      expect(param.required?).to be false
    end

    it 'can be toggled multiple times' do
      param = described_class.new(:test_param)

      param.required true
      expect(param.required?).to be true

      param.required false
      expect(param.required?).to be false

      param.required true
      expect(param.required?).to be true
    end

    it 'setter does not interfere with getter' do
      param = described_class.new(:test_param)

      # Set to false
      param.required false

      # Check multiple times - should stay false, not flip to true
      expect(param.required?).to be false
      expect(param.required?).to be false
      expect(param.required?).to be false
    end
  end

  describe '#to_schema' do
    it 'includes basic schema attributes' do
      param = described_class.new(:test_param)
      param.type :string
      param.description 'A test parameter'

      schema = param.to_schema

      expect(schema['type']).to eq('string')
      expect(schema['description']).to eq('A test parameter')
    end

    it 'includes enum when set' do
      param = described_class.new(:test_param)
      param.type :string
      param.enum %w[a b c]

      schema = param.to_schema

      expect(schema['enum']).to eq(%w[a b c])
    end

    it 'includes default when set' do
      param = described_class.new(:test_param)
      param.type :string
      param.default 'default_value'

      schema = param.to_schema

      expect(schema['default']).to eq('default_value')
    end
  end

  describe 'validators' do
    describe '#validate_value' do
      it 'returns nil when no validator is set' do
        param = described_class.new(:test_param)
        error = param.validate_value('any value')
        expect(error).to be_nil
      end

      it 'validates with regex' do
        param = described_class.new(:test_param)
        param.validate(/^\d+$/)

        expect(param.validate_value('123')).to be_nil
        expect(param.validate_value('abc')).to include('invalid format')
      end

      it 'validates with proc returning boolean' do
        param = described_class.new(:test_param)
        param.validate ->(val) { val.to_i > 0 }

        expect(param.validate_value(5)).to be_nil
        expect(param.validate_value(-1)).to include('validation failed')
      end

      it 'validates with proc returning error message' do
        param = described_class.new(:test_param)
        param.validate ->(val) { val.to_i > 0 ? true : 'Must be positive' }

        expect(param.validate_value(5)).to be_nil
        expect(param.validate_value(-1)).to eq('Must be positive')
      end
    end

    describe '#email_format' do
      it 'validates email addresses' do
        param = described_class.new(:email)
        param.email_format

        expect(param.validate_value('test@example.com')).to be_nil
        expect(param.validate_value('invalid')).to include('invalid format')
      end
    end

    describe '#url_format' do
      it 'validates URLs' do
        param = described_class.new(:url)
        param.url_format

        expect(param.validate_value('https://example.com')).to be_nil
        expect(param.validate_value('invalid')).to include('invalid format')
      end
    end

    describe '#phone_format' do
      it 'validates phone numbers' do
        param = described_class.new(:phone)
        param.phone_format

        expect(param.validate_value('+12345678901')).to be_nil
        expect(param.validate_value('invalid')).to include('invalid format')
      end
    end
  end

  describe 'type mapping' do
    it 'maps Ruby types to JSON schema types' do
      tests = {
        string: 'string',
        number: 'number',
        integer: 'number',
        boolean: 'boolean',
        array: 'array',
        object: 'object',
        unknown: 'string' # Default
      }

      tests.each do |ruby_type, json_type|
        param = described_class.new(:test)
        param.type ruby_type
        expect(param.to_schema['type']).to eq(json_type)
      end
    end
  end
end
