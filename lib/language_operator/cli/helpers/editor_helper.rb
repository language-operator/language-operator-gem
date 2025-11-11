# frozen_string_literal: true

require 'tempfile'

module LanguageOperator
  module CLI
    module Helpers
      # Helper module for editing content in the user's preferred editor.
      # Handles tempfile creation, cleanup, and editor invocation.
      module EditorHelper
        # Edit content in the user's preferred editor
        #
        # @param content [String] Content to edit
        # @param filename_prefix [String] Prefix for the temp file name
        # @param extension [String] File extension (default: '.txt')
        # @param default_editor [String] Editor to use if $EDITOR not set (default: 'vi')
        # @return [String] The edited content
        # @raise [RuntimeError] If editor command fails
        #
        # @example Edit agent instructions
        #   new_content = EditorHelper.edit_content(
        #     current_instructions,
        #     'agent-instructions-',
        #     '.txt'
        #   )
        #
        # @example Edit YAML configuration
        #   new_yaml = EditorHelper.edit_content(
        #     model.to_yaml,
        #     'model-',
        #     '.yaml',
        #     default_editor: 'vim'
        #   )
        def self.edit_content(content, filename_prefix, extension = '.txt', default_editor: 'vi')
          editor = ENV['EDITOR'] || default_editor
          tempfile = Tempfile.new([filename_prefix, extension])

          begin
            # Write content and flush to ensure it's on disk
            tempfile.write(content)
            tempfile.flush
            tempfile.close

            # Open in editor
            success = system("#{editor} #{tempfile.path}")
            raise "Editor command failed: #{editor}" unless success

            # Read edited content
            File.read(tempfile.path)
          ensure
            # Clean up temp file
            tempfile.unlink
          end
        end
      end
    end
  end
end
