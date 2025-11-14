.PHONY: test test-all clean help list

help:
	@echo "Synthesis Test Suite"
	@echo ""
	@echo "Available targets:"
	@echo "  make test         - Run synthesis for all test cases"
	@echo "  make test-all     - Run synthesis for all models in all test cases"
	@echo "  make clean        - Clean all generated files"
	@echo "  make list         - List all test cases"
	@echo ""
	@echo "Individual test cases:"
	@echo "  make test-001     - Run test 001 (hello-world)"
	@echo ""
	@echo "Usage:"
	@echo "  cd 001 && make synthesize         - Synthesize single test with default model"
	@echo "  cd 001 && make synthesize-all     - Synthesize with all models"
	@echo "  cd 001 && make run                - Execute synthesized code"

test:
	@echo "Running synthesis tests..."
	@$(MAKE) -C 001 synthesize

test-001:
	@echo "Running test 001..."
	@$(MAKE) -C 001 synthesize

test-all:
	@echo "Running synthesis with all models..."
	@$(MAKE) -C 001 synthesize-all

clean:
	@echo "Cleaning all test artifacts..."
	@$(MAKE) -C 001 clean
	@echo "Clean complete!"

list:
	@echo "Available test cases:"
	@echo "  001 - hello-world (Say something in your logs)"
