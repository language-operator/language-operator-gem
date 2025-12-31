.PHONY: create code logs clean events validate run

AGENT := s004
AICTL := bundle exec ../../bin/langop agent
TOOLS := workspace

create:
	cat instructions.txt | $(AICTL) create --name $(AGENT) --tools "$(TOOLS)"

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

# Health monitoring specific commands
events:
	@echo "=== Checking for Task Completion events ===" && \
	kubectl get events -n language-operator --field-selector involvedObject.name=$(AGENT) --sort-by='.lastTimestamp' || \
	echo "No events found - this may indicate observability issues"

validate:
	@echo "=== Validating observability infrastructure ===" && \
	echo "1. Checking if agent exists..." && \
	$(AICTL) inspect $(AGENT) && \
	echo "2. Checking recent logs..." && \
	$(AICTL) logs $(AGENT) --tail=20 && \
	echo "3. Checking for events..." && \
	make events && \
	echo "4. Checking CronJob status..." && \
	kubectl get cronjob $(AGENT) -n language-operator

health:
	@echo "=== System Health Check Status ===" && \
	echo "Last execution logs:" && \
	$(AICTL) logs $(AGENT) --tail=50 | grep -E "(healthy|error|fail|success|reachable)" || \
	echo "No health status found in recent logs"

clean:
	$(AICTL) delete $(AGENT) --force

save:
	$(AICTL) code $(AGENT) --raw > agent.rb
	$(AICTL) logs $(AGENT) > output.log