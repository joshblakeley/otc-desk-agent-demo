-- Four login roles, one per SQL MCP server. This file is the hard boundary.
--
-- The MCP server's own settings narrow what a query may do, but they are not a
-- security boundary on their own: `readonly` only disables the Execute tool, and
-- the Query tool will run whatever SQL it is given. What a login can touch is
-- decided here, by Postgres. `make verify` checks every combination.
--
-- Run AFTER 02-views.sql: replacing a view can drop the grants on it.
--
--   psql -v blotter_pw=... -v pricing_pw=... -v refdata_pw=... -v rollup_pw=... -f 03-roles.sql

BEGIN;

-- Roles are instance-wide. Refuse to touch a same-named role this demo did not
-- create, rather than silently resetting another workload's password.
DO $$
DECLARE
  marker text := 'otc-desk-agent-demo';
  r      text;
  owner  text;
BEGIN
  FOREACH r IN ARRAY ARRAY['blotter_sql', 'pricing_sql', 'refdata_sql', 'rollup_sql'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      SELECT shobj_description(oid, 'pg_authid') INTO owner FROM pg_roles WHERE rolname = r;
      IF owner IS DISTINCT FROM marker THEN
        RAISE EXCEPTION 'role "%" exists and was not created by % (comment: %). Refusing to reset its password.',
          r, marker, coalesce(owner, '<none>');
      END IF;
    ELSE
      EXECUTE format('CREATE ROLE %I LOGIN', r);
      EXECUTE format('COMMENT ON ROLE %I IS %L', r, marker);
    END IF;
  END LOOP;
END $$;

ALTER ROLE blotter_sql PASSWORD :'blotter_pw';
ALTER ROLE pricing_sql PASSWORD :'pricing_pw';
ALTER ROLE refdata_sql PASSWORD :'refdata_pw';
ALTER ROLE rollup_sql  PASSWORD :'rollup_pw';

-- Read-only at the session level too, as defence in depth.
ALTER ROLE blotter_sql SET default_transaction_read_only = on;
ALTER ROLE pricing_sql SET default_transaction_read_only = on;
ALTER ROLE refdata_sql SET default_transaction_read_only = on;
ALTER ROLE rollup_sql  SET default_transaction_read_only = on;

-- Start from nothing.
REVOKE ALL ON SCHEMA trades, market, refdata, desk, public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA trades, market, refdata, desk FROM PUBLIC;
REVOKE CONNECT, TEMPORARY ON DATABASE :"dbname" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"dbname" TO blotter_sql, pricing_sql, refdata_sql, rollup_sql;

-- Each login reaches exactly one schema.
GRANT USAGE  ON SCHEMA trades  TO blotter_sql;
GRANT SELECT ON trades.blotter TO blotter_sql;

GRANT USAGE  ON SCHEMA market TO pricing_sql;
GRANT SELECT ON market.indicative_prices, market.latest_prices TO pricing_sql;

GRANT USAGE  ON SCHEMA refdata TO refdata_sql;
GRANT SELECT ON refdata.counterparties TO refdata_sql;

GRANT USAGE  ON SCHEMA desk TO rollup_sql;
GRANT SELECT ON desk.daily_volumes TO rollup_sql;

COMMIT;
