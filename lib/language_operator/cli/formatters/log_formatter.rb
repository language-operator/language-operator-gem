# frozen_string_literal: true

require_relative '../helpers/pastel_helper'
require 'json'
require 'time'

module LanguageOperator
  module CLI
    module Formatters
      # Formatter for displaying agent execution logs with color and icons
      class LogFormatter
        class << self
          include Helpers::PastelHelper

          # Format a single log line from kubectl output
          #
          # @param line [String] Raw log line from kubectl (with [pod/container] prefix)
          # @return [String] Formatted log line with colors and icons
          def format_line(line)
            return line if line.strip.empty?

            # Parse kubectl prefix: [pod-name/container-name] log_content
            prefix, content = parse_kubectl_prefix(line)

            # Format the log content based on detected format
            formatted_content = format_log_content(content)

            # Combine with dimmed prefix
            if prefix
              "#{pastel.dim(prefix)} #{formatted_content}"
            else
              formatted_content
            end
          end

          private

          # Parse the kubectl prefix from the log line
          # Returns [prefix, content] or [nil, original_line]
          def parse_kubectl_prefix(line)
            if line =~ /\A\[([^\]]+)\]\s+(.*)/
              prefix = "[#{Regexp.last_match(1)}]"
              content = Regexp.last_match(2)
              [prefix, content]
            else
              [nil, line]
            end
          end

          # Format log content based on detected format (pretty/text/json)
          def format_log_content(content)
            # Try JSON first
            if content.strip.start_with?('{')
              format_json_log(content)
            # Check for text format with timestamp
            elsif content =~ /\A\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}/
              format_text_log(content)
            # Default to pretty format
            else
              format_pretty_log(content)
            end
          rescue StandardError
            # Fallback to plain if parsing fails
            content
          end

          # Format JSON log format
          def format_json_log(content)
            data = JSON.parse(content)
            timestamp = format_timestamp_from_iso(data['timestamp'])
            level = data['level']
            message = data['message']

            # Build formatted line
            formatted = "#{timestamp} #{format_message_with_icon(message, level)}"

            # Add metadata if present
            metadata_keys = data.keys - %w[timestamp level component message]
            if metadata_keys.any?
              metadata_str = metadata_keys.map { |k| "#{k}=#{data[k]}" }.join(', ')
              formatted += " #{pastel.dim("(#{metadata_str})")}"
            end

            formatted
          rescue JSON::ParserError
            content
          end

          # Format text log format: 2024-11-07 14:32:15 INFO [Component] message
          def format_text_log(content)
            if content =~ /\A(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(\w+)\s+(?:\[([^\]]+)\]\s+)?(.*)/
              timestamp_str = Regexp.last_match(1)
              level = Regexp.last_match(2)
              _component = Regexp.last_match(3)
              message = Regexp.last_match(4)

              timestamp = format_timestamp_from_text(timestamp_str)
              "#{timestamp} #{format_message_with_icon(message, level)}"
            else
              content
            end
          end

          # Format pretty log format: emoji message (metadata)
          def format_pretty_log(content)
            # Extract emoji and message
            if content =~ /\A([^\s]+)\s+(.*)/
              emoji_or_text = Regexp.last_match(1)
              rest = Regexp.last_match(2)

              # Check if first part is an emoji (common log emojis)
              if emoji_or_text =~ /[▶👤◆🤖→✓✅✗❌⚠️🔍ℹ🔄]/
                level = emoji_to_level(emoji_or_text)
                # Message already has emoji, just format rest without adding another icon
                message_text, metadata = extract_metadata(rest)
                color = determine_color_from_level(level)
                formatted = pastel.send(color, "#{emoji_or_text} #{message_text}")
                formatted += " #{format_metadata(metadata)}" if metadata
                formatted
              else
                format_message_with_icon(content, 'INFO')
              end
            else
              format_message_with_icon(content, 'INFO')
            end
          end

          # Format a message with appropriate icon and color based on content and level
          def format_message_with_icon(message, level)
            # Extract metadata from message (key=value pairs in parens)
            message_text, metadata = extract_metadata(message)

            # Determine icon and color based on message content
            icon, color = determine_icon_and_color(message_text, level)

            # Format the main message
            formatted = pastel.send(color, "#{icon} #{message_text}")

            # Add metadata if present
            formatted += " #{format_metadata(metadata)}" if metadata

            formatted
          end

          # Extract metadata from message
          # Returns [message_without_metadata, metadata_hash]
          def extract_metadata(message)
            if message =~ /\A(.*?)\s*\(([^)]+)\)\s*\z/
              message_text = Regexp.last_match(1)
              metadata_str = Regexp.last_match(2)

              # Parse key=value pairs
              metadata = {}
              metadata_str.scan(/(\w+)=([^,]+)(?:,\s*)?/) do |key, value|
                metadata[key] = value.strip
              end

              [message_text, metadata]
            else
              [message, nil]
            end
          end

          # Determine icon and color based on message content
          def determine_icon_and_color(message, level)
            case message
            when /Starting execution|Starting iteration|Starting autonomous/i
              ['▶', :cyan]
            when /Loading persona|Persona:/i
              ['👤', :cyan]
            when /Connecting to tool|Calling tool|MCP server/i
              ['◆', :blue]
            when /LLM request|Prompt|🤖/i
              ['🤖', :magenta]
            when /Tool completed|result|response|found/i
              ['→', :yellow]
            when /Iteration completed|completed|finished/i
              ['✓', :green]
            when /Execution complete|✅|workflow.*completed/i
              ['✅', :green]
            when /error|fail|✗|❌/i
              ['✗', :red]
            when /warn|⚠️/i
              ['⚠️', :yellow]
            else
              # Default based on level
              case level&.upcase
              when 'ERROR'
                ['✗', :red]
              when 'WARN'
                ['⚠️', :yellow]
              when 'DEBUG'
                ['🔍', :dim]
              else
                ['', :white]
              end
            end
          end

          # Format metadata hash
          def format_metadata(metadata)
            return '' unless metadata&.any?

            parts = metadata.map do |key, value|
              # Highlight durations
              if key == 'duration_s' || key.include?('duration')
                duration_val = value.to_f
                formatted_duration = duration_val < 1 ? "#{(duration_val * 1000).round}ms" : "#{duration_val.round(1)}s"
                "duration=#{pastel.yellow(formatted_duration)}"
              # Highlight counts and numbers
              elsif value =~ /^\d+$/
                "#{key}=#{pastel.yellow(value)}"
              # Highlight tool names
              elsif %w[tool name].include?(key)
                "#{key}=#{pastel.bold(value)}"
              else
                "#{key}=#{value}"
              end
            end

            pastel.dim("(#{parts.join(', ')})")
          end

          # Format timestamp from ISO8601 format
          def format_timestamp_from_iso(timestamp_str)
            return '' unless timestamp_str

            time = Time.parse(timestamp_str)
            format_time(time)
          rescue StandardError
            ''
          end

          # Format timestamp from text format (YYYY-MM-DD HH:MM:SS)
          def format_timestamp_from_text(timestamp_str)
            return '' unless timestamp_str

            time = Time.parse(timestamp_str)
            format_time(time)
          rescue StandardError
            ''
          end

          # Format Time object as HH:MM:SS
          def format_time(time)
            pastel.dim(time.strftime('%H:%M:%S'))
          end

          # Convert emoji to log level
          def emoji_to_level(emoji)
            case emoji
            when 'ℹ️', 'ℹ'
              'INFO'
            when '🔍'
              'DEBUG'
            when '⚠️', '⚠'
              'WARN'
            when '❌', '✗'
              'ERROR'
            when '▶', '👤', '◆'
              'INFO'
            when '🤖'
              'INFO'
            when '→', '✓', '✅'
              'INFO'
            else
              'INFO'
            end
          end

          # Determine color from log level
          def determine_color_from_level(level)
            case level&.upcase
            when 'ERROR'
              :red
            when 'WARN'
              :yellow
            when 'DEBUG'
              :dim
            else
              :white
            end
          end
        end
      end
    end
  end
end
