.PHONY: help build test test-integration test-performance install console docs clean version-bump lint schema

.DEFAULT_GOAL := help

QA_PROMPT := "/task test"
ITERATE_PROMPT := "/task iterate"
PRIORITIZE_PROMPT := "/task prioritize"
DISTILL_PROMPT := "/task distill"

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort


# Claude development tasks
# ------------------------

distill: ## Distill SCRATCH.md
	@claude --dangerously-skip-permissions $(DISTILL_PROMPT)

prioritize: ## Prioritize the backlog and queue work
	@claude --dangerously-skip-permissions $(PRIORITIZE_PROMPT)

iterate: ## Do the next right thing
	@claude $(ITERATE_PROMPT)

qa: ## Find bugs and file GitHub issues
	@claude $(QA_PROMPT)


## Standard development tasks
# ---------------------------

console: ## Open an IRB console with the gem loaded
	@bundle exec rake console

build: schema ## Build the gem
	@gem build language-operator.gemspec

install: clean build ## Build and install the gem locally
	@gem install language-operator-*.gem

lint: ## Run RuboCop linter
	@bundle exec rubocop || [ $$? -eq 1 ]

lint-fix: ## Run Rubocop and auto-fix issues
	@bundle exec rubocop --autocorrect-all

schema: ## Generate schema artifacts (JSON Schema and OpenAPI)
	@bundle exec rake schema:generate

test: ## Run the unit test suite (use VERBOSE=1 to show all output)
	@bundle exec parallel_rspec spec/language_operator/

test-integration: ## Run integration tests for DSL v1 task execution
	@INTEGRATION_MOCK_LLM=true INTEGRATION_BENCHMARK=false bundle exec rspec spec/integration/ --tag type:integration

test-performance: ## Run performance benchmarks
	@INTEGRATION_MOCK_LLM=true INTEGRATION_BENCHMARK=true bundle exec rspec spec/integration/performance_benchmarks_spec.rb --tag type:integration

test-all: test test-integration ## Run all tests (unit + integration)

yard-docs: ## Generate YARD documentation
	@bundle exec yard doc

clean: ## Clean build artifacts
	@rm -f language-operator-*.gem
	@rm -rf doc/
	@rm -rf .yardoc/
