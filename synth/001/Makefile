.PHONY: create code logs clean

AGENT := synth-001
AICTL := bundle exec ../../bin/aictl agent

create:
	cat agent.txt | $(AICTL) create --name $(AGENT)

code:
	$(AICTL) code $(AGENT)

logs:
	$(AICTL) logs $(AGENT)

clean:
	$(AICTL) delete $(AGENT) --force