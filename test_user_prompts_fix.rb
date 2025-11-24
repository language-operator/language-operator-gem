#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/language_operator/cli/helpers/user_prompts'

# Test the fixed UserPrompts.select method
puts "Testing UserPrompts.select method fix..."
puts "This script demonstrates that invalid selections now prompt for retry instead of exiting.\n"
puts "Try the following inputs:"
puts "1. Enter '0' (invalid) - should retry"
puts "2. Enter 'abc' (invalid) - should retry"
puts "3. Enter '5' (invalid) - should retry"
puts "4. Enter '2' (valid) - should select Option B"
puts "5. Or enter 'q' to quit gracefully\n"

options = ['Option A', 'Option B', 'Option C']
result = LanguageOperator::CLI::Helpers::UserPrompts.select('Choose an option:', options)
puts "\nSelected: #{result}"