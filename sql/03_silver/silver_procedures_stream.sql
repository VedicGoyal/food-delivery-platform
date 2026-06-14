USE SCHEMA FOOD_PLATFORM.SILVER;

-- ─────────────────────────────────────────────────────
-- INCREMENTAL: SP_CLEAN_ORDERS_INCR
-- Reads from STREAM (only new Bronze rows)
-- Used by Tasks — not for manual backfill
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_ORDERS_INCR()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    null_count     INTEGER DEFAULT 0;
    amount_count   INTEGER DEFAULT 0;
    status_count   INTEGER DEFAULT 0;
    source_count   INTEGER DEFAULT 0;
    orphan_count   INTEGER DEFAULT 0;
    valid_count    INTEGER DEFAULT 0;
BEGIN
    -- BEGIN TRANSACTION: all steps read the SAME stream snapshot
    -- Stream offset only advances on COMMIT
    BEGIN TRANSACTION;

    -- Step A: Null mandatory fields
    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_ORDERS',
        CASE
            WHEN order_id        IS NULL THEN 'NULL_ORDER_ID'
            WHEN customer_id     IS NULL THEN 'NULL_CUSTOMER_ID'
            WHEN order_placed_at IS NULL THEN 'NULL_TIMESTAMP'
        END,
        OBJECT_CONSTRUCT(
            'order_id', order_id, 'customer_id', customer_id,
            'order_status', order_status, 'total_amount', total_amount,
            'order_placed_at', order_placed_at, '_file_name', _file_name
        ),
        'SP_CLEAN_ORDERS_INCR'
    FROM BRONZE.STREAM_RAW_ORDERS  -- ← reads from stream, not base table
    WHERE order_id IS NULL OR customer_id IS NULL OR order_placed_at IS NULL;
    null_count := SQLROWCOUNT;

    -- Step B: Invalid amounts
    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_ORDERS', 'INVALID_AMOUNT',
        OBJECT_CONSTRUCT(
            'order_id', order_id,
            'total_amount', total_amount,
            'delivery_fee', delivery_fee,
            '_file_name', _file_name
        ),
        'SP_CLEAN_ORDERS_INCR'
    FROM BRONZE.STREAM_RAW_ORDERS
    WHERE order_id IS NOT NULL AND customer_id IS NOT NULL AND order_placed_at IS NOT NULL
      AND (
          TRY_TO_NUMBER(total_amount) IS NULL
          OR TRY_TO_NUMBER(total_amount) <= 0
          OR (delivery_fee IS NOT NULL AND TRY_TO_NUMBER(delivery_fee) < 0)
      );
    amount_count := SQLROWCOUNT;

    -- Step C: Invalid status
    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_ORDERS', 'INVALID_STATUS',
        OBJECT_CONSTRUCT('order_id', order_id, 'order_status', order_status),
        'SP_CLEAN_ORDERS_INCR'
    FROM BRONZE.STREAM_RAW_ORDERS
    WHERE order_id IS NOT NULL AND customer_id IS NOT NULL AND order_placed_at IS NOT NULL
      AND TRY_TO_NUMBER(total_amount) > 0
      AND (delivery_fee IS NULL OR TRY_TO_NUMBER(delivery_fee) >= 0)
      AND (order_status IS NULL OR order_status NOT IN (
          'DELIVERED','CANCELLED','FAILED','PENDING'));
    status_count := SQLROWCOUNT;

    -- Step D: Invalid source
    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_ORDERS', 'INVALID_ORDER_SOURCE',
        OBJECT_CONSTRUCT('order_id', order_id, 'order_source', order_source),
        'SP_CLEAN_ORDERS_INCR'
    FROM BRONZE.STREAM_RAW_ORDERS
    WHERE order_id IS NOT NULL AND customer_id IS NOT NULL AND order_placed_at IS NOT NULL
      AND TRY_TO_NUMBER(total_amount) > 0
      AND (delivery_fee IS NULL OR TRY_TO_NUMBER(delivery_fee) >= 0)
      AND order_status IN ('DELIVERED','CANCELLED','FAILED','PENDING')
      AND (order_source IS NULL OR order_source NOT IN ('APP','WEBSITE','PHONE'));
    source_count := SQLROWCOUNT;

    -- Step E: Orphan FKs
    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_ORDERS', 'ORPHAN_FOREIGN_KEY',
        OBJECT_CONSTRUCT(
            'order_id', order_id,
            'customer_id', customer_id,
            'restaurant_id', restaurant_id,
            'agent_id', agent_id
        ),
        'SP_CLEAN_ORDERS_INCR'
    FROM BRONZE.STREAM_RAW_ORDERS
    WHERE order_id IS NOT NULL AND customer_id IS NOT NULL AND order_placed_at IS NOT NULL
      AND TRY_TO_NUMBER(total_amount) > 0
      AND (delivery_fee IS NULL OR TRY_TO_NUMBER(delivery_fee) >= 0)
      AND order_status IN ('DELIVERED','CANCELLED','FAILED','PENDING')
      AND order_source IN ('APP','WEBSITE','PHONE')
      AND (customer_id LIKE '%INVALID%' OR restaurant_id LIKE '%INVALID%'
           OR agent_id LIKE '%INVALID%');
    orphan_count := SQLROWCOUNT;

    -- Step F: Valid rows → Silver
    INSERT INTO SILVER.CLEAN_ORDERS
    SELECT
        order_id, customer_id, restaurant_id, agent_id,
        TRY_TO_TIMESTAMP_NTZ(order_placed_at,   'YYYY-MM-DD HH24:MI:SS'),
        TRY_TO_TIMESTAMP_NTZ(order_accepted_at,  'YYYY-MM-DD HH24:MI:SS'),
        TRY_TO_TIMESTAMP_NTZ(order_delivered_at, 'YYYY-MM-DD HH24:MI:SS'),
        order_status,
        TRY_TO_NUMBER(total_amount,   10, 2),
        COALESCE(TRY_TO_NUMBER(discount_amount, 10, 2), 0),
        COALESCE(TRY_TO_NUMBER(delivery_fee,    10, 2), 0),
        COALESCE(TRY_TO_NUMBER(tax_amount,      10, 2), 0),
        TRY_TO_NUMBER(final_amount,   10, 2),
        TRY_TO_NUMBER(delivery_distance_km,     8, 2),
        TRY_TO_NUMBER(estimated_delivery_time),
        TRY_TO_NUMBER(actual_delivery_time),
        delivery_city, delivery_pincode, order_source, promo_code,
        _loaded_at, _source, _file_name
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY order_id ORDER BY _loaded_at DESC
               ) AS rn
        FROM BRONZE.STREAM_RAW_ORDERS
        WHERE order_id IS NOT NULL AND customer_id IS NOT NULL
          AND order_placed_at IS NOT NULL
          AND TRY_TO_NUMBER(total_amount) > 0
          AND (delivery_fee IS NULL OR TRY_TO_NUMBER(delivery_fee) >= 0)
          AND order_status IN ('DELIVERED','CANCELLED','FAILED','PENDING')
          AND order_source IN ('APP','WEBSITE','PHONE')
          AND customer_id   NOT LIKE '%INVALID%'
          AND restaurant_id NOT LIKE '%INVALID%'
          AND agent_id      NOT LIKE '%INVALID%'
    ) WHERE rn = 1;
    valid_count := SQLROWCOUNT;

    COMMIT;  -- stream offset advances HERE, only after all steps complete

    RETURN 'Orders → nulls:' || null_count || ' amounts:' || amount_count ||
           ' status:' || status_count || ' source:' || source_count ||
           ' orphan:' || orphan_count || ' to_silver:' || valid_count;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;  -- if anything fails, stream offset stays unchanged → retry next run
        RETURN 'ERROR: ' || SQLERRM;
END;
$$;


-- ─────────────────────────────────────────────────────
-- INCREMENTAL: SP_CLEAN_ORDER_ITEMS_INCR
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_ORDER_ITEMS_INCR()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    invalid_count INTEGER DEFAULT 0;
    valid_count   INTEGER DEFAULT 0;
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_ORDER_ITEMS',
        CASE
            WHEN order_item_id IS NULL THEN 'NULL_ITEM_ID'
            WHEN order_id      IS NULL THEN 'NULL_ORDER_ID'
            WHEN TRY_TO_NUMBER(quantity)   IS NULL
              OR TRY_TO_NUMBER(quantity)   <= 0 THEN 'INVALID_QUANTITY'
            WHEN TRY_TO_NUMBER(unit_price) IS NULL
              OR TRY_TO_NUMBER(unit_price) <= 0 THEN 'INVALID_PRICE'
        END,
        OBJECT_CONSTRUCT(
            'order_item_id', order_item_id, 'order_id', order_id,
            'quantity', quantity, 'unit_price', unit_price
        ),
        'SP_CLEAN_ORDER_ITEMS_INCR'
    FROM BRONZE.STREAM_RAW_ORDER_ITEMS
    WHERE order_item_id IS NULL OR order_id IS NULL
       OR TRY_TO_NUMBER(quantity)   IS NULL OR TRY_TO_NUMBER(quantity)   <= 0
       OR TRY_TO_NUMBER(unit_price) IS NULL OR TRY_TO_NUMBER(unit_price) <= 0;
    invalid_count := SQLROWCOUNT;

    INSERT INTO SILVER.CLEAN_ORDER_ITEMS
    SELECT
        order_item_id, order_id, item_name, category,
        TRY_TO_NUMBER(quantity)::NUMBER,
        TRY_TO_NUMBER(unit_price, 10, 2),
        COALESCE(TRY_TO_NUMBER(total_price, 10, 2),
                 TRY_TO_NUMBER(unit_price, 10, 2) * TRY_TO_NUMBER(quantity)),
        CASE UPPER(TRIM(is_veg))
            WHEN 'TRUE' THEN TRUE WHEN 'FALSE' THEN FALSE
            WHEN 'Y'    THEN TRUE WHEN 'N'     THEN FALSE
            ELSE NULL END,
        _loaded_at, _source, _file_name
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY order_item_id ORDER BY _loaded_at DESC
               ) AS rn
        FROM BRONZE.STREAM_RAW_ORDER_ITEMS
        WHERE order_item_id IS NOT NULL AND order_id IS NOT NULL
          AND TRY_TO_NUMBER(quantity) > 0 AND TRY_TO_NUMBER(unit_price) > 0
    ) WHERE rn = 1;
    valid_count := SQLROWCOUNT;

    COMMIT;
    RETURN 'Items → invalid:' || invalid_count || ' to_silver:' || valid_count;
EXCEPTION
    WHEN OTHER THEN ROLLBACK; RETURN 'ERROR: ' || SQLERRM;
END;
$$;


-- ─────────────────────────────────────────────────────
-- INCREMENTAL: SP_CLEAN_CUSTOMERS_INCR
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_CUSTOMERS_INCR()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    invalid_count INTEGER DEFAULT 0;
    valid_count   INTEGER DEFAULT 0;
BEGIN
    BEGIN TRANSACTION;

    -- Null customer_id
    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_CUSTOMERS', 'NULL_CUSTOMER_ID',
        OBJECT_CONSTRUCT('customer_id', customer_id, 'email', email),
        'SP_CLEAN_CUSTOMERS_INCR'
    FROM BRONZE.STREAM_RAW_CUSTOMERS
    WHERE customer_id IS NULL;

    -- Null or invalid email
    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_CUSTOMERS',
        CASE WHEN email IS NULL THEN 'NULL_EMAIL' ELSE 'INVALID_EMAIL' END,
        OBJECT_CONSTRUCT('customer_id', customer_id, 'email', email),
        'SP_CLEAN_CUSTOMERS_INCR'
    FROM BRONZE.STREAM_RAW_CUSTOMERS
    WHERE customer_id IS NOT NULL
      AND (email IS NULL
           OR NOT REGEXP_LIKE(email, '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'));

    -- Invalid segment
    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_CUSTOMERS', 'INVALID_SEGMENT',
        OBJECT_CONSTRUCT('customer_id', customer_id,
                         'customer_segment', customer_segment),
        'SP_CLEAN_CUSTOMERS_INCR'
    FROM BRONZE.STREAM_RAW_CUSTOMERS
    WHERE customer_id IS NOT NULL
      AND REGEXP_LIKE(email, '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$')
      AND (customer_segment IS NULL
           OR customer_segment NOT IN ('NEW','REGULAR','PREMIUM','CHURNED'));
    invalid_count := SQLROWCOUNT;

    INSERT INTO SILVER.CLEAN_CUSTOMERS
    SELECT
        customer_id, first_name, last_name, email, phone_number,
        TRY_TO_DATE(date_of_birth, 'YYYY-MM-DD'),
        gender, address_line1, city, state, pincode,
        TRY_TO_DATE(signup_date, 'YYYY-MM-DD'),
        customer_segment,
        CASE UPPER(TRIM(is_active))
            WHEN 'TRUE'  THEN TRUE  WHEN 'FALSE' THEN FALSE
            WHEN '1'     THEN TRUE  WHEN '0'     THEN FALSE ELSE NULL END,
        TRY_TO_DATE(last_order_date, 'YYYY-MM-DD'),
        TRY_TO_TIMESTAMP_NTZ(updated_at, 'YYYY-MM-DD HH24:MI:SS'),
        _loaded_at, _source, _file_name
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY customer_id ORDER BY updated_at DESC NULLS LAST
               ) AS rn
        FROM BRONZE.STREAM_RAW_CUSTOMERS
        WHERE customer_id IS NOT NULL
          AND REGEXP_LIKE(email, '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$')
          AND customer_segment IN ('NEW','REGULAR','PREMIUM','CHURNED')
    ) WHERE rn = 1;
    valid_count := SQLROWCOUNT;

    COMMIT;
    RETURN 'Customers → invalid:' || invalid_count || ' to_silver:' || valid_count;
EXCEPTION
    WHEN OTHER THEN ROLLBACK; RETURN 'ERROR: ' || SQLERRM;
END;
$$;


-- ─────────────────────────────────────────────────────
-- INCREMENTAL: SP_CLEAN_RESTAURANTS_INCR
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_RESTAURANTS_INCR()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    invalid_count INTEGER DEFAULT 0;
    valid_count   INTEGER DEFAULT 0;
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_RESTAURANTS',
        CASE
            WHEN raw_json:restaurant_id::VARCHAR IS NULL THEN 'NULL_RESTAURANT_ID'
            WHEN TRY_TO_NUMBER(raw_json:rating::VARCHAR) IS NULL THEN 'INVALID_RATING_FORMAT'
            ELSE 'RATING_OUT_OF_RANGE'
        END,
        raw_json, 'SP_CLEAN_RESTAURANTS_INCR'
    FROM BRONZE.STREAM_RAW_RESTAURANTS
    WHERE raw_json:restaurant_id::VARCHAR IS NULL
       OR TRY_TO_NUMBER(raw_json:rating::VARCHAR) IS NULL
       OR TRY_TO_NUMBER(raw_json:rating::VARCHAR) NOT BETWEEN 0 AND 5;

    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_RESTAURANTS', 'NEGATIVE_COMMISSION',
        raw_json, 'SP_CLEAN_RESTAURANTS_INCR'
    FROM BRONZE.STREAM_RAW_RESTAURANTS
    WHERE raw_json:restaurant_id::VARCHAR IS NOT NULL
      AND TRY_TO_NUMBER(raw_json:rating::VARCHAR) BETWEEN 0 AND 5
      AND TRY_TO_NUMBER(raw_json:commission_rate::VARCHAR) < 0;

    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_RESTAURANTS', 'NEGATIVE_PREP_TIME',
        raw_json, 'SP_CLEAN_RESTAURANTS_INCR'
    FROM BRONZE.STREAM_RAW_RESTAURANTS
    WHERE raw_json:restaurant_id::VARCHAR IS NOT NULL
      AND TRY_TO_NUMBER(raw_json:rating::VARCHAR) BETWEEN 0 AND 5
      AND (raw_json:commission_rate::VARCHAR IS NULL
           OR TRY_TO_NUMBER(raw_json:commission_rate::VARCHAR) >= 0)
      AND TRY_TO_NUMBER(raw_json:average_prep_time::VARCHAR) < 0;
    invalid_count := SQLROWCOUNT;

    INSERT INTO SILVER.CLEAN_RESTAURANTS
    SELECT
        raw_json:restaurant_id::VARCHAR,
        raw_json:restaurant_name::VARCHAR,
        raw_json:cuisine_type::VARCHAR,
        raw_json:city::VARCHAR,
        raw_json:state::VARCHAR,
        raw_json:pincode::VARCHAR,
        TRY_TO_NUMBER(raw_json:rating::VARCHAR, 3, 1),
        TRY_TO_NUMBER(raw_json:average_prep_time::VARCHAR),
        TRY_TO_NUMBER(raw_json:commission_rate::VARCHAR, 5, 2),
        raw_json:opening_time::VARCHAR,
        raw_json:closing_time::VARCHAR,
        CASE LOWER(raw_json:is_active::VARCHAR)
            WHEN 'true' THEN TRUE WHEN 'false' THEN FALSE ELSE NULL END,
        TRY_TO_TIMESTAMP_NTZ(
            raw_json:updated_at::VARCHAR, 'YYYY-MM-DD HH24:MI:SS'),
        _loaded_at, _source, _file_name
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY raw_json:restaurant_id::VARCHAR
                   ORDER BY _loaded_at DESC
               ) AS rn
        FROM BRONZE.STREAM_RAW_RESTAURANTS
        WHERE raw_json:restaurant_id::VARCHAR IS NOT NULL
          AND TRY_TO_NUMBER(raw_json:rating::VARCHAR) BETWEEN 0 AND 5
          AND (raw_json:commission_rate::VARCHAR IS NULL
               OR TRY_TO_NUMBER(raw_json:commission_rate::VARCHAR) >= 0)
          AND (raw_json:average_prep_time::VARCHAR IS NULL
               OR TRY_TO_NUMBER(raw_json:average_prep_time::VARCHAR) >= 0)
    ) WHERE rn = 1;
    valid_count := SQLROWCOUNT;

    COMMIT;
    RETURN 'Restaurants → invalid:' || invalid_count || ' to_silver:' || valid_count;
EXCEPTION
    WHEN OTHER THEN ROLLBACK; RETURN 'ERROR: ' || SQLERRM;
END;
$$;


-- ─────────────────────────────────────────────────────
-- INCREMENTAL: SP_CLEAN_AGENTS_INCR
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_AGENTS_INCR()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    invalid_count INTEGER DEFAULT 0;
    valid_count   INTEGER DEFAULT 0;
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_AGENTS',
        CASE
            WHEN agent_id IS NULL THEN 'NULL_AGENT_ID'
            WHEN TRY_TO_NUMBER(agent_rating) IS NULL THEN 'INVALID_RATING_FORMAT'
            WHEN TRY_TO_NUMBER(agent_rating) NOT BETWEEN 0 AND 5 THEN 'RATING_OUT_OF_RANGE'
            WHEN vehicle_type IS NULL
              OR vehicle_type NOT IN ('BIKE','SCOOTER','CYCLE') THEN 'INVALID_VEHICLE_TYPE'
            ELSE 'INVALID_AVAILABILITY_STATUS'
        END,
        OBJECT_CONSTRUCT(
            'agent_id', agent_id, 'agent_rating', agent_rating,
            'vehicle_type', vehicle_type,
            'availability_status', availability_status
        ),
        'SP_CLEAN_AGENTS_INCR'
    FROM BRONZE.STREAM_RAW_AGENTS
    WHERE agent_id IS NULL
       OR TRY_TO_NUMBER(agent_rating) IS NULL
       OR TRY_TO_NUMBER(agent_rating) NOT BETWEEN 0 AND 5
       OR vehicle_type IS NULL OR vehicle_type NOT IN ('BIKE','SCOOTER','CYCLE')
       OR availability_status IS NULL
       OR availability_status NOT IN ('ONLINE','OFFLINE','BUSY');
    invalid_count := SQLROWCOUNT;

    INSERT INTO SILVER.CLEAN_AGENTS
    SELECT
        agent_id, agent_name, phone_number, city, vehicle_type,
        TRY_TO_DATE(joining_date, 'YYYY-MM-DD'),
        TRY_TO_NUMBER(agent_rating, 3, 1),
        availability_status,
        TRY_TO_TIMESTAMP_NTZ(updated_at, 'YYYY-MM-DD HH24:MI:SS'),
        _loaded_at, _source, _file_name
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY agent_id ORDER BY updated_at DESC NULLS LAST
               ) AS rn
        FROM BRONZE.STREAM_RAW_AGENTS
        WHERE agent_id IS NOT NULL
          AND TRY_TO_NUMBER(agent_rating) BETWEEN 0 AND 5
          AND vehicle_type IN ('BIKE','SCOOTER','CYCLE')
          AND availability_status IN ('ONLINE','OFFLINE','BUSY')
    ) WHERE rn = 1;
    valid_count := SQLROWCOUNT;

    COMMIT;
    RETURN 'Agents → invalid:' || invalid_count || ' to_silver:' || valid_count;
EXCEPTION
    WHEN OTHER THEN ROLLBACK; RETURN 'ERROR: ' || SQLERRM;
END;
$$;


-- ─────────────────────────────────────────────────────
-- INCREMENTAL: SP_CLEAN_PAYMENTS_INCR
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_PAYMENTS_INCR()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    invalid_count INTEGER DEFAULT 0;
    valid_count   INTEGER DEFAULT 0;
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
        source_table, rejection_reason, raw_record, rejected_by
    )
    SELECT 'RAW_PAYMENTS',
        CASE
            WHEN payment_id        IS NULL THEN 'NULL_PAYMENT_ID'
            WHEN payment_timestamp IS NULL THEN 'NULL_TIMESTAMP'
            WHEN TRY_TO_NUMBER(amount) IS NULL
              OR TRY_TO_NUMBER(amount) <= 0   THEN 'INVALID_AMOUNT'
            WHEN payment_method IS NULL
              OR payment_method NOT IN ('UPI','CARD','CASH','WALLET')
                                              THEN 'INVALID_PAYMENT_METHOD'
            WHEN payment_status IS NULL
              OR payment_status NOT IN ('SUCCESS','FAILED','PENDING','REFUNDED')
                                              THEN 'INVALID_PAYMENT_STATUS'
            ELSE 'ORPHAN_ORDER_ID'
        END,
        OBJECT_CONSTRUCT(
            'payment_id', payment_id, 'order_id', order_id,
            'amount', amount, 'payment_method', payment_method,
            'payment_status', payment_status
        ),
        'SP_CLEAN_PAYMENTS_INCR'
    FROM BRONZE.STREAM_RAW_PAYMENTS
    WHERE payment_id IS NULL OR payment_timestamp IS NULL
       OR TRY_TO_NUMBER(amount) IS NULL OR TRY_TO_NUMBER(amount) <= 0
       OR payment_method IS NULL
       OR payment_method NOT IN ('UPI','CARD','CASH','WALLET')
       OR payment_status IS NULL
       OR payment_status NOT IN ('SUCCESS','FAILED','PENDING','REFUNDED')
       OR order_id LIKE '%INVALID%';
    invalid_count := SQLROWCOUNT;

    INSERT INTO SILVER.CLEAN_PAYMENTS
    SELECT
        payment_id, order_id,
        TRY_TO_NUMBER(amount, 10, 2),
        payment_method, payment_gateway, payment_status,
        TRY_TO_TIMESTAMP_NTZ(payment_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
        refund_status,
        TRY_TO_NUMBER(refund_amount, 10, 2),
        card_last4,
        _loaded_at, _source, _file_name
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY payment_id ORDER BY _loaded_at DESC
               ) AS rn
        FROM BRONZE.STREAM_RAW_PAYMENTS
        WHERE payment_id IS NOT NULL AND payment_timestamp IS NOT NULL
          AND TRY_TO_NUMBER(amount) > 0
          AND payment_method IN ('UPI','CARD','CASH','WALLET')
          AND payment_status IN ('SUCCESS','FAILED','PENDING','REFUNDED')
          AND order_id NOT LIKE '%INVALID%'
    ) WHERE rn = 1;
    valid_count := SQLROWCOUNT;

    COMMIT;
    RETURN 'Payments → invalid:' || invalid_count || ' to_silver:' || valid_count;
EXCEPTION
    WHEN OTHER THEN ROLLBACK; RETURN 'ERROR: ' || SQLERRM;
END;
$$;