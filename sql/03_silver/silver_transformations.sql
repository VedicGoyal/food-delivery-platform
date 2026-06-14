USE SCHEMA FOOD_PLATFORM.SILVER;

-- ─────────────────────────────────────────────────────
-- PROCEDURE 1: Clean Orders
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_ORDERS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Step A: Quarantine NULL mandatory fields
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT
      'RAW_ORDERS',
      CASE
          WHEN order_id   IS NULL THEN 'NULL_ORDER_ID'
          WHEN customer_id IS NULL THEN 'NULL_CUSTOMER_ID'
          WHEN order_placed_at IS NULL THEN 'NULL_TIMESTAMP'
      END,
      OBJECT_CONSTRUCT(
          'order_id',        order_id,
          'customer_id',     customer_id,
          'restaurant_id',   restaurant_id,
          'order_status',    order_status,
          'total_amount',    total_amount,
          'order_placed_at', order_placed_at,
          '_file_name',      _file_name
      ),
      'SP_CLEAN_ORDERS'
  FROM BRONZE.RAW_ORDERS
  WHERE order_id IS NULL
     OR customer_id IS NULL
     OR order_placed_at IS NULL;

  -- Step B: Quarantine invalid amounts
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT
      'RAW_ORDERS',
      'INVALID_AMOUNT',
      OBJECT_CONSTRUCT(
          'order_id',     order_id,
          'total_amount', total_amount,
          'delivery_fee', delivery_fee,
          '_file_name',   _file_name
      ),
      'SP_CLEAN_ORDERS'
  FROM BRONZE.RAW_ORDERS
  WHERE order_id IS NOT NULL
    AND customer_id IS NOT NULL
    AND order_placed_at IS NOT NULL
    AND (
        TRY_TO_NUMBER(total_amount) IS NULL
        OR TRY_TO_NUMBER(total_amount) <= 0
        OR TRY_TO_NUMBER(delivery_fee) < 0
    );

  -- Step C: Quarantine invalid status codes
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT
      'RAW_ORDERS',
      'INVALID_STATUS',
      OBJECT_CONSTRUCT(
          'order_id',     order_id,
          'order_status', order_status,
          '_file_name',   _file_name
      ),
      'SP_CLEAN_ORDERS'
  FROM BRONZE.RAW_ORDERS
  WHERE order_id IS NOT NULL
    AND customer_id IS NOT NULL
    AND order_placed_at IS NOT NULL
    AND TRY_TO_NUMBER(total_amount) > 0
    AND order_status NOT IN (
        'PLACED','ACCEPTED','PREPARING',
        'OUT_FOR_DELIVERY','DELIVERED','FAILED'
    );

  -- Step D: Insert valid + deduplicated rows into Silver
  -- ROW_NUMBER deduplicates: if same order_id appears twice,
  -- keep only the latest one by _loaded_at
  INSERT INTO SILVER.CLEAN_ORDERS
  SELECT
      order_id,
      customer_id,
      restaurant_id,
      agent_id,
      TRY_TO_TIMESTAMP_NTZ(order_placed_at,  'YYYY-MM-DD HH24:MI:SS'),
      TRY_TO_TIMESTAMP_NTZ(order_accepted_at, 'YYYY-MM-DD HH24:MI:SS'),
      TRY_TO_TIMESTAMP_NTZ(order_delivered_at,'YYYY-MM-DD HH24:MI:SS'),
      order_status,
      TRY_TO_NUMBER(total_amount,   10, 2),
      TRY_TO_NUMBER(discount_amount,10, 2),
      TRY_TO_NUMBER(delivery_fee,   10, 2),
      TRY_TO_NUMBER(tax_amount,     10, 2),
      TRY_TO_NUMBER(final_amount,   10, 2),
      TRY_TO_NUMBER(delivery_distance_km, 8, 2),
      TRY_TO_NUMBER(estimated_delivery_time),
      TRY_TO_NUMBER(actual_delivery_time),
      delivery_city,
      delivery_pincode,
      order_source,
      promo_code,
      _loaded_at,
      _source,
      _file_name
  FROM (
      SELECT *,
             ROW_NUMBER() OVER (
                 PARTITION BY order_id
                 ORDER BY _loaded_at DESC
             ) AS rn
      FROM BRONZE.RAW_ORDERS
      WHERE order_id IS NOT NULL
        AND customer_id IS NOT NULL
        AND order_placed_at IS NOT NULL
        AND TRY_TO_NUMBER(total_amount) > 0
        AND TRY_TO_NUMBER(delivery_fee) >= 0
        AND order_status IN (
            'PLACED','ACCEPTED','PREPARING',
            'OUT_FOR_DELIVERY','DELIVERED','FAILED'
        )
  )
  WHERE rn = 1;

  RETURN 'SP_CLEAN_ORDERS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 2: Clean Order Items
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_ORDER_ITEMS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Quarantine: null IDs or invalid prices/quantities
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT
      'RAW_ORDER_ITEMS',
      CASE
          WHEN order_item_id IS NULL THEN 'NULL_ITEM_ID'
          WHEN order_id IS NULL      THEN 'NULL_ORDER_ID'
          WHEN TRY_TO_NUMBER(quantity)   IS NULL
            OR TRY_TO_NUMBER(quantity)   <= 0  THEN 'INVALID_QUANTITY'
          WHEN TRY_TO_NUMBER(unit_price) IS NULL
            OR TRY_TO_NUMBER(unit_price) <= 0  THEN 'INVALID_PRICE'
      END,
      OBJECT_CONSTRUCT(
          'order_item_id', order_item_id,
          'order_id',      order_id,
          'item_name',     item_name,
          'quantity',      quantity,
          'unit_price',    unit_price,
          '_file_name',    _file_name
      ),
      'SP_CLEAN_ORDER_ITEMS'
  FROM BRONZE.RAW_ORDER_ITEMS
  WHERE order_item_id IS NULL
     OR order_id IS NULL
     OR TRY_TO_NUMBER(quantity)   IS NULL OR TRY_TO_NUMBER(quantity)   <= 0
     OR TRY_TO_NUMBER(unit_price) IS NULL OR TRY_TO_NUMBER(unit_price) <= 0;

  -- Insert valid rows (deduplicated by order_item_id)
  INSERT INTO SILVER.CLEAN_ORDER_ITEMS
  SELECT
      order_item_id,
      order_id,
      item_name,
      category,
      TRY_TO_NUMBER(quantity)::NUMBER,
      TRY_TO_NUMBER(unit_price, 10, 2),
      TRY_TO_NUMBER(total_price, 10, 2),
      CASE UPPER(is_veg) WHEN 'Y' THEN TRUE
                         WHEN 'N' THEN FALSE
                         ELSE NULL END,
      _loaded_at, _source, _file_name
  FROM (
      SELECT *,
             ROW_NUMBER() OVER (
                 PARTITION BY order_item_id
                 ORDER BY _loaded_at DESC
             ) AS rn
      FROM BRONZE.RAW_ORDER_ITEMS
      WHERE order_item_id IS NOT NULL
        AND order_id IS NOT NULL
        AND TRY_TO_NUMBER(quantity)   > 0
        AND TRY_TO_NUMBER(unit_price) > 0
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_ORDER_ITEMS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 3: Clean Customers
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_CUSTOMERS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Quarantine: null customer_id or obviously bad email
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT
      'RAW_CUSTOMERS',
      CASE
          WHEN customer_id IS NULL THEN 'NULL_CUSTOMER_ID'
          WHEN email IS NULL       THEN 'NULL_EMAIL'
          WHEN email NOT LIKE '%@%.%' THEN 'INVALID_EMAIL'
      END,
      OBJECT_CONSTRUCT(
          'customer_id',     customer_id,
          'first_name',      first_name,
          'email',           email,
          'phone_number',    phone_number,
          'customer_segment',customer_segment,
          '_file_name',      _file_name
      ),
      'SP_CLEAN_CUSTOMERS'
  FROM BRONZE.RAW_CUSTOMERS
  WHERE customer_id IS NULL
     OR email IS NULL
     OR email NOT LIKE '%@%.%';

  -- Insert valid rows
  INSERT INTO SILVER.CLEAN_CUSTOMERS
  SELECT
      customer_id,
      first_name, last_name, email, phone_number,
      TRY_TO_DATE(date_of_birth, 'YYYY-MM-DD'),
      gender, address_line1, city, state, pincode,
      TRY_TO_DATE(signup_date, 'YYYY-MM-DD'),
      customer_segment,
      CASE UPPER(is_active) WHEN 'TRUE'  THEN TRUE
                            WHEN 'FALSE' THEN FALSE
                            WHEN '1'     THEN TRUE
                            WHEN '0'     THEN FALSE
                            ELSE NULL END,
      TRY_TO_DATE(last_order_date, 'YYYY-MM-DD'),
      TRY_TO_TIMESTAMP_NTZ(updated_at, 'YYYY-MM-DD HH24:MI:SS'),
      _loaded_at, _source, _file_name
  FROM (
      SELECT *,
             ROW_NUMBER() OVER (
                 PARTITION BY customer_id
                 ORDER BY updated_at DESC
             ) AS rn
      FROM BRONZE.RAW_CUSTOMERS
      WHERE customer_id IS NOT NULL
        AND email IS NOT NULL
        AND email LIKE '%@%.%'
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_CUSTOMERS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 4: Clean Restaurants (parse from VARIANT)
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_RESTAURANTS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Quarantine: null restaurant_id or rating out of range
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT
      'RAW_RESTAURANTS',
      CASE
          WHEN raw_json:restaurant_id::VARCHAR IS NULL
            THEN 'NULL_RESTAURANT_ID'
          WHEN TRY_TO_NUMBER(raw_json:rating::VARCHAR) IS NULL
            OR  TRY_TO_NUMBER(raw_json:rating::VARCHAR) < 0
            OR  TRY_TO_NUMBER(raw_json:rating::VARCHAR) > 5
            THEN 'INVALID_RATING'
      END,
      raw_json,
      'SP_CLEAN_RESTAURANTS'
  FROM BRONZE.RAW_RESTAURANTS
  WHERE raw_json:restaurant_id::VARCHAR IS NULL
     OR TRY_TO_NUMBER(raw_json:rating::VARCHAR) IS NULL
     OR TRY_TO_NUMBER(raw_json:rating::VARCHAR) NOT BETWEEN 0 AND 5;

  -- Insert valid rows (parse JSON into columns)
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
      CASE raw_json:is_active::VARCHAR
          WHEN 'true'  THEN TRUE
          WHEN 'false' THEN FALSE
          ELSE NULL END,
      TRY_TO_TIMESTAMP_NTZ(raw_json:updated_at::VARCHAR,'YYYY-MM-DD HH24:MI:SS'),
      _loaded_at, _source, _file_name
  FROM (
      SELECT *,
             ROW_NUMBER() OVER (
                 PARTITION BY raw_json:restaurant_id::VARCHAR
                 ORDER BY _loaded_at DESC
             ) AS rn
      FROM BRONZE.RAW_RESTAURANTS
      WHERE raw_json:restaurant_id::VARCHAR IS NOT NULL
        AND TRY_TO_NUMBER(raw_json:rating::VARCHAR) BETWEEN 0 AND 5
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_RESTAURANTS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 5: Clean Agents
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_AGENTS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Quarantine: null agent_id or invalid rating
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT
      'RAW_AGENTS',
      CASE
          WHEN agent_id IS NULL THEN 'NULL_AGENT_ID'
          WHEN TRY_TO_NUMBER(agent_rating) IS NULL
            OR TRY_TO_NUMBER(agent_rating) NOT BETWEEN 0 AND 5
            THEN 'INVALID_RATING'
      END,
      OBJECT_CONSTRUCT(
          'agent_id',     agent_id,
          'agent_name',   agent_name,
          'agent_rating', agent_rating,
          'vehicle_type', vehicle_type,
          '_file_name',   _file_name
      ),
      'SP_CLEAN_AGENTS'
  FROM BRONZE.RAW_AGENTS
  WHERE agent_id IS NULL
     OR TRY_TO_NUMBER(agent_rating) IS NULL
     OR TRY_TO_NUMBER(agent_rating) NOT BETWEEN 0 AND 5;

  -- Insert valid rows
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
                 PARTITION BY agent_id
                 ORDER BY updated_at DESC
             ) AS rn
      FROM BRONZE.RAW_AGENTS
      WHERE agent_id IS NOT NULL
        AND TRY_TO_NUMBER(agent_rating) BETWEEN 0 AND 5
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_AGENTS completed';
END;
$$;

-- Run this in Snowflake worksheet
-- Snowpark runs INSIDE Snowflake — no local Python needed

CREATE OR REPLACE PROCEDURE SILVER.SP_DELIVERY_METRICS()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session):

    # Load clean orders that have both timestamps
    orders = session.table('FOOD_PLATFORM.SILVER.CLEAN_ORDERS').filter(
        "order_placed_at IS NOT NULL AND order_delivered_at IS NOT NULL"
    )

    from snowflake.snowpark.functions import (
        col, datediff, when, lit, round as sf_round
    )

    # Calculate delivery duration in minutes
    with_duration = orders.with_column(
        'actual_duration_min',
        datediff('minute', col('ORDER_PLACED_AT'), col('ORDER_DELIVERED_AT'))
    )

    # Flag late deliveries (actual > estimated by more than 15 min)
    with_flags = with_duration.with_column(
        'is_late_delivery',
        when(
            col('ACTUAL_DELIVERY_TIME') > col('ESTIMATED_DELIVERY_TIME') + 15,
            lit(True)
        ).otherwise(lit(False))
    )

    # Calculate speed score (0-100, higher is better)
    with_score = with_flags.with_column(
        'delivery_speed_score',
        when(col('ACTUAL_DURATION_MIN') <= 20, lit(100))
        .when(col('ACTUAL_DURATION_MIN') <= 30, lit(85))
        .when(col('ACTUAL_DURATION_MIN') <= 45, lit(70))
        .when(col('ACTUAL_DURATION_MIN') <= 60, lit(50))
        .otherwise(lit(25))
    )

    # Select final columns and write to a Silver metrics table
    result = with_score.select(
        'ORDER_ID', 'AGENT_ID', 'DELIVERY_CITY',
        'ORDER_STATUS', 'ACTUAL_DURATION_MIN',
        'IS_LATE_DELIVERY', 'DELIVERY_SPEED_SCORE',
        'ORDER_PLACED_AT'
    )

    # Write to Silver delivery metrics table
    result.write.mode('overwrite').save_as_table(
        'FOOD_PLATFORM.SILVER.DELIVERY_METRICS'
    )

    total = result.count()
    late  = result.filter(col('IS_LATE_DELIVERY') == True).count()

    return f'Processed {total} orders. Late deliveries: {late}'
$$;

-- Table that Snowpark procedure writes to
CREATE TABLE IF NOT EXISTS SILVER.DELIVERY_METRICS (
    order_id              VARCHAR,
    agent_id              VARCHAR,
    delivery_city         VARCHAR,
    order_status          VARCHAR,
    actual_duration_min   NUMBER,
    is_late_delivery      BOOLEAN,
    delivery_speed_score  NUMBER,
    order_placed_at       TIMESTAMP_NTZ
);

USE WAREHOUSE TRANSFORM_WH;

-- Manually trigger all Silver procedures once
CALL SILVER.SP_CLEAN_ORDERS();
CALL SILVER.SP_CLEAN_ORDER_ITEMS();
CALL SILVER.SP_CLEAN_CUSTOMERS();
CALL SILVER.SP_CLEAN_RESTAURANTS();
CALL SILVER.SP_CLEAN_AGENTS();
CALL SILVER.SP_DELIVERY_METRICS();

-- Row counts: Silver vs Bronze vs Quarantine
SELECT 'BRONZE - ORDERS'    AS layer, COUNT(*) AS records FROM BRONZE.RAW_ORDERS
UNION ALL SELECT 'SILVER - ORDERS',   COUNT(*) FROM SILVER.CLEAN_ORDERS
UNION ALL SELECT 'BRONZE - CUSTOMERS', COUNT(*) FROM BRONZE.RAW_CUSTOMERS
UNION ALL SELECT 'SILVER - CUSTOMERS', COUNT(*) FROM SILVER.CLEAN_CUSTOMERS
UNION ALL SELECT 'BRONZE - AGENTS',   COUNT(*) FROM BRONZE.RAW_AGENTS
UNION ALL SELECT 'SILVER - AGENTS',   COUNT(*) FROM SILVER.CLEAN_AGENTS
UNION ALL SELECT 'QUARANTINE',        COUNT(*) FROM QUARANTINE.QUARANTINE_RECORDS
ORDER BY layer;

-- Quarantine breakdown — see which rules fired most
SELECT
    source_table,
    rejection_reason,
    COUNT(*) AS bad_records
FROM QUARANTINE.QUARANTINE_RECORDS
GROUP BY source_table, rejection_reason
ORDER BY bad_records DESC;

-- Check task run history
SELECT
    name,
    state,
    scheduled_time,
    completed_time,
    error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP())
))
ORDER BY scheduled_time DESC;

SELECT COUNT(*) FROM QUARANTINE.QUARANTINE_RECORDS
WHERE source_table = 'RAW_CUSTOMERS';

select * from CLEAN_CUSTOMERS;

-- How many orders have NULL delivery_fee?
SELECT
    COUNT(*)                                          AS total_orders,
    COUNT(CASE WHEN delivery_fee IS NULL THEN 1 END)  AS null_delivery_fee,
    COUNT(CASE WHEN TRY_TO_NUMBER(delivery_fee) < 0
               THEN 1 END)                            AS negative_fee,
    COUNT(CASE WHEN TRY_TO_NUMBER(delivery_fee) >= 0
               THEN 1 END)                            AS valid_fee
FROM BRONZE.RAW_ORDERS
WHERE order_id IS NOT NULL
  AND customer_id IS NOT NULL
  AND order_placed_at IS NOT NULL
  AND TRY_TO_NUMBER(total_amount) > 0
  AND order_status IN (
      'PLACED','ACCEPTED','PREPARING',
      'OUT_FOR_DELIVERY','DELIVERED','FAILED'
  );

  -- Check if order_ids repeat across files
SELECT
    order_id,
    COUNT(*)        AS occurrences,
    COUNT(DISTINCT _file_name) AS appears_in_n_files
FROM BRONZE.RAW_ORDERS
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 10;

-- Unique vs total orders
SELECT
    COUNT(*)              AS total_bronze_rows,
    COUNT(DISTINCT order_id) AS unique_order_ids,
    total_bronze_rows / unique_order_ids AS avg_copies_per_order
FROM BRONZE.RAW_ORDERS;




-- Orders: what bad values actually exist?
SELECT order_status, COUNT(*) AS cnt
FROM BRONZE.RAW_ORDERS
GROUP BY order_status ORDER BY cnt DESC;

SELECT
    MIN(total_amount) AS min_amt, MAX(total_amount) AS max_amt,
    COUNT(CASE WHEN TRY_TO_NUMBER(total_amount) IS NULL THEN 1 END) AS non_numeric,
    COUNT(CASE WHEN TRY_TO_NUMBER(total_amount) <= 0    THEN 1 END) AS zero_or_neg
FROM BRONZE.RAW_ORDERS;

-- Customers: what bad emails look like?
SELECT email, COUNT(*) AS cnt
FROM BRONZE.RAW_CUSTOMERS
WHERE email NOT LIKE '%@%.%' OR email IS NULL
GROUP BY email ORDER BY cnt DESC LIMIT 20;

-- Agents: what bad ratings look like?
SELECT agent_rating, COUNT(*) AS cnt
FROM BRONZE.RAW_AGENTS
GROUP BY agent_rating ORDER BY cnt DESC;

-- What does is_active look like across tables?
SELECT is_active, COUNT(*) FROM BRONZE.RAW_CUSTOMERS GROUP BY is_active;
SELECT availability_status, COUNT(*) FROM BRONZE.RAW_AGENTS GROUP BY availability_status;