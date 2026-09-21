-- ============================================================================
-- 03_data_quality_validation.sql
-- GlowBeauty Premium Skincare Audience Feed — validation & profiling
--
-- Depends on: 01_create_tables.sql, 02_build_audience_feed.sql
-- (views: deduped_customers, skincare_events, customer_engagement)
--
-- Sections:
--   A. Population coverage / exclusion funnel
--   B. Required-field completeness
--   C. Identifier quality (email / hashed email)
--   D. Data-quality checks (opt-out leakage, nulls, duplicates, bad dates,
--      orphaned records)
--   E. Expected vs. actual matchability
-- ============================================================================

-- ============================================================================
-- A. POPULATION COVERAGE — how many survive each stage of the funnel?
-- ============================================================================

-- A1. Exclusion funnel: engaged base -> opt-outs -> bad identifiers -> feed
WITH engaged AS (
    SELECT DISTINCT eng.customer_id, dc.opt_out_flag, dc.email
    FROM customer_engagement eng
    JOIN deduped_customers dc ON dc.customer_id = eng.customer_id
),
staged AS (
    SELECT
        COUNT(*) AS engaged_customers,
        COUNT(*) FILTER (WHERE opt_out_flag = 1) AS excluded_opt_out,
        COUNT(*) FILTER (
            WHERE opt_out_flag = 0
              AND (email IS NULL OR email = ''
                   OR NOT regexp_matches(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'))
        ) AS excluded_bad_identifier
    FROM engaged
)
SELECT
    'engaged_in_window'        AS stage,
    engaged_customers          AS customer_count,
    ROUND(100.0 * engaged_customers / engaged_customers, 1) AS pct_of_engaged
FROM staged
UNION ALL
SELECT 'excluded_opt_out',  excluded_opt_out,
       ROUND(100.0 * excluded_opt_out / engaged_customers, 1) FROM staged
UNION ALL
SELECT 'excluded_bad_identifier', excluded_bad_identifier,
       ROUND(100.0 * excluded_bad_identifier / engaged_customers, 1) FROM staged
UNION ALL
SELECT 'final_feed', (SELECT COUNT(*) FROM audience_feed),
       ROUND(100.0 * (SELECT COUNT(*) FROM audience_feed) / engaged_customers, 1) FROM staged
ORDER BY customer_count DESC;

-- A2. Audience composition by engagement tier and premium interaction
SELECT
    engagement_tier,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_feed,
    ROUND(AVG(engagement_score), 1) AS avg_score,
    SUM(premium_interaction_flag) AS premium_interactors,
    ROUND(SUM(total_spend), 2) AS total_spend
FROM audience_feed
GROUP BY engagement_tier
ORDER BY customers DESC;

-- ============================================================================
-- B. REQUIRED-FIELD COMPLETENESS (spec threshold: >= 95% per required field)
-- Required fields for delivery health: zip_code, product_category,
-- last_activity_date, engagement_score.
-- NOTE: hashed_email is intentionally NOT in this block -- it is measured
-- under C (identifier quality) and E (matchability), because a missing hash
-- does not block delivery but does reduce the match rate. This separation
-- is the core of the gap analysis: completeness can pass while
-- matchability fails.
-- ============================================================================
SELECT 'zip_code' AS field,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE zip_code IS NOT NULL AND zip_code <> ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE zip_code IS NOT NULL AND zip_code <> '') / COUNT(*), 1)
FROM audience_feed
UNION ALL
SELECT 'product_category', COUNT(*),
    COUNT(*) FILTER (WHERE product_category IS NOT NULL AND product_category <> ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE product_category IS NOT NULL AND product_category <> '') / COUNT(*), 1)
FROM audience_feed
UNION ALL
SELECT 'last_activity_date', COUNT(*),
    COUNT(last_activity_date),
    ROUND(100.0 * COUNT(last_activity_date) / COUNT(*), 1)
FROM audience_feed
UNION ALL
SELECT 'engagement_score', COUNT(*),
    COUNT(engagement_score),
    ROUND(100.0 * COUNT(engagement_score) / COUNT(*), 1)
FROM audience_feed;

-- ============================================================================
-- C. IDENTIFIER QUALITY
-- ============================================================================

-- C1. Email validity across the full customer base (deduped)
SELECT
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE email IS NULL OR email = '') AS missing_email,
    ROUND(100.0 * COUNT(*) FILTER (WHERE email IS NULL OR email = '') / COUNT(*), 1) AS missing_pct,
    COUNT(*) FILTER (WHERE email IS NOT NULL AND email <> ''
                     AND NOT regexp_matches(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')) AS invalid_email,
    ROUND(100.0 * COUNT(*) FILTER (WHERE email IS NOT NULL AND email <> ''
                     AND NOT regexp_matches(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')) / COUNT(*), 1) AS invalid_pct,
    COUNT(*) FILTER (WHERE email IS NOT NULL AND email <> ''
                     AND regexp_matches(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')) AS valid_email,
    COUNT(*) FILTER (WHERE hashed_email IS NOT NULL AND hashed_email <> '') AS with_hashed_email
FROM deduped_customers;

-- C2. Hashed-email coverage inside the final feed (= matchability input)
SELECT
    COUNT(*) AS feed_rows,
    COUNT(*) FILTER (WHERE hashed_email IS NOT NULL AND hashed_email <> '') AS with_hash,
    ROUND(100.0 * COUNT(*) FILTER (WHERE hashed_email IS NOT NULL AND hashed_email <> '') / COUNT(*), 1) AS hash_coverage_pct,
    COUNT(*) FILTER (WHERE hashed_email IS NULL OR hashed_email = '') AS missing_hash
FROM audience_feed;

-- C3. Duplicate identifier check (raw customers table, pre-dedupe)
SELECT
    customer_id,
    COUNT(*) AS occurrences
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;

-- ============================================================================
-- D. DATA-QUALITY CHECKS — each of these should return 0 rows / 0
-- ============================================================================

-- D1. Opt-out leakage: opted-out customers must NEVER appear in the feed
SELECT COUNT(*) AS opted_out_in_feed
FROM audience_feed f
JOIN deduped_customers dc ON dc.customer_id = f.customer_id
WHERE dc.opt_out_flag = 1;

-- D2. Null delivery-required fields in the final feed
-- (hashed_email excluded here: it is a matchability input, measured in E)
SELECT COUNT(*) AS rows_with_null_required_fields
FROM audience_feed
WHERE zip_code IS NULL OR zip_code = ''
   OR product_category IS NULL
   OR last_activity_date IS NULL
   OR engagement_score IS NULL;

-- D3. Duplicate customer_ids in the final feed
SELECT customer_id, COUNT(*) AS occurrences
FROM audience_feed
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- D4. Invalid or future event dates in the source events table
SELECT
    COUNT(*) FILTER (WHERE event_date > DATE '2026-09-21') AS future_dated_events,
    COUNT(*) FILTER (WHERE event_date < DATE '2026-06-23') AS outdated_events,
    COUNT(*) FILTER (WHERE event_date IS NULL)             AS null_dated_events
FROM events;

-- D5. Orphaned records: events/orders pointing at unknown customers/products
SELECT
    (SELECT COUNT(*) FROM events e
     LEFT JOIN deduped_customers dc ON dc.customer_id = e.customer_id
     WHERE e.customer_id IS NULL OR e.customer_id = '' OR dc.customer_id IS NULL) AS events_orphaned_customer,
    (SELECT COUNT(*) FROM events e
     LEFT JOIN products p ON p.product_id = e.product_id
     WHERE p.product_id IS NULL) AS events_unknown_product,
    (SELECT COUNT(*) FROM orders o
     LEFT JOIN deduped_customers dc ON dc.customer_id = o.customer_id
     WHERE o.customer_id IS NULL OR o.customer_id = '' OR dc.customer_id IS NULL) AS orders_orphaned_customer,
    (SELECT COUNT(*) FROM orders o
     LEFT JOIN products p ON p.product_id = o.product_id
     WHERE p.product_id IS NULL) AS orders_unknown_product;

-- D6. Events with missing customer_id (unattributable engagement)
SELECT COUNT(*) AS events_missing_customer_id
FROM events
WHERE customer_id IS NULL OR customer_id = '';

-- ============================================================================
-- E. EXPECTED VS. ACTUAL MATCHABILITY
-- Target: >= 70% of feed rows matchable (valid email + hashed email present)
-- ============================================================================
WITH m AS (
    SELECT
        COUNT(*) AS feed_rows,
        COUNT(*) FILTER (
            WHERE email IS NOT NULL AND email <> ''
              AND regexp_matches(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
              AND hashed_email IS NOT NULL AND hashed_email <> ''
        ) AS matchable_rows
    FROM audience_feed
)
SELECT
    70.0 AS target_matchability_pct,
    ROUND(100.0 * matchable_rows / feed_rows, 1) AS actual_matchability_pct,
    feed_rows,
    matchable_rows,
    feed_rows - matchable_rows AS unmatchable_rows,
    CASE
        WHEN 100.0 * matchable_rows / feed_rows >= 70.0 THEN 'PASS'
        ELSE 'FAIL — see diagnosis below'
    END AS verdict
FROM m;

-- E2. Diagnosis: why is matchability below target?
-- (Rows are in the feed with a valid email but no hashed email.)
SELECT
    COUNT(*) AS feed_rows_missing_hash,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM audience_feed), 1) AS pct_of_feed
FROM audience_feed
WHERE hashed_email IS NULL OR hashed_email = '';
