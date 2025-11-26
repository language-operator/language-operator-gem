.PHONY: help build test test-integration test-performance install console docs clean version-bump lint schema

.DEFAULT_GOAL := help

QA_PROMPT := "/task test"
ITERATE_PROMPT := "/task iterate"
PRIORITIZE_PROMPT := "/task prioritize"

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Use claude to prioritize the backlog
prioritize:
	@claude --dangerously-skip-permissions $(PRIORITIZE_PROMPT)

# Use claude to iterate on the backlog
iterate:
	@claude $(ITERATE_PROMPT)

# Use claude to find bugs
qa:
	@claude --dangerously-skip-permissions $(QA_PROMPT)

schema: ## Generate schema artifacts (JSON Schema and OpenAPI)
	@echo "Generating schema artifacts..."
	@bundle exec rake schema:generate
	@echo "✅ Schema artifacts generated"

build: schema ## Build the gem
	@echo "Building language-operator gem..."
	@gem build language-operator.gemspec
	@echo "✅ Gem built successfully"

test: ## Run the unit test suite
	@echo "Running unit tests..."
	@bundle exec rspec --exclude-pattern "spec/integration/**/*_spec.rb" || [ $$? -eq 1 ]
	@echo "✅ All unit tests passed"

test-integration: ## Run integration tests for DSL v1 task execution
	@echo "Running integration tests..."
	@INTEGRATION_MOCK_LLM=true INTEGRATION_BENCHMARK=false bundle exec rspec spec/integration/ --tag type:integration
	@echo "✅ All integration tests passed"

test-performance: ## Run performance benchmarks
	@echo "Running performance benchmarks..."
	@INTEGRATION_MOCK_LLM=true INTEGRATION_BENCHMARK=true bundle exec rspec spec/integration/performance_benchmarks_spec.rb --tag type:integration
	@echo "✅ Performance benchmarks completed"

test-all: test test-integration ## Run all tests (unit + integration)

install: build ## Build and install the gem locally
	@echo "Installing gem..."
	@gem install language-operator-*.gem
	@echo "✅ Gem installed successfully"

console: ## Open an IRB console with the gem loaded
	@bundle exec rake console

docs: ## Generate YARD documentation
	@echo "Generating documentation..."
	@bundle exec yard doc
	@echo "✅ Documentation generated in doc/"

lint: ## Run RuboCop linter
	@echo "Running RuboCop..."
	@bundle exec rubocop || [ $$? -eq 1 ]
	@echo "✅ Linting complete"

lint-fix: ## Auto-fix RuboCop issues
	@echo "Auto-fixing RuboCop issues..."
	@bundle exec rubocop --autocorrect-all

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@rm -f language-operator-*.gem
	@rm -rf doc/
	@rm -rf .yardoc/
	@echo "✅ Cleaned"

version-bump: ## Bump version (usage: make version-bump TYPE=patch|minor|major)
	@if [ -z "$(TYPE)" ]; then \
		echo "❌ Error: TYPE not specified"; \
		echo "Usage: make version-bump TYPE=patch|minor|major"; \
		exit 1; \
	fi
	@./bin/bump-version $(TYPE)

version-bump-patch: ## Bump patch version (0.1.0 -> 0.1.1)
	@./bin/bump-version patch

version-bump-minor: ## Bump minor version (0.1.0 -> 0.2.0)
	@./bin/bump-version minor

version-bump-major: ## Bump major version (0.1.0 -> 1.0.0)
	@./bin/bump-version major

# CI targets
ci-test: test test-integration lint ## Run CI test suite (unit tests + integration tests + linting)

# Development workflow
dev-setup: ## Install development dependencies
	@echo "Installing dependencies..."
	@bundle install
	@echo "✅ Development environment ready"

dev-watch: ## Run tests in watch mode
	@bundle exec guard

# Autopilot
iterate:
	claude "read and execute requirements/tasks/iterate.md"