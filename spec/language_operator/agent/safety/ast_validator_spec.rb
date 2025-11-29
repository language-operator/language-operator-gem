# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/safety/ast_validator'

RSpec.describe LanguageOperator::Agent::Safety::ASTValidator do
  let(:validator) { described_class.new }

  describe '#validate!' do
    context 'with valid DSL v1 (task/main) code' do
      it 'allows agent definition with task primitives' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "test-agent" do
              description "Test agent"
              persona "Test persona"

              task :fetch_data,
                instructions: "Fetch data",
                inputs: { id: 'integer' },
                outputs: { data: 'hash' }

              main do |inputs|
                result = execute_task(:fetch_data, inputs: inputs)
                result
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows symbolic task with execute block' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "calc" do
              task :calculate,
                inputs: { numbers: 'array' },
                outputs: { total: 'number' }
              do |inputs|
                { total: inputs[:numbers].sum }
              end

              main do |inputs|
                execute_task(:calculate, inputs: inputs)
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows task with TypeCoercion' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "coerce-agent" do
              task :validate_input do |inputs|
                value = TypeCoercion.coerce(inputs[:value], 'integer')
                { result: value }
              end

              main do |inputs|
                execute_task(:validate_input, inputs: inputs)
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows main block with control flow' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "flow-agent" do
              task :check_value do |inputs|
                { valid: inputs[:value] > 10 }
              end

              main do |inputs|
                result = execute_task(:check_value, inputs: inputs)

                if result[:valid]
                  { status: 'success' }
                else
                  { status: 'failure' }
                end
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows main block with error handling' do
        code = <<~'RUBY'
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "error-handler" do
              main do |inputs|
                begin
                  result = execute_task(:risky_task, inputs: inputs)
                  { success: true, result: result }
                rescue => error
                  logger.error("Task failed: #{error.message}")
                  { success: false, error: error.message }
                end
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows task with inputs, outputs, and instructions' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "neural-agent" do
              task :analyze,
                instructions: "Analyze the data for patterns",
                inputs: { data: 'array' },
                outputs: { patterns: 'array', summary: 'string' }

              main do |inputs|
                execute_task(:analyze, inputs: inputs)
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end
    end

    context 'with dangerous code in tasks' do
      it 'rejects system call in symbolic task' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "malicious" do
              task :bad_task do |inputs|
                system("rm -rf /")
                { status: 'done' }
              end

              main do |inputs|
                execute_task(:bad_task, inputs: inputs)
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'system' is not allowed/
        )
      end

      it 'rejects eval in main block' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "eval-agent" do
              main do |inputs|
                eval(inputs[:code])
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'eval' is not allowed/
        )
      end

      it 'rejects File operations in task' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "file-agent" do
              task :write_file do |inputs|
                File.write('/tmp/data.txt', inputs[:data])
                { status: 'written' }
              end

              main do |inputs|
                execute_task(:write_file, inputs: inputs)
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Access to File\.write is not allowed/
        )
      end

      it 'rejects backtick execution in task' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "backtick-agent" do
              task :run_command do |inputs|
                output = `ls -la`
                { output: output }
              end

              main do |inputs|
                execute_task(:run_command, inputs: inputs)
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Backtick command execution is not allowed/
        )
      end

      it 'rejects spawn in main block' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "spawn-agent" do
              main do |inputs|
                spawn('malicious-process')
                { status: 'spawned' }
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'spawn' is not allowed/
        )
      end

      it 'rejects fork in task' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "fork-agent" do
              task :fork_process do |inputs|
                fork { puts 'child process' }
                { status: 'forked' }
              end

              main do |inputs|
                execute_task(:fork_process, inputs: inputs)
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'fork' is not allowed/
        )
      end

      it 'rejects dangerous constant access' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "const-agent" do
              task :access_io do |inputs|
                puts STDIN.read
                { status: 'read' }
              end

              main do |inputs|
                execute_task(:access_io, inputs: inputs)
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Direct access to STDIN constant is not allowed/
        )
      end

      it 'rejects exec call' do
        code = <<~RUBY
          require 'language_operator'

          LanguageOperator::Dsl.define_agents do
            agent "exec-agent" do
              main do |inputs|
                exec('/bin/bash')
              end
            end
          end
        RUBY

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'exec' is not allowed/
        )
      end
    end


    context 'with empty or nil code' do
      it 'does not raise error for empty code' do
        expect { validator.validate!('') }.not_to raise_error
      end

      it 'does not raise error for whitespace-only code' do
        expect { validator.validate!('   ') }.not_to raise_error
      end

      it 'does not raise error for comments only' do
        code = <<~RUBY
          # This is a comment
          # Another comment
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end
    end
  end

  describe '#validate (non-raising version)' do
    it 'returns empty array for valid code' do
      code = <<~RUBY
        require 'language_operator'

        LanguageOperator::Dsl.define_agents do
          agent "valid" do
            task :test do |inputs|
              { result: 'ok' }
            end

            main do |inputs|
              execute_task(:test, inputs: inputs)
            end
          end
        end
      RUBY

      violations = validator.validate(code)
      expect(violations).to be_empty
    end

    it 'returns violations array for dangerous code' do
      code = <<~RUBY
        require 'language_operator'

        LanguageOperator::Dsl.define_agents do
          agent "invalid" do
            main do |inputs|
              system('rm -rf /')
              eval(inputs[:code])
            end
          end
        end
      RUBY

      violations = validator.validate(code)
      expect(violations).not_to be_empty
      expect(violations.size).to eq(2)

      expect(violations[0][:type]).to eq(:dangerous_method)
      expect(violations[0][:method]).to eq('system')

      expect(violations[1][:type]).to eq(:dangerous_method)
      expect(violations[1][:method]).to eq('eval')
    end

  end

  describe 'safe method constants' do
    it 'includes task/main primitives in SAFE_AGENT_METHODS' do
      expect(described_class::SAFE_AGENT_METHODS).to include('task')
      expect(described_class::SAFE_AGENT_METHODS).to include('main')
      expect(described_class::SAFE_AGENT_METHODS).to include('execute_task')
      expect(described_class::SAFE_AGENT_METHODS).to include('inputs')
      expect(described_class::SAFE_AGENT_METHODS).to include('outputs')
      expect(described_class::SAFE_AGENT_METHODS).to include('instructions')
    end

    it 'does not include deprecated workflow/step primitives' do
      expect(described_class::SAFE_AGENT_METHODS).not_to include('workflow')
      expect(described_class::SAFE_AGENT_METHODS).not_to include('step')
      expect(described_class::SAFE_AGENT_METHODS).not_to include('depends_on')
      expect(described_class::SAFE_AGENT_METHODS).not_to include('prompt')
    end

    it 'includes TypeCoercion in SAFE_HELPER_METHODS' do
      expect(described_class::SAFE_HELPER_METHODS).to include('TypeCoercion')
    end
  end

  describe 'integration with real agent patterns' do
    it 'validates complex agent with multiple tasks' do
      code = <<~RUBY
        require 'language_operator'

        LanguageOperator::Dsl.define_agents do
          agent "complex-agent" do
            description "Complex multi-task agent"
            persona "Helpful assistant"

            task :fetch_data,
              instructions: "Fetch data from external source",
              inputs: { source: 'string' },
              outputs: { data: 'array' }

            task :transform_data do |inputs|
              transformed = inputs[:data].map { |item| item.upcase }
              { transformed_data: transformed }
            end

            task :validate_data do |inputs|
              valid = inputs[:transformed_data].all? { |item| item.is_a?(String) }
              { valid: valid }
            end

            main do |inputs|
              raw_data = execute_task(:fetch_data, inputs: { source: inputs[:source] })
              transformed = execute_task(:transform_data, inputs: raw_data)
              validation = execute_task(:validate_data, inputs: transformed)

              if validation[:valid]
                transformed
              else
                { error: 'Validation failed' }
              end
            end

            output do |outputs|
              # Output handling
            end
          end
        end
      RUBY

      expect { validator.validate!(code) }.not_to raise_error
    end

    it 'validates hybrid task (both neural and symbolic)' do
      code = <<~RUBY
        require 'language_operator'

        LanguageOperator::Dsl.define_agents do
          agent "hybrid-agent" do
            task :hybrid_task,
              instructions: "Process the data intelligently",
              inputs: { data: 'array' },
              outputs: { result: 'hash' }
            do |inputs|
              # Symbolic preprocessing
              preprocessed = inputs[:data].compact
              { result: { count: preprocessed.size } }
            end

            main do |inputs|
              execute_task(:hybrid_task, inputs: inputs)
            end
          end
        end
      RUBY

      expect { validator.validate!(code) }.not_to raise_error
    end
  end
end
