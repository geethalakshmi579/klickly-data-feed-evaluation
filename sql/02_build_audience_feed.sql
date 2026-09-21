-- ============================================================================
-- 02_build_audience_feed.sql
-- GlowBeauty Premium Skincare Audience Feed — audience construction
--
-- Business rule recap (see docs/feed_specification.pdf):
--   * Target : customers with SKINCARE engagement in the last 90 days
--   * Exclude: opted-out customers, missing/invalid email identifiers
--   * Output : one row per customer with engagement + purchase attributes
--
-- Reference date is 2026-09-21, so the 90-day window is 2026-06-23..2026-09-21.
-- In production replace the literals with CURRENT_DATE - INTERVAL '90 days'.
--
-- Dialect note: regexp_matches() is DuckDB syntax. In PostgreSQL use
--   email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
-- ============================================================================

-- --------------------------------------------------------------------------
-- Step 1: deduplicate customers.
-- Survivorship rule: keep the record with a usable email first, then one with
-- a hashed email, then the most recently created record.
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW deduped_customers AS
SELECT
    customer_id,
    email,
    hashed_email,
    zip_code,
    opt_out_flag,
    created_date
FROM (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY
                (email IS NOT NULL AND email <> ''
                 AND regexp_matches(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')) DESC,
                (hashed_email IS NOT NULL AND hashed_email <> '') DESC,
                created_date DESC
        ) AS rn
    FROM customers c
) ranked
WHERE rn = 1;

-- --------------------------------------------------------------------------
-- Step 2: in-window skincare engagement events.
-- Drops: non-skincare products, events outside the 90-day window,
-- future-dated events, events with missing customer_id, unknown products.
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW skincare_events AS
SELECT
    e.event_id,
    e.customer_id,
    e.event_type,
    e.event_date,
    e.product_id,
    e.session_id,
    p.product_name,
    p.price,
    p.premium_flag
FROM events e
JOIN products p
  ON p.product_id = e.product_id
WHERE p.category = 'Skincare'
  AND e.event_date BETWEEN DATE '2026-06-23' AND DATE '2026-09-21'
  AND e.customer_id IS NOT NULL
  AND e.customer_id <> '';

-- --------------------------------------------------------------------------
-- Step 3: per-customer engagement rollup.
-- engagement_score weights intent: page_view=1, product_view=2,
-- add_to_cart=5, purchase=10 (capped at 100).
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW customer_engagement AS
SELECT
    customer_id,
    MAX(event_date) AS last_activity_date,
    COUNT(*) AS total_events,
    COUNT(*) FILTER (WHERE event_type = 'page_view')    AS page_views,
    COUNT(*) FILTER (WHERE event_type = 'product_view') AS product_views,
    COUNT(*) FILTER (WHERE event_type = 'add_to_cart')  AS add_to_carts,
    COUNT(*) FILTER (WHERE event_type = 'purchase')     AS purchases,
    MAX(premium_flag) AS premium_interaction_flag,
    LEAST(100,
        SUM(CASE event_type
                WHEN 'page_view'    THEN 1
                WHEN 'product_view' THEN 2
                WHEN 'add_to_cart'  THEN 5
                WHEN 'purchase'     THEN 10
                ELSE 0
            END)
    ) AS engagement_score
FROM skincare_events
GROUP BY customer_id;

-- --------------------------------------------------------------------------
-- Step 4: per-customer purchase rollup (valid products, in-window orders).
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW customer_orders AS
SELECT
    o.customer_id,
    COUNT(*) AS total_purchases,
    SUM(o.order_value) AS total_spend
FROM orders o
JOIN products p
  ON p.product_id = o.product_id
WHERE o.order_date BETWEEN DATE '2026-06-23' AND DATE '2026-09-21'
  AND o.customer_id IS NOT NULL
  AND o.customer_id <> ''
GROUP BY o.customer_id;

-- --------------------------------------------------------------------------
-- Step 5: final audience feed.
-- Excludes opted-out customers and rows without a usable (valid-format) email.
-- Customers missing hashed_email are KEPT but flagged by the matchability
-- check in 03_data_quality_validation.sql — this is the deliberate tradeoff
-- between reach and match rate analyzed in the findings report.
-- --------------------------------------------------------------------------
DROP TABLE IF EXISTS audience_feed;
CREATE TABLE audience_feed AS
SELECT
    dc.customer_id,
    dc.email,
    dc.hashed_email,
    dc.zip_code,
    'Skincare' AS product_category,
    eng.last_activity_date,
    COALESCE(ord.total_purchases, 0)          AS total_purchases,
    COALESCE(ord.total_spend, 0.00)           AS total_spend,
    eng.engagement_score,
    eng.premium_interaction_flag,
    CASE
        WHEN eng.engagement_score >= 10 THEN 'high'
        WHEN eng.engagement_score >= 4  THEN 'medium'
        ELSE 'low'
    END AS engagement_tier
    -- Tier cutoffs are calibrated to the 90-day window's observed score
    -- distribution (min 1, p50 ~2, p90 ~10): they segment relative intent,
    -- not an absolute 0-100 scale.
FROM deduped_customers dc
JOIN customer_engagement eng
  ON eng.customer_id = dc.customer_id
LEFT JOIN customer_orders ord
  ON ord.customer_id = dc.customer_id
WHERE dc.opt_out_flag = 0
  AND dc.email IS NOT NULL
  AND dc.email <> ''
  AND regexp_matches(dc.email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Preview
SELECT * FROM audience_feed ORDER BY engagement_score DESC LIMIT 20;
