#!/usr/bin/env bash
# Remove everything this demo created in the ADP org. Postgres stays as it is.
# `make db-drop` handles that.

. "$(dirname "$0")/_lib.sh"
require_token

adp_rpc redpanda.api.adp.v1alpha1.BudgetService/DeleteBudget "$(jq -nc --arg n "$BUDGET_NAME" '{name:$n}')" >/dev/null 2>&1 || true
ok "budget $BUDGET_NAME"
rpai agent delete "$AGENT_NAME" >/dev/null 2>&1 || true; ok "agent $AGENT_NAME"
for p in "$POLICY_NAME" desk-assistant-mcp desk-assistant-llm; do
  rpai policy delete "policies/$p" >/dev/null 2>&1 || true; ok "policy $p"
done
for m in "$MCP_BLOTTER" "$MCP_PRICING" "$MCP_REFDATA" "$MCP_ROLLUP"; do
  rpai mcp delete "$m" >/dev/null 2>&1 || true; ok "mcp $m"
done
for s in "$PG_BLOTTER_SECRET" "$PG_PRICING_SECRET" "$PG_REFDATA_SECRET" "$PG_ROLLUP_SECRET"; do
  dp_del "/v1/secrets/$s" >/dev/null 2>&1 || true; ok "secret $s"
done
rm -rf "$STATE_DIR"
