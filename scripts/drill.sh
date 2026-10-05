#!/usr/bin/env bash
# Kill-switch drill: provoke a burst of data-policy denials through the agent
# and wait for the kill-switch policy to record a firing.
#
# Breaks the masked column (so every broker query is withheld by data policy),
# sends DRILL_N broker questions concurrently, restores the column, then polls
# for a firing. Windows are 5 minutes and need at least 10 calls, so expect the
# firing a few minutes after the burst. In SHADOW mode, nothing stops. In
# ENFORCE mode, the agent's kill switch engages. Release it with
# `make release`.

. "$(dirname "$0")/_lib.sh"
require_token
: "${DRILL_N:=14}"

restore() { pgd -c "ALTER TABLE trades.blotter RENAME COLUMN client_contact TO client_trader_email;" >/dev/null 2>&1 || true; }
trap restore EXIT

pgd -c "ALTER TABLE trades.blotter RENAME COLUMN client_trader_email TO client_contact;"
log "masked column renamed — broker queries on the blotter will be withheld"

firing_names() {
  adp_rpc redpanda.api.adp.v1alpha1.KillSwitchPolicyService/ListKillSwitchFirings '{"pageSize":100}' 2>/dev/null \
    | jq -r --arg a "agents/$AGENT_NAME" '.killSwitchFirings[]? | select(.agentName == $a) | .name'
}
BEFORE="$(firing_names | sort)"
log "sending $DRILL_N broker questions concurrently"
OUT="$STATE_DIR/drill"; rm -rf "$OUT"; mkdir -p "$OUT"
for i in $(seq 1 "$DRILL_N"); do
  ( export RPAI_CONFIG="$HOME/.rpai/broker" RPAI_CREDENTIALS="$HOME/.rpai/broker.credentials"
    rpai agent a2a send "$AGENT_NAME" "Show me Rates trade number $i from the last business day, with the client trader." > "$OUT/$i.out" 2>&1 ) &
done
wait
withheld="$(grep -l 'response withheld' "$OUT"/*.out 2>/dev/null | wc -l | tr -d ' ')"
log "$withheld of $DRILL_N answers report a response withheld by data policy (transcripts in $OUT)"
restore; trap - EXIT
ok "burst sent, column restored"

log "waiting for a firing (up to 10 minutes)"
for _ in $(seq 1 40); do
  NEW="$(comm -13 <(echo "$BEFORE") <(firing_names | sort) | head -1)"
  F=""
  [ -n "$NEW" ] && F="$(adp_rpc redpanda.api.adp.v1alpha1.KillSwitchPolicyService/ListKillSwitchFirings '{"pageSize":100}' \
      | jq -c --arg n "$NEW" '.killSwitchFirings[] | select(.name == $n)')"
  if [ -n "$F" ]; then
    ok "firing recorded:"
    echo "$F" | jq '{windowStart, policyName, signal, detector, observedRate, statistic, threshold, mode}'
    exit 0
  fi
  sleep 15
done
warn "no firing yet — check 'make firings' in a few minutes"
