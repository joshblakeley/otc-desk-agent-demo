#!/usr/bin/env bash
# Check the things that cannot be fixed on demo morning. Run it the day before.

. "$(dirname "$0")/_lib.sh"

fails=0
check() { printf "  %-48s" "$1"; }
pass()  { printf "%s✓%s %s\n" "$c_green" "$c_reset" "${1:-}"; }
fail()  { printf "%s✗%s %s\n" "$c_red" "$c_reset" "$1"; fails=$((fails+1)); }
soft()  { printf "%s?%s %s\n" "$c_yellow" "$c_reset" "$1"; }

echo "=== tooling ==="
for t in rpai jq curl psql python3; do
  check "$t on PATH"; command -v "$t" >/dev/null && pass || fail "not found"
done
check "rpai 0.2.x or newer"
v="$(rpai version 2>/dev/null | awk '{print $2}')"
case "$v" in 0.2*|0.[3-9]*|[1-9]*) pass "$v" ;; *) fail "${v:-unknown} — brew upgrade rpai" ;; esac

echo; echo "=== identities ==="
for who in "desk head::$DESK_HEAD_EMAIL" "broker:broker:$BROKER_EMAIL"; do
  label="${who%%:*}"; rest="${who#*:}"; as="${rest%%:*}"; want="${rest#*:}"
  check "$label signed in as $want"
  got="$(AS="$as" bash -c '. "'"$ROOT"'/scripts/_lib.sh"; rpai auth token >/dev/null 2>&1 && rpai_identity' 2>/dev/null || true)"
  [ "$got" = "$want" ] && pass || fail "got '${got:-nothing}'. Sign in: ${as:+RPAI_CONFIG=~/.rpai/$as RPAI_CREDENTIALS=~/.rpai/$as.credentials }rpai auth login"
done

echo; echo "=== postgres ==="
check "PG_ADMIN_DSN reachable"
psql "${PG_ADMIN_DSN:-}" -tAc 'SELECT 1' >/dev/null 2>&1 && pass || fail "cannot connect (security group? sslmode?)"

if require_token >/dev/null 2>&1; then
  echo; echo "=== org ==="
  check "LLM provider '$LLM_PROVIDER'"
  rpai llm-provider list -o json 2>/dev/null | jq -e --arg n "$LLM_PROVIDER" '[.. | objects | .name? // empty] | index($n) != null' >/dev/null 2>&1 \
    && pass || soft "not confirmed — check it exists and allows '$LLM_MODEL'"
fi

echo
[ "$fails" -eq 0 ] || die "$fails preflight check(s) failed"
ok "preflight clean"
