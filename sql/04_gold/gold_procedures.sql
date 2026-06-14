-- ─────────────────────────────────────────────────────
-- SCD2 PROCEDURE: DIM_CUSTOMER
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GOLD.SP_LOAD_DIM_CUSTOMER()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    -- Step 1: Close existing records where attributes have changed
    -- Compare Silver against current Gold version
    UPDATE GOLD.DIM_CUSTOMER dim
    SET
        effective_end_date = CURRENT_TIMESTAMP(),
        is_current         = FALSE
    FROM SILVER.CLEAN_CUSTOMERS src
    WHERE dim.customer_id  = src.customer_id
      AND dim.is_current   = TRUE
      -- detect any attribute change:
      AND (
          dim.email            <> src.email            OR
          dim.phone_number     <> src.phone_number     OR
          dim.address_line1    <> src.address_line1    OR
          dim.city             <> src.city             OR
          dim.customer_segment <> src.customer_segment OR
          dim.is_active        <> src.is_active        OR
          -- handle nulls in comparison
          (dim.email IS NULL AND src.email IS NOT NULL) OR
          (dim.city  IS NULL AND src.city  IS NOT NULL)
      );

    -- Step 2: Insert new versions of changed records
    -- AND insert brand new customers
    INSERT INTO GOLD.DIM_CUSTOMER (
        customer_id, first_name, last_name, email, phone_number,
        date_of_birth, gender, address_line1, city, state, pincode,
        signup_date, customer_segment, is_active, last_order_date,
        effective_start_date, effective_end_date, is_current
    )
    SELECT
        src.customer_id, src.first_name, src.last_name,
        src.email, src.phone_number, src.date_of_birth,
        src.gender, src.address_line1, src.city, src.state,
        src.pincode, src.signup_date, src.customer_segment,
        src.is_active, src.last_order_date,
        CURRENT_TIMESTAMP(),  -- effective_start_date
        NULL,                 -- effective_end_date (currently active)
        TRUE                  -- is_current
    FROM SILVER.CLEAN_CUSTOMERS src
    WHERE NOT EXISTS (
        -- skip if a current record already exists with same values
        SELECT 1 FROM GOLD.DIM_CUSTOMER dim
        WHERE dim.customer_id = src.customer_id
          AND dim.is_current  = TRUE
          AND dim.email            = src.email
          AND dim.customer_segment = src.customer_segment
          AND dim.is_active        = src.is_active
    );

    RETURN 'SP_LOAD_DIM_CUSTOMER completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- SCD2 PROCEDURE: DIM_RESTAURANT
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GOLD.SP_LOAD_DIM_RESTAURANT()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    -- Step 1: Close changed records
    UPDATE GOLD.DIM_RESTAURANT dim
    SET
        effective_end_date = CURRENT_TIMESTAMP(),
        is_current         = FALSE
    FROM SILVER.CLEAN_RESTAURANTS src
    WHERE dim.restaurant_id = src.restaurant_id
      AND dim.is_current    = TRUE
      AND (
          dim.restaurant_name  <> src.restaurant_name  OR
          dim.cuisine_type     <> src.cuisine_type     OR
          dim.city             <> src.city             OR
          dim.rating           <> src.rating           OR
          dim.commission_rate  <> src.commission_rate  OR
          dim.is_active        <> src.is_active        OR
          (dim.rating IS NULL AND src.rating IS NOT NULL)
      );

    -- Step 2: Insert new versions + new restaurants
    INSERT INTO GOLD.DIM_RESTAURANT (
        restaurant_id, restaurant_name, cuisine_type,
        city, state, pincode, rating, average_prep_time,
        commission_rate, opening_time, closing_time, is_active,
        effective_start_date, effective_end_date, is_current
    )
    SELECT
        src.restaurant_id, src.restaurant_name, src.cuisine_type,
        src.city, src.state, src.pincode, src.rating,
        src.average_prep_time, src.commission_rate,
        src.opening_time, src.closing_time, src.is_active,
        CURRENT_TIMESTAMP(), NULL, TRUE
    FROM SILVER.CLEAN_RESTAURANTS src
    WHERE NOT EXISTS (
        SELECT 1 FROM GOLD.DIM_RESTAURANT dim
        WHERE dim.restaurant_id  = src.restaurant_id
          AND dim.is_current     = TRUE
          AND dim.rating         = src.rating
          AND dim.is_active      = src.is_active
          AND dim.commission_rate= src.commission_rate
    );

    RETURN 'SP_LOAD_DIM_RESTAURANT completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- SCD2 PROCEDURE: DIM_DELIVERY
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GOLD.SP_LOAD_DIM_DELIVERY()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    -- Step 1: Close changed records
    UPDATE GOLD.DIM_DELIVERY dim
    SET
        effective_end_date = CURRENT_TIMESTAMP(),
        is_current         = FALSE
    FROM SILVER.CLEAN_AGENTS src
    WHERE dim.agent_id    = src.agent_id
      AND dim.is_current  = TRUE
      AND (
          dim.vehicle_type        <> src.vehicle_type        OR
          dim.agent_rating        <> src.agent_rating        OR
          dim.availability_status <> src.availability_status OR
          dim.city                <> src.city                OR
          (dim.agent_rating IS NULL AND src.agent_rating IS NOT NULL)
      );

    -- Step 2: Insert new versions + new agents
    INSERT INTO GOLD.DIM_DELIVERY (
        agent_id, agent_name, phone_number, city,
        vehicle_type, agent_rating, availability_status,
        joining_date, effective_start_date, effective_end_date, is_current
    )
    SELECT
        src.agent_id, src.agent_name, src.phone_number,
        src.city, src.vehicle_type, src.agent_rating,
        src.availability_status, src.joining_date,
        CURRENT_TIMESTAMP(), NULL, TRUE
    FROM SILVER.CLEAN_AGENTS src
    WHERE NOT EXISTS (
        SELECT 1 FROM GOLD.DIM_DELIVERY dim
        WHERE dim.agent_id            = src.agent_id
          AND dim.is_current          = TRUE
          AND dim.vehicle_type        = src.vehicle_type
          AND dim.availability_status = src.availability_status
    );

    RETURN 'SP_LOAD_DIM_DELIVERY completed';
END;
$$;

-- ─────────────────────────────────────────────────────
-- PROCEDURE: Load FACT_ORDERS
-- Joins Silver orders to dimension surrogate keys
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GOLD.SP_LOAD_FACT_ORDERS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    INSERT INTO GOLD.FACT_ORDERS (
        order_id, customer_sk, restaurant_sk, delivery_sk, date_sk,
        order_placed_at, order_accepted_at, order_delivered_at,
        order_status, order_source, promo_code,
        delivery_city, delivery_pincode,
        total_amount, discount_amount, delivery_fee,
        tax_amount, final_amount,
        delivery_distance_km, estimated_delivery_time, actual_delivery_time
    )
    SELECT
        o.order_id,
        c.customer_sk,
        r.restaurant_sk,
        d.delivery_sk,
        -- date_sk: YYYYMMDDHH from order_placed_at
        TO_NUMBER(TO_CHAR(o.order_placed_at, 'YYYYMMDDHH24')) AS date_sk,
        o.order_placed_at, o.order_accepted_at, o.order_delivered_at,
        o.order_status, o.order_source, o.promo_code,
        o.delivery_city, o.delivery_pincode,
        o.total_amount, o.discount_amount, o.delivery_fee,
        o.tax_amount, o.final_amount,
        o.delivery_distance_km, o.estimated_delivery_time, o.actual_delivery_time
    FROM SILVER.CLEAN_ORDERS o
    -- join to current dimension records only
    LEFT JOIN GOLD.DIM_CUSTOMER    c ON o.customer_id   = c.customer_id
                                    AND c.is_current = TRUE
    LEFT JOIN GOLD.DIM_RESTAURANT  r ON o.restaurant_id = r.restaurant_id
                                    AND r.is_current = TRUE
    LEFT JOIN GOLD.DIM_DELIVERY    d ON o.agent_id      = d.agent_id
                                    AND d.is_current = TRUE
    -- only load orders not already in FACT_ORDERS
    WHERE NOT EXISTS (
        SELECT 1 FROM GOLD.FACT_ORDERS f
        WHERE f.order_id = o.order_id
    );

    RETURN 'SP_LOAD_FACT_ORDERS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE: Load FACT_PAYMENTS
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GOLD.SP_LOAD_FACT_PAYMENTS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    INSERT INTO GOLD.FACT_PAYMENTS (
        payment_id, order_id, customer_sk, date_sk,
        payment_method, payment_gateway, payment_status,
        payment_timestamp, refund_status,
        amount, refund_amount, card_last4
    )
    SELECT
        p.payment_id, p.order_id,
        c.customer_sk,
        TO_NUMBER(TO_CHAR(p.payment_timestamp, 'YYYYMMDDHH24')) AS date_sk,
        p.payment_method, p.payment_gateway, p.payment_status,
        p.payment_timestamp, p.refund_status,
        p.amount, p.refund_amount, p.card_last4
    FROM SILVER.CLEAN_PAYMENTS p
    -- get customer_sk via order_id → FACT_ORDERS → customer_sk
    LEFT JOIN GOLD.FACT_ORDERS fo ON p.order_id = fo.order_id
    LEFT JOIN GOLD.DIM_CUSTOMER c  ON fo.customer_sk = c.customer_sk
                                  AND c.is_current = TRUE
    WHERE NOT EXISTS (
        SELECT 1 FROM GOLD.FACT_PAYMENTS f
        WHERE f.payment_id = p.payment_id
    );

    RETURN 'SP_LOAD_FACT_PAYMENTS completed';
END;
$$;

-- ─────────────────────────────────────────────────────
-- PROCEDURE: Hourly KPI aggregation
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GOLD.SP_AGG_HOURLY_KPI()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    -- Full refresh of hourly KPIs
    DELETE FROM GOLD.AGG_HOURLY_KPI;

    INSERT INTO GOLD.AGG_HOURLY_KPI (
        kpi_hour, total_orders, delivered_orders,
        cancelled_orders, failed_orders, pending_orders,
        total_revenue, avg_order_value,
        order_success_rate, failed_order_rate, avg_delivery_time
    )
    SELECT
        DATE_TRUNC('HOUR', order_placed_at)                AS kpi_hour,
        COUNT(*)                                           AS total_orders,
        COUNT(CASE WHEN order_status = 'DELIVERED' THEN 1 END) AS delivered_orders,
        COUNT(CASE WHEN order_status = 'CANCELLED' THEN 1 END) AS cancelled_orders,
        COUNT(CASE WHEN order_status = 'FAILED'    THEN 1 END) AS failed_orders,
        COUNT(CASE WHEN order_status = 'PENDING'   THEN 1 END) AS pending_orders,
        SUM(total_amount)                                  AS total_revenue,
        AVG(total_amount)                                  AS avg_order_value,
        ROUND(COUNT(CASE WHEN order_status = 'DELIVERED'
                    THEN 1 END) * 100.0 / COUNT(*), 2)    AS order_success_rate,
        ROUND(COUNT(CASE WHEN order_status = 'FAILED'
                    THEN 1 END) * 100.0 / COUNT(*), 2)    AS failed_order_rate,
        AVG(actual_delivery_time)                          AS avg_delivery_time
    FROM GOLD.FACT_ORDERS
    WHERE order_placed_at IS NOT NULL
      AND order_placed_at <= CURRENT_TIMESTAMP()   -- exclude future dates
    GROUP BY DATE_TRUNC('HOUR', order_placed_at);

    RETURN 'SP_AGG_HOURLY_KPI completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE: City daily aggregation
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GOLD.SP_AGG_CITY_DAILY()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    DELETE FROM GOLD.AGG_CITY_DAILY;

    INSERT INTO GOLD.AGG_CITY_DAILY (
        report_date, delivery_city, total_orders,
        total_revenue, avg_order_value,
        delivered_orders, failed_orders
    )
    SELECT
        DATE(order_placed_at)                              AS report_date,
        delivery_city,
        COUNT(*)                                           AS total_orders,
        SUM(total_amount)                                  AS total_revenue,
        AVG(total_amount)                                  AS avg_order_value,
        COUNT(CASE WHEN order_status = 'DELIVERED' THEN 1 END),
        COUNT(CASE WHEN order_status = 'FAILED'    THEN 1 END)
    FROM GOLD.FACT_ORDERS
    WHERE delivery_city IS NOT NULL
      AND order_placed_at IS NOT NULL
      AND order_placed_at <= CURRENT_TIMESTAMP()
    GROUP BY DATE(order_placed_at), delivery_city;

    RETURN 'SP_AGG_CITY_DAILY completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE: Payment method mix
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GOLD.SP_AGG_PAYMENT_MIX()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    DELETE FROM GOLD.AGG_PAYMENT_MIX;

    INSERT INTO GOLD.AGG_PAYMENT_MIX (
        report_date, payment_method, transaction_count,
        total_amount, success_count, failed_count, refund_count
    )
    SELECT
        DATE(payment_timestamp)                            AS report_date,
        payment_method,
        COUNT(*)                                           AS transaction_count,
        SUM(amount)                                        AS total_amount,
        COUNT(CASE WHEN payment_status = 'SUCCESS'   THEN 1 END),
        COUNT(CASE WHEN payment_status = 'FAILED'    THEN 1 END),
        COUNT(CASE WHEN payment_status = 'REFUNDED'  THEN 1 END)
    FROM GOLD.FACT_PAYMENTS
    WHERE payment_timestamp IS NOT NULL
    GROUP BY DATE(payment_timestamp), payment_method;

    RETURN 'SP_AGG_PAYMENT_MIX completed';
END;
$$;


USE WAREHOUSE TRANSFORM_WH;

-- 1. Load dimensions first (SCD Type 2)
CALL GOLD.SP_LOAD_DIM_CUSTOMER();
CALL GOLD.SP_LOAD_DIM_RESTAURANT();
CALL GOLD.SP_LOAD_DIM_DELIVERY();

-- 2. Load fact tables (need dimension SKs)
CALL GOLD.SP_LOAD_FACT_ORDERS();
CALL GOLD.SP_LOAD_FACT_PAYMENTS();

-- 3. Build aggregates (need fact tables)
CALL GOLD.SP_AGG_HOURLY_KPI();
CALL GOLD.SP_AGG_CITY_DAILY();
CALL GOLD.SP_AGG_PAYMENT_MIX();

-- Row counts for all Gold tables
SELECT 'DIM_CUSTOMER'     AS tbl, COUNT(*) AS records FROM GOLD.DIM_CUSTOMER
UNION ALL SELECT 'DIM_RESTAURANT',  COUNT(*) FROM GOLD.DIM_RESTAURANT
UNION ALL SELECT 'DIM_DELIVERY',    COUNT(*) FROM GOLD.DIM_DELIVERY
UNION ALL SELECT 'DIM_DATE',        COUNT(*) FROM GOLD.DIM_DATE
UNION ALL SELECT 'FACT_ORDERS',     COUNT(*) FROM GOLD.FACT_ORDERS
UNION ALL SELECT 'FACT_PAYMENTS',   COUNT(*) FROM GOLD.FACT_PAYMENTS
UNION ALL SELECT 'AGG_HOURLY_KPI',  COUNT(*) FROM GOLD.AGG_HOURLY_KPI
UNION ALL SELECT 'AGG_CITY_DAILY',  COUNT(*) FROM GOLD.AGG_CITY_DAILY
UNION ALL SELECT 'AGG_PAYMENT_MIX', COUNT(*) FROM GOLD.AGG_PAYMENT_MIX
ORDER BY tbl;

-- SCD Type 2 check: every customer should have exactly 1 current record
SELECT customer_id, COUNT(*) AS current_versions
FROM GOLD.DIM_CUSTOMER
WHERE is_current = TRUE
GROUP BY customer_id
HAVING COUNT(*) > 1;  -- should return 0 rows

-- Star Schema join test: fact + all 4 dimensions
SELECT
    o.order_id,
    c.customer_segment,
    r.cuisine_type,
    d.vehicle_type,
    dd.day_name,
    dd.is_weekend,
    o.total_amount,
    o.order_status
FROM GOLD.FACT_ORDERS o
LEFT JOIN GOLD.DIM_CUSTOMER   c  ON o.customer_sk   = c.customer_sk
LEFT JOIN GOLD.DIM_RESTAURANT r  ON o.restaurant_sk = r.restaurant_sk
LEFT JOIN GOLD.DIM_DELIVERY   d  ON o.delivery_sk   = d.delivery_sk
LEFT JOIN GOLD.DIM_DATE       dd ON o.date_sk        = dd.date_sk
LIMIT 10;

-- Key business query: revenue by city and cuisine
SELECT
    o.delivery_city,
    r.cuisine_type,
    COUNT(*)          AS total_orders,
    SUM(o.total_amount) AS revenue,
    AVG(o.total_amount) AS avg_order_value
FROM GOLD.FACT_ORDERS o
JOIN GOLD.DIM_RESTAURANT r ON o.restaurant_sk = r.restaurant_sk
WHERE o.order_status = 'DELIVERED'
  AND o.delivery_city IS NOT NULL
GROUP BY o.delivery_city, r.cuisine_type
ORDER BY revenue DESC
LIMIT 10;

-- Hourly KPI summary
SELECT
    kpi_hour,
    total_orders,
    total_revenue,
    order_success_rate,
    failed_order_rate,
    avg_delivery_time
FROM GOLD.AGG_HOURLY_KPI
ORDER BY kpi_hour;