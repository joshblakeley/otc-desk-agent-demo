-- Trades and prices. Generated relative to current_date so "yesterday" and
-- "this week" mean something on the day of the demo, and seeded so two loads
-- on the same day produce the same book.
--
-- Showcase trades (trade_id SHOW-*) are pinned: the largest trade of the
-- previous business day on each desk, so "what were yesterday's biggest
-- trades?" has a known answer. See WALKTHROUGH.md.

BEGIN;

SELECT setseed(0.4207) \gset

-- Instrument catalogue: desk, product, instrument, ccy, typical price, price
-- jitter, notional range (millions), unit.
CREATE TEMP TABLE instruments (desk text, product text, instrument text, ccy text,
  px numeric, jitter numeric, nmin int, nmax int, unit text) ON COMMIT DROP;
INSERT INTO instruments VALUES
 ('RATES',  'IRS',       'EUR IRS 2Y',            'EUR', 2.1450, 0.04,  50, 500, 'rate %'),
 ('RATES',  'IRS',       'EUR IRS 5Y',            'EUR', 2.3125, 0.05,  25, 400, 'rate %'),
 ('RATES',  'IRS',       'EUR IRS 10Y',           'EUR', 2.6010, 0.05,  25, 300, 'rate %'),
 ('RATES',  'IRS',       'USD SOFR IRS 5Y',       'USD', 3.6420, 0.06,  50, 500, 'rate %'),
 ('RATES',  'OIS',       'GBP SONIA OIS 1Y',      'GBP', 3.9875, 0.03, 100, 750, 'rate %'),
 ('FXMM',   'FX_FWD',    'EURUSD 3M FWD',         'EUR', 1.1062, 0.004, 10, 250, 'fx rate'),
 ('FXMM',   'FX_FWD',    'USDJPY 1M FWD',         'USD', 148.35, 0.60,  10, 200, 'fx rate'),
 ('FXMM',   'FX_OPTION', 'EURUSD 1M 25D RR',      'EUR', 0.3500, 0.10,  10, 100, 'vol pts'),
 ('FXMM',   'DEPO',      'USD DEPO 1M',           'USD', 4.3100, 0.02,  50, 500, 'rate %'),
 ('CREDIT', 'CDS_INDEX', 'iTraxx Main S44 5Y',    'EUR', 58.25,  1.50,  10, 200, 'spread bp'),
 ('CREDIT', 'CDS_INDEX', 'CDX IG S45 5Y',         'USD', 52.10,  1.20,  10, 250, 'spread bp'),
 ('CREDIT', 'CDS_INDEX', 'iTraxx Crossover S44 5Y','EUR',298.50,  6.00,   5,  75, 'spread bp'),
 ('ENERGY', 'GAS_SWAP',  'TTF Gas Month-Ahead',   'EUR', 34.80,  0.90,   5,  60, 'EUR/MWh'),
 ('ENERGY', 'POWER_SWAP','UK Power Base Q1',      'GBP', 82.40,  2.10,   5,  40, 'GBP/MWh'),
 ('ENERGY', 'OIL_SWAP',  'Brent Swap Cal-27',     'USD', 71.25,  0.80,   5,  80, 'USD/bbl');

-- Ten business days of history, ~5,000 trades.
INSERT INTO trades.blotter
SELECT
  'T' || to_char(d.day, 'YYMMDD') || '-' || lpad(g::text, 5, '0'),
  d.day + interval '7 hours' + (random() * interval '10 hours'),
  d.day,
  i.desk, i.product, i.instrument,
  CASE WHEN random() < 0.5 THEN 'BUY' ELSE 'SELL' END,
  ((i.nmin + floor(random() * (i.nmax - i.nmin)))::int * 1000000),
  i.ccy,
  round(i.px + (random()::numeric - 0.5) * 2 * i.jitter, 4),
  (ARRAY['OTF','OTF','MTF','VOICE'])[1 + floor(random() * 4)::int],
  (ARRAY['a.okafor','b.lindqvist','c.marchetti','d.huang','e.walsh','f.rahman','g.novak','h.silva'])[1 + floor(random() * 8)::int],
  lower(split_part(c.counterparty_name, ' ', 1)) || '.trader' || (1 + floor(random() * 6)::int) || '@' ||
    lower(split_part(c.counterparty_name, ' ', 1)) || '.example',
  c.counterparty_lei, c.counterparty_name,
  CASE WHEN random() < 0.94 THEN 'CONFIRMED' WHEN random() < 0.6 THEN 'PENDING' ELSE 'CANCELLED' END
FROM generate_series(1, 5000) AS g
-- `+ g * 0` makes each subquery correlated, so Postgres re-runs it per row
-- instead of picking one day, instrument and counterparty for all 5,000.
CROSS JOIN LATERAL (
  SELECT day FROM (
    SELECT (current_date - k)::date AS day FROM generate_series(1, 14) AS k
  ) days WHERE extract(isodow FROM day) < 6
  ORDER BY day DESC OFFSET (floor(random() * 10)::int + g * 0) LIMIT 1
) d
CROSS JOIN LATERAL (SELECT * FROM instruments ORDER BY random() + g * 0 LIMIT 1) i
CROSS JOIN LATERAL (SELECT * FROM refdata.counterparties
                    WHERE kyc_status <> 'restricted'
                    ORDER BY random() + g * 0 LIMIT 1) c;

-- Showcase trades on the previous business day: the largest on each desk.
WITH prev AS (
  SELECT max(day)::date AS day FROM (
    SELECT (current_date - k)::date AS day FROM generate_series(1, 5) AS k
  ) x WHERE extract(isodow FROM day) < 6
)
INSERT INTO trades.blotter
SELECT v.trade_id, prev.day + v.t, prev.day, v.desk, v.product, v.instrument, v.side,
       v.notional, v.ccy, v.price, v.venue, v.broker, v.email, v.lei, c.counterparty_name, 'CONFIRMED'
FROM prev, (VALUES
  ('SHOW-RATES-1',  interval '9 hours 14 minutes', 'RATES',  'OIS',        'GBP SONIA OIS 1Y',   'BUY',  1250000000, 'GBP',   3.9850, 'VOICE', 'e.walsh',     'r.ashby@northbridge.example',   'DEMO00NORTHBRIDGE001'),
  ('SHOW-RATES-2',  interval '11 hours 2 minutes', 'RATES',  'IRS',        'EUR IRS 10Y',        'SELL',  900000000, 'EUR',   2.5975, 'OTF',   'c.marchetti', 'm.dahl@halversen.example',      'DEMO00HALVERSEN00002'),
  ('SHOW-FXMM-1',   interval '8 hours 40 minutes', 'FXMM',   'FX_FWD',     'EURUSD 3M FWD',      'BUY',   600000000, 'EUR',   1.1071, 'VOICE', 'd.huang',     'p.osei@kestrel.example',        'DEMO00KESTREL0000004'),
  ('SHOW-CREDIT-1', interval '14 hours 5 minutes', 'CREDIT', 'CDS_INDEX',  'iTraxx Main S44 5Y', 'SELL',  450000000, 'EUR',  57.7500, 'MTF',   'b.lindqvist', 'l.fenwick@ashgrove.example',    'DEMO00ASHGROVE000003'),
  ('SHOW-ENERGY-1', interval '10 hours 30 minutes','ENERGY', 'POWER_SWAP', 'UK Power Base Q1',   'BUY',   150000000, 'GBP',  83.1000, 'VOICE', 'h.silva',     's.brandt@meridian.example',     'DEMO00MERIDIANPWR005')
) AS v(trade_id, t, desk, product, instrument, side, notional, ccy, price, venue, broker, email, lei)
JOIN refdata.counterparties c ON c.counterparty_lei = v.lei;

-- Indicative prices: one snapshot per instrument every 30 minutes today.
INSERT INTO market.indicative_prices
SELECT i.instrument, i.desk, i.product,
       round(m - i.jitter * 0.1, 4), round(m + i.jitter * 0.1, 4), round(m, 4),
       i.unit,
       CASE WHEN random() < 0.8 THEN 'composite' ELSE 'desk_axe' END,
       current_date + interval '7 hours' + s * interval '30 minutes'
FROM instruments i
CROSS JOIN generate_series(0, 20) AS s
CROSS JOIN LATERAL (SELECT i.px + (random()::numeric - 0.5) * i.jitter AS m) p;

COMMIT;
