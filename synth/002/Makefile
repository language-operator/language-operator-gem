.PHONY: synthesize exec help

help:
	@echo "Synthesis Test Targets:"
	@echo "  make synthesize         - Generate agent.rb using default model"
	@echo "  make exec                - Execute agent.rb locally with bundle exec"

synthesize:
	cat agent.txt | bundle exec ../../bin/aictl system synthesize --raw | tee agent.rb

exec:
	cat agent.rb | bundle exec ../../bin/aictl system exec | tee output.log
