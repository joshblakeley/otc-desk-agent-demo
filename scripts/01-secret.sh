#!/usr/bin/env bash
# Create or update the four Postgres DSN secrets, one per SQL MCP server, each
# carrying a different least-privilege login.
#
# DSNs are assembled here from PG_HOST/PG_PORT/PG_DATABASE and the passwords in
# env/secrets.env, so a full connection string never lands in a committed file.
# The secret store is write-only: once stored, a value cannot be read back
# through the API, only referenced by name from an MCP server.

. "$(dirname "$0")/_lib.sh"
require_token

: "${PG_HOST:?set PG_HOST in env/<env>.env}"
: "${PG_PORT:=5432}"
: "${PG_DATABASE:?set PG_DATABASE in env/<env>.env}"

case "$PG_HOST" in
  localhost|127.0.0.1|10.*|192.168.*|172.1[6-9].*|172.2*.*|172.3[01].*)
    warn "PG_HOST=$PG_HOST looks private. The gateway refuses to dial private addresses." ;;
esac

SCOPES='["SCOPE_MCP_SERVER","SCOPE_AI_AGENT","SCOPE_AI_GATEWAY"]'

put_dsn_secret() {
  local secret_name="$1" role="$2" password="$3"
  [ -n "$password" ] || die "no password for $role in env/secrets.env"
  local dsn="postgres://${role}:${password}@${PG_HOST}:${PG_PORT}/${PG_DATABASE}?sslmode=require"
  local body
  body="$(jq -nc --arg id "$secret_name" --arg s "$(b64 "$dsn")" --argjson scopes "$SCOPES" \
    '{id:$id, secret_data:$s, scopes:$scopes, labels:{owner:"otc-desk-agent-demo"}}')"

  if [ -n "$(dp_get "/v1/secrets/$secret_name" 2>/dev/null | jq -r '.secret.id // empty')" ]; then
    dp_put "/v1/secrets/$secret_name" "$body" >/dev/null
    ok "$secret_name updated -> login '$role'"
  else
    dp_post "/v1/secrets" "$body" >/dev/null
    ok "$secret_name created -> login '$role'"
  fi
}

put_dsn_secret "$PG_BLOTTER_SECRET" blotter_sql "${PG_BLOTTER_PW:-}"
put_dsn_secret "$PG_PRICING_SECRET" pricing_sql "${PG_PRICING_PW:-}"
put_dsn_secret "$PG_REFDATA_SECRET" refdata_sql "${PG_REFDATA_PW:-}"
put_dsn_secret "$PG_ROLLUP_SECRET"  rollup_sql  "${PG_ROLLUP_PW:-}"
