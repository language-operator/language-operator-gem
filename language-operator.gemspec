# frozen_string_literal: true

require_relative 'lib/language_operator/version'

Gem::Specification.new do |spec|
  spec.name          = 'language-operator'
  spec.version       = LanguageOperator::VERSION
  spec.authors       = ['James Ryan']
  spec.email         = ['james@theryans.io']

  spec.summary       = 'Ruby SDK for Language Operator'
  spec.description   = 'Used in conjunction with the Language Operator for Kubernetes'
  spec.homepage      = 'https://github.com/language-operator/language-operator'
  spec.license       = 'FSL-1.1-Apache-2.0'
  spec.required_ruby_version = '>= 3.4.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/language-operator/language-operator-gem'
  spec.metadata['changelog_uri'] = 'https://github.com/language-operator/language-operator-gem/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) ||
        f.match(%r{\A(?:(?:bin|test|spec|features|requirements)/|\.(?:git|travis|circleci)|appveyor)}) ||
        f.end_with?('.gem')
    end
  end
  spec.bindir        = 'bin'
  spec.executables   = ['aictl']
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'mcp', '~> 0.4'
  spec.add_dependency 'ruby_llm', '~> 1.8'
  spec.add_dependency 'ruby_llm-mcp', '~> 0.1'
  spec.add_dependency 'thor', '~> 1.3'

  # HTTP server dependencies for MCP tools and agents
  spec.add_dependency 'puma', '~> 6.0'
  spec.add_dependency 'rack', '~> 3.0'
  spec.add_dependency 'rackup', '~> 2.0'

  # Agent dependencies
  spec.add_dependency 'parallel', '~> 1.26'

  # Cache dependencies
  spec.add_dependency 'lru_redux', '~> 1.1'

  # HTTP client for synthesis and external APIs
  spec.add_dependency 'faraday', '~> 2.0'

  # Kubernetes client
  spec.add_dependency 'k8s-ruby', '~> 0.17'

  # OpenTelemetry instrumentation
  spec.add_dependency 'opentelemetry-exporter-otlp', '~> 0.27'
  spec.add_dependency 'opentelemetry-instrumentation-http', '~> 0.23'
  spec.add_dependency 'opentelemetry-instrumentation-rack', '~> 0.24'
  spec.add_dependency 'opentelemetry-sdk', '~> 1.4'

  # Beautiful CLI output
  spec.add_dependency 'pastel', '~> 0.8'
  spec.add_dependency 'rouge', '~> 4.0'
  spec.add_dependency 'tty-box', '~> 0.7'
  spec.add_dependency 'tty-prompt', '~> 0.23'
  spec.add_dependency 'tty-spinner', '~> 0.9'
  spec.add_dependency 'tty-table', '~> 0.12'

  # Development dependencies
  spec.add_development_dependency 'benchmark', '~> 0.4'
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'memory_profiler', '~> 1.0'
  spec.add_development_dependency 'rack-test', '~> 2.1'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.60'
  spec.add_development_dependency 'rubocop-performance', '~> 1.20'
  spec.add_development_dependency 'webmock', '~> 3.23'
  spec.add_development_dependency 'yard', '~> 0.9.37'
end
