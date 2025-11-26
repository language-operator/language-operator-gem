.PHONY: create code logs clean

AGENT := s001
AICTL := bundle exec ../../bin/aictl agent
TOOLS := workspace

create:
	cat agent.txt | $(AICTL) create --name $(AGENT)

code:
	$(AICTL) code $(AGENT)

logs:
	$(AICTL) logs $(AGENT)

clean:
	$(AICTL) delete $(AGENT)

save:
	$(AICTL) code $(AGENT) --raw > agent.rb
	$(AICTL) logs $(AGENT) > output.log
