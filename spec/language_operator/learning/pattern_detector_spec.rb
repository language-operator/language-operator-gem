# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/learning/pattern_detector'
require 'language_operator/learning/trace_analyzer'
require 'language_operator/agent/safety/ast_validator'

RSpec.describe LanguageOperator::Learning::PatternDetector do
  let(:trace_analyzer) { instance_double(LanguageOperator::Learning::TraceAnalyzer) }
  let(:validator) { instance_double(LanguageOperator::Agent::Safety::ASTValidator) }
  let(:detector) { described_class.new(trace_analyzer: trace_analyzer, validator: validator) }

  describe '#initialize' do
    it 'accepts trace_analyzer and validator dependencies' do
      expect(detector).to be_a(described_class)
    end

    it 'accepts optional logger' do
      logger = instance_double(Logger)
      detector_with_logger = described_class.new(
        trace_analyzer: trace_analyzer,
        validator: validator,
        logger: logger
      )
      expect(detector_with_logger).to be_a(described_class)
    end
  end

  describe '#detect_pattern' do
    context 'with valid analysis result meeting all criteria' do
      let(:analysis_result) do
        {
          task_name: 'fetch_user',
          execution_count: 15,
          consistency_score: 0.92,
          consistency_threshold: 0.85,
          ready_for_learning: true,
          common_pattern: 'db_fetch → cache_get',
          input_signatures: 2
        }
      end

      it 'generates symbolic code from consistent pattern' do
        allow(validator).to receive(:validate).and_return([])

        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:success]).to be true
        expect(result[:task_name]).to eq('fetch_user')
        expect(result[:generated_code]).to include("execute_tool('db_fetch'")
        expect(result[:generated_code]).to include("execute_tool('cache_get'")
        expect(result[:generated_code]).to include('require \'language_operator\'')
      end

      it 'includes metadata in result' do
        allow(validator).to receive(:validate).and_return([])

        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:consistency_score]).to eq(0.92)
        expect(result[:execution_count]).to eq(15)
        expect(result[:pattern]).to eq('db_fetch → cache_get')
        expect(result[:generated_at]).to be_a(String)
      end

      it 'marks as ready_to_deploy when consistency >= 0.90' do
        allow(validator).to receive(:validate).and_return([])

        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:ready_to_deploy]).to be true
      end

      it 'not ready_to_deploy when consistency < 0.90' do
        analysis_result[:consistency_score] = 0.87
        allow(validator).to receive(:validate).and_return([])

        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:ready_to_deploy]).to be false
      end
    end

    context 'with low consistency score' do
      let(:analysis_result) do
        {
          task_name: 'inconsistent_task',
          execution_count: 15,
          consistency_score: 0.70,
          ready_for_learning: false,
          common_pattern: 'db_fetch'
        }
      end

      it 'returns rejection with reason' do
        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:success]).to be false
        expect(result[:reason]).to include('consistency')
      end

      it 'includes diagnostic information' do
        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:task_name]).to eq('inconsistent_task')
        expect(result[:consistency_score]).to eq(0.70)
        expect(result[:execution_count]).to eq(15)
      end
    end

    context 'with insufficient executions' do
      let(:analysis_result) do
        {
          task_name: 'new_task',
          execution_count: 5,
          consistency_score: 0.95,
          ready_for_learning: false,
          common_pattern: 'api_call'
        }
      end

      it 'returns rejection with reason' do
        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:success]).to be false
        expect(result[:reason]).to include('Insufficient executions')
        expect(result[:reason]).to include('5/10')
      end
    end

    context 'with no common pattern' do
      let(:analysis_result) do
        {
          task_name: 'random_task',
          execution_count: 15,
          consistency_score: 0.95,
          ready_for_learning: false,
          common_pattern: nil
        }
      end

      it 'returns rejection with reason' do
        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:success]).to be false
        expect(result[:reason]).to include('No common pattern')
      end
    end

    context 'with validation failures' do
      let(:analysis_result) do
        {
          task_name: 'fetch_user',
          execution_count: 15,
          consistency_score: 0.92,
          ready_for_learning: true,
          common_pattern: 'db_fetch'
        }
      end

      it 'returns failure when generated code has violations' do
        violations = [
          { type: :dangerous_method, method: 'system', location: 5 }
        ]
        allow(validator).to receive(:validate).and_return(violations)

        result = detector.detect_pattern(analysis_result: analysis_result)

        expect(result[:success]).to be false
        expect(result[:validation_violations]).to eq(violations)
        expect(result[:ready_to_deploy]).to be false
      end
    end

    context 'with nil analysis result' do
      it 'returns rejection' do
        result = detector.detect_pattern(analysis_result: nil)

        expect(result[:success]).to be false
        expect(result[:reason]).to include('Invalid analysis result')
      end
    end

    context 'with invalid analysis result type' do
      it 'returns rejection for non-hash input' do
        result = detector.detect_pattern(analysis_result: 'invalid')

        expect(result[:success]).to be false
        expect(result[:reason]).to include('Invalid analysis result')
      end
    end
  end

  describe '#generate_symbolic_code' do
    it 'generates code with single tool call' do
      code = detector.generate_symbolic_code(
        pattern: 'fetch_api',
        task_name: 'get_data'
      )

      expect(code).to include('require \'language_operator\'')
      expect(code).to include('agent "get-data-symbolic"')
      expect(code).to include('task :core_pattern')
      expect(code).to include("execute_tool('fetch_api', inputs)")
      expect(code).to include('final_result = step1_result')
      expect(code).to include('{ result: final_result }')
    end

    it 'generates code with two chained tool calls' do
      code = detector.generate_symbolic_code(
        pattern: 'db_fetch → cache_set',
        task_name: 'cache_user'
      )

      expect(code).to include("step1_result = execute_tool('db_fetch', inputs)")
      expect(code).to include("final_result = execute_tool('cache_set', step1_result)")
      expect(code).to include('{ result: final_result }')
    end

    it 'generates code with three chained tool calls' do
      code = detector.generate_symbolic_code(
        pattern: 'db_fetch → transform → api_send',
        task_name: 'sync_data'
      )

      expect(code).to include("step1_result = execute_tool('db_fetch', inputs)")
      expect(code).to include("step2_result = execute_tool('transform', step1_result)")
      expect(code).to include("final_result = execute_tool('api_send', step2_result)")
      expect(code).to include('{ result: final_result }')
    end

    it 'generates code with five chained tool calls' do
      code = detector.generate_symbolic_code(
        pattern: 'fetch → validate → transform → enrich → send',
        task_name: 'etl_pipeline'
      )

      expect(code).to include("step1_result = execute_tool('fetch', inputs)")
      expect(code).to include("step2_result = execute_tool('validate', step1_result)")
      expect(code).to include("step3_result = execute_tool('transform', step2_result)")
      expect(code).to include("step4_result = execute_tool('enrich', step3_result)")
      expect(code).to include("final_result = execute_tool('send', step4_result)")
    end

    it 'includes proper agent metadata' do
      code = detector.generate_symbolic_code(
        pattern: 'db_fetch',
        task_name: 'test_task'
      )

      expect(code).to include('agent "test-task-symbolic"')
      expect(code).to include('description "Symbolic implementation of test_task (learned from execution patterns)"')
    end

    it 'includes task definition with inputs and outputs' do
      code = detector.generate_symbolic_code(
        pattern: 'api_call',
        task_name: 'call_service'
      )

      expect(code).to include('task :core_pattern,')
      expect(code).to include('inputs: { data: \'hash\' },')
      expect(code).to include('outputs: { result: \'hash\' }')
    end

    it 'includes main block that executes the core pattern' do
      code = detector.generate_symbolic_code(
        pattern: 'api_call',
        task_name: 'call_service'
      )

      expect(code).to include('main do |inputs|')
      expect(code).to include('execute_task(:core_pattern, inputs: inputs)')
    end

    it 'converts task names with underscores to kebab-case for agent name' do
      code = detector.generate_symbolic_code(
        pattern: 'api',
        task_name: 'fetch_user_data'
      )

      expect(code).to include('agent "fetch-user-data-symbolic"')
    end

    it 'handles empty pattern gracefully' do
      code = detector.generate_symbolic_code(
        pattern: '',
        task_name: 'empty_task'
      )

      expect(code).to include('{ result: {} }')
    end
  end

  describe '#validate_generated_code' do
    it 'returns valid when no violations found' do
      code = 'valid ruby code'
      allow(validator).to receive(:validate).with(code).and_return([])

      result = detector.validate_generated_code(code: code)

      expect(result[:valid]).to be true
      expect(result[:violations]).to eq([])
      expect(result[:safe_methods_used]).to be true
    end

    it 'returns invalid when violations found' do
      code = 'dangerous code'
      violations = [
        { type: :dangerous_method, method: 'system', location: 5 }
      ]
      allow(validator).to receive(:validate).with(code).and_return(violations)

      result = detector.validate_generated_code(code: code)

      expect(result[:valid]).to be false
      expect(result[:violations]).to eq(violations)
    end

    it 'handles validator errors gracefully' do
      code = 'code'
      allow(validator).to receive(:validate).and_raise(StandardError, 'Validation error')

      result = detector.validate_generated_code(code: code)

      expect(result[:valid]).to be false
      expect(result[:violations].first[:type]).to eq(:validation_error)
      expect(result[:safe_methods_used]).to be false
    end
  end

  describe 'integration with real ASTValidator' do
    let(:real_validator) { LanguageOperator::Agent::Safety::ASTValidator.new }
    let(:detector_with_real_validator) do
      described_class.new(
        trace_analyzer: trace_analyzer,
        validator: real_validator
      )
    end

    it 'generates code that passes AST validation' do
      code = detector_with_real_validator.generate_symbolic_code(
        pattern: 'db_fetch → api_call',
        task_name: 'fetch_data'
      )

      result = detector_with_real_validator.validate_generated_code(code: code)

      expect(result[:valid]).to be true
      expect(result[:violations]).to be_empty
    end

    it 'detects if generated code somehow contains dangerous methods' do
      # This shouldn't happen in normal operation, but test the safety net
      dangerous_code = <<~RUBY
        require 'language_operator'
        system('rm -rf /')
      RUBY

      result = detector_with_real_validator.validate_generated_code(code: dangerous_code)

      expect(result[:valid]).to be false
      expect(result[:violations]).not_to be_empty
    end
  end

  describe 'edge cases' do
    it 'handles patterns with extra whitespace' do
      code = detector.generate_symbolic_code(
        pattern: '  db_fetch   →   cache_get  ',
        task_name: 'test'
      )

      expect(code).to include("execute_tool('db_fetch'")
      expect(code).to include("execute_tool('cache_get'")
    end

    it 'handles task names with special characters' do
      code = detector.generate_symbolic_code(
        pattern: 'api',
        task_name: 'fetch:user:data'
      )

      expect(code).to include('agent "fetch:user:data-symbolic"')
    end

    it 'handles very long tool chains' do
      pattern = (1..10).map { |i| "tool#{i}" }.join(' → ')
      code = detector.generate_symbolic_code(
        pattern: pattern,
        task_name: 'long_chain'
      )

      (1..10).each do |i|
        expect(code).to include("execute_tool('tool#{i}")
      end
    end
  end

  describe 'end-to-end pattern detection flow' do
    let(:real_validator) { LanguageOperator::Agent::Safety::ASTValidator.new }
    let(:detector_with_real_validator) do
      described_class.new(
        trace_analyzer: trace_analyzer,
        validator: real_validator
      )
    end

    it 'completes full flow from analysis to validated code' do
      analysis_result = {
        task_name: 'fetch_user_profile',
        execution_count: 20,
        consistency_score: 0.95,
        ready_for_learning: true,
        common_pattern: 'database_query → cache_store → api_enrich',
        input_signatures: 3
      }

      result = detector_with_real_validator.detect_pattern(analysis_result: analysis_result)

      expect(result[:success]).to be true
      expect(result[:ready_to_deploy]).to be true
      expect(result[:validation_violations]).to be_empty
      expect(result[:generated_code]).to include('agent "fetch-user-profile-symbolic"')
      expect(result[:generated_code]).to include("execute_tool('database_query'")
      expect(result[:generated_code]).to include("execute_tool('cache_store'")
      expect(result[:generated_code]).to include("execute_tool('api_enrich'")
    end
  end
end
