-- Views. A view runs with its owner's privileges, so a login granted only the
-- view reads the aggregate without any permission on the table underneath.
-- That is how rollup_sql sees desk volumes but never a counterparty.

BEGIN;

-- Cross-desk aggregates with no counterparty, client or broker columns.
-- Aggregates like this are what an information barrier permits to cross it.
CREATE OR REPLACE VIEW desk.daily_volumes AS
SELECT trade_date,
       desk,
       product,
       count(*)                          AS trade_count,
       sum(notional)                     AS total_notional,
       ccy,
       count(*) FILTER (WHERE venue = 'VOICE') AS voice_trades
FROM trades.blotter
WHERE status <> 'CANCELLED'
GROUP BY trade_date, desk, product, ccy;

CREATE OR REPLACE VIEW market.latest_prices AS
SELECT DISTINCT ON (instrument)
       instrument, desk, product, bid, offer, mid, unit, source, as_of
FROM market.indicative_prices
ORDER BY instrument, as_of DESC;

COMMIT;
