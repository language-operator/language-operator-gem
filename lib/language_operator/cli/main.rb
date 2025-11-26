# frozen_string_literal: true

require 'thor'
require 'fileutils'
require_relative '../utils/secure_path'
require_relative 'commands/cluster'
require_relative 'commands/use'
require_relative 'commands/agent/base'
require_relative 'commands/status'
require_relative 'commands/persona'
require_relative 'commands/tool/base'
require_relative 'commands/model/base'
require_relative 'commands/quickstart'
require_relative 'commands/install'
require_relative 'commands/system/base'
require_relative 'formatters/progress_formatter'
require_relative 'helpers/ux_helper'
require_relative '../config/cluster_config'
require_relative '../kubernetes/client'
require_relative 'errors/thor_errors'

module LanguageOperator
  module CLI
    # Main CLI class for aictl command
    #
    # Provides commands for creating, running, and managing language-operator resources.
    class Main < Thor
      include Helpers::UxHelper

      def self.exit_on_failure?
        true
      end

      desc 'status', 'Show system status and overview'
      def status
        Commands::Status.new.invoke(:overview)
      end

      desc 'version', 'Show aictl and operator version'
      def version
        # Check operator installation status first
        current_cluster = Config::ClusterConfig.current_cluster
        operator_version = nil
        operator_installed = false

        if current_cluster
          cluster_config = Config::ClusterConfig.get_cluster(current_cluster)
          begin
            k8s = Kubernetes::Client.new(
              kubeconfig: cluster_config[:kubeconfig],
              context: cluster_config[:context]
            )

            if k8s.operator_installed?
              operator_installed = true
              operator_version = k8s.operator_version || 'unknown'
            end
          rescue StandardError
            # Silently handle connection errors - we'll show appropriate message below
          end
        end

        # Show sparkly logo with appropriate subtitle
        if operator_installed
          logo(sparkle: true, title: "kubernetes language-operator detected (v#{operator_version})")
        else
          logo(sparkle: true, title: 'kubernetes language-operator not found')
        end
      end

      desc 'cluster SUBCOMMAND ...ARGS', 'Manage clusters'
      subcommand 'cluster', Commands::Cluster

      desc 'use CLUSTER', 'Switch to a different cluster'
      def use(cluster_name)
        Commands::Use.new.switch(cluster_name)
      end

      desc 'agent SUBCOMMAND ...ARGS', 'Manage agents'
      subcommand 'agent', Commands::Agent::Base

      desc 'persona SUBCOMMAND ...ARGS', 'Manage personas'
      subcommand 'persona', Commands::Persona

      desc 'tool SUBCOMMAND ...ARGS', 'Manage tools'
      subcommand 'tool', Commands::Tool::Base

      desc 'model SUBCOMMAND ...ARGS', 'Manage models'
      subcommand 'model', Commands::Model::Base

      desc 'system SUBCOMMAND ...ARGS', 'System utilities'
      subcommand 'system', Commands::System::Base

      desc 'quickstart', 'Wizard for first-time users'
      def quickstart
        Commands::Quickstart.new.invoke(:start)
      end

      desc 'install', 'Install the language-operator using Helm'
      long_desc Commands::Install.long_desc_for(:install)
      option :values, type: :string, desc: 'Path to custom Helm values file'
      option :namespace, type: :string, default: Commands::Install::DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
      option :version, type: :string, desc: 'Specific chart version to install'
      option :dry_run, type: :boolean, default: false, desc: 'Preview installation without applying'
      option :wait, type: :boolean, default: true, desc: 'Wait for deployment to complete'
      option :create_namespace, type: :boolean, default: true, desc: 'Create namespace if it does not exist'
      def install
        Commands::Install.new([], options).install
      end

      desc 'upgrade', 'Upgrade the language-operator using Helm'
      long_desc Commands::Install.long_desc_for(:upgrade)
      option :values, type: :string, desc: 'Path to custom Helm values file'
      option :namespace, type: :string, default: Commands::Install::DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
      option :version, type: :string, desc: 'Specific chart version to upgrade to'
      option :dry_run, type: :boolean, default: false, desc: 'Preview upgrade without applying'
      option :wait, type: :boolean, default: true, desc: 'Wait for deployment to complete'
      def upgrade
        Commands::Install.new([], options).upgrade
      end

      desc 'uninstall', 'Uninstall the language-operator using Helm'
      long_desc Commands::Install.long_desc_for(:uninstall)
      option :namespace, type: :string, default: Commands::Install::DEFAULT_NAMESPACE, desc: 'Kubernetes namespace'
      option :force, type: :boolean, default: false, desc: 'Skip confirmation prompt'
      def uninstall
        Commands::Install.new([], options).uninstall
      end

      desc 'completion SHELL', 'Install shell completion for aictl (bash, zsh, fish)'
      long_desc <<-DESC
        Install shell completion for aictl. Supports bash, zsh, and fish.

        Examples:
          aictl completion bash
          aictl completion zsh
          aictl completion fish

        Manual installation:
          bash: Add to ~/.bashrc:
            source <(aictl completion bash --stdout)

          zsh: Add to ~/.zshrc:
            source <(aictl completion zsh --stdout)

          fish: Run once:
            aictl completion fish | source
      DESC
      option :stdout, type: :boolean, desc: 'Print completion script to stdout instead of installing'
      def completion(shell)
        case shell.downcase
        when 'bash'
          install_bash_completion
        when 'zsh'
          install_zsh_completion
        when 'fish'
          install_fish_completion
        else
          message = "Unsupported shell: #{shell}"
          Formatters::ProgressFormatter.error(message)
          puts
          puts 'Supported shells: bash, zsh, fish'
          raise Errors::ValidationError, message
        end
      end

      def help(command = nil, subcommand = false)
        if command.nil? && !subcommand
          # Show logo when displaying general help (no specific command)
          logo
        end

        # Delegate to Thor's original help method
        super
      end

      private

      def install_bash_completion
        completion_file = File.expand_path('../../completions/aictl.bash', __dir__)

        if options[:stdout]
          puts File.read(completion_file)
          return
        end

        target = LanguageOperator::Utils::SecurePath.expand_home_path('.bash_completion.d/aictl')
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(completion_file, target)

        Formatters::ProgressFormatter.success('Bash completion installed')
        puts
        puts 'Add to your ~/.bashrc:'
        puts '  [ -f ~/.bash_completion.d/aictl ] && source ~/.bash_completion.d/aictl'
        puts
        puts 'Then reload your shell:'
        puts '  source ~/.bashrc'
      end

      def install_zsh_completion
        completion_file = File.expand_path('../../completions/_aictl', __dir__)

        if options[:stdout]
          puts File.read(completion_file)
          return
        end

        # Check if user has a custom fpath directory
        fpath_dir = LanguageOperator::Utils::SecurePath.expand_home_path('.zsh/completions')
        FileUtils.mkdir_p(fpath_dir)

        target = File.join(fpath_dir, '_aictl')
        FileUtils.cp(completion_file, target)

        Formatters::ProgressFormatter.success('Zsh completion installed')
        puts
        puts 'Add to your ~/.zshrc (before compinit):'
        puts '  fpath=(~/.zsh/completions $fpath)'
        puts '  autoload -Uz compinit && compinit'
        puts
        puts 'Then reload your shell:'
        puts '  source ~/.zshrc'
      end

      def install_fish_completion
        completion_file = File.expand_path('../../completions/aictl.fish', __dir__)

        if options[:stdout]
          puts File.read(completion_file)
          return
        end

        target = LanguageOperator::Utils::SecurePath.expand_home_path('.config/fish/completions/aictl.fish')
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(completion_file, target)

        Formatters::ProgressFormatter.success('Fish completion installed')
        puts
        puts 'Reload completions:'
        puts '  fish_update_completions'
        puts
        puts 'Or restart your fish shell'
      end
    end
  end
end
