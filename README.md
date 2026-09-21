# GlowBeauty Premium Skincare — Customer Data Feed Evaluation

> **All data in this repository is synthetic.** Names, emails, addresses, and
> identifiers were randomly generated for demonstration purposes and do not
> correspond to real people. This is an independent, simulated case study of a
> customer-audience feed evaluation — it was not produced for or with any
> real company, and contains no real customer or ad-platform data.

## What this is

A mock "brand audience / feed evaluation" project demonstrating the end-to-end
workflow of scoping, building, validating, and communicating about a customer
data feed:

1. **Translate a business goal into data requirements** — a fictional
   e-commerce brand (GlowBeauty) wants a customer audience feed for a premium
   skincare campaign: reach likely buyers while maintaining data quality and
   matchability.
2. **Profile the feed with SQL** — build the audience, then validate coverage,
   field completeness, identifier quality, duplicates, opt-out handling, and
   orphaned records.
3. **Identify gaps** — the feed meets the 95% field-completeness bar but misses
   the 70% matchability target (actual: 58.8%), and the analysis diagnoses why.
4. **Explain tradeoffs** — a smaller high-matchability audience vs. a larger
   expanded audience, with a production monitoring plan.

## Repository structure

```
klickly-data-feed-evaluation/
├── README.md
├── data/
│   ├── customers.csv              # 306 rows (300 unique customers + 6 duplicate rows)
│   ├── events.csv                 # 500 engagement events
│   ├── products.csv               # 30 products (12 skincare, 7 premium)
│   ├── orders.csv                 # 150 orders
│   └── generate_synthetic_data.py # reproducible data generator (seed=42)
├── sql/
│   ├── 01_create_tables.sql       # DDL + load (DuckDB / PostgreSQL / Databricks notes)
│   ├── 02_build_audience_feed.sql # dedupe, engagement rollup, audience build
│   └── 03_data_quality_validation.sql  # coverage, completeness, identifiers, DQ checks
├── python/
│   └── feed_validation.py         # pandas-free stdlib validation: schema, nulls,
│                                  # dupes, email patterns, matchability; exports
│                                  # data_quality_summary.csv + cleaned feed
├── docs/
│   ├── feed_specification.pdf     # 1-page feed spec
│   └── evaluation_findings.pdf    # 6-page findings report
└── output/
    ├── glowbeauty_audience_feed.csv        # final audience feed (131 rows)
    ├── glowbeauty_audience_feed_clean.csv  # feed + matchable_flag + dq_notes
    └── data_quality_summary.csv            # validation metric table
```

## How to run

**DuckDB** (verified with DuckDB ≥ 1.0; run from the project root):

```sql
.read sql/01_create_tables.sql
.read sql/02_build_audience_feed.sql
.read sql/03_data_quality_validation.sql
COPY audience_feed TO 'output/glowbeauty_audience_feed.csv' (HEADER, DELIMITER ',');
```

**PostgreSQL**: run the DDL in `01_create_tables.sql`, then
`\copy <table> FROM 'data/<table>.csv' WITH (FORMAT csv, HEADER true);`
(`regexp_matches(...)` in `02`/`03` becomes `email ~ '<pattern>'`).

**Databricks**: `CREATE TABLE ... USING CSV OPTIONS (path 'data/...', header 'true')`
or `spark.read.option("header","true").csv("data/...")`, then run `02` and `03`.

**Python validation** (stdlib only — no pandas required):

```bash
python python/feed_validation.py
```

Exit code `0` = all checks pass, `2` = failed checks (details printed + written to
`output/data_quality_summary.csv`). In this dataset it exits `2` on purpose:
hashed-email coverage is 58.8% vs. the 70% target — the central finding.

Regenerate the synthetic data any time with:

```bash
python data/generate_synthetic_data.py
```

## Headline results (computed from the synthetic data, 90-day window ending 2026-09-21)

| Check | Result | Threshold | Status |
|---|---|---|---|
| Eligible (skincare engagement, in-window) | 166 customers | — | — |
| Excluded: opted out | 16 (9.6%) | must exclude all | ✅ 0 leaked |
| Excluded: missing/invalid email | 19 (11.4%) | must exclude all | ✅ |
| Final feed | 131 customers (78.9% of eligible) | — | — |
| Required-field completeness (ZIP, category, last activity, score) | 96.2–100% | ≥ 95% | ✅ PASS |
| Email validity in source base | 87.7% valid (7.7% missing, 4.7% invalid) | — | finding |
| Hashed-email coverage in feed | 58.8% (77/131) | ≥ 70% | ❌ FAIL |
| Duplicate customer_ids in feed | 0 (6 pairs resolved upstream) | 0 | ✅ PASS |
| Future-dated / outdated events | 4 / 31 | 0 in feed | ✅ excluded |
| Orphaned event records | 20 (10 missing customer_id, 10 unknown) | — | finding |

**Gap analysis in one line:** the feed meets completeness requirements but does
not meet the 70% matchability target, because 41.2% of feed rows were never
provisioned a hashed email upstream. See `docs/evaluation_findings.pdf` for the
full diagnosis, the high-matchability vs. expanded-audience tradeoff, and the
production monitoring plan.

## Intentionally injected quality problems

Missing emails · invalid email formats · duplicate customer_id rows · missing
ZIPs · events with missing/unknown customer_ids · orders tied to unknown
products · opted-out customers with recent engagement (correctly excluded) ·
outdated (>90d) and future-dated events · unprovisioned hashed emails.

## Interview framing

> After our conversation, I built a small simulated customer-feed evaluation to
> better understand this kind of work. I defined a brand's audience objective,
> translated it into feed requirements and validation criteria, used SQL to build
> and profile the audience, and analyzed identifier coverage, field completeness,
> duplicates, opt-out exclusions, and matchability gaps. I documented the
> tradeoff between a broader audience and a smaller, higher-matchability
> audience, plus a production monitoring plan. It reinforced that the role isn't
> only about delivering data — it's about setting realistic expectations and
> helping customers understand coverage, quality, and performance limitations.
