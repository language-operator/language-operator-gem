.PHONY: create code logs clean

AGENT := synth-003
AICTL := bundle exec ../../bin/aictl agent
TOOLS := workspace

create:
	cat agent.txt | $(AICTL) create --name $(AGENT) --tools "$(TOOLS)"

code:
	$(AICTL) code $(AGENT)

logs:
	$(AICTL) logs $(AGENT)

clean:
	$(AICTL) delete $(AGENT) --force

save:
	$(AICTL) code $(AGENT) --raw > agent.rb
	$(AICTL) logs $(AGENT) > output.log