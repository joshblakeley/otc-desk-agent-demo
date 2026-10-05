-- Synthetic counterparties. Names are invented. LEIs start with DEMO so they
-- cannot collide with a real Legal Entity Identifier.

BEGIN;

INSERT INTO refdata.counterparties VALUES
-- showcase: referenced by name in WALKTHROUGH.md
('DEMO00NORTHBRIDGE001', 'Northbridge Capital',          'bank',          'GB', 'approved',   750000000, 612000000, current_date + 41),
('DEMO00HALVERSEN00002', 'Halversen Bank',               'bank',          'NO', 'approved',   900000000, 210000000, current_date + 120),
('DEMO00ASHGROVE000003', 'Ashgrove Asset Management',    'asset_manager', 'GB', 'review_due', 300000000, 288000000, current_date + 6),
('DEMO00KESTREL0000004', 'Kestrel Macro Partners',       'hedge_fund',    'US', 'approved',   250000000,  91000000, current_date + 75),
('DEMO00MERIDIANPWR005', 'Meridian Power Trading',       'energy_trader', 'DE', 'approved',   400000000, 377000000, current_date + 18),
-- the rest of the book
('DEMO00ALDGATE0000006', 'Aldgate Securities',           'bank',          'GB', 'approved',   650000000, 140000000, current_date + 200),
('DEMO00BAYVIEW0000007', 'Bayview Pension Trustees',     'asset_manager', 'IE', 'approved',   200000000,  35000000, current_date + 150),
('DEMO00CALLOWAY000008', 'Calloway Bank AG',             'bank',          'CH', 'approved',   800000000, 402000000, current_date + 90),
('DEMO00DUNMORE0000009', 'Dunmore Credit Opportunities', 'hedge_fund',    'US', 'restricted', 100000000,  99000000, current_date - 3),
('DEMO00EASTWICK000010', 'Eastwick Commodities',         'energy_trader', 'GB', 'approved',   350000000, 120000000, current_date + 60),
('DEMO00FAIRHOLM000011', 'Fairholm Insurance',           'asset_manager', 'FR', 'approved',   250000000,  61000000, current_date + 180),
('DEMO00GLENROCK000012', 'Glenrock Bank plc',            'bank',          'GB', 'approved',   700000000, 515000000, current_date + 33),
('DEMO00HARTWELL000013', 'Hartwell Global Macro',        'hedge_fund',    'US', 'approved',   300000000, 144000000, current_date + 95),
('DEMO00IVERSON0000014', 'Iverson Utilities',            'corporate',     'NL', 'approved',   150000000,  48000000, current_date + 210),
('DEMO00JUNIPER0000015', 'Juniper Rates Fund',           'hedge_fund',    'GB', 'review_due', 200000000, 170000000, current_date + 9),
('DEMO00KINGSMERE00016', 'Kingsmere Banking Corp',       'bank',          'US', 'approved',   950000000, 330000000, current_date + 140),
('DEMO00LOWTHER0000017', 'Lowther Investment Partners',  'asset_manager', 'GB', 'approved',   180000000,  22000000, current_date + 160),
('DEMO00MONTCLAIR00018', 'Montclair Energy',             'energy_trader', 'US', 'approved',   300000000, 255000000, current_date + 27),
('DEMO00NAVARRO0000019', 'Navarro Banco SA',             'bank',          'ES', 'approved',   500000000, 260000000, current_date + 100),
('DEMO00ORMSBY00000020', 'Ormsby Treasury Services',     'corporate',     'GB', 'approved',   120000000,  15000000, current_date + 230),
('DEMO00PEMBROKE000021', 'Pembroke Capital Markets',     'bank',          'GB', 'approved',   600000000, 190000000, current_date + 70),
('DEMO00QUANTOCK000022', 'Quantock Systematic',          'hedge_fund',    'GB', 'approved',   220000000,  80000000, current_date + 110),
('DEMO00RAVENSWD000023', 'Ravenswood Asset Management',  'asset_manager', 'LU', 'approved',   260000000,  97000000, current_date + 85),
('DEMO00SELWYN00000024', 'Selwyn Bank',                  'bank',          'DE', 'approved',   850000000, 470000000, current_date + 55),
('DEMO00THORNBURY00025', 'Thornbury Gas & Power',        'energy_trader', 'GB', 'review_due', 280000000, 240000000, current_date + 4),
('DEMO00UPTONVALE00026', 'Upton Vale Credit',            'hedge_fund',    'US', 'approved',   160000000,  58000000, current_date + 130),
('DEMO00VANTAGE0000027', 'Vantage Bank NV',              'bank',          'NL', 'approved',   700000000, 310000000, current_date + 45),
('DEMO00WESTCOMBE00028', 'Westcombe Pension Fund',       'asset_manager', 'GB', 'approved',   240000000,  44000000, current_date + 190),
('DEMO00YARDLEY0000029', 'Yardley Shipping',             'corporate',     'SG', 'approved',   110000000,  37000000, current_date + 170),
('DEMO00ZEPHYR00000030', 'Zephyr Renewables',            'energy_trader', 'DK', 'approved',   200000000,  66000000, current_date + 125);

COMMIT;
