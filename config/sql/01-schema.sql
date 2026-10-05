-- A fictional wholesale broker with four desks. Everything here is synthetic.
--
--   trades.blotter            the authoritative trade store (golden source)
--   market.indicative_prices  indicative bid/offer/mid by instrument
--   refdata.counterparties    counterparty reference data and credit limits
--   desk.*                    aggregates (views, see 02-views.sql)
--
-- Re-runnable: drops and recreates everything it owns.

BEGIN;

DROP SCHEMA IF EXISTS desk, trades, market, refdata CASCADE;

CREATE SCHEMA refdata;
CREATE SCHEMA trades;
CREATE SCHEMA market;
CREATE SCHEMA desk;

CREATE TABLE refdata.counterparties (
  counterparty_lei   text PRIMARY KEY,          -- synthetic: always starts DEMO
  counterparty_name  text NOT NULL,
  counterparty_type  text NOT NULL,             -- bank, asset_manager, hedge_fund, corporate, energy_trader
  country            text NOT NULL,
  kyc_status         text NOT NULL,             -- approved, review_due, restricted
  credit_limit_usd   numeric(18,0) NOT NULL,
  limit_used_usd     numeric(18,0) NOT NULL,
  limit_review_date  date NOT NULL
);

CREATE TABLE trades.blotter (
  trade_id             text PRIMARY KEY,
  trade_ts             timestamptz NOT NULL,
  trade_date           date NOT NULL,
  desk                 text NOT NULL,           -- RATES, FXMM, CREDIT, ENERGY
  product              text NOT NULL,
  instrument           text NOT NULL,
  side                 text NOT NULL,           -- BUY / SELL from the client's view
  notional             numeric(18,0) NOT NULL,
  ccy                  text NOT NULL,
  price                numeric(12,4) NOT NULL,  -- rate %, FX rate, spread bp or EUR/MWh — see product
  venue                text NOT NULL,           -- OTF, MTF, VOICE
  broker               text NOT NULL,
  client_trader_email  text NOT NULL,
  counterparty_lei     text NOT NULL REFERENCES refdata.counterparties,
  counterparty_name    text NOT NULL,
  status               text NOT NULL            -- CONFIRMED, PENDING, CANCELLED
);
CREATE INDEX ON trades.blotter (trade_date, desk);

CREATE TABLE market.indicative_prices (
  instrument  text NOT NULL,
  desk        text NOT NULL,
  product     text NOT NULL,
  bid         numeric(12,4) NOT NULL,
  offer       numeric(12,4) NOT NULL,
  mid         numeric(12,4) NOT NULL,
  unit        text NOT NULL,
  source      text NOT NULL,                    -- composite, desk_axe
  as_of       timestamptz NOT NULL,
  PRIMARY KEY (instrument, as_of)
);

COMMIT;
