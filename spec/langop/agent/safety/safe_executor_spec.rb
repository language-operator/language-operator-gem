# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/safety/safe_executor'
require 'language_operator/dsl/context'
require 'language_operator/dsl/registry'

RSpec.describe LanguageOperator::Agent::Safety::SafeExecutor do
  let(:registry) { LanguageOperator::Dsl::Registry.new }
  let(:context) { LanguageOperator::Dsl::Context.new(registry) }
  let(:executor) { described_class.new(context) }

  describe '#eval' do
    context 'with safe code' do
      it 'executes safe tool definition' do
        code = <<~RUBY
          tool "greet" do
            description "Greet someone"
            parameter :name do
              type :string
            end
            execute do |params|
              "Hello, \#{params['name']}!"
            end
          end
        RUBY

        expect { executor.eval(code) }.not_to raise_error
        expect(registry.all.length).to eq(1)
        expect(registry.get('greet')).not_to be_nil
      end

      it 'executes safe Ruby code in DSL context' do
        code = <<~RUBY
          tool "math" do
            description "Do math"
            execute do |params|
              x = [1, 2, 3]
              y = x.map { |n| n * 2 }
              y.sum
            end
          end
        RUBY

        expect { executor.eval(code) }.not_to raise_error
        tool = registry.get('math')
        result = tool.call({})
        expect(result).to eq(12)
      end
    end

    context 'with dangerous code detected by AST validator' do
      it 'blocks code with system() calls' do
        code = 'system("ls")'

        expect { executor.eval(code) }.to raise_error(
          LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
          /Code validation failed/
        )
      end

      it 'blocks code with File operations' do
        code = 'File.read("/etc/passwd")'

        expect { executor.eval(code) }.to raise_error(
          LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
          /Code validation failed/
        )
      end

      it 'blocks code with eval' do
        code = 'eval("puts 1")'

        expect { executor.eval(code) }.to raise_error(
          LanguageOperator::Agent::Safety::SafeExecutor::SecurityError,
          /Code validation failed/
        )
      end
    end

    context 'audit logging' do
      it 'logs method calls during execution' do
        code = <<~RUBY
          tool "test" do
            description "Test"
          end
        RUBY

        executor.eval(code)

        expect(executor.audit_log).not_to be_empty
        expect(executor.audit_log.first[:method]).to eq(:tool)
      end

      it 'includes timestamp in audit log' do
        code = <<~RUBY
          tool "test" do
            description "Test"
          end
        RUBY

        executor.eval(code)

        log_entry = executor.audit_log.first
        expect(log_entry[:timestamp]).to be_a(Time)
      end

      it 'includes receiver class in audit log' do
        code = <<~RUBY
          tool "test" do
            description "Test"
          end
        RUBY

        executor.eval(code)

        log_entry = executor.audit_log.first
        expect(log_entry[:receiver]).to eq('LanguageOperator::Dsl::Context')
      end
    end
  end

  describe 'SandboxProxy' do
    it 'delegates safe DSL methods to context' do
      code = <<~RUBY
        tool "test" do
          description "A test tool"
        end
      RUBY

      executor.eval(code)

      tool = registry.get('test')
      expect(tool.description).to eq('A test tool')
    end

    it 'allows chaining DSL methods' do
      code = <<~RUBY
        tool "chain" do
          description "Chained calls"
          parameter :x do
            type :string
            required true
          end
        end
      RUBY

      expect { executor.eval(code) }.not_to raise_error

      tool = registry.get('chain')
      expect(tool.parameters['x'].required?).to be true
    end
  end
end
