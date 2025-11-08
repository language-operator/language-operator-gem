# frozen_string_literal: true

require_relative '../../logger'
require_relative '../../loggable'

module LanguageOperator
  module Agent
    module Safety
      # Budget Tracker for enforcing cost and token limits
      #
      # Tracks cumulative costs and token usage per agent instance
      # and enforces configured budgets.
      #
      # @example
      #   tracker = BudgetTracker.new(daily_budget: 10.0, hourly_budget: 1.0)
      #   tracker.check_budget!(estimated_cost: 0.05, estimated_tokens: 500)
      class BudgetTracker
        include LanguageOperator::Loggable

        attr_reader :daily_budget, :hourly_budget, :token_budget

        class BudgetExceededError < StandardError; end

        def initialize(daily_budget: nil, hourly_budget: nil, token_budget: nil)
          @daily_budget = daily_budget&.to_f
          @hourly_budget = hourly_budget&.to_f
          @token_budget = token_budget&.to_i

          @daily_spending = 0.0
          @hourly_spending = 0.0
          @daily_tokens = 0
          @hourly_tokens = 0

          @day_start = Time.now
          @hour_start = Time.now

          logger.info('Budget tracker initialized',
                      daily_budget: @daily_budget&.round(2),
                      hourly_budget: @hourly_budget&.round(2),
                      token_budget: @token_budget)
        end

        # Check if a request would exceed budget limits
        #
        # @param estimated_cost [Float] Estimated cost for the request
        # @param estimated_tokens [Integer] Estimated token count
        # @raise [BudgetExceededError] If budget would be exceeded
        def check_budget!(estimated_cost: 0.0, estimated_tokens: 0)
          reset_if_needed

          # Check daily budget
          if @daily_budget && (@daily_spending + estimated_cost) > @daily_budget
            remaining = [@daily_budget - @daily_spending, 0].max
            logger.error('Daily budget exceeded',
                         current: @daily_spending.round(4),
                         limit: @daily_budget,
                         remaining: remaining.round(4),
                         requested: estimated_cost.round(4))
            raise BudgetExceededError,
                  "Daily budget exceeded: $#{@daily_spending.round(4)}/$#{@daily_budget} " \
                  "(requested: $#{estimated_cost.round(4)})"
          end

          # Check hourly budget
          if @hourly_budget && (@hourly_spending + estimated_cost) > @hourly_budget
            remaining = [@hourly_budget - @hourly_spending, 0].max
            logger.error('Hourly budget exceeded',
                         current: @hourly_spending.round(4),
                         limit: @hourly_budget,
                         remaining: remaining.round(4),
                         requested: estimated_cost.round(4))
            raise BudgetExceededError,
                  "Hourly budget exceeded: $#{@hourly_spending.round(4)}/$#{@hourly_budget} " \
                  "(requested: $#{estimated_cost.round(4)})"
          end

          # Check token budget
          if @token_budget && (@daily_tokens + estimated_tokens) > @token_budget
            remaining = [@token_budget - @daily_tokens, 0].max
            logger.error('Token budget exceeded',
                         current: @daily_tokens,
                         limit: @token_budget,
                         remaining: remaining,
                         requested: estimated_tokens)
            raise BudgetExceededError,
                  "Token budget exceeded: #{@daily_tokens}/#{@token_budget} " \
                  "(requested: #{estimated_tokens})"
          end

          logger.debug('Budget check passed',
                       estimated_cost: estimated_cost.round(4),
                       estimated_tokens: estimated_tokens)
        end

        # Record actual spending after a request
        #
        # @param cost [Float] Actual cost of the request
        # @param tokens [Integer] Actual token count
        def record_spending(cost:, tokens:)
          reset_if_needed

          @daily_spending += cost
          @hourly_spending += cost
          @daily_tokens += tokens
          @hourly_tokens += tokens

          logger.debug('Spending recorded',
                       cost: cost.round(4),
                       tokens: tokens,
                       daily_total: @daily_spending.round(4),
                       hourly_total: @hourly_spending.round(4),
                       daily_tokens: @daily_tokens)
        end

        # Get current budget status
        #
        # @return [Hash] Budget status information
        def status
          reset_if_needed

          {
            daily: {
              spending: @daily_spending.round(4),
              budget: @daily_budget&.round(2),
              remaining: @daily_budget ? (@daily_budget - @daily_spending).round(4) : nil,
              percentage: @daily_budget ? ((@daily_spending / @daily_budget) * 100).round(1) : nil
            },
            hourly: {
              spending: @hourly_spending.round(4),
              budget: @hourly_budget&.round(2),
              remaining: @hourly_budget ? (@hourly_budget - @hourly_spending).round(4) : nil,
              percentage: @hourly_budget ? ((@hourly_spending / @hourly_budget) * 100).round(1) : nil
            },
            tokens: {
              used: @daily_tokens,
              budget: @token_budget,
              remaining: @token_budget ? (@token_budget - @daily_tokens) : nil,
              percentage: @token_budget ? ((@daily_tokens.to_f / @token_budget) * 100).round(1) : nil
            }
          }
        end

        private

        def logger_component
          'Safety::BudgetTracker'
        end

        # Reset counters if time periods have elapsed
        def reset_if_needed
          now = Time.now

          # Reset daily counters
          if (now - @day_start) >= 86_400 # 24 hours
            logger.info('Resetting daily budget counters',
                        previous_spending: @daily_spending.round(4),
                        previous_tokens: @daily_tokens)
            @daily_spending = 0.0
            @daily_tokens = 0
            @day_start = now
          end

          # Reset hourly counters
          return unless (now - @hour_start) >= 3600 # 1 hour

          logger.debug('Resetting hourly budget counters',
                       previous_spending: @hourly_spending.round(4))
          @hourly_spending = 0.0
          @hourly_tokens = 0
          @hour_start = now
        end
      end
    end
  end
end
