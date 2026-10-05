#!/usr/bin/env bash
# Create the database if needed, then load schema, views, logins and data, in
# order. Safe to re-run: it rebuilds the demo's schemas from scratch and leaves
# every other database on the instance alone.
#
# 03-roles.sql runs AFTER 02-views.sql because replacing a view can drop the
# grants on it. `make verify` is the check.

. "$(dirname "$0")/_lib.sh"

: "${PG_ADMIN_DSN:?set PG_ADMIN_DSN in env/secrets.env}"
for v in PG_BLOTTER_PW PG_PRICING_PW PG_REFDATA_PW PG_ROLLUP_PW; do
  [ -n "${!v:-}" ] || die "set $v in env/secrets.env"
done

if [ "$(pg -tAc "SELECT 1 FROM pg_database WHERE datname = '$PG_DATABASE'")" != "1" ]; then
  log "creating database $PG_DATABASE"
  pg -c "CREATE DATABASE \"$PG_DATABASE\""
fi

SQL="$ROOT/config/sql"
log "schema";      pgd -f "$SQL/01-schema.sql" 2>/dev/null
log "views";       pgd -f "$SQL/02-views.sql"
log "logins and grants (after views)"
pgd -v dbname="$PG_DATABASE" \
    -v blotter_pw="$PG_BLOTTER_PW" -v pricing_pw="$PG_PRICING_PW" \
    -v refdata_pw="$PG_REFDATA_PW" -v rollup_pw="$PG_ROLLUP_PW" \
    -f "$SQL/03-roles.sql"
log "counterparties"; pgd -f "$SQL/04-seed-refdata.sql"
log "trades and prices"; pgd -f "$SQL/05-seed-trades.sql" >/dev/null

ok "$(pgd -tAc "SELECT count(*) || ' trades, ' || count(DISTINCT trade_date) || ' days, ' || count(DISTINCT desk) || ' desks' FROM trades.blotter")"
ok "$(pgd -tAc "SELECT count(*) || ' counterparties' FROM refdata.counterparties")"
ok "$(pgd -tAc "SELECT string_agg(trade_id, ', ' ORDER BY trade_id) FROM trades.blotter WHERE trade_id LIKE 'SHOW-%'") (showcase, on $(pgd -tAc "SELECT max(trade_date) FROM trades.blotter"))"
