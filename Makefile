.SHELLFLAGS := -eu -o pipefail -c
SHELL := /usr/bin/env bash

ENV ?= production
export ENV

# The two questions the walkthrough is built around.
Q_BOOK   := Show me the largest trade on each desk on the last business day, with the counterparty and the client trader.
Q_CREDIT := What is our credit limit headroom with Northbridge Capital, and is their KYC current?

.DEFAULT_GOAL := help

help:
	@awk 'BEGIN{FS=":.*##"; printf "Usage: make <target> [AS=broker]\n\n"} \
	     /^# ---/ {sub(/^# --- /,""); sub(/ -+$$/,""); printf "\n%s:\n", $$0} \
	     /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --- provision ---------------------------------------------------------------

up: secret db mcp policy agent budget ## Build everything (safe to re-run)
	@echo "✓ up — next: make verify, then make smoke"

preflight: ## Check identities, Postgres and the org before demo day
	@bash scripts/00-preflight.sh

secret: ## Store the four database DSNs as cluster secrets
	@bash scripts/01-secret.sh

db: ## Create the database, logins and synthetic book
	@bash scripts/02-db.sh

mcp: secret ## Reconcile the four SQL MCP servers and the data policy
	@bash scripts/03-mcp.sh

policy: ## Reconcile the access policies
	@bash scripts/04-policy.sh

agent: mcp ## Reconcile the desk assistant and its two specialists
	@bash scripts/05-agent.sh

budget: agent ## Set a daily spend limit on the agent
	@bash scripts/06-budget.sh

diff: ## Show what applying the repo would change, without applying it
	@. scripts/_lib.sh; require_token; R=$$(mktemp -d); trap 'rm -rf $$R' EXIT; \
	mkdir $$R/mcp $$R/pol; \
	for m in config/manifests/*.yaml; do sed "s|__BROKER_EMAIL__|$$BROKER_EMAIL|g" $$m > $$R/mcp/$$(basename $$m); done; \
	for p in config/policies/*.yaml;  do sed "s|__BROKER_EMAIL__|$$BROKER_EMAIL|g" $$p > $$R/pol/$$(basename $$p); done; \
	bash scripts/render-agent.sh > $$R/agent.yaml; \
	echo "--- MCP servers ---"; rpai mcp diff -f $$R/mcp || true; \
	echo "--- policies ---";    rpai policy diff -f $$R/pol || true; \
	echo "--- agent ---";       rpai agent diff -f $$R/agent.yaml || true

down: ## Remove everything from the org (leaves Postgres)
	@bash scripts/99-teardown.sh

# --- verify ------------------------------------------------------------------

verify: ## Prove each database login reaches only its own data
	@. scripts/_lib.sh; \
	echo "each login should reach ONLY its own schema:"; fails=0; \
	probe() { \
	  printf "  %-40s" "$$1"; \
	  if out=$$(PGPASSWORD="$$3" psql "host=$$PG_HOST port=$${PG_PORT:-5432} dbname=$$PG_DATABASE user=$$2 sslmode=$${PG_SSLMODE:-require}" -tAq -c "$$4" 2>&1); then \
	    echo "OK ($$out rows)"; \
	  elif echo "$$out" | grep -qi "permission denied"; then echo "DENIED"; \
	  elif echo "$$out" | grep -qi "read-only transaction"; then echo "DENIED (read-only login)"; \
	  else echo "ERROR — $$(echo "$$out" | head -1 | cut -c1-60)"; fails=$$((fails+1)); fi; \
	}; \
	probe "blotter_sql -> trades.blotter"        blotter_sql "$$PG_BLOTTER_PW" "SELECT count(*) FROM trades.blotter"; \
	probe "blotter_sql -> refdata.counterparties" blotter_sql "$$PG_BLOTTER_PW" "SELECT count(*) FROM refdata.counterparties"; \
	probe "pricing_sql -> market.latest_prices"  pricing_sql "$$PG_PRICING_PW" "SELECT count(*) FROM market.latest_prices"; \
	probe "pricing_sql -> trades.blotter"        pricing_sql "$$PG_PRICING_PW" "SELECT count(*) FROM trades.blotter"; \
	probe "refdata_sql -> refdata.counterparties" refdata_sql "$$PG_REFDATA_PW" "SELECT count(*) FROM refdata.counterparties"; \
	probe "refdata_sql -> trades.blotter"        refdata_sql "$$PG_REFDATA_PW" "SELECT count(*) FROM trades.blotter"; \
	probe "rollup_sql  -> desk.daily_volumes"    rollup_sql  "$$PG_ROLLUP_PW"  "SELECT count(*) FROM desk.daily_volumes"; \
	probe "rollup_sql  -> trades.blotter"        rollup_sql  "$$PG_ROLLUP_PW"  "SELECT count(*) FROM trades.blotter"; \
	probe "blotter_sql -> write attempt"         blotter_sql "$$PG_BLOTTER_PW" "UPDATE trades.blotter SET status = 'CANCELLED' WHERE false"; \
	echo "  (expected: OK, DENIED, OK, DENIED, OK, DENIED, OK, DENIED, DENIED)"; \
	if [ "$$fails" -gt 0 ]; then \
	  echo "  ✗ $$fails probe(s) failed for a reason other than permissions — a connection"; \
	  echo "    error is not proof of isolation. Fix the connection first."; exit 1; fi

book: ## The answer to the showcase question, straight from SQL
	@. scripts/_lib.sh; pgd -c "\
	SELECT DISTINCT ON (desk) desk, trade_id, instrument, notional, ccy, counterparty_name, counterparty_lei, client_trader_email \
	FROM trades.blotter \
	WHERE trade_date = (SELECT max(trade_date) FROM trades.blotter WHERE trade_date < current_date) \
	  AND status <> 'CANCELLED' ORDER BY desk, notional DESC;"

# --- run ---------------------------------------------------------------------

ask: ## Ask the agent. make ask Q="..." [AS=broker]
	@[ -n "$(Q)" ] || { echo 'usage: make ask Q="your question" [AS=broker]'; exit 1; }; \
	. scripts/_lib.sh; require_token; \
	echo "→ asking as: $$(token_identity)"; \
	rpai agent a2a send "$$AGENT_NAME" "$(Q)"

smoke: ## The showcase question as the desk head, then as the broker
	@echo "=== desk head ==="; $(MAKE) --no-print-directory ask Q="$(Q_BOOK)"
	@echo; echo "=== Rates broker ==="; $(MAKE) --no-print-directory ask AS=broker Q="$(Q_BOOK)"

credit: ## The counterparty credit question, as both identities
	@echo "=== desk head ==="; $(MAKE) --no-print-directory ask Q="$(Q_CREDIT)"
	@echo; echo "=== Rates broker (expect: refused by access policy) ==="; $(MAKE) --no-print-directory ask AS=broker Q="$(Q_CREDIT)"

status: ## What is running
	@. scripts/_lib.sh; rpai mcp list; rpai agent get "$$AGENT_NAME"; rpai policy get "policies/$$POLICY_NAME" 2>/dev/null || true

spend: ## Spend so far against the limit
	@. scripts/_lib.sh; require_token; \
	adp_rpc redpanda.api.adp.v1alpha1.BudgetService/GetBudget "$$(jq -nc --arg n "$$BUDGET_NAME" '{name:$$n}')" \
	  | jq -r '.budget | "limit: $$\(.limitMicrocents|tonumber/100000000)  spent: $$\(((.currentSpendMicrocents//"0")|tonumber)/100000000)"'

stop-agent: ## Pause the agent
	@. scripts/_lib.sh; rpai agent stop "$$AGENT_NAME"

start-agent: ## Resume the agent
	@. scripts/_lib.sh; rpai agent start "$$AGENT_NAME"

# --- fail closed -------------------------------------------------------------

break-schema: ## Rename a masked column, to show the policy refuse rather than leak
	@. scripts/_lib.sh; pgd -c "ALTER TABLE trades.blotter RENAME COLUMN client_trader_email TO client_contact;"; \
	echo "✗ client_trader_email renamed to client_contact."; \
	echo "  Ask the broker the showcase question now: make smoke"; \
	echo "  The redact rule has absence_safe: false, so for the broker the call is"; \
	echo "  refused rather than the address passing through under a new name."; \
	echo "  The desk head is unaffected. Restore with: make fix-schema"

fix-schema: ## Put the column back
	@. scripts/_lib.sh; pgd -c "ALTER TABLE trades.blotter RENAME COLUMN client_contact TO client_trader_email;"; echo "✓ restored"

db-drop: ## Drop the demo database
	@. scripts/_lib.sh; pg -c "DROP DATABASE IF EXISTS \"$$PG_DATABASE\" WITH (FORCE);"; echo "✓ dropped $$PG_DATABASE"

.PHONY: help up preflight secret db mcp policy agent budget diff down verify book \
        ask smoke credit status spend stop-agent start-agent break-schema fix-schema db-drop
