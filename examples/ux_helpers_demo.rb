#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showcasing all UxHelper components
#
# Usage:
#   ruby examples/ux_helpers_demo.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'language_operator/cli/helpers/ux_helper'

# Demo class showing all UX helper features
class UxDemo
  include LanguageOperator::CLI::Helpers::UxHelper

  def run
    show_header
    demo_colors
    demo_spinner
    demo_table
    demo_box
    demo_prompt if ARGV.include?('--interactive')
  end

  private

  def show_header
    puts "\n"
    puts pastel.bold.cyan('=' * 60)
    puts pastel.bold.cyan('  UxHelper Demo - All Available Components')
    puts pastel.bold.cyan('=' * 60)
    puts "\n"
  end

  def demo_colors
    puts pastel.bold('1. Colors & Styles')
    puts pastel.dim('-' * 40)
    puts "  #{pastel.green('✓')} Success message"
    puts "  #{pastel.yellow('⚠')} Warning message"
    puts "  #{pastel.red('✗')} Error message"
    puts "  #{pastel.cyan('ℹ')} Info message"
    puts "  #{pastel.bold('Bold text')}"
    puts "  #{pastel.dim('Dimmed text')}"
    puts "  #{pastel.red.bold('Combined: red + bold')}"
    puts "\n"
  end

  def demo_spinner
    puts pastel.bold('2. Spinners')
    puts pastel.dim('-' * 40)

    # Example 1: Success
    spin = spinner('Loading configuration...')
    spin.auto_spin
    sleep 1.5
    spin.success('Config loaded!')

    # Example 2: Processing
    spin = spinner('Processing data...')
    spin.auto_spin
    sleep 1
    spin.success('Data processed!')

    # Example 3: Error handling
    spin = spinner('Connecting to cluster...')
    spin.auto_spin
    sleep 1
    if rand > 0.5
      spin.success('Connected!')
    else
      spin.error('Connection failed!')
    end

    puts "\n"
  end

  def demo_table
    puts pastel.bold('3. Tables')
    puts pastel.dim('-' * 40)

    # Agent status table
    agents = [
      ['agent-web', pastel.green('running'), '2h 15m', '42.3 MB'],
      ['agent-data', pastel.green('running'), '5h 02m', '128.7 MB'],
      ['agent-sync', pastel.yellow('pending'), '0m', '-'],
      ['agent-test', pastel.red('stopped'), '12m', '8.1 MB']
    ]

    puts table(%w[Name Status Uptime Memory], agents)
    puts "\n"
  end

  def demo_box
    puts pastel.bold('4. Boxes')
    puts pastel.dim('-' * 40)
    puts "\n"

    # Simple box
    puts box('Simple framed message')
    puts "\n"

    # Box with title
    puts box(
      'Agent deployed successfully to cluster!',
      title: 'Success'
    )
    puts "\n"

    # Warning box
    puts box(
      'This action cannot be undone.',
      title: 'Warning',
      border: :thick
    )
    puts "\n"

    # Multi-line box
    puts box(<<~MSG, title: 'Next Steps', padding: 2)
      1. Monitor logs:    aictl agent logs my-agent
      2. Check status:    aictl agent inspect my-agent
      3. View metrics:    aictl agent metrics my-agent
      4. Scale replicas:  aictl agent scale my-agent --replicas=3
    MSG
    puts "\n"
  end

  def demo_prompt
    puts pastel.bold('5. Interactive Prompts')
    puts pastel.dim('-' * 40)

    name = prompt.ask('What is your name?')
    puts "  Hello, #{pastel.cyan(name)}!"

    if prompt.yes?('Do you like the new UX helpers?')
      puts "  #{pastel.green('Great!')} We're glad you like them."
    else
      puts "  #{pastel.yellow('Thanks for the feedback!')} We'll keep improving."
    end

    choice = prompt.select(
      'Which helper is your favorite?',
      %w[pastel prompt spinner table box]
    )
    puts "  You selected: #{pastel.bold(choice)}"

    puts "\n"
  end
end

# Run the demo
if __FILE__ == $PROGRAM_NAME
  demo = UxDemo.new
  demo.run

  puts demo.pastel.bold.cyan('Demo complete!')
  puts demo.pastel.dim("Run with --interactive for prompt examples: ruby #{__FILE__} --interactive")
  puts "\n"
end
