#!/usr/bin/env bash
# A daily spend limit for the agent, so spend is visible and capped.
#
# Budgets are per agent: there is no per-user limit, though spend can be broken
# down by user in reporting. Amounts are microcents: 1 USD = 100,000,000.

. "$(dirname "$0")/_lib.sh"
require_token

: "${BUDGET_LIMIT_USD:=25}"; : "${BUDGET_WARN_USD:=20}"
LIMIT_MC=$(( BUDGET_LIMIT_USD * 100000000 )); WARN_MC=$(( BUDGET_WARN_USD * 100000000 ))

# filter_agent_name takes the resource name ("agents/<name>"), not the bare
# name. A bare name creates a budget that matches nothing. It is immutable, so
# a changed budget is deleted and recreated.
BODY="$(jq -nc --arg name "$BUDGET_NAME" --arg dn "Desk assistant daily limit" \
  --arg agent "agents/$AGENT_NAME" --argjson limit "$LIMIT_MC" --argjson warn "$WARN_MC" \
  '{budget:{name:$name, displayName:$dn, poolingMode:"POOLING_MODE_PER_AGENT",
    filterAgentName:$agent, period:"BUDGET_PERIOD_DAILY",
    limitMicrocents:$limit, warnAtMicrocents:$warn}}')"

if adp_rpc redpanda.api.adp.v1alpha1.BudgetService/GetBudget "$(jq -nc --arg n "$BUDGET_NAME" '{name:$n}')" >/dev/null 2>&1; then
  adp_rpc redpanda.api.adp.v1alpha1.BudgetService/DeleteBudget "$(jq -nc --arg n "$BUDGET_NAME" '{name:$n}')" >/dev/null
fi
adp_rpc redpanda.api.adp.v1alpha1.BudgetService/CreateBudget "$BODY" >/dev/null
ok "budget '$BUDGET_NAME': \$$BUDGET_LIMIT_USD/day on '$AGENT_NAME' (warn at \$$BUDGET_WARN_USD)"
