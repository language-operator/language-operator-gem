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
    demo_highlighted_box
    demo_list_box
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
      1. Monitor logs:    langop agent logs my-agent
      2. Check status:    langop agent inspect my-agent
      3. View metrics:    langop agent metrics my-agent
      4. Scale replicas:  langop agent scale my-agent --replicas=3
    MSG
    puts "\n"
  end

  def demo_highlighted_box
    puts pastel.bold('5. Highlighted Boxes')
    puts pastel.dim('-' * 40)
    puts "\n"

    # Model details
    highlighted_box(
      title: 'LanguageModel Details',
      rows: {
        'Name' => 'gpt-4-turbo',
        'Provider' => 'OpenAI',
        'Model' => 'gpt-4-turbo-preview',
        'Cluster' => 'production'
      }
    )
    puts "\n"

    # Agent configuration with nil values (skipped)
    highlighted_box(
      title: 'Agent Configuration',
      rows: {
        'Name' => 'web-scraper',
        'Mode' => 'scheduled',
        'Schedule' => '0 */6 * * *',
        'Endpoint' => nil, # This will be skipped
        'Replicas' => '3',
        'Status' => pastel.green('Running')
      }
    )
    puts "\n"

    # Resource summary with custom character
    highlighted_box(
      title: 'Resource Summary',
      rows: {
        'Created' => '5 agents',
        'Updated' => '2 models',
        'Deleted' => '0 personas'
      },
      title_char: '▶'
    )
    puts "\n"

    # Deployment status
    highlighted_box(
      title: 'Deployment Status',
      rows: {
        'Cluster' => 'production-us-west',
        'Namespace' => 'language-operator',
        'Available' => pastel.green('12/12'),
        'Ready' => pastel.green('12/12'),
        'Up-to-date' => pastel.green('12/12')
      }
    )
    puts "\n"

    # Custom colors
    highlighted_box(
      title: 'Success',
      rows: {
        'Operation' => 'Model created',
        'Status' => 'Completed'
      },
      color: :green
    )
    puts "\n"

    highlighted_box(
      title: 'Error',
      rows: {
        'Code' => '500',
        'Message' => 'Connection failed'
      },
      color: :red
    )
    puts "\n"
  end

  def demo_list_box
    puts pastel.bold('6. List Boxes')
    puts pastel.dim('-' * 40)
    puts "\n"

    # Simple list
    list_box(
      title: 'Models',
      items: ['gpt-4-turbo', 'claude-3-opus', 'llama-3-70b']
    )
    puts "\n"

    # Detailed list
    list_box(
      title: 'Agents',
      items: [
        { name: 'bash-agent', status: pastel.green('Running') },
        { name: 'web-scraper', status: pastel.yellow('Pending') },
        { name: 'data-processor', status: pastel.red('Stopped') }
      ],
      style: :detailed
    )
    puts "\n"

    # Conditions style
    list_box(
      title: 'Conditions',
      items: [
        { type: 'Ready', status: 'True', message: 'Agent is ready' },
        { type: 'Synthesized', status: 'True', message: 'Code synthesized successfully' },
        { type: 'Validated', status: 'False', message: 'Validation pending' }
      ],
      style: :conditions
    )
    puts "\n"

    # Key-value pairs
    list_box(
      title: 'Labels',
      items: {
        'app' => 'language-operator',
        'env' => 'production',
        'version' => 'v1.0.0'
      },
      style: :key_value
    )
    puts "\n"

    # Empty list
    list_box(
      title: 'Personas',
      items: [],
      empty_message: 'No personas configured'
    )
    puts "\n"
  end

  def demo_prompt
    puts pastel.bold('7. Interactive Prompts')
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
      %w[pastel prompt spinner table box highlighted_box list_box]
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
