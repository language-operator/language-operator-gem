# frozen_string_literal: true

require_relative '../base_command'
require 'pastel'
require_relative '../formatters/progress_formatter'
require_relative '../../config/cluster_config'

module LanguageOperator
  module CLI
    module Commands
      # Switch cluster context command
      class Use < BaseCommand
        desc 'use CLUSTER', 'Switch to a different cluster context'
        def self.exit_on_failure?
          true
        end

        def switch(cluster_name)
          handle_command_error('switch cluster') do
            unless Config::ClusterConfig.cluster_exists?(cluster_name)
              Formatters::ProgressFormatter.error("Cluster '#{cluster_name}' not found")
              puts "\nAvailable clusters:"
              Config::ClusterConfig.list_clusters.each do |cluster|
                puts "  - #{cluster[:name]}"
              end
              exit 1
            end

            Config::ClusterConfig.set_current_cluster(cluster_name)
            cluster = Config::ClusterConfig.get_cluster(cluster_name)

            Formatters::ProgressFormatter.success("Switched to cluster '#{cluster_name}'")

            pastel = Pastel.new
            puts "\nCluster Details"
            puts '----------------'
            puts "Name: #{pastel.bold.white(cluster[:name])}"
            puts "Namespace: #{pastel.bold.white(cluster[:namespace])}"
          end
        end
      end
    end
  end
end
