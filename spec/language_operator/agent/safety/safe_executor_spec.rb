# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Agent::Safety::SafeExecutor do
  let(:context) { double('context') }
  let(:validator) { double('validator') }
  let(:executor) { described_class.new(context, validator: validator) }

  describe 'security sandbox' do
    context 'when preventing dangerous constant access' do
      before do
        allow(validator).to receive(:validate!).and_return(true)
      end

      it 'blocks access to dangerous constants (via NameError or SecurityError)' do
        dangerous_constants = %w[File Dir Process IO Kernel ObjectSpace Thread Socket TCPSocket STDIN STDOUT STDERR]

        dangerous_constants.each do |const_name|
          expect { executor.eval(const_name) }.to raise_error(StandardError) do |error|
            # Either NameError (not in scope) or SecurityError (const_missing protection)
            expect([NameError, LanguageOperator::Agent::Safety::SafeExecutor::SecurityError]).to include(error.class)
          end
        end
      end

      it 'const_missing method blocks dangerous constants when accessed dynamically' do
        # Test the const_missing protection directly
        registry = LanguageOperator::Dsl::Registry.new
        context = LanguageOperator::Dsl::Context.new(registry)
        sandbox = LanguageOperator::Agent::Safety::SafeExecutor::SandboxProxy.new(context, executor)

        dangerous_constants = %i[File Dir Process IO Kernel ObjectSpace Thread Socket]

        dangerous_constants.each do |const_name|
          expect { sandbox.const_missing(const_name) }.to raise_error(
            LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
            /Access to constant '#{const_name}' is not allowed in sandbox/
          )
        end
      end
    end

    context 'when allowing safe constants' do
      before do
        allow(validator).to receive(:validate!).and_return(true)
      end

      it 'allows access to safe Ruby constants through proper constant resolution' do
        # Test that safe constants work in realistic usage scenarios
        # where they are accessed as part of type checking or object creation

        # String class should be accessible for type checking
        expect(executor.eval('"test".is_a?(String)')).to be true

        # Array class should be accessible
        expect(executor.eval('[1, 2, 3].is_a?(Array)')).to be true

        # Hash class should be accessible
        expect(executor.eval('{a: 1}.is_a?(Hash)')).to be true

        # Integer class should be accessible
        expect(executor.eval('42.is_a?(Integer)')).to be true
      end

      it 'const_missing method allows safe constants when accessed dynamically' do
        # Test the const_missing protection for allowed constants
        registry = LanguageOperator::Dsl::Registry.new
        context = LanguageOperator::Dsl::Context.new(registry)
        sandbox = LanguageOperator::Agent::Safety::SafeExecutor::SandboxProxy.new(context, executor)

        safe_constants = %i[String Array Hash Integer Float Numeric Symbol Time Date TrueClass FalseClass NilClass HTTP Shell]

        safe_constants.each do |const_name|
          expect { sandbox.const_missing(const_name) }.not_to raise_error
        end
      end
    end

    context 'when testing method chaining bypass attempts with AST validator' do
      it 'blocks dangerous method access like const_get via AST validation' do
        # Test that AST validator blocks const_get
        expect(validator).to receive(:validate!).with('String.const_get(:File)', anything)
                                                .and_raise(LanguageOperator::Agent::Safety::ASTValidator::SecurityError.new('const_get not allowed'))

        expect { executor.eval('String.const_get(:File)') }.to raise_error(
          LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
          /Code validation failed: const_get not allowed/
        )
      end

      it 'blocks reflection methods via AST validation' do
        expect(validator).to receive(:validate!).with('send(:const_get, :File)', anything)
                                                .and_raise(LanguageOperator::Agent::Safety::ASTValidator::SecurityError.new('send not allowed'))

        expect { executor.eval('send(:const_get, :File)') }.to raise_error(
          LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
          /Code validation failed: send not allowed/
        )
      end
    end

    context 'when validating error messages' do
      it 'provides clear security error messages for denied constants via const_missing' do
        # Test error messages from const_missing directly
        registry = LanguageOperator::Dsl::Registry.new
        context = LanguageOperator::Dsl::Context.new(registry)
        sandbox = LanguageOperator::Agent::Safety::SafeExecutor::SandboxProxy.new(context, executor)

        expect { sandbox.const_missing(:File) }.to raise_error(
          LanguageOperator::Agent::Safety::SafeExecutor::SecurityError
        ) do |error|
          expect(error.message).to include('Access to constant')
          expect(error.message).to include('File')
          expect(error.message).to include('not allowed in sandbox')
          expect(error.message).to include('security restriction')
        end
      end
    end

    context 'when preventing constant redefinition warnings' do
      before do
        allow(validator).to receive(:validate!).and_return(true)
      end

      it 'allows user code to define constants without warnings' do
        # This should not generate redefinition warnings
        expect do
          # Capture warnings during execution
          original_verbose = $VERBOSE
          warnings = []
          Warning.singleton_class.prepend(Module.new do
            def warn(message, *args)
              warnings << message
              super
            end
          end)

          executor.eval('String = "custom_value"')

          # Check that no redefinition warnings were generated
          redefinition_warnings = warnings.select { |w| w.include?('already initialized constant') }
          expect(redefinition_warnings).to be_empty
        ensure
          $VERBOSE = original_verbose
        end
      end

      it 'maintains type checking consistency after user redefinition' do
        # User defines their own String constant
        result = executor.eval(<<~RUBY)
          String = "my_custom_string"
          value = "test"
          value.is_a?(::String)  # Should still work with global String class
        RUBY

        expect(result).to be true
      end

      it 'allows access to safe constants even when user redefines them' do
        # User redefines Array, but can still access the real Array via const_missing
        result = executor.eval(<<~RUBY)
          Array = "not_an_array"
          [1, 2, 3].is_a?(::Array)  # Access real Array class
        RUBY

        expect(result).to be true
      end
    end
  end

  describe 'audit logging' do
    let(:mock_context) do
      double('context').tap do |ctx|
        allow(ctx).to receive(:respond_to?).with(:safe_method).and_return(true)
        allow(ctx).to receive(:safe_method).and_return('result')
      end
    end

    before do
      allow(validator).to receive(:validate!).and_return(true)
    end

    it 'logs method calls for security auditing' do
      executor_with_context = described_class.new(mock_context, validator: validator)

      expect { executor_with_context.eval('safe_method') }.not_to raise_error

      expect(executor_with_context.audit_log).not_to be_empty
      log_entry = executor_with_context.audit_log.first
      expect(log_entry[:method]).to eq(:safe_method) # Method names are stored as symbols
      expect(log_entry[:receiver]).to include('Double')
      expect(log_entry[:timestamp]).to be_a(Time)
    end
  end

  describe 'integration with AST validator' do
    it 'validates code through AST validator before execution' do
      dangerous_code = 'system("rm -rf /")'

      expect(validator).to receive(:validate!).with(dangerous_code, anything)
                                              .and_raise(LanguageOperator::Agent::Safety::ASTValidator::SecurityError.new('Dangerous code'))

      expect { executor.eval(dangerous_code) }.to raise_error(
        LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
        /Code validation failed: Dangerous code/
      )
    end
  end
end
