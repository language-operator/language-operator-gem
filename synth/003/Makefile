.PHONY: create code logs clean

AGENT := s003
AICTL := bundle exec ../../bin/aictl agent
TOOLS := workspace

create:
	cat agent.txt | $(AICTL) create --name $(AGENT) --tools "$(TOOLS)"

run:
	@JOB_NAME=$(AGENT)-$(shell date +%s); \
	kubectl create job --from=cronjob/$(AGENT) $$JOB_NAME && \
	trap "kubectl delete job $$JOB_NAME" EXIT; \
	kubectl wait --for=condition=ready pod -l job-name=$$JOB_NAME --timeout=60s && \
	kubectl logs -f job/$$JOB_NAME

code:
	$(AICTL) code $(AGENT)

inspect:
	$(AICTL) inspect $(AGENT)

logs:
	$(AICTL) logs $(AGENT)

clean:
	$(AICTL) delete $(AGENT) --force

save:
	$(AICTL) code $(AGENT) --raw > agent.rb
	$(AICTL) logs $(AGENT) > output.log
