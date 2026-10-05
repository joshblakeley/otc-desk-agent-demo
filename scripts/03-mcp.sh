#!/usr/bin/env bash
# Reconcile the four SQL MCP servers from config/manifests/*.yaml.
#
# Four servers rather than one because a server cannot be narrowed per agent:
# each logs into Postgres as a different login, so the boundary is a database
# permission rather than a filter. The data policy lives on the server it
# applies to, so there is no separate step for it.

. "$(dirname "$0")/_lib.sh"
require_token

: "${BROKER_EMAIL:?set BROKER_EMAIL in env/<env>.env}"
case "$BROKER_EMAIL" in Group:*) die "BROKER_EMAIL is a group. Group targeting refuses every call on the server. Target one person.";; esac
grep -rq 'Group:' "$ROOT/config/manifests" && die "a manifest targets a group — unsupported, and it refuses every call on the whole server."

RENDERED="$(mktemp -d)"; trap 'rm -rf "$RENDERED"' EXIT
for m in "$ROOT"/config/manifests/*.yaml; do
  sed "s|__BROKER_EMAIL__|$BROKER_EMAIL|g" "$m" > "$RENDERED/$(basename "$m")"
done

log "diff against live"
rpai mcp diff -f "$RENDERED" || true
log "applying"
rpai mcp apply -f "$RENDERED"

# A server that fell back to positional rows would turn every per-field rule
# into a no-op with no error anywhere. Check the setting stuck.
for name in "$MCP_BLOTTER" "$MCP_PRICING" "$MCP_REFDATA" "$MCP_ROLLUP"; do
  fmt="$(rpai mcp get "$name" -o json 2>/dev/null | jq -r '.managed.config.row_format // "<absent>"')"
  [ "$fmt" = "ROW_FORMAT_OBJECT" ] || die "$name has row_format '$fmt'; per-field data policies would silently do nothing."
done
ok "four servers reconciled, row format confirmed"

# Check the broker's policy does what it says, using the gateway's own engine
# against a sample response. Nothing is saved. The sample uses strings for
# every value because that is what the SQL server sends.
SAMPLE='{"columns":["trade_id","desk","client_trader_email","counterparty_lei","counterparty_name"],
  "records":[
    {"trade_id":"P-1","desk":"RATES","client_trader_email":"a@x.example","counterparty_lei":"DEMO00NORTHBRIDGE001","counterparty_name":"Northbridge Capital"},
    {"trade_id":"P-2","desk":"FXMM","client_trader_email":"b@x.example","counterparty_lei":"DEMO00KESTREL0000004","counterparty_name":"Kestrel Macro Partners"},
    {"trade_id":"P-3","desk":"CREDIT","client_trader_email":"c@x.example","counterparty_lei":"DEMO00ASHGROVE000003","counterparty_name":"Ashgrove Asset Management"}
  ],"row_count":3,"rows":[],"truncated":false}'

DRAFT="$(sed "s|__BROKER_EMAIL__|$BROKER_EMAIL|g" "$ROOT/config/manifests/blotter-sql.yaml" \
  | python3 -c 'import sys,yaml,json; print(json.dumps(yaml.safe_load(sys.stdin)["data_policies"][0] | {"principals": []}))')"

SHAPED="$(adp_rpc redpanda.api.adp.v1alpha1.MCPServerService/PreviewToolResponse \
  "$(jq -nc --arg n "$MCP_BLOTTER" --arg t query --arg s "$SAMPLE" --argjson d "$DRAFT" \
    '{name:$n, tool:$t, sampleResponse:$s, draftDataPolicies:[$d], hasDraft:true}')" \
  2>/dev/null | jq -r '.shapedResponse // empty')"

if [ -z "$SHAPED" ]; then
  warn "$MCP_BLOTTER: preview returned nothing — check the policy by hand"
else
  fails=""
  echo "$SHAPED" | jq -e '(.records | length) == 1'                        >/dev/null || fails="$fails row-filter"
  echo "$SHAPED" | jq -e '.records[0].desk == "RATES"'                     >/dev/null || fails="$fails desk"
  echo "$SHAPED" | jq -e '.records[0].client_trader_email == "[redacted]"' >/dev/null || fails="$fails redact"
  echo "$SHAPED" | jq -e '.records[0].counterparty_lei | endswith("R001") and startswith("*")' >/dev/null || fails="$fails lei-mask"
  [ -z "$fails" ] || die "$MCP_BLOTTER: the policy did not behave as configured —$fails"
  ok "$MCP_BLOTTER: row filter, redact and partial mask confirmed"
fi
warn "a row filter removes records but does not update row_count in the response."
