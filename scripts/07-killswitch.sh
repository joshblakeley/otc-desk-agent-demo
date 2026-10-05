#!/usr/bin/env bash
# Reconcile the kill-switch policies in config/killswitch/ onto the agent.
# Create if absent, otherwise update display name and spec.

. "$(dirname "$0")/_lib.sh"
require_token

PARENT="agents/$AGENT_NAME"
SVC=redpanda.api.adp.v1alpha1.KillSwitchPolicyService

for f in "$ROOT"/config/killswitch/*.yaml; do
  POLICY="$(python3 - "$f" "${KILLSWITCH_MODE:-}" <<'PY'
import sys, yaml, json
doc = yaml.safe_load(open(sys.argv[1]))
if sys.argv[2]:
    mode = "KILL_SWITCH_POLICY_MODE_" + sys.argv[2].upper()
    # Evaluation errors are a configuration fault, not evidence about the
    # agent, so that signal caps at WARN.
    if doc["spec"]["signal"].endswith("EVALUATION_ERROR_RATE") and mode.endswith("ENFORCE"):
        mode = "KILL_SWITCH_POLICY_MODE_WARN"
    doc["spec"]["mode"] = mode
print(json.dumps(doc))
PY
)"
  id="$(echo "$POLICY" | jq -r .name)"; name="$PARENT/killSwitchPolicies/$id"
  mode="$(echo "$POLICY" | jq -r .spec.mode)"

  if adp_rpc "$SVC/GetKillSwitchPolicy" "$(jq -nc --arg n "$name" '{name:$n}')" >/dev/null 2>&1; then
    adp_rpc "$SVC/UpdateKillSwitchPolicy" "$(echo "$POLICY" | jq -c --arg n "$name" \
      '{killSwitchPolicy: {name:$n, displayName:.display_name, spec:.spec}, updateMask:"displayName,spec"}')" >/dev/null
    ok "kill-switch policy $id updated (${mode#KILL_SWITCH_POLICY_MODE_})"
  else
    adp_rpc "$SVC/CreateKillSwitchPolicy" "$(echo "$POLICY" | jq -c --arg p "$PARENT" \
      '{parent:$p, killSwitchPolicy: {name:.name, displayName:.display_name, spec:.spec}}')" >/dev/null
    ok "kill-switch policy $id created (${mode#KILL_SWITCH_POLICY_MODE_})"
  fi
done
