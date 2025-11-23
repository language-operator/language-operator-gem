# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Dsl do
  let(:temp_dir) { Dir.mktmpdir }
  let(:valid_tool_content) do
    <<~RUBY
      tool "test_tool" do
        description "A test tool"
        parameter :name do
          type :string
          required true
        end
        execute do |params|
          "Hello, \#{params['name']}!"
        end
      end
    RUBY
  end

  let(:valid_agent_content) do
    <<~RUBY
      agent "test_agent" do
        description "A test agent"
        mode :autonomous
        
        task :simple_task do |inputs|
          { result: "completed" }
        end
        
        main do |inputs|
          execute_task(:simple_task)
        end
      end
    RUBY
  end

  let(:invalid_syntax_content) do
    <<~RUBY
      tool "broken_tool" do
        description "This will fail"
        def broken_method(
          # Missing closing parenthesis
      end
    RUBY
  end

  after do
    FileUtils.remove_entry(temp_dir)
    described_class.clear!
    described_class.clear_agents!
  end

  describe '.load_file' do
    context 'when file exists and is valid' do
      let(:tool_file) { File.join(temp_dir, 'valid_tool.rb') }

      before do
        File.write(tool_file, valid_tool_content)
      end

      it 'loads the tool successfully' do
        registry = described_class.load_file(tool_file)
        
        expect(registry.get('test_tool')).not_to be_nil
        expect(registry.get('test_tool').description).to eq('A test tool')
      end

      it 'returns the global registry' do
        result = described_class.load_file(tool_file)
        expect(result).to be(described_class.registry)
      end
    end

    context 'when file does not exist' do
      let(:missing_file) { File.join(temp_dir, 'missing.rb') }

      it 'raises FileNotFoundError with helpful message' do
        expect { described_class.load_file(missing_file) }.to raise_error(
          LanguageOperator::FileNotFoundError,
          /Tool definition file not found at '.*missing\.rb'/
        )
      end
    end

    context 'when file is a directory' do
      let(:directory_path) { File.join(temp_dir, 'directory') }

      before do
        Dir.mkdir(directory_path)
      end

      it 'raises FileNotFoundError with helpful message' do
        expect { described_class.load_file(directory_path) }.to raise_error(
          LanguageOperator::FileNotFoundError,
          /Tool definition file not found at '.*directory'/
        )
      end
    end

    context 'when file has permission issues' do
      let(:restricted_file) { File.join(temp_dir, 'restricted.rb') }

      before do
        File.write(restricted_file, valid_tool_content)
        File.chmod(0o000, restricted_file) # Remove all permissions
      end

      after do
        File.chmod(0o644, restricted_file) if File.exist?(restricted_file)
      end

      it 'raises FilePermissionError with helpful message' do
        expect { described_class.load_file(restricted_file) }.to raise_error(
          LanguageOperator::FilePermissionError,
          /Permission denied reading tool definition file '.*restricted\.rb'/
        )
      end
    end

    context 'when file has syntax errors' do
      let(:syntax_error_file) { File.join(temp_dir, 'syntax_error.rb') }

      before do
        File.write(syntax_error_file, invalid_syntax_content)
      end

      it 'raises FileSyntaxError with helpful message' do
        expect { described_class.load_file(syntax_error_file) }.to raise_error(
          LanguageOperator::FileSyntaxError,
          /Syntax error in tool definition file '.*syntax_error\.rb'/
        )
      end
    end

    context 'when file contains runtime errors' do
      let(:runtime_error_file) { File.join(temp_dir, 'runtime_error.rb') }
      let(:runtime_error_content) do
        <<~RUBY
          tool "error_tool" do
            description "This will cause a runtime error"
            execute do |params|
              raise StandardError, "Intentional error"
            end
          end
          
          # This will cause an error during loading
          undefined_method_call
        RUBY
      end

      before do
        File.write(runtime_error_file, runtime_error_content)
      end

      it 'raises FileLoadError with helpful message' do
        expect { described_class.load_file(runtime_error_file) }.to raise_error(
          LanguageOperator::FileLoadError,
          /Error executing tool definition file '.*runtime_error\.rb'/
        )
      end
    end
  end

  describe '.load_agent_file' do
    context 'when file exists and is valid' do
      let(:agent_file) { File.join(temp_dir, 'valid_agent.rb') }

      before do
        File.write(agent_file, valid_agent_content)
      end

      it 'loads the agent successfully' do
        registry = described_class.load_agent_file(agent_file)
        
        expect(registry.get('test_agent')).not_to be_nil
        expect(registry.get('test_agent').description).to eq('A test agent')
      end

      it 'returns the global agent registry' do
        result = described_class.load_agent_file(agent_file)
        expect(result).to be(described_class.agent_registry)
      end
    end

    context 'when file does not exist' do
      let(:missing_file) { File.join(temp_dir, 'missing_agent.rb') }

      it 'raises FileNotFoundError with helpful message' do
        expect { described_class.load_agent_file(missing_file) }.to raise_error(
          LanguageOperator::FileNotFoundError,
          /Agent definition file not found at '.*missing_agent\.rb'/
        )
      end
    end

    context 'when file is a directory' do
      let(:directory_path) { File.join(temp_dir, 'agent_directory') }

      before do
        Dir.mkdir(directory_path)
      end

      it 'raises FileNotFoundError with helpful message' do
        expect { described_class.load_agent_file(directory_path) }.to raise_error(
          LanguageOperator::FileNotFoundError,
          /Agent definition file not found at '.*agent_directory'/
        )
      end
    end

    context 'when file has permission issues' do
      let(:restricted_file) { File.join(temp_dir, 'restricted_agent.rb') }

      before do
        File.write(restricted_file, valid_agent_content)
        File.chmod(0o000, restricted_file) # Remove all permissions
      end

      after do
        File.chmod(0o644, restricted_file) if File.exist?(restricted_file)
      end

      it 'raises FilePermissionError with helpful message' do
        expect { described_class.load_agent_file(restricted_file) }.to raise_error(
          LanguageOperator::FilePermissionError,
          /Permission denied reading agent definition file '.*restricted_agent\.rb'/
        )
      end
    end

    context 'when file has syntax errors' do
      let(:syntax_error_file) { File.join(temp_dir, 'agent_syntax_error.rb') }

      before do
        File.write(syntax_error_file, invalid_syntax_content.gsub('tool', 'agent'))
      end

      it 'raises FileSyntaxError with helpful message' do
        expect { described_class.load_agent_file(syntax_error_file) }.to raise_error(
          LanguageOperator::FileSyntaxError,
          /Syntax error in agent definition file '.*agent_syntax_error\.rb'/
        )
      end
    end

    context 'when file contains runtime errors' do
      let(:runtime_error_file) { File.join(temp_dir, 'agent_runtime_error.rb') }
      let(:runtime_error_content) do
        <<~RUBY
          agent "error_agent" do
            description "This will cause a runtime error"
            mode :autonomous
          end
          
          # This will cause an error during loading
          undefined_method_call
        RUBY
      end

      before do
        File.write(runtime_error_file, runtime_error_content)
      end

      it 'raises FileLoadError with helpful message' do
        expect { described_class.load_agent_file(runtime_error_file) }.to raise_error(
          LanguageOperator::FileLoadError,
          /Error executing agent definition file '.*agent_runtime_error\.rb'/
        )
      end
    end
  end

  describe 'error message quality' do
    let(:missing_file) { '/non/existent/path/missing.rb' }

    it 'provides actionable error messages for missing files' do
      expect { described_class.load_file(missing_file) }.to raise_error do |error|
        expect(error.message).to include('Tool definition file not found')
        expect(error.message).to include(missing_file)
        expect(error.message).to include('Please check the file path exists')
      end
    end

    it 'provides actionable error messages for permission issues' do
      restricted_file = File.join(temp_dir, 'restricted.rb')
      File.write(restricted_file, valid_tool_content)
      File.chmod(0o000, restricted_file)

      expect { described_class.load_file(restricted_file) }.to raise_error do |error|
        expect(error.message).to include('Permission denied')
        expect(error.message).to include(restricted_file)
        expect(error.message).to include('check file permissions')
      end

      File.chmod(0o644, restricted_file) if File.exist?(restricted_file)
    end
  end
end