# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  t.exclude_pattern = 'spec/e2e/**/*_spec.rb'
end

RSpec::Core::RakeTask.new(:e2e) do |t|
  t.pattern = 'spec/e2e/**/*_spec.rb'
  t.rspec_opts = '--tag e2e'
end

RuboCop::RakeTask.new

desc 'Run all tests (unit + e2e)'
task test: %i[spec e2e]

task default: %i[spec rubocop]

desc 'Generate YARD documentation'
task :docs do
  sh 'yard doc'
end

desc 'Open console with gem loaded'
task :console do
  require 'irb'
  require 'language_operator'
  ARGV.clear
  IRB.start
end

namespace :schema do
  desc 'Generate schema artifacts (JSON Schema and OpenAPI)'
  task :generate do
    require 'json'
    require 'yaml'
    require_relative 'lib/language_operator/dsl/schema'

    schema_dir = File.join(__dir__, 'lib', 'language_operator', 'templates', 'schema')
    FileUtils.mkdir_p(schema_dir)

    # Generate JSON Schema
    json_schema_path = File.join(schema_dir, 'agent_dsl_schema.json')
    puts "Generating JSON Schema: #{json_schema_path}"
    schema = LanguageOperator::Dsl::Schema.to_json_schema
    File.write(json_schema_path, JSON.pretty_generate(schema))
    puts "✅ Generated #{json_schema_path}"

    # Generate OpenAPI spec
    openapi_path = File.join(schema_dir, 'agent_dsl_openapi.yaml')
    puts "Generating OpenAPI spec: #{openapi_path}"
    openapi = LanguageOperator::Dsl::Schema.to_openapi
    File.write(openapi_path, YAML.dump(openapi))
    puts "✅ Generated #{openapi_path}"

    puts "\nSchema artifacts generated successfully!"
    puts "Version: #{LanguageOperator::Dsl::Schema.version}"
  end
end
