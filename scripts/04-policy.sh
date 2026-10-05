#!/usr/bin/env bash
# Reconcile the access policies in config/policies/.

. "$(dirname "$0")/_lib.sh"
require_token
: "${BROKER_EMAIL:?set BROKER_EMAIL in env/<env>.env}"

RENDERED="$(mktemp -d)"; trap 'rm -rf "$RENDERED"' EXIT
for p in "$ROOT"/config/policies/*.yaml; do
  sed "s|__BROKER_EMAIL__|$BROKER_EMAIL|g" "$p" > "$RENDERED/$(basename "$p")"
done

log "diff against live"
rpai policy diff -f "$RENDERED" || true
log "applying"
rpai policy apply -f "$RENDERED"
ok "policies reconciled"
