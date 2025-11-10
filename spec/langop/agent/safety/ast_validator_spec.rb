# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/safety/ast_validator'

RSpec.describe LanguageOperator::Agent::Safety::ASTValidator do
  let(:validator) { described_class.new }

  describe '#validate!' do
    context 'with safe code' do
      it 'allows safe agent DSL code' do
        code = <<~RUBY
          agent "test" do
            description "Test agent"
            workflow do
              step :test
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows safe tool DSL code' do
        code = <<~RUBY
          tool "test" do
            description "Test tool"
            parameter :name do
              type :string
            end
            execute do |params|
              "Hello, \#{params[:name]}!"
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows safe helper method calls' do
        code = <<~RUBY
          execute do |params|
            validate_email(params[:email])
            env_get('API_KEY')
            HTTP.get('https://api.example.com')
            Shell.run('echo', 'hello')
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows safe Ruby operations' do
        code = <<~RUBY
          x = [1, 2, 3]
          y = x.map { |n| n * 2 }
          z = { name: "Test" }
          puts y.inspect
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end
    end

    context 'with dangerous methods' do
      it 'blocks system()' do
        code = 'system("ls")'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'system'/
        )
      end

      it 'blocks exec()' do
        code = 'exec("whoami")'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'exec'/
        )
      end

      it 'blocks eval()' do
        code = 'eval("puts 1")'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'eval'/
        )
      end

      it 'blocks backtick execution' do
        code = '`ls -la`'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Backtick command execution/
        )
      end

      it 'blocks require() for non-allowlisted gems' do
        code = 'require "socket"'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'require'/
        )
      end

      it 'allows require for language_operator with single quotes' do
        code = "require 'language_operator'"

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows require for language_operator with double quotes' do
        code = 'require "language_operator"'

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'allows full agent code with require language_operator' do
        code = <<~RUBY
          require 'language_operator'

          agent "test" do
            workflow do
              step :hello, execute: -> { puts "hello" }
            end
          end
        RUBY

        expect { validator.validate!(code) }.not_to raise_error
      end

      it 'blocks load()' do
        code = 'load "/etc/passwd"'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'load'/
        )
      end

      it 'blocks send()' do
        code = 'obj.send(:private_method)'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Dangerous method 'send'/
        )
      end
    end

    context 'with dangerous constants' do
      it 'blocks File operations' do
        code = 'File.read("/etc/passwd")'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Access to File\.read is not allowed/
        )
      end

      it 'blocks Dir operations' do
        code = 'Dir.entries("/")'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Access to Dir\.entries is not allowed/
        )
      end

      it 'blocks IO operations' do
        code = 'IO.popen("ls")'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Access to IO\.popen is not allowed/
        )
      end

      it 'blocks Process operations' do
        code = 'Process.spawn("ls")'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Access to Process\.spawn is not allowed/
        )
      end

      it 'blocks Socket operations' do
        code = 'Socket.tcp("evil.com", 4444)'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Access to Socket\.tcp is not allowed/
        )
      end
    end

    context 'with dangerous global variables' do
      it 'blocks $LOAD_PATH access' do
        code = '$LOAD_PATH << "/tmp"'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Access to global variable \$LOAD_PATH/
        )
      end

      it 'blocks $: access' do
        code = '$: << "/tmp"'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Access to global variable \$:/
        )
      end
    end

    context 'with multiple violations' do
      it 'reports all violations' do
        code = <<~RUBY
          system("ls")
          File.read("/etc/passwd")
          eval("puts 1")
        RUBY

        expect { validator.validate!(code) }.to raise_error do |error|
          expect(error).to be_a(LanguageOperator::Agent::Safety::ASTValidator::SecurityError)
          expect(error.message).to include('system')
          expect(error.message).to include('File.read')
          expect(error.message).to include('eval')
        end
      end
    end

    context 'with syntax errors' do
      it 'raises SecurityError for invalid syntax' do
        code = 'tool "broken" do
  description "test'

        expect { validator.validate!(code) }.to raise_error(
          LanguageOperator::Agent::Safety::ASTValidator::SecurityError,
          /Syntax error/
        )
      end
    end

    context 'with empty code' do
      it 'allows empty code' do
        expect { validator.validate!('') }.not_to raise_error
      end

      it 'allows whitespace only' do
        expect { validator.validate!("  \n  \n  ") }.not_to raise_error
      end
    end
  end

  describe '#validate (non-raising version)' do
    it 'returns empty array for safe code' do
      code = 'puts "hello"'
      violations = validator.validate(code)

      expect(violations).to be_empty
    end

    it 'returns array of violations for dangerous code' do
      code = 'system("ls")'
      violations = validator.validate(code)

      expect(violations).not_to be_empty
      expect(violations.first[:type]).to eq(:dangerous_method)
      expect(violations.first[:method]).to eq('system')
    end

    it 'returns syntax error for invalid code' do
      code = 'tool "broken" do
  description "test'
      violations = validator.validate(code)

      expect(violations).not_to be_empty
      expect(violations.first[:type]).to eq(:syntax_error)
    end
  end
end
