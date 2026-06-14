USE ROLE SYSADMIN;
USE DATABASE FOOD_PLATFORM;
USE SCHEMA GOLD;
USE WAREHOUSE TRANSFORM_WH;

-- ─────────────────────────────────────────────────────
-- DIM_CUSTOMER (SCD Type 2)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS DIM_CUSTOMER (
    -- surrogate key (system generated, never from source)
    customer_sk         NUMBER        NOT NULL AUTOINCREMENT PRIMARY KEY,

    -- business key (from source system)
    customer_id         VARCHAR       NOT NULL,

    -- descriptive attributes
    first_name          VARCHAR,
    last_name           VARCHAR,
    email               VARCHAR,
    phone_number        VARCHAR,
    date_of_birth       DATE,
    gender              VARCHAR,
    address_line1       VARCHAR,
    city                VARCHAR,
    state               VARCHAR,
    pincode             VARCHAR,
    signup_date         DATE,
    customer_segment    VARCHAR,
    is_active           BOOLEAN,
    last_order_date     DATE,

    -- SCD Type 2 control columns
    effective_start_date TIMESTAMP_NTZ NOT NULL,
    effective_end_date   TIMESTAMP_NTZ,          -- NULL = currently active
    is_current           BOOLEAN       NOT NULL DEFAULT TRUE,

    -- metadata
    _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────
-- DIM_RESTAURANT (SCD Type 2)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS DIM_RESTAURANT (
    restaurant_sk       NUMBER        NOT NULL AUTOINCREMENT PRIMARY KEY,
    restaurant_id       VARCHAR       NOT NULL,
    restaurant_name     VARCHAR,
    cuisine_type        VARCHAR,
    city                VARCHAR,
    state               VARCHAR,
    pincode             VARCHAR,
    rating              NUMBER(3,1),
    average_prep_time   NUMBER,
    commission_rate     NUMBER(5,2),
    opening_time        VARCHAR,
    closing_time        VARCHAR,
    is_active           BOOLEAN,
    effective_start_date TIMESTAMP_NTZ NOT NULL,
    effective_end_date   TIMESTAMP_NTZ,
    is_current           BOOLEAN       NOT NULL DEFAULT TRUE,
    _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────
-- DIM_DELIVERY (delivery agents, SCD Type 2)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS DIM_DELIVERY (
    delivery_sk         NUMBER        NOT NULL AUTOINCREMENT PRIMARY KEY,
    agent_id            VARCHAR       NOT NULL,
    agent_name          VARCHAR,
    phone_number        VARCHAR,
    city                VARCHAR,
    vehicle_type        VARCHAR,
    agent_rating        NUMBER(3,1),
    availability_status VARCHAR,
    joining_date        DATE,
    effective_start_date TIMESTAMP_NTZ NOT NULL,
    effective_end_date   TIMESTAMP_NTZ,
    is_current           BOOLEAN       NOT NULL DEFAULT TRUE,
    _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────
-- DIM_DATE (static, no SCD — dates never change)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS DIM_DATE (
    date_sk     NUMBER        NOT NULL PRIMARY KEY,  -- YYYYMMDD integer
    full_date   DATE          NOT NULL,
    year        NUMBER,
    quarter     NUMBER,
    month       NUMBER,
    month_name  VARCHAR,
    week        NUMBER,
    day_of_week NUMBER,        -- 1=Monday ... 7=Sunday
    day_name    VARCHAR,
    hour        NUMBER,        -- 0–23
    is_weekend  BOOLEAN
);

SHOW TABLES IN SCHEMA FOOD_PLATFORM.GOLD;

-- ─────────────────────────────────────────────────────
-- FACT_ORDERS
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS FACT_ORDERS (
    order_sk                NUMBER    NOT NULL AUTOINCREMENT PRIMARY KEY,

    -- degenerate dimension (order_id kept for traceability)
    order_id                VARCHAR   NOT NULL,

    -- foreign keys to dimensions
    customer_sk             NUMBER    REFERENCES DIM_CUSTOMER(customer_sk),
    restaurant_sk           NUMBER    REFERENCES DIM_RESTAURANT(restaurant_sk),
    delivery_sk             NUMBER    REFERENCES DIM_DELIVERY(delivery_sk),
    date_sk                 NUMBER    REFERENCES DIM_DATE(date_sk),

    -- order timestamps
    order_placed_at         TIMESTAMP_NTZ,
    order_accepted_at       TIMESTAMP_NTZ,
    order_delivered_at      TIMESTAMP_NTZ,

    -- order attributes
    order_status            VARCHAR,
    order_source            VARCHAR,
    promo_code              VARCHAR,
    delivery_city           VARCHAR,
    delivery_pincode        VARCHAR,

    -- measures
    total_amount            NUMBER(10,2),
    discount_amount         NUMBER(10,2),
    delivery_fee            NUMBER(10,2),
    tax_amount              NUMBER(10,2),
    final_amount            NUMBER(10,2),
    delivery_distance_km    NUMBER(8,2),
    estimated_delivery_time NUMBER,
    actual_delivery_time    NUMBER,

    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────
-- FACT_PAYMENTS
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS FACT_PAYMENTS (
    payment_sk          NUMBER    NOT NULL AUTOINCREMENT PRIMARY KEY,
    payment_id          VARCHAR   NOT NULL,
    order_id            VARCHAR,

    -- foreign keys
    customer_sk         NUMBER    REFERENCES DIM_CUSTOMER(customer_sk),
    date_sk             NUMBER    REFERENCES DIM_DATE(date_sk),

    -- payment attributes
    payment_method      VARCHAR,
    payment_gateway     VARCHAR,
    payment_status      VARCHAR,
    payment_timestamp   TIMESTAMP_NTZ,
    refund_status       VARCHAR,

    -- measures
    amount              NUMBER(10,2),
    refund_amount       NUMBER(10,2),
    card_last4          VARCHAR,

    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────
-- Hourly KPIs — used directly by Streamlit dashboards
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS AGG_HOURLY_KPI (
    kpi_hour            TIMESTAMP_NTZ NOT NULL PRIMARY KEY,
    total_orders        NUMBER,
    delivered_orders    NUMBER,
    cancelled_orders    NUMBER,
    failed_orders       NUMBER,
    pending_orders      NUMBER,
    total_revenue       NUMBER(12,2),
    avg_order_value     NUMBER(10,2),
    order_success_rate  NUMBER(5,2),   -- % delivered
    failed_order_rate   NUMBER(5,2),   -- % failed
    avg_delivery_time   NUMBER(8,2),   -- minutes
    _refreshed_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────
-- City-level daily revenue
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS AGG_CITY_DAILY (
    report_date         DATE          NOT NULL,
    delivery_city       VARCHAR       NOT NULL,
    total_orders        NUMBER,
    total_revenue       NUMBER(12,2),
    avg_order_value     NUMBER(10,2),
    delivered_orders    NUMBER,
    failed_orders       NUMBER,
    PRIMARY KEY (report_date, delivery_city),
    _refreshed_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ─────────────────────────────────────────────────────
-- Payment method breakdown by day
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS AGG_PAYMENT_MIX (
    report_date         DATE          NOT NULL,
    payment_method      VARCHAR       NOT NULL,
    transaction_count   NUMBER,
    total_amount        NUMBER(12,2),
    success_count       NUMBER,
    failed_count        NUMBER,
    refund_count        NUMBER,
    PRIMARY KEY (report_date, payment_method),
    _refreshed_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

SHOW TABLES IN SCHEMA FOOD_PLATFORM.GOLD;

-- Generate one row per hour for 2024–2028
-- date_sk format: YYYYMMDDHH (e.g. 2026051310 = May 13 2026 10am)
INSERT INTO GOLD.DIM_DATE
SELECT
    TO_NUMBER(TO_CHAR(hour_ts, 'YYYYMMDDHH24'))  AS date_sk,
    DATE(hour_ts)                                AS full_date,
    YEAR(hour_ts)                                AS year,
    QUARTER(hour_ts)                             AS quarter,
    MONTH(hour_ts)                               AS month,
    MONTHNAME(hour_ts)                           AS month_name,
    WEEKOFYEAR(hour_ts)                          AS week,
    DAYOFWEEKISO(hour_ts)                        AS day_of_week,  -- 1=Mon 7=Sun
    DAYNAME(hour_ts)                             AS day_name,
    HOUR(hour_ts)                                AS hour,
    CASE WHEN DAYOFWEEKISO(hour_ts) IN (6,7)
         THEN TRUE ELSE FALSE END                AS is_weekend
FROM (
    SELECT DATEADD(HOUR, SEQ4(),
           '2024-01-01 00:00:00'::TIMESTAMP_NTZ) AS hour_ts
    FROM TABLE(GENERATOR(ROWCOUNT => 43824))     -- 5 years × 8766 hrs
)
WHERE hour_ts < '2029-01-01 00:00:00'::TIMESTAMP_NTZ;

-- Verify
SELECT COUNT(*) FROM GOLD.DIM_DATE;  -- should be ~43,824
SELECT * FROM GOLD.DIM_DATE LIMIT 5;