# frozen_string_literal: true

module LanguageOperator
  module CLI
    module Formatters
      # Utility module for formatting values (time, duration, file sizes, etc.)
      # for display in CLI output. Provides consistent formatting across commands.
      module ValueFormatter
        SECONDS_PER_MINUTE = 60
        SECONDS_PER_HOUR = 3600
        SECONDS_PER_DAY = 86_400
        SECONDS_PER_WEEK = 604_800
        BYTES_PER_KB = 1024
        BYTES_PER_MB = 1024 * 1024
        BYTES_PER_GB = 1024 * 1024 * 1024

        # Format time until a future event
        #
        # @param future_time [Time] The future time
        # @return [String] Formatted string like "in 5m" or "in 2h 15m"
        #
        # @example
        #   ValueFormatter.time_until(Time.now + 300) # => "in 5m"
        def self.time_until(future_time)
          diff = future_time - Time.now

          if diff.negative?
            'overdue'
          elsif diff < SECONDS_PER_MINUTE
            "in #{diff.to_i}s"
          elsif diff < SECONDS_PER_HOUR
            minutes = (diff / SECONDS_PER_MINUTE).to_i
            "in #{minutes}m"
          elsif diff < SECONDS_PER_DAY
            hours = (diff / SECONDS_PER_HOUR).to_i
            minutes = ((diff % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE).to_i
            "in #{hours}h #{minutes}m"
          else
            days = (diff / SECONDS_PER_DAY).to_i
            hours = ((diff % SECONDS_PER_DAY) / SECONDS_PER_HOUR).to_i
            "in #{days}d #{hours}h"
          end
        end

        # Format a duration in seconds
        #
        # @param seconds [Numeric] Duration in seconds
        # @return [String] Formatted string like "1.5s" or "2m 30s"
        #
        # @example
        #   ValueFormatter.duration(0.5) # => "500ms"
        #   ValueFormatter.duration(90) # => "1m 30s"
        def self.duration(seconds)
          if seconds < 1
            "#{(seconds * 1000).round}ms"
          elsif seconds < SECONDS_PER_MINUTE
            "#{seconds.round(1)}s"
          else
            minutes = (seconds / SECONDS_PER_MINUTE).floor
            secs = (seconds % SECONDS_PER_MINUTE).round
            "#{minutes}m #{secs}s"
          end
        end

        # Format file size in bytes to human-readable format
        #
        # @param bytes [Integer] File size in bytes
        # @return [String] Formatted string like "1.5KB" or "2.3MB"
        #
        # @example
        #   ValueFormatter.file_size(1500) # => "1.5KB"
        def self.file_size(bytes)
          if bytes < BYTES_PER_KB
            "#{bytes}B"
          elsif bytes < BYTES_PER_MB
            "#{(bytes / BYTES_PER_KB.to_f).round(1)}KB"
          elsif bytes < BYTES_PER_GB
            "#{(bytes / BYTES_PER_MB.to_f).round(1)}MB"
          else
            "#{(bytes / BYTES_PER_GB.to_f).round(1)}GB"
          end
        end

        # Format a timestamp as relative time or absolute date
        #
        # @param time [Time] The timestamp to format
        # @return [String] Formatted string like "5 minutes ago" or "2025-01-15 14:30"
        #
        # @example
        #   ValueFormatter.timestamp(Time.now - 300) # => "5 minutes ago"
        def self.timestamp(time)
          now = Time.now
          diff = now - time

          if diff < SECONDS_PER_MINUTE
            "#{diff.to_i} seconds ago"
          elsif diff < SECONDS_PER_HOUR
            minutes = (diff / SECONDS_PER_MINUTE).to_i
            "#{minutes} minute#{'s' if minutes != 1} ago"
          elsif diff < SECONDS_PER_DAY
            hours = (diff / SECONDS_PER_HOUR).to_i
            "#{hours} hour#{'s' if hours != 1} ago"
          elsif diff < SECONDS_PER_WEEK
            days = (diff / SECONDS_PER_DAY).to_i
            "#{days} day#{'s' if days != 1} ago"
          else
            time.strftime('%Y-%m-%d %H:%M')
          end
        end

        # Format Time object as HH:MM:SS for logs
        #
        # @param time [Time] The time to format
        # @return [String] Formatted string like "14:30:25"
        #
        # @example
        #   ValueFormatter.log_time(Time.now) # => "14:30:25"
        def self.log_time(time)
          time.strftime('%H:%M:%S')
        end

        # Parse timestamp string and format as HH:MM:SS
        #
        # @param timestamp_str [String] ISO or text format timestamp
        # @return [String] Formatted time or empty string on parse error
        #
        # @example
        #   ValueFormatter.parse_and_format_time("2025-01-15T14:30:25Z") # => "14:30:25"
        def self.parse_and_format_time(timestamp_str)
          return '' unless timestamp_str

          time = Time.parse(timestamp_str)
          log_time(time)
        rescue StandardError
          ''
        end

        # Format time components as HH:MM for schedules
        #
        # @param hours [Integer] Hours (0-23)
        # @param minutes [Integer] Minutes (0-59)
        # @return [String] Formatted string like "14:30"
        #
        # @example
        #   ValueFormatter.schedule_time(14, 30) # => "14:30"
        def self.schedule_time(hours, minutes)
          format('%<hours>02d:%<minutes>02d', hours: hours, minutes: minutes)
        end
      end
    end
  end
end
