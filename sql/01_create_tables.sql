-- ============================================================================
-- 01_create_tables.sql
-- GlowBeauty Premium Skincare Audience Feed — table definitions
--
-- Run the DDL once, then load the CSVs with the COPY block for your engine:
--   DuckDB    : COPY <table> FROM '<path>' (HEADER, DELIMITER ',');
--   PostgreSQL: \copy <table> FROM '<path>' WITH (FORMAT csv, HEADER true);
--   Databricks: CREATE TABLE ... USING CSV OPTIONS (path '<path>', header 'true')
--               or spark.read.option("header","true").csv("<path>")
-- ============================================================================

DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id   VARCHAR     NOT NULL,
    email         VARCHAR,
    hashed_email  VARCHAR,      -- SHA-256 hex of lowercase email
    zip_code      VARCHAR,
    opt_out_flag  INTEGER       NOT NULL DEFAULT 0,  -- 1 = opted out of marketing
    created_date  DATE
);

DROP TABLE IF EXISTS events;
CREATE TABLE events (
    event_id     VARCHAR NOT NULL,
    customer_id  VARCHAR,       -- may be NULL/unknown (data-quality case)
    event_type   VARCHAR NOT NULL,  -- page_view | product_view | add_to_cart | purchase
    event_date   DATE    NOT NULL,
    product_id   VARCHAR,
    session_id   VARCHAR
);

DROP TABLE IF EXISTS products;
CREATE TABLE products (
    product_id    VARCHAR NOT NULL,
    product_name  VARCHAR NOT NULL,
    category      VARCHAR NOT NULL,  -- Skincare | Makeup | Fragrance | Haircare | Tools
    price         DECIMAL(10,2) NOT NULL,
    premium_flag  INTEGER NOT NULL DEFAULT 0   -- 1 = premium product
);

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id     VARCHAR NOT NULL,
    customer_id  VARCHAR,
    order_date   DATE    NOT NULL,
    order_value  DECIMAL(10,2) NOT NULL,
    product_id   VARCHAR
);

-- --------------------------------------------------------------------------
-- DuckDB load (run from the project root so relative paths resolve)
-- --------------------------------------------------------------------------
COPY customers FROM 'data/customers.csv' (HEADER, DELIMITER ',');
COPY events    FROM 'data/events.csv'    (HEADER, DELIMITER ',');
COPY products  FROM 'data/products.csv'  (HEADER, DELIMITER ',');
COPY orders    FROM 'data/orders.csv'    (HEADER, DELIMITER ',');

-- --------------------------------------------------------------------------
-- PostgreSQL equivalent (psql):
--   \copy customers FROM 'data/customers.csv' WITH (FORMAT csv, HEADER true);
--   \copy events    FROM 'data/events.csv'    WITH (FORMAT csv, HEADER true);
--   \copy products  FROM 'data/products.csv'  WITH (FORMAT csv, HEADER true);
--   \copy orders    FROM 'data/orders.csv'    WITH (FORMAT csv, HEADER true);
-- Databricks equivalent:
--   CREATE TABLE customers USING CSV OPTIONS (path 'data/customers.csv', header 'true', inferSchema 'true');
-- --------------------------------------------------------------------------
