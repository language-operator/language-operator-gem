.PHONY: synthesize synthesize-all synthesize-sonnet synthesize-gpt-4 run run-docker validate clean compare help

# Default model - inherit from SYNTHESIS_MODEL env var, no hardcoded fallback
MODEL ?= $(SYNTHESIS_MODEL)

# Model-specific names
SONNET_MODEL = claude-3-7-sonnet-20250219
GPT4_MODEL = gpt-4-turbo

help:
	@echo "Synthesis Test Targets:"
	@echo "  make synthesize         - Generate agent.rb using default model"
	@echo "  make synthesize-all     - Generate for all configured models"
	@echo "  make synthesize-sonnet  - Generate agent.sonnet.rb"
	@echo "  make synthesize-gpt-4   - Generate agent.gpt-4.rb"
	@echo "  make run                - Execute agent.rb locally with bundle exec"
	@echo "  make run-docker         - Execute agent.rb in Docker container"
	@echo "  make validate           - Validate agent.rb syntax"
	@echo "  make clean              - Remove all generated .rb files"
	@echo "  make compare            - Compare outputs from different models"

synthesize:
	@echo "Synthesizing agent.rb with model: $(MODEL)..."
	@bundle exec ruby -I ../../lib -e "\
	  require 'language_operator/synthesis_test_harness'; \
	  harness = LanguageOperator::SynthesisTestHarness.new(model: '$(MODEL)'); \
	  code = harness.synthesize('agent.yaml'); \
	  File.write('agent.rb', code); \
	  puts 'Generated: agent.rb'"

synthesize-sonnet:
	@echo "Synthesizing with Claude Sonnet..."
	@bundle exec ruby -I ../../lib -e "\
	  require 'language_operator/synthesis_test_harness'; \
	  harness = LanguageOperator::SynthesisTestHarness.new(model: '$(SONNET_MODEL)'); \
	  code = harness.synthesize('agent.yaml'); \
	  File.write('agent.sonnet.rb', code); \
	  puts 'Generated: agent.sonnet.rb'"

synthesize-gpt-4:
	@echo "Synthesizing with GPT-4..."
	@bundle exec ruby -I ../../lib -e "\
	  require 'language_operator/synthesis_test_harness'; \
	  harness = LanguageOperator::SynthesisTestHarness.new(model: '$(GPT4_MODEL)'); \
	  code = harness.synthesize('agent.yaml'); \
	  File.write('agent.gpt-4.rb', code); \
	  puts 'Generated: agent.gpt-4.rb'"

synthesize-all: synthesize-sonnet synthesize-gpt-4
	@echo "All synthesis complete!"

run:
	@if [ ! -f agent.rb ]; then \
	  echo "Error: agent.rb not found. Run 'make synthesize' first."; \
	  exit 1; \
	fi
	@echo "Executing agent.rb in Docker container..."
	@docker run --rm -i \
	  --network host \
	  -e AGENT_NAME=hello-world \
	  -e AGENT_MODE=autonomous \
	  -e AGENT_CODE_PATH=/agent/agent.rb \
	  -e LLM_MODEL=$(SYNTHESIS_MODEL) \
	  -e MODEL_ENDPOINTS=$(SYNTHESIS_ENDPOINT) \
	  -e OPENAI_API_KEY=$(SYNTHESIS_API_KEY) \
	  -e ANTHROPIC_API_KEY=$(ANTHROPIC_API_KEY) \
	  -v $(PWD)/agent.rb:/agent/agent.rb:ro \
	  ghcr.io/language-operator/agent:dev

validate:
	@if [ ! -f agent.rb ]; then \
	  echo "Error: agent.rb not found. Run 'make synthesize' first."; \
	  exit 1; \
	fi
	@echo "Validating agent.rb..."
	@ruby -c agent.rb && echo "Syntax: OK"

clean:
	@echo "Cleaning generated files..."
	@rm -f agent.rb agent.*.rb
	@echo "Clean complete!"

compare:
	@echo "Comparing model outputs..."
	@if [ -f agent.sonnet.rb ] && [ -f agent.gpt-4.rb ]; then \
	  echo "=== Claude Sonnet vs GPT-4 ==="; \
	  diff -u agent.sonnet.rb agent.gpt-4.rb || true; \
	else \
	  echo "Error: Run 'make synthesize-all' first to generate comparison files"; \
	fi
