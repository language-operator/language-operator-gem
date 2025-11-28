# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/agent/task_executor'
require 'language_operator/dsl/task_definition'

RSpec.describe LanguageOperator::Agent::TaskExecutor do
  let(:agent) { instance_double(LanguageOperator::Agent::Base) }
  let(:tasks) { {} }
  let(:executor) { described_class.new(agent, tasks) }

  describe '#initialize' do
    it 'initializes with agent and tasks' do
      expect(executor.agent).to eq(agent)
      expect(executor.tasks).to eq(tasks)
    end

    it 'accepts empty tasks registry' do
      exec = described_class.new(agent)
      expect(exec.tasks).to eq({})
    end
  end

  describe '#execute_task' do
    context 'when task not found' do
      it 'raises TaskValidationError with available tasks' do
        tasks[:foo] = double
        tasks[:bar] = double

        expect do
          executor.execute_task(:missing, inputs: {})
        end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Task not found: missing.*Available tasks: (foo, bar|bar, foo)/)
      end
    end

    context 'with symbolic task' do
      let(:task_def) do
        LanguageOperator::Dsl::TaskDefinition.new(:calculate_total).tap do |t|
          t.inputs({ items: 'array' })
          t.outputs({ total: 'number' })
          t.execute do |inputs|
            { total: inputs[:items].sum }
          end
        end
      end

      before do
        tasks[:calculate_total] = task_def
      end

      it 'executes symbolic task and returns validated output' do
        result = executor.execute_task(:calculate_total, inputs: { items: [1, 2, 3, 4, 5] })

        expect(result).to eq({ total: 15 })
      end

      it 'validates inputs before execution' do
        expect do
          executor.execute_task(:calculate_total, inputs: {})
        end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Missing required input parameter: items/)
      end

      it 'validates outputs after execution' do
        # Create a task that returns invalid output
        broken_task = LanguageOperator::Dsl::TaskDefinition.new(:broken).tap do |t|
          t.inputs({})
          t.outputs({ result: 'string' })
          t.execute do |_inputs|
            { wrong_field: 'oops' } # Missing required output field
          end
        end
        tasks[:broken] = broken_task

        expect do
          executor.execute_task(:broken, inputs: {})
        end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Missing required output field: result/)
      end

      it 'provides task executor as context to symbolic tasks' do
        # Create a task that uses execute_task internally
        nested_task = LanguageOperator::Dsl::TaskDefinition.new(:nested).tap do |t|
          t.inputs({})
          t.outputs({ sum: 'number' })
          t.execute do |_inputs|
            # Call another task via self (the task executor context)
            # When context is provided, instance_exec makes it available as self
            result = execute_task(:calculate_total, inputs: { items: [10, 20, 30] })
            { sum: result[:total] }
          end
        end
        tasks[:nested] = nested_task

        result = executor.execute_task(:nested, inputs: {})
        expect(result).to eq({ sum: 60 })
      end
    end

    context 'with neural task' do
      let(:neural_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:summarize_text).tap do |t|
          t.instructions('Summarize the given text')
          t.inputs({ text: 'string' })
          t.outputs({ summary: 'string' })
        end
      end

      let(:llm_response) do
        instance_double(RubyLLM::Message, content: '{"summary": "This is a summary"}', is_a?: false)
      end

      before do
        tasks[:summarize_text] = neural_task
        allow(agent).to receive(:send_message).and_return(llm_response)
      end

      it 'executes neural task via LLM' do
        result = executor.execute_task(:summarize_text, inputs: { text: 'Long text here...' })

        expect(result).to eq({ summary: 'This is a summary' })
        expect(agent).to have_received(:send_message)
      end

      it 'builds prompt with task instructions and inputs' do
        executor.execute_task(:summarize_text, inputs: { text: 'Sample text' })

        expect(agent).to have_received(:send_message) do |prompt|
          expect(prompt).to include('summarize_text')
          expect(prompt).to include('Summarize the given text')
          expect(prompt).to include('Sample text')
          expect(prompt).to include('summary (string)')
        end
      end

      it 'parses JSON from code blocks' do
        allow(agent).to receive(:send_message).and_return(
          instance_double(RubyLLM::Message,
                          content: "Here's the result:\n```json\n{\"summary\": \"Parsed from code block\"}\n```",
                          is_a?: false)
        )

        result = executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        expect(result).to eq({ summary: 'Parsed from code block' })
      end

      it 'parses raw JSON objects' do
        allow(agent).to receive(:send_message).and_return(
          instance_double(RubyLLM::Message,
                          content: '{"summary": "Raw JSON object"}',
                          is_a?: false)
        )

        result = executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        expect(result).to eq({ summary: 'Raw JSON object' })
      end

      it 'raises error if LLM returns invalid JSON' do
        allow(agent).to receive(:send_message).and_return(
          instance_double(RubyLLM::Message,
                          content: 'Not JSON at all',
                          is_a?: false)
        )

        expect do
          executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        end.to raise_error(LanguageOperator::Agent::TaskExecutionError, /returned invalid JSON/)
      end

      it 'retries LLM call when JSON parsing fails initially' do
        # First call returns invalid JSON, second call returns valid JSON
        call_count = 0
        allow(agent).to receive(:send_message) do
          call_count += 1
          if call_count == 1
            instance_double(RubyLLM::Message,
                            content: 'Not JSON at all',
                            is_a?: false)
          else
            instance_double(RubyLLM::Message,
                            content: '{"summary": "Retry successful"}',
                            is_a?: false)
          end
        end

        result = executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        expect(result).to eq({ summary: 'Retry successful' })
        expect(call_count).to eq(2)
      end

      it 'only retries JSON parsing once per task' do
        # Track calls to verify parsing retry behavior
        call_count = 0
        allow(agent).to receive(:send_message) do
          call_count += 1
          # First call gets parsing retry (call 2), then normal task retries (calls 3-5)
          instance_double(RubyLLM::Message,
                          content: 'Not JSON at all',
                          is_a?: false)
        end

        expect do
          executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        end.to raise_error(LanguageOperator::Agent::TaskExecutionError, /returned invalid JSON/)

        # Should make 5 calls total:
        # Call 1: Original attempt
        # Call 2: JSON parsing retry with clarified prompt
        # Calls 3-5: Normal task retries (max_retries = 3)
        expect(call_count).to eq(5)
      end

      it 'validates neural task outputs against schema' do
        # LLM returns wrong field
        allow(agent).to receive(:send_message).and_return(
          instance_double(RubyLLM::Message,
                          content: '{"wrong_field": "value"}',
                          is_a?: false)
        )

        expect do
          executor.execute_task(:summarize_text, inputs: { text: 'Text' })
        end.to raise_error(LanguageOperator::Agent::TaskValidationError, /Missing required output field: summary/)
      end
    end

    context 'error handling' do
      let(:failing_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:failing).tap do |t|
          t.inputs({})
          t.outputs({ result: 'string' })
          t.execute do |_inputs|
            raise StandardError, 'Task execution error'
          end
        end
      end

      let(:timeout_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:timeout_task).tap do |t|
          t.inputs({})
          t.outputs({ result: 'string' })
          t.execute do |_inputs|
            sleep(2)
            { result: 'completed' }
          end
        end
      end

      let(:network_error_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:network_error_task).tap do |t|
          t.inputs({})
          t.outputs({ result: 'string' })
          t.execute do |_inputs|
            raise Errno::ECONNREFUSED, 'Connection refused'
          end
        end
      end

      let(:validation_error_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:validation_error_task).tap do |t|
          t.inputs({ required_param: 'string' })
          t.outputs({ result: 'string' })
          t.execute do |inputs|
            { result: inputs[:required_param] }
          end
        end
      end

      before do
        tasks[:failing] = failing_task
        tasks[:timeout_task] = timeout_task
        tasks[:network_error_task] = network_error_task
        tasks[:validation_error_task] = validation_error_task
      end

      context 'basic error handling' do
        it 'wraps execution errors with task context' do
          expect { executor.execute_task(:failing, inputs: {}) }
            .to raise_error(LanguageOperator::Agent::TaskExecutionError) do |error|
            expect(error.message).to include("Task 'failing' execution failed")
            expect(error.task_name).to eq(:failing)
            expect(error.original_error).to be_a(StandardError)
          end
        end

        it 'raises TaskValidationError for validation errors' do
          expect { executor.execute_task(:validation_error_task, inputs: {}) }
            .to raise_error(LanguageOperator::Agent::TaskValidationError) do |error|
            expect(error.task_name).to eq(:validation_error_task)
            expect(error.original_error).to be_a(ArgumentError)
          end
        end
      end

      context 'timeout handling' do
        let(:timeout_executor) do
          described_class.new(agent, tasks, { timeout_symbolic: 0.5, max_retries: 0 })
        end

        it 'raises TaskTimeoutError when task times out' do
          expect { timeout_executor.execute_task(:timeout_task, inputs: {}, timeout: 0.5) }
            .to raise_error(LanguageOperator::Agent::TaskTimeoutError) do |error|
            expect(error.message).to include('timed out')
            expect(error.task_name).to eq(:timeout_task)
          end
        end

        it 'respects timeout override parameter' do
          expect do
            executor.execute_task(:timeout_task, inputs: {}, timeout: 0.5)
          end.to raise_error(LanguageOperator::Agent::TaskTimeoutError)
        end

        it 'allows unlimited timeout when set to 0' do
          result = timeout_executor.execute_task(:timeout_task, inputs: {}, timeout: 0)
          expect(result).to eq({ result: 'completed' })
        end
      end

      context 'retry logic' do
        let(:retry_executor) do
          described_class.new(agent, tasks, { max_retries: 2, retry_delay_base: 0.1 })
        end

        it 'retries network errors up to max_retries' do
          # Mock sleep to speed up test
          allow(retry_executor).to receive(:sleep)

          expect do
            retry_executor.execute_task(:network_error_task, inputs: {})
          end.to raise_error(LanguageOperator::Agent::TaskExecutionError)

          # Should have tried 3 times total (initial + 2 retries)
          expect(retry_executor).to have_received(:sleep).twice
        end

        it 'does not retry validation errors' do
          allow(retry_executor).to receive(:sleep)

          expect do
            retry_executor.execute_task(:validation_error_task, inputs: {})
          end.to raise_error(LanguageOperator::Agent::TaskValidationError)

          expect(retry_executor).not_to have_received(:sleep)
        end

        it 'respects max_retries override parameter' do
          allow(retry_executor).to receive(:sleep)

          expect do
            retry_executor.execute_task(:network_error_task, inputs: {}, max_retries: 1)
          end.to raise_error(LanguageOperator::Agent::TaskExecutionError)

          # Should have tried 2 times total (initial + 1 retry)
          expect(retry_executor).to have_received(:sleep).once
        end

        it 'calculates exponential backoff delays' do
          delays = []
          allow(retry_executor).to receive(:sleep) { |delay| delays << delay }

          expect do
            retry_executor.execute_task(:network_error_task, inputs: {})
          end.to raise_error(LanguageOperator::Agent::TaskExecutionError)

          expect(delays).to eq([0.1, 0.2]) # 2^0 * 0.1, 2^1 * 0.1
        end
      end

      context 'error categorization' do
        it 'categorizes validation errors correctly' do
          error_category = nil
          allow(executor).to receive(:log_task_error) do |_, _, category, _, _|
            error_category = category
          end

          expect do
            executor.execute_task(:validation_error_task, inputs: {})
          end.to raise_error(LanguageOperator::Agent::TaskValidationError)

          expect(error_category).to eq(:validation)
        end

        it 'categorizes network errors correctly' do
          captured_categories = []
          allow(executor).to receive(:log_task_error) do |_, _, category, _, _|
            captured_categories << category
          end

          expect do
            executor.execute_task(:network_error_task, inputs: {})
          end.to raise_error(LanguageOperator::Agent::TaskExecutionError)

          # Should have categorized the network error correctly in at least one of the log calls
          expect(captured_categories).to include(:network)
        end
      end

      context 'configuration' do
        it 'uses default configuration when none provided' do
          default_executor = described_class.new(agent, tasks)
          expect(default_executor.config[:timeout_symbolic]).to eq(30.0)
          expect(default_executor.config[:max_retries]).to eq(3)
        end

        it 'merges provided config with defaults' do
          custom_executor = described_class.new(agent, tasks, { timeout_symbolic: 60.0 })
          expect(custom_executor.config[:timeout_symbolic]).to eq(60.0)
          expect(custom_executor.config[:max_retries]).to eq(3) # default
        end
      end
    end
  end

  describe '#execute_tool' do
    it 'executes tool directly via MCP' do
      tool_mock = double('Tool', name: 'my_tool', call: { result: 'success' })
      allow(agent).to receive(:tools).and_return([tool_mock])

      result = executor.execute_tool('my_tool', { param: 'value' })

      expect(result).to eq({ result: 'success' })
      expect(tool_mock).to have_received(:call).with(param: 'value')
    end
  end

  describe '#execute_llm' do
    it 'delegates to agent.send_message and extracts content' do
      llm_response = instance_double(RubyLLM::Message, content: 'LLM response text', is_a?: false)
      allow(agent).to receive(:send_message).and_return(llm_response)

      result = executor.execute_llm('Test prompt')

      expect(result).to eq('LLM response text')
      expect(agent).to have_received(:send_message).with('Test prompt')
    end

    it 'handles string responses' do
      allow(agent).to receive(:send_message).and_return('Direct string response')

      result = executor.execute_llm('Test prompt')

      expect(result).to eq('Direct string response')
    end
  end

  describe 'integration with MainDefinition' do
    let(:main_def) { LanguageOperator::Dsl::MainDefinition.new }
    let(:task1) do
      LanguageOperator::Dsl::TaskDefinition.new(:task1).tap do |t|
        t.inputs({ value: 'integer' })
        t.outputs({ doubled: 'integer' })
        t.execute do |inputs|
          { doubled: inputs[:value] * 2 }
        end
      end
    end
    let(:task2) do
      LanguageOperator::Dsl::TaskDefinition.new(:task2).tap do |t|
        t.inputs({ value: 'integer' })
        t.outputs({ result: 'string' })
        t.execute do |inputs|
          { result: "The answer is #{inputs[:value]}" }
        end
      end
    end

    before do
      tasks[:task1] = task1
      tasks[:task2] = task2
    end

    it 'executes main block with task executor as context' do
      main_def.execute do |inputs|
        result1 = execute_task(:task1, inputs: { value: inputs[:number] })
        result2 = execute_task(:task2, inputs: { value: result1[:doubled] })
        result2
      end

      result = main_def.call({ number: 21 }, executor)

      expect(result).to eq({ result: 'The answer is 42' })
    end

    context 'error handling in main blocks' do
      let(:failing_task) do
        LanguageOperator::Dsl::TaskDefinition.new(:failing).tap do |t|
          t.inputs({})
          t.outputs({ result: 'string' })
          t.execute do |_inputs|
            raise StandardError, 'Task failed'
          end
        end
      end

      before do
        tasks[:failing] = failing_task
      end

      it 'allows main block to catch task execution errors' do
        main_def.execute do |_inputs|
          execute_task(:failing, inputs: {})
        rescue LanguageOperator::Agent::TaskExecutionError => e
          { error: e.message, recovered: true }
        end

        result = main_def.call({}, executor)

        expect(result[:recovered]).to be true
        expect(result[:error]).to include('Task \'failing\' execution failed')
      end

      it 'allows main block to use ensure blocks' do
        cleanup_called = false
        main_def.execute do |_inputs|
          execute_task(:failing, inputs: {})
        ensure
          cleanup_called = true
        end

        expect do
          main_def.call({}, executor)
        end.to raise_error(LanguageOperator::Agent::TaskExecutionError)

        expect(cleanup_called).to be true
      end

      it 'propagates unhandled errors from main block' do
        main_def.execute do |_inputs|
          execute_task(:failing, inputs: {})
        end

        expect do
          main_def.call({}, executor)
        end.to raise_error(LanguageOperator::Agent::TaskExecutionError)
      end
    end
  end

  describe 'timeout and error precedence (race condition fix)' do
    let(:network_error_task) do
      LanguageOperator::Dsl::TaskDefinition.new(:network_error).tap do |t|
        t.inputs({})
        t.outputs({ result: 'string' })
        t.execute do |_inputs|
          raise Errno::ECONNRESET, 'Connection reset'
        end
      end
    end

    let(:slow_network_task) do
      LanguageOperator::Dsl::TaskDefinition.new(:slow_network).tap do |t|
        t.inputs({})
        t.outputs({ result: 'string' })
        t.execute do |_inputs|
          sleep(2) # Will timeout before completing
          { result: 'success' }
        end
      end
    end

    let(:timeout_then_network_task) do
      LanguageOperator::Dsl::TaskDefinition.new(:timeout_then_network).tap do |t|
        t.inputs({})
        t.outputs({ result: 'string' })
        t.execute do |_inputs|
          sleep(0.5) # Partial execution
          raise Errno::ECONNRESET, 'Connection reset during timeout'
        end
      end
    end

    before do
      tasks[:network_error] = network_error_task
      tasks[:slow_network] = slow_network_task
      tasks[:timeout_then_network] = timeout_then_network_task
    end

    describe 'error precedence hierarchy' do
      it 'timeout errors always take precedence over network errors' do
        # Short timeout to ensure timeout wins
        expect do
          executor.execute_task(:timeout_then_network, inputs: {}, timeout: 0.1)
        end.to raise_error(LanguageOperator::Agent::TaskTimeoutError) do |error|
          expect(error.message).to include('timed out after 0.1s')
          expect(error.task_name).to eq(:timeout_then_network)
          expect(error.original_error).to be_a(Timeout::Error)
        end
      end

      it 'pure network errors are classified as network errors' do
        expect do
          executor.execute_task(:network_error, inputs: {})
        end.to raise_error(LanguageOperator::Agent::TaskNetworkError) do |error|
          expect(error.message).to include('network error: Connection reset')
          expect(error.task_name).to eq(:network_error)
          expect(error.original_error).to be_a(Errno::ECONNRESET)
        end
      end

      it 'timeout errors on slow tasks are always timeout errors' do
        expect do
          executor.execute_task(:slow_network, inputs: {}, timeout: 0.1)
        end.to raise_error(LanguageOperator::Agent::TaskTimeoutError) do |error|
          expect(error.message).to include('timed out after 0.1s')
          expect(error.task_name).to eq(:slow_network)
        end
      end
    end

    describe 'error categorization consistency' do
      it 'categorizes timeout errors consistently' do
        timeout_error = LanguageOperator::Agent::TaskTimeoutError.new(:test, 'timeout', nil)
        timeout_stdlib_error = Timeout::Error.new

        expect(executor.send(:categorize_error, timeout_error)).to eq(:timeout)
        expect(executor.send(:categorize_error, timeout_stdlib_error)).to eq(:timeout)
      end

      it 'categorizes network errors consistently' do
        network_error = LanguageOperator::Agent::TaskNetworkError.new(:test, 'network', nil)
        socket_error = SocketError.new
        connection_error = Errno::ECONNRESET.new

        expect(executor.send(:categorize_error, network_error)).to eq(:network)
        expect(executor.send(:categorize_error, socket_error)).to eq(:network)
        expect(executor.send(:categorize_error, connection_error)).to eq(:network)
      end

      it 'categorizes validation errors consistently' do
        validation_error = LanguageOperator::Agent::TaskValidationError.new(:test, 'validation', nil)
        argument_error = ArgumentError.new

        expect(executor.send(:categorize_error, validation_error)).to eq(:validation)
        expect(executor.send(:categorize_error, argument_error)).to eq(:validation)
      end

      it 'timeout precedence overrides nested error classification' do
        # Simulate wrapped network error inside timeout error
        network_error = Errno::ECONNRESET.new
        timeout_error = LanguageOperator::Agent::TaskTimeoutError.new(:test, 'timeout', network_error)

        # Should still be classified as timeout
        expect(executor.send(:categorize_error, timeout_error)).to eq(:timeout)
      end
    end

    describe 'retry behavior consistency' do
      it 'retries network errors consistently' do
        retry_count = 0
        allow(executor).to receive(:execute_task_implementation) do
          retry_count += 1
          raise Errno::ECONNRESET, 'Connection reset' if retry_count <= 2

          { result: 'success after retries' }
        end

        result = executor.execute_task(:network_error, inputs: {}, max_retries: 3)
        expect(result).to eq({ result: 'success after retries' })
        expect(retry_count).to eq(3) # Initial attempt + 2 retries
      end

      it 'does not retry timeout errors' do
        retry_count = 0
        allow(executor).to receive(:execute_task_implementation) do
          retry_count += 1
          raise Timeout::Error, 'Timeout'
        end

        expect do
          executor.execute_task(:network_error, inputs: {}, max_retries: 3, timeout: 1)
        end.to raise_error(LanguageOperator::Agent::TaskTimeoutError)

        # Should not retry timeout errors
        expect(retry_count).to eq(1)
      end

      it 'does not retry validation errors' do
        retry_count = 0
        allow(executor).to receive(:execute_task_implementation) do
          retry_count += 1
          raise ArgumentError, 'Invalid input'
        end

        expect do
          executor.execute_task(:network_error, inputs: {}, max_retries: 3)
        end.to raise_error(LanguageOperator::Agent::TaskValidationError)

        # Should not retry validation errors
        expect(retry_count).to eq(1)
      end
    end

    describe 'race condition scenarios' do
      it 'timeout wrapper always classifies timeout errors as timeout' do
        # Test the core fix: timeout wrapper preserves timeout classification
        # regardless of any nested network errors
        expect do
          executor.send(:execute_with_timeout, timeout_then_network_task, :timeout_then_network, {}, 0.1)
        end.to raise_error(LanguageOperator::Agent::TaskTimeoutError) do |error|
          # Timeout should always win, even if network error occurs during execution
          expect(error.message).to include('timed out after 0.1s')
          expect(error.task_name).to eq(:timeout_then_network)
        end
      end

      it 'preserves error context in timeout wrapper' do
        expect do
          executor.execute_task(:timeout_then_network, inputs: {}, timeout: 0.1)
        end.to raise_error(LanguageOperator::Agent::TaskTimeoutError) do |error|
          # Should include execution time in message
          expect(error.message).to match(/execution_time: \d+\.\d+s/)
          expect(error.original_error).to be_a(Timeout::Error)
          expect(error.task_name).to eq(:timeout_then_network)
        end
      end
    end

    describe 'telemetry integration' do
      it 'logs timeout precedence information' do
        logger_double = double('logger')
        allow(logger_double).to receive(:debug)
        allow(logger_double).to receive(:info)
        allow(logger_double).to receive(:warn)
        allow(logger_double).to receive(:error)
        allow(logger_double).to receive(:logger).and_return(double(level: 1)) # INFO level
        allow(executor).to receive(:logger).and_return(logger_double)

        expect do
          executor.execute_task(:timeout_then_network, inputs: {}, timeout: 0.1)
        end.to raise_error(LanguageOperator::Agent::TaskTimeoutError)

        # Verify the logger methods were called with timeout precedence info
        expect(logger_double).to have_received(:warn).with(
          'Task execution timed out',
          hash_including(
            task: :timeout_then_network,
            timeout: 0.1,
            timeout_precedence: 'timeout error takes precedence over any nested errors'
          )
        )
      end
    end
  end
end
