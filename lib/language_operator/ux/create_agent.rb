# frozen_string_literal: true

require_relative 'base'
require_relative 'concerns/headings'
require_relative '../cli/helpers/schedule_builder'

module LanguageOperator
  module Ux
    # Interactive flow for creating agents
    #
    # Guides users through task description, scheduling, and tool configuration.
    #
    # @example
    #   description = Ux::CreateAgent.execute(ctx)
    #
    # rubocop:disable Metrics/ClassLength, Metrics/AbcSize
    class CreateAgent < Base
      include Concerns::Headings

      # Execute the agent creation flow
      #
      # @return [String, nil] Generated description or nil if cancelled
      def execute
        show_welcome

        # Step 1: Get task description
        task = ask_task_description
        return nil unless task

        # Step 2: Determine schedule
        schedule_info = ask_schedule
        return nil unless schedule_info

        # Step 3: Tool detection and configuration
        tools_config = configure_tools(task)

        # Step 4: Preview and confirm
        description = build_description(task, schedule_info, tools_config)

        show_preview(description, schedule_info, tools_config)

        return nil unless confirm_creation?

        description
      end

      private

      def show_welcome
        heading('Model quick start')
      end

      def ask_task_description
        prompt.ask('What should your agent do?') do |q|
          q.required true
          q.validate(/\w+/)
          q.messages[:valid?] = 'Please describe a task (cannot be empty)'
        end
      rescue TTY::Reader::InputInterrupt
        CLI::Formatters::ProgressFormatter.error('Cancelled')
        nil
      end

      def ask_schedule
        puts
        schedule_type = prompt.select('How often should it run?') do |menu|
          menu.choice 'Every day at a specific time', :daily
          menu.choice 'Every few minutes/hours', :interval
          menu.choice 'Continuously (whenever something changes)', :continuous
          menu.choice 'Only when I trigger it manually', :manual
        end

        case schedule_type
        when :daily
          ask_daily_schedule
        when :interval
          ask_interval_schedule
        when :continuous
          { type: :continuous, description: 'continuously' }
        when :manual
          { type: :manual, description: 'on manual trigger' }
        end
      rescue TTY::Reader::InputInterrupt
        CLI::Formatters::ProgressFormatter.error('Cancelled')
        nil
      end

      def ask_daily_schedule
        puts
        time_input = prompt.ask('What time each day? (e.g., 4pm, 9:30am, 16:00):') do |q|
          q.required true
          q.validate(lambda do |input|
            CLI::Helpers::ScheduleBuilder.parse_time(input)
            true
          rescue ArgumentError
            false
          end)
          q.messages[:valid?] = 'Invalid time format. Try: 4pm, 9:30am, or 16:00'
        end

        time_24h = CLI::Helpers::ScheduleBuilder.parse_time(time_input)
        cron = CLI::Helpers::ScheduleBuilder.daily_cron(time_24h)

        {
          type: :daily,
          time: time_24h,
          cron: cron,
          description: "daily at #{time_input}"
        }
      end

      def ask_interval_schedule
        puts
        interval = prompt.ask('How often?', convert: :int) do |q|
          q.required true
          q.validate(->(v) { v.to_i.positive? })
          q.messages[:valid?] = 'Please enter a positive number'
        end

        unit = prompt.select('Minutes, hours, or days?', %w[minutes hours days])

        cron = CLI::Helpers::ScheduleBuilder.interval_cron(interval, unit)

        {
          type: :interval,
          interval: interval,
          unit: unit,
          cron: cron,
          description: "every #{interval} #{unit}"
        }
      end

      def configure_tools(task_description)
        detected = detect_tools(task_description)
        config = {}

        return config if detected.empty?

        puts
        puts "I detected these tools: #{pastel.yellow(detected.join(', '))}"
        puts

        detected.each do |tool|
          case tool
          when 'email'
            config[:email] = ask_email_config
          when 'google-sheets', 'spreadsheet'
            config[:spreadsheet] = ask_spreadsheet_config
          when 'slack'
            config[:slack] = ask_slack_config
          end
        end

        config[:tools] = detected
        config
      end

      def detect_tools(description)
        tools = []
        text = description.downcase

        tools << 'email' if text.match?(/email|mail|send.*message/i)
        tools << 'google-sheets' if text.match?(/spreadsheet|sheet|excel|csv/i)
        tools << 'slack' if text.match?(/slack/i)
        tools << 'github' if text.match?(/github|git|repo/i)

        tools
      end

      def ask_email_config
        email = prompt.ask('Your email for notifications:') do |q|
          q.required true
          q.validate(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i)
          q.messages[:valid?] = 'Please enter a valid email address'
        end
        { address: email }
      end

      def ask_spreadsheet_config
        url = prompt.ask('Spreadsheet URL:') do |q|
          q.required true
          q.validate(%r{^https?://}i)
          q.messages[:valid?] = 'Please enter a valid URL'
        end
        { url: url }
      end

      def ask_slack_config
        channel = prompt.ask('Slack channel (e.g., #general):') do |q|
          q.required true
        end
        { channel: channel }
      end

      def build_description(task, schedule_info, tools_config)
        parts = [task]

        # Add schedule information
        case schedule_info[:type]
        when :daily
          parts << schedule_info[:description]
        when :interval
          parts << schedule_info[:description]
        when :continuous
          # "continuously" might already be implied in task
          parts << 'continuously' unless task.downcase.include?('continuous')
        when :manual
          # Manual trigger doesn't need to be in description
        end

        # Add tool-specific details
        parts << "and email me at #{tools_config[:email][:address]}" if tools_config[:email]

        if tools_config[:spreadsheet] && !task.include?('http')
          # Replace generic "spreadsheet" with specific URL if not already present
          parts << "using spreadsheet at #{tools_config[:spreadsheet][:url]}"
        end

        parts << "and send results to #{tools_config[:slack][:channel]}" if tools_config[:slack]

        parts.join(' ')
      end

      def show_preview(description, schedule_info, tools_config)
        puts
        puts pastel.cyan('╭─ Preview ──────────────────────────────╮')
        puts '│'
        puts "│  #{pastel.bold('Task:')} #{description}"

        if schedule_info[:type] == :manual
          puts "│  #{pastel.bold('Mode:')} Manual trigger"
        else
          schedule_text = schedule_info[:description] || 'on demand'
          puts "│  #{pastel.bold('Schedule:')} #{schedule_text}"
        end

        puts "│  #{pastel.bold('Cron:')} #{pastel.dim(schedule_info[:cron])}" if schedule_info[:cron]

        puts "│  #{pastel.bold('Tools:')} #{tools_config[:tools].join(', ')}" if tools_config[:tools]&.any?

        puts '│'
        puts pastel.cyan('╰────────────────────────────────────────╯')
        puts
      end

      def confirm_creation?
        puts
        prompt.yes?('Create this agent?')
      rescue TTY::Reader::InputInterrupt
        false
      end
    end
    # rubocop:enable Metrics/ClassLength, Metrics/AbcSize
  end
end
