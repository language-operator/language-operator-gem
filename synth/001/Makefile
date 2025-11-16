.PHONY: synthesize exec

help:
	@echo "Synthesis Test Targets:"
	@echo "  make synthesize         - Generate agent.rb using default model"
	@echo "  make run                - Execute agent.rb locally with bundle exec"
	@echo "  make validate           - Validate agent.rb syntax"
	@echo "  make clean              - Remove all generated .rb files"

synthesize:
	cat agent.txt | bundle exec ../../bin/aictl system synthesize --raw | tee agent.rb

exec:
	cat agent.rb | bundle exec ../../bin/aictl system exec | tee output.log
