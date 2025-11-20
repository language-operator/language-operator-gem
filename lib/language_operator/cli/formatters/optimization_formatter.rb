# frozen_string_literal: true

require 'pastel'

module LanguageOperator
  module CLI
    module Formatters
      # Formats optimization analysis and proposals for CLI display
      class OptimizationFormatter
        def initialize
          @pastel = Pastel.new
        end

        # Format analysis results showing optimization opportunities
        #
        # @param agent_name [String] Name of the agent
        # @param opportunities [Array<Hash>] Optimization opportunities
        # @return [String] Formatted output
        def format_analysis(agent_name:, opportunities:)
          output = []
          output << ''
          output << @pastel.bold("Analyzing agent '#{agent_name}'...")
          output << @pastel.dim('─' * 70)
          output << ''

          if opportunities.empty?
            output << @pastel.yellow('No optimization opportunities found.')
            output << ''
            output << 'Possible reasons:'
            output << '  • All tasks are already symbolic'
            output << "  • Neural tasks haven't executed enough times (need 10+)"
            output << '  • Execution patterns are too inconsistent (<85%)'
            output << ''
            return output.join("\n")
          end

          # Group by status
          ready = opportunities.select { |opp| opp[:ready_for_learning] }
          not_ready = opportunities.reject { |opp| opp[:ready_for_learning] }

          output << @pastel.bold("Found #{opportunities.size} neural task(s)\n")

          # Show ready tasks
          if ready.any?
            output << @pastel.green.bold("✓ Ready for Optimization (#{ready.size})")
            output << ''
            ready.each do |opp|
              output << format_opportunity(opp, ready: true)
              output << ''
            end
          end

          # Show not ready tasks
          if not_ready.any?
            output << @pastel.yellow.bold("⚠ Not Ready (#{not_ready.size})")
            output << ''
            not_ready.each do |opp|
              output << format_opportunity(opp, ready: false)
              output << ''
            end
          end

          # Summary
          output << @pastel.dim('─' * 70)
          output << if ready.any?
                      @pastel.green.bold("#{ready.size}/#{opportunities.size} tasks eligible for optimization")
                    else
                      @pastel.yellow("0/#{opportunities.size} tasks ready - check requirements above")
                    end
          output << ''

          output.join("\n")
        end

        # Format a single optimization opportunity
        #
        # @param opp [Hash] Opportunity data
        # @param ready [Boolean] Whether task is ready for optimization
        # @return [String] Formatted output
        def format_opportunity(opp, ready:)
          output = []

          # Task name
          status_icon = ready ? @pastel.green('✓') : @pastel.yellow('⚠')
          output << "  #{status_icon} #{@pastel.bold(opp[:task_name])}"

          # Metrics
          exec_label = @pastel.dim('    Executions:')
          exec_value = format_count_status(opp[:execution_count], 10, ready)
          output << "#{exec_label} #{exec_value}"

          cons_label = @pastel.dim('    Consistency:')
          cons_value = format_percentage_status(opp[:consistency_score], 0.85, ready)
          output << "#{cons_label} #{cons_value}"

          # Pattern or reason
          if ready && opp[:common_pattern]
            output << "#{@pastel.dim('    Pattern:')} #{opp[:common_pattern]}"
          elsif opp[:reason]
            output << "#{@pastel.dim('    Reason:')} #{@pastel.yellow(opp[:reason])}"
          end

          output.join("\n")
        end

        # Format optimization proposal with diff and metrics
        #
        # @param proposal [Hash] Proposal data
        # @return [String] Formatted output
        def format_proposal(proposal:)
          output = []
          output << ''
          output << @pastel.bold("Optimization Proposal: #{proposal[:task_name]}")
          output << @pastel.dim('=' * 70)
          output << ''

          # Current code
          output << @pastel.yellow.bold('Current (Neural):')
          output << @pastel.dim('─' * 70)
          proposal[:current_code].each_line do |line|
            output << @pastel.yellow("  #{line.rstrip}")
          end
          output << ''

          # Proposed code
          output << @pastel.green.bold('Proposed (Symbolic):')
          output << @pastel.dim('─' * 70)
          proposal[:proposed_code].each_line do |line|
            output << @pastel.green("  #{line.rstrip}")
          end
          output << ''

          # Performance impact
          output << @pastel.bold('Performance Impact:')
          output << @pastel.dim('─' * 70)
          impact = proposal[:performance_impact]
          output << format_impact_line('Execution Time:', impact[:current_avg_time], impact[:optimized_avg_time], 's', impact[:time_reduction_pct])
          output << format_impact_line('Cost Per Call:', impact[:current_avg_cost], impact[:optimized_avg_cost], '$', impact[:cost_reduction_pct])
          output << ''
          output << "  #{@pastel.dim('Projected Monthly Savings:')} #{@pastel.green.bold("$#{impact[:projected_monthly_savings]}")}"
          output << ''

          # Metadata
          output << @pastel.bold('Analysis:')
          output << @pastel.dim('─' * 70)
          output << "  #{@pastel.dim('Executions Observed:')} #{proposal[:execution_count]}"
          output << "  #{@pastel.dim('Pattern Consistency:')} #{format_percentage(proposal[:consistency_score])}"
          output << "  #{@pastel.dim('Tool Sequence:')} #{proposal[:pattern]}"
          output << "  #{@pastel.dim('Validation:')} #{proposal[:validation_violations].empty? ? @pastel.green('✓ Passed') : @pastel.red('✗ Failed')}"
          output << ''

          output.join("\n")
        end

        # Format success message after applying optimization
        #
        # @param result [Hash] Application result
        # @return [String] Formatted output
        def format_success(result:)
          output = []
          output << ''
          output << @pastel.green.bold('✓ Optimization applied successfully!')
          output << ''
          output << "  Task '#{result[:task_name]}' has been optimized to symbolic execution."
          output << ''
          output << @pastel.dim('Next steps:')
          output << "  • Monitor performance: aictl agent logs #{result[:task_name]}"
          output << "  • View changes: aictl agent code #{result[:task_name]}"
          output << ''
          output.join("\n")
        end

        private

        # Format a count with status indicator
        def format_count_status(count, threshold, ready)
          if count >= threshold
            @pastel.green("#{count} (≥#{threshold})")
          else
            ready ? @pastel.yellow("#{count}/#{threshold}") : @pastel.red("#{count}/#{threshold}")
          end
        end

        # Format a percentage with status indicator
        def format_percentage_status(score, threshold, ready)
          return @pastel.red('N/A') if score.nil?

          pct = (score * 100).round(1)
          threshold_pct = (threshold * 100).round(1)

          if score >= threshold
            @pastel.green("#{pct}% (≥#{threshold_pct}%)")
          else
            ready ? @pastel.yellow("#{pct}%/#{threshold_pct}%") : @pastel.red("#{pct}%/#{threshold_pct}%")
          end
        end

        # Format percentage value
        def format_percentage(score)
          return @pastel.red('N/A') if score.nil?

          pct = (score * 100).round(1)
          @pastel.green("#{pct}%")
        end

        # Format performance impact line
        def format_impact_line(label, current, optimized, unit, reduction_pct)
          current_str = unit == '$' ? format('$%.4f', current) : "#{current}#{unit}"
          optimized_str = unit == '$' ? format('$%.4f', optimized) : "#{optimized}#{unit}"

          "  #{@pastel.dim(label)} #{current_str} → #{@pastel.green(optimized_str)} " \
            "#{@pastel.green("(#{reduction_pct}% faster)")}"
        end
      end
    end
  end
end
