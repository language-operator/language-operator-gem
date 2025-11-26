# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Helpers
      # Helper for building schedules from natural language inputs
      class ScheduleBuilder
        class << self
          # Parse natural language time input and return 24-hour format
          # Examples: "4pm" -> "16:00", "9:30am" -> "09:30", "16:00" -> "16:00"
          def parse_time(input)
            input = input.strip.downcase

            # Handle 24-hour format (e.g., "16:00", "9:30")
            if input.match?(/^\d{1,2}:\d{2}$/)
              hours, minutes = input.split(':').map(&:to_i)
              return format_time(hours, minutes) if valid_time?(hours, minutes)

              raise ArgumentError, "Invalid time: #{input}"
            end

            # Handle 12-hour format with am/pm (e.g., "4pm", "9:30am")
            match = input.match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$/i)
            raise ArgumentError, "Invalid time format: #{input}" unless match

            hours = match[1].to_i
            minutes = match[2].to_i
            period = match[3].downcase

            # Convert to 24-hour format
            hours = 0 if hours == 12 && period == 'am'
            hours = 12 if hours == 12 && period == 'pm'
            hours += 12 if period == 'pm' && hours != 12

            raise ArgumentError, "Invalid time: #{input}" unless valid_time?(hours, minutes)

            format_time(hours, minutes)
          end

          # Build a cron expression for daily execution at a specific time
          def daily_cron(time_string)
            hours, minutes = time_string.split(':').map(&:to_i)
            "#{minutes} #{hours} * * *"
          end

          # Build a cron expression for interval-based execution
          def interval_cron(interval, unit)
            validate_interval(interval, unit)

            case unit.downcase
            when 'minutes', 'minute'
              "*/#{interval} * * * *"
            when 'hours', 'hour'
              "0 */#{interval} * * *"
            when 'days', 'day'
              "0 0 */#{interval} * *"
            else
              raise ArgumentError, "Invalid unit: #{unit}"
            end
          end

          # Convert cron expression to human-readable format
          def cron_to_human(cron_expr)
            parts = cron_expr.split
            return cron_expr if parts.length != 5

            minute, hour, day, month, weekday = parts

            # Daily at specific time
            if minute =~ /^\d+$/ && hour =~ /^\d+$/ && day == '*' && month == '*' && weekday == '*'
              time_str = format_time(hour.to_i, minute.to_i)
              return "Daily at #{time_str}"
            end

            # Every N minutes
            if minute.start_with?('*/') && hour == '*'
              interval = minute[2..].to_i
              return "Every #{interval} minute#{'s' if interval > 1}"
            end

            # Every N hours
            if minute == '0' && hour.start_with?('*/')
              interval = hour[2..].to_i
              return "Every #{interval} hour#{'s' if interval > 1}"
            end

            # Every N days
            if minute == '0' && hour == '0' && day.start_with?('*/')
              interval = day[2..].to_i
              return "Every #{interval} day#{'s' if interval > 1}"
            end

            # Fallback to cron expression
            cron_expr
          end

          private

          def valid_time?(hours, minutes)
            hours >= 0 && hours < 24 && minutes >= 0 && minutes < 60
          end

          def format_time(hours, minutes)
            format('%<hours>02d:%<minutes>02d', hours: hours, minutes: minutes)
          end

          def validate_interval(interval, unit)
            raise ArgumentError, "Interval must be a positive integer, got: #{interval}" unless interval.is_a?(Integer) && interval.positive?

            case unit.downcase
            when 'minutes', 'minute'
              raise ArgumentError, "Minutes interval must be between 1-59, got: #{interval}" if interval >= 60
            when 'hours', 'hour'
              raise ArgumentError, "Hours interval must be between 1-23, got: #{interval}" if interval >= 24
            when 'days', 'day'
              raise ArgumentError, "Days interval must be between 1-31, got: #{interval}" if interval >= 32
            else
              # Will be caught by the existing case statement
              nil
            end
          end
        end
      end
    end
  end
end
