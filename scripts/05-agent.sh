#!/usr/bin/env bash
# Reconcile the orchestrator and its two specialists.
#
#   desk-assistant      rollup-sql, refdata-sql
#   ├─ trade-analyst    blotter-sql
#   └─ pricing-analyst  pricing-sql
#
# `rpai agent apply` updates only the fields that differ, so editing a prompt
# and re-running changes the prompt and nothing else.

. "$(dirname "$0")/_lib.sh"
require_token

[[ "$AGENT_NAME" =~ ^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "AGENT_NAME must be a DNS-1123 label; got '$AGENT_NAME'"

MANIFEST="$(mktemp)"; trap 'rm -f "$MANIFEST"' EXIT
bash "$ROOT/scripts/render-agent.sh" > "$MANIFEST"

log "diff against live"
rpai agent diff -f "$MANIFEST" || true
log "applying"
rpai agent apply -f "$MANIFEST"

log "waiting for the agent to start"
URL=""
for _ in $(seq 1 60); do
  GET="$(rpai agent get "$AGENT_NAME" -o json 2>/dev/null || true)"
  case "$(echo "$GET" | jq -r '.managed.status.state // ""')" in
    AGENT_STATE_RUNNING) URL="$(echo "$GET" | jq -r '.managed.status.url // ""')"; ok "running"; break ;;
    AGENT_STATE_FAILED)  die "agent failed to start: $(echo "$GET" | jq -r '.managed.status.stateReason // ""')" ;;
  esac
  sleep 5
done
[ -n "$URL" ] || URL="$AIGW_URL/a2a/v1/$AGENT_NAME"
echo "$URL" > "$STATE_DIR/agent_url"
ok "agent: $AGENT_NAME  url: $URL"
