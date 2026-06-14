-- ─────────────────────────────────────────────────────
-- PROCEDURE 1: SP_CLEAN_ORDERS
-- Fixes: correct status enum, source validation,
--        orphan FK check, NULL delivery_fee handling
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_ORDERS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Step A: NULL mandatory fields
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
          'order_id',        order_id,
          'customer_id',     customer_id,
          'order_status',    order_status,
          'total_amount',    total_amount,
          'order_placed_at', order_placed_at,
          '_file_name',      _file_name
      ),
      'SP_CLEAN_ORDERS'
  FROM BRONZE.RAW_ORDERS
  WHERE order_id IS NULL OR customer_id IS NULL OR order_placed_at IS NULL;

  -- Step B: Invalid amounts (negative or zero total, or negative fee)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_ORDERS', 'INVALID_AMOUNT',
      OBJECT_CONSTRUCT(
          'order_id',     order_id,
          'total_amount', total_amount,
          'delivery_fee', delivery_fee,
          '_file_name',   _file_name
      ),
      'SP_CLEAN_ORDERS'
  FROM BRONZE.RAW_ORDERS
  WHERE order_id IS NOT NULL AND customer_id IS NOT NULL AND order_placed_at IS NOT NULL
    AND (
        TRY_TO_NUMBER(total_amount) IS NULL
        OR TRY_TO_NUMBER(total_amount) <= 0
        OR (delivery_fee IS NOT NULL AND TRY_TO_NUMBER(delivery_fee) < 0)
    );

  -- Step C: Invalid order status
  -- Valid: DELIVERED, CANCELLED, FAILED, PENDING (from generator)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_ORDERS', 'INVALID_STATUS',
      OBJECT_CONSTRUCT(
          'order_id',     order_id,
          'order_status', order_status,
          '_file_name',   _file_name
      ),
      'SP_CLEAN_ORDERS'
  FROM BRONZE.RAW_ORDERS
  WHERE order_id IS NOT NULL AND customer_id IS NOT NULL AND order_placed_at IS NOT NULL
    AND TRY_TO_NUMBER(total_amount) > 0
    AND (delivery_fee IS NULL OR TRY_TO_NUMBER(delivery_fee) >= 0)
    AND (order_status IS NULL
         OR order_status NOT IN ('DELIVERED','CANCELLED','FAILED','PENDING'));

  -- Step D: Invalid order source
  -- Valid: APP, WEBSITE, PHONE (from generator)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_ORDERS', 'INVALID_ORDER_SOURCE',
      OBJECT_CONSTRUCT(
          'order_id',     order_id,
          'order_source', order_source,
          '_file_name',   _file_name
      ),
      'SP_CLEAN_ORDERS'
  FROM BRONZE.RAW_ORDERS
  WHERE order_id IS NOT NULL AND customer_id IS NOT NULL AND order_placed_at IS NOT NULL
    AND TRY_TO_NUMBER(total_amount) > 0
    AND (delivery_fee IS NULL OR TRY_TO_NUMBER(delivery_fee) >= 0)
    AND order_status IN ('DELIVERED','CANCELLED','FAILED','PENDING')
    AND (order_source IS NULL
         OR order_source NOT IN ('APP','WEBSITE','PHONE'));

  -- Step E: Orphan foreign keys (INVALID pattern injected by generator)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_ORDERS', 'ORPHAN_FOREIGN_KEY',
      OBJECT_CONSTRUCT(
          'order_id',       order_id,
          'customer_id',    customer_id,
          'restaurant_id',  restaurant_id,
          'agent_id',       agent_id,
          '_file_name',     _file_name
      ),
      'SP_CLEAN_ORDERS'
  FROM BRONZE.RAW_ORDERS
  WHERE order_id IS NOT NULL AND customer_id IS NOT NULL AND order_placed_at IS NOT NULL
    AND TRY_TO_NUMBER(total_amount) > 0
    AND (delivery_fee IS NULL OR TRY_TO_NUMBER(delivery_fee) >= 0)
    AND order_status IN ('DELIVERED','CANCELLED','FAILED','PENDING')
    AND order_source IN ('APP','WEBSITE','PHONE')
    AND (
        customer_id   LIKE '%INVALID%'
        OR restaurant_id LIKE '%INVALID%'
        OR agent_id      LIKE '%INVALID%'
    );

  -- Step F: Valid rows → Silver (deduplicated)
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
      FROM BRONZE.RAW_ORDERS
      WHERE order_id IS NOT NULL
        AND customer_id IS NOT NULL
        AND order_placed_at IS NOT NULL
        AND TRY_TO_NUMBER(total_amount) > 0
        AND (delivery_fee IS NULL OR TRY_TO_NUMBER(delivery_fee) >= 0)
        AND order_status IN ('DELIVERED','CANCELLED','FAILED','PENDING')
        AND order_source IN ('APP','WEBSITE','PHONE')
        AND customer_id   NOT LIKE '%INVALID%'
        AND restaurant_id NOT LIKE '%INVALID%'
        AND agent_id      NOT LIKE '%INVALID%'
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_ORDERS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 2: SP_CLEAN_ORDER_ITEMS
-- Fixes: null_item_name and null_category are minor
--        (don't quarantine) — only quarantine on IDs
--        and invalid numeric values
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_ORDER_ITEMS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Quarantine: null IDs or invalid quantity/price
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
          'order_item_id', order_item_id,
          'order_id',      order_id,
          'item_name',     item_name,
          'quantity',      quantity,
          'unit_price',    unit_price,
          '_file_name',    _file_name
      ),
      'SP_CLEAN_ORDER_ITEMS'
  FROM BRONZE.RAW_ORDER_ITEMS
  WHERE order_item_id IS NULL OR order_id IS NULL
     OR TRY_TO_NUMBER(quantity)   IS NULL OR TRY_TO_NUMBER(quantity)   <= 0
     OR TRY_TO_NUMBER(unit_price) IS NULL OR TRY_TO_NUMBER(unit_price) <= 0;

  -- Valid rows → Silver
  -- Note: null_item_name and null_category are accepted (minor corruptions)
  --       total_price_mismatch accepted — Silver stores what arrived
  INSERT INTO SILVER.CLEAN_ORDER_ITEMS
  SELECT
      order_item_id, order_id,
      item_name,     -- NULL allowed (minor corruption)
      category,      -- NULL allowed (minor corruption)
      TRY_TO_NUMBER(quantity)::NUMBER,
      TRY_TO_NUMBER(unit_price, 10, 2),
      COALESCE(TRY_TO_NUMBER(total_price, 10, 2),
               TRY_TO_NUMBER(unit_price, 10, 2) * TRY_TO_NUMBER(quantity)),
      CASE UPPER(TRIM(is_veg))
          WHEN 'TRUE'  THEN TRUE  WHEN 'FALSE' THEN FALSE
          WHEN 'Y'     THEN TRUE  WHEN 'N'     THEN FALSE
          ELSE NULL END,
      _loaded_at, _source, _file_name
  FROM (
      SELECT *,
             ROW_NUMBER() OVER (
                 PARTITION BY order_item_id ORDER BY _loaded_at DESC
             ) AS rn
      FROM BRONZE.RAW_ORDER_ITEMS
      WHERE order_item_id IS NOT NULL
        AND order_id      IS NOT NULL
        AND TRY_TO_NUMBER(quantity)   > 0
        AND TRY_TO_NUMBER(unit_price) > 0
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_ORDER_ITEMS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 3: SP_CLEAN_CUSTOMERS
-- Fixes: REGEXP_LIKE for email (catches '@.com',
--        'user@@domain.com'), segment validation
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_CUSTOMERS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Step A: NULL customer_id
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_CUSTOMERS', 'NULL_CUSTOMER_ID',
      OBJECT_CONSTRUCT(
          'customer_id', customer_id,
          'email',       email,
          '_file_name',  _file_name
      ),
      'SP_CLEAN_CUSTOMERS'
  FROM BRONZE.RAW_CUSTOMERS
  WHERE customer_id IS NULL;

  -- Step B: NULL or invalid email
  -- REGEXP_LIKE catches '@.com' and 'user@@domain.com' that LIKE missed
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_CUSTOMERS',
      CASE WHEN email IS NULL THEN 'NULL_EMAIL' ELSE 'INVALID_EMAIL' END,
      OBJECT_CONSTRUCT(
          'customer_id', customer_id,
          'email',       email,
          '_file_name',  _file_name
      ),
      'SP_CLEAN_CUSTOMERS'
  FROM BRONZE.RAW_CUSTOMERS
  WHERE customer_id IS NOT NULL
    AND (
        email IS NULL
        -- Must have: chars@chars.chars, no double @, no spaces
        OR NOT REGEXP_LIKE(email, '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$')
    );

  -- Step C: Invalid customer segment
  -- Valid: NEW, REGULAR, PREMIUM, CHURNED (from generator)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_CUSTOMERS', 'INVALID_SEGMENT',
      OBJECT_CONSTRUCT(
          'customer_id',      customer_id,
          'customer_segment', customer_segment,
          '_file_name',       _file_name
      ),
      'SP_CLEAN_CUSTOMERS'
  FROM BRONZE.RAW_CUSTOMERS
  WHERE customer_id IS NOT NULL
    AND REGEXP_LIKE(email, '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$')
    AND (customer_segment IS NULL
         OR customer_segment NOT IN ('NEW','REGULAR','PREMIUM','CHURNED'));

  -- Valid rows → Silver
  -- Minor corruptions accepted: invalid_phone, null_name, future_dob,
  -- invalid_gender, null_city, null_signup_date
  INSERT INTO SILVER.CLEAN_CUSTOMERS
  SELECT
      customer_id, first_name, last_name, email, phone_number,
      TRY_TO_DATE(date_of_birth, 'YYYY-MM-DD'),
      gender, address_line1, city, state, pincode,
      TRY_TO_DATE(signup_date, 'YYYY-MM-DD'),
      customer_segment,
      -- Generator writes Python bool → CSV as 'True'/'False'
      CASE UPPER(TRIM(is_active))
          WHEN 'TRUE'  THEN TRUE  WHEN 'FALSE' THEN FALSE
          WHEN '1'     THEN TRUE  WHEN '0'     THEN FALSE
          ELSE NULL END,
      TRY_TO_DATE(last_order_date, 'YYYY-MM-DD'),
      TRY_TO_TIMESTAMP_NTZ(updated_at, 'YYYY-MM-DD HH24:MI:SS'),
      _loaded_at, _source, _file_name
  FROM (
      SELECT *,
             ROW_NUMBER() OVER (
                 PARTITION BY customer_id ORDER BY updated_at DESC NULLS LAST
             ) AS rn
      FROM BRONZE.RAW_CUSTOMERS
      WHERE customer_id IS NOT NULL
        AND REGEXP_LIKE(email, '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$')
        AND customer_segment IN ('NEW','REGULAR','PREMIUM','CHURNED')
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_CUSTOMERS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 4: SP_CLEAN_RESTAURANTS
-- Fixes: added commission_rate and prep_time validation,
--        is_active handles Python bool true/false
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_RESTAURANTS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Step A: NULL restaurant_id
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_RESTAURANTS', 'NULL_RESTAURANT_ID',
      raw_json, 'SP_CLEAN_RESTAURANTS'
  FROM BRONZE.RAW_RESTAURANTS
  WHERE raw_json:restaurant_id::VARCHAR IS NULL;

  -- Step B: Invalid rating (negative or > 5)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_RESTAURANTS',
      CASE
          WHEN TRY_TO_NUMBER(raw_json:rating::VARCHAR) IS NULL THEN 'INVALID_RATING_FORMAT'
          ELSE 'RATING_OUT_OF_RANGE'
      END,
      raw_json, 'SP_CLEAN_RESTAURANTS'
  FROM BRONZE.RAW_RESTAURANTS
  WHERE raw_json:restaurant_id::VARCHAR IS NOT NULL
    AND (
        TRY_TO_NUMBER(raw_json:rating::VARCHAR) IS NULL
        OR TRY_TO_NUMBER(raw_json:rating::VARCHAR) NOT BETWEEN 0 AND 5
    );

  -- Step C: Negative commission rate (financial field)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_RESTAURANTS', 'NEGATIVE_COMMISSION',
      raw_json, 'SP_CLEAN_RESTAURANTS'
  FROM BRONZE.RAW_RESTAURANTS
  WHERE raw_json:restaurant_id::VARCHAR IS NOT NULL
    AND TRY_TO_NUMBER(raw_json:rating::VARCHAR) BETWEEN 0 AND 5
    AND TRY_TO_NUMBER(raw_json:commission_rate::VARCHAR) < 0;

  -- Step D: Negative prep time
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_RESTAURANTS', 'NEGATIVE_PREP_TIME',
      raw_json, 'SP_CLEAN_RESTAURANTS'
  FROM BRONZE.RAW_RESTAURANTS
  WHERE raw_json:restaurant_id::VARCHAR IS NOT NULL
    AND TRY_TO_NUMBER(raw_json:rating::VARCHAR) BETWEEN 0 AND 5
    AND (TRY_TO_NUMBER(raw_json:commission_rate::VARCHAR) >= 0
         OR raw_json:commission_rate::VARCHAR IS NULL)
    AND TRY_TO_NUMBER(raw_json:average_prep_time::VARCHAR) < 0;

  -- Valid rows → Silver
  -- Minor corruptions accepted: null_restaurant_name, null_cuisine,
  -- null_city, invalid_time_format, null_pincode
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
      -- Generator writes Python bool → JSON as true/false (lowercase)
      CASE LOWER(raw_json:is_active::VARCHAR)
          WHEN 'true'  THEN TRUE
          WHEN 'false' THEN FALSE
          ELSE NULL END,
      TRY_TO_TIMESTAMP_NTZ(
          raw_json:updated_at::VARCHAR, 'YYYY-MM-DD HH24:MI:SS'),
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
        AND (raw_json:commission_rate::VARCHAR IS NULL
             OR TRY_TO_NUMBER(raw_json:commission_rate::VARCHAR) >= 0)
        AND (raw_json:average_prep_time::VARCHAR IS NULL
             OR TRY_TO_NUMBER(raw_json:average_prep_time::VARCHAR) >= 0)
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_RESTAURANTS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 5: SP_CLEAN_AGENTS
-- Fixes: vehicle_type validation added,
--        ON_BREAK removed from valid availability
--        (it is injected as invalid by generator)
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_AGENTS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Step A: NULL agent_id
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_AGENTS', 'NULL_AGENT_ID',
      OBJECT_CONSTRUCT(
          'agent_id',   agent_id,
          'agent_name', agent_name,
          '_file_name', _file_name
      ),
      'SP_CLEAN_AGENTS'
  FROM BRONZE.RAW_AGENTS
  WHERE agent_id IS NULL;

  -- Step B: Invalid rating (negative or > 5)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_AGENTS',
      CASE
          WHEN TRY_TO_NUMBER(agent_rating) IS NULL THEN 'INVALID_RATING_FORMAT'
          ELSE 'RATING_OUT_OF_RANGE'
      END,
      OBJECT_CONSTRUCT(
          'agent_id',     agent_id,
          'agent_rating', agent_rating,
          '_file_name',   _file_name
      ),
      'SP_CLEAN_AGENTS'
  FROM BRONZE.RAW_AGENTS
  WHERE agent_id IS NOT NULL
    AND (TRY_TO_NUMBER(agent_rating) IS NULL
         OR TRY_TO_NUMBER(agent_rating) NOT BETWEEN 0 AND 5);

  -- Step C: Invalid vehicle type
  -- Valid: BIKE, SCOOTER, CYCLE (from generator)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_AGENTS', 'INVALID_VEHICLE_TYPE',
      OBJECT_CONSTRUCT(
          'agent_id',     agent_id,
          'vehicle_type', vehicle_type,
          '_file_name',   _file_name
      ),
      'SP_CLEAN_AGENTS'
  FROM BRONZE.RAW_AGENTS
  WHERE agent_id IS NOT NULL
    AND TRY_TO_NUMBER(agent_rating) BETWEEN 0 AND 5
    AND (vehicle_type IS NULL
         OR vehicle_type NOT IN ('BIKE','SCOOTER','CYCLE'));

  -- Step D: Invalid availability status
  -- Valid: ONLINE, OFFLINE, BUSY (from generator AVAILABILITY list)
  -- ON_BREAK is injected as a CORRUPTION — not a valid status
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_AGENTS', 'INVALID_AVAILABILITY_STATUS',
      OBJECT_CONSTRUCT(
          'agent_id',            agent_id,
          'availability_status', availability_status,
          '_file_name',          _file_name
      ),
      'SP_CLEAN_AGENTS'
  FROM BRONZE.RAW_AGENTS
  WHERE agent_id IS NOT NULL
    AND TRY_TO_NUMBER(agent_rating) BETWEEN 0 AND 5
    AND vehicle_type IN ('BIKE','SCOOTER','CYCLE')
    AND (availability_status IS NULL
         OR availability_status NOT IN ('ONLINE','OFFLINE','BUSY'));

  -- Valid rows → Silver
  -- Minor corruptions accepted: null_agent_name, invalid_phone,
  -- null_city, future_joining_date, null_updated_at
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
      FROM BRONZE.RAW_AGENTS
      WHERE agent_id IS NOT NULL
        AND TRY_TO_NUMBER(agent_rating) BETWEEN 0 AND 5
        AND vehicle_type IN ('BIKE','SCOOTER','CYCLE')
        AND availability_status IN ('ONLINE','OFFLINE','BUSY')
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_AGENTS completed';
END;
$$;


-- ─────────────────────────────────────────────────────
-- PROCEDURE 6: SP_CLEAN_PAYMENTS (NEW — wasn't written before)
-- Payment method: UPI, CARD, CASH, WALLET
-- Payment status: SUCCESS, FAILED, PENDING, REFUNDED
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SILVER.SP_CLEAN_PAYMENTS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

  -- Step A: NULL mandatory fields
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_PAYMENTS',
      CASE
          WHEN payment_id        IS NULL THEN 'NULL_PAYMENT_ID'
          WHEN payment_timestamp IS NULL THEN 'NULL_TIMESTAMP'
      END,
      OBJECT_CONSTRUCT(
          'payment_id',        payment_id,
          'order_id',          order_id,
          'payment_status',    payment_status,
          'amount',            amount,
          '_file_name',        _file_name
      ),
      'SP_CLEAN_PAYMENTS'
  FROM BRONZE.RAW_PAYMENTS
  WHERE payment_id IS NULL OR payment_timestamp IS NULL;

  -- Step B: Invalid amount (negative or zero)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_PAYMENTS', 'INVALID_AMOUNT',
      OBJECT_CONSTRUCT(
          'payment_id', payment_id,
          'amount',     amount,
          '_file_name', _file_name
      ),
      'SP_CLEAN_PAYMENTS'
  FROM BRONZE.RAW_PAYMENTS
  WHERE payment_id IS NOT NULL AND payment_timestamp IS NOT NULL
    AND (TRY_TO_NUMBER(amount) IS NULL OR TRY_TO_NUMBER(amount) <= 0);

  -- Step C: Invalid payment method
  -- Valid: UPI, CARD, CASH, WALLET (from generator)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_PAYMENTS', 'INVALID_PAYMENT_METHOD',
      OBJECT_CONSTRUCT(
          'payment_id',     payment_id,
          'payment_method', payment_method,
          '_file_name',     _file_name
      ),
      'SP_CLEAN_PAYMENTS'
  FROM BRONZE.RAW_PAYMENTS
  WHERE payment_id IS NOT NULL AND payment_timestamp IS NOT NULL
    AND TRY_TO_NUMBER(amount) > 0
    AND (payment_method IS NULL
         OR payment_method NOT IN ('UPI','CARD','CASH','WALLET'));

  -- Step D: Invalid payment status
  -- Valid: SUCCESS, FAILED, PENDING, REFUNDED (from generator)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_PAYMENTS', 'INVALID_PAYMENT_STATUS',
      OBJECT_CONSTRUCT(
          'payment_id',     payment_id,
          'payment_status', payment_status,
          '_file_name',     _file_name
      ),
      'SP_CLEAN_PAYMENTS'
  FROM BRONZE.RAW_PAYMENTS
  WHERE payment_id IS NOT NULL AND payment_timestamp IS NOT NULL
    AND TRY_TO_NUMBER(amount) > 0
    AND payment_method IN ('UPI','CARD','CASH','WALLET')
    AND (payment_status IS NULL
         OR payment_status NOT IN ('SUCCESS','FAILED','PENDING','REFUNDED'));

  -- Step E: Orphan order_ids (ORD_INVALID_X pattern)
  INSERT INTO QUARANTINE.QUARANTINE_RECORDS (
      source_table, rejection_reason, raw_record, rejected_by
  )
  SELECT 'RAW_PAYMENTS', 'ORPHAN_ORDER_ID',
      OBJECT_CONSTRUCT(
          'payment_id', payment_id,
          'order_id',   order_id,
          '_file_name', _file_name
      ),
      'SP_CLEAN_PAYMENTS'
  FROM BRONZE.RAW_PAYMENTS
  WHERE payment_id IS NOT NULL AND payment_timestamp IS NOT NULL
    AND TRY_TO_NUMBER(amount) > 0
    AND payment_method IN ('UPI','CARD','CASH','WALLET')
    AND payment_status IN ('SUCCESS','FAILED','PENDING','REFUNDED')
    AND order_id LIKE '%INVALID%';

  -- Valid rows → Silver
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
      FROM BRONZE.RAW_PAYMENTS
      WHERE payment_id        IS NOT NULL
        AND payment_timestamp IS NOT NULL
        AND TRY_TO_NUMBER(amount) > 0
        AND payment_method IN ('UPI','CARD','CASH','WALLET')
        AND payment_status IN ('SUCCESS','FAILED','PENDING','REFUNDED')
        AND order_id NOT LIKE '%INVALID%'
  ) WHERE rn = 1;

  RETURN 'SP_CLEAN_PAYMENTS completed';
END;
$$;

USE WAREHOUSE TRANSFORM_WH;
CALL SILVER.SP_CLEAN_ORDERS();
CALL SILVER.SP_CLEAN_ORDER_ITEMS();
CALL SILVER.SP_CLEAN_CUSTOMERS();
CALL SILVER.SP_CLEAN_RESTAURANTS();
CALL SILVER.SP_CLEAN_AGENTS();
CALL SILVER.SP_CLEAN_PAYMENTS();

-- 3. Check counts
SELECT 'SILVER - ORDERS'      AS tbl, COUNT(*) AS records FROM SILVER.CLEAN_ORDERS
UNION ALL SELECT 'SILVER - ITEMS',     COUNT(*) FROM SILVER.CLEAN_ORDER_ITEMS
UNION ALL SELECT 'SILVER - CUSTOMERS', COUNT(*) FROM SILVER.CLEAN_CUSTOMERS
UNION ALL SELECT 'SILVER - RESTAURANTS',COUNT(*) FROM SILVER.CLEAN_RESTAURANTS
UNION ALL SELECT 'SILVER - AGENTS',    COUNT(*) FROM SILVER.CLEAN_AGENTS
UNION ALL SELECT 'SILVER - PAYMENTS',  COUNT(*) FROM SILVER.CLEAN_PAYMENTS
UNION ALL SELECT 'QUARANTINE - TOTAL', COUNT(*) FROM QUARANTINE.QUARANTINE_RECORDS
ORDER BY tbl;

-- 4. Quarantine breakdown
SELECT source_table, rejection_reason, COUNT(*) AS cnt
FROM QUARANTINE.QUARANTINE_RECORDS
GROUP BY source_table, rejection_reason
ORDER BY source_table, cnt DESC;


-- Orders: unique valid + unique bad = unique total
SELECT
    (SELECT COUNT(DISTINCT order_id) FROM SILVER.CLEAN_ORDERS)   AS unique_valid,
    (SELECT COUNT(DISTINCT raw_record:order_id::VARCHAR)
     FROM QUARANTINE.QUARANTINE_RECORDS
     WHERE source_table = 'RAW_ORDERS')                          AS unique_quarantined,
    (SELECT COUNT(DISTINCT order_id)
     FROM BRONZE.RAW_ORDERS)                                     AS unique_bronze;
-- unique_valid + unique_quarantined should ≈ unique_bronze

-- Show what minor corruptions made it into Silver
SELECT
    COUNT(*) FILTER (WHERE delivery_distance_km < 0) AS negative_distance_in_silver,
    COUNT(*) FILTER (WHERE order_placed_at > CURRENT_TIMESTAMP()) AS future_dates_in_silver,
    COUNT(*) FILTER (WHERE final_amount != total_amount - discount_amount
                              + delivery_fee + tax_amount) AS amount_mismatch_in_silver,
    COUNT(*) FILTER (WHERE delivery_city IS NULL) AS null_city_in_silver
FROM SILVER.CLEAN_ORDERS;

-- Quarantine breakdown by table and reason
SELECT
    source_table,
    rejection_reason,
    COUNT(*) AS rows_in_quarantine
FROM QUARANTINE.QUARANTINE_RECORDS
GROUP BY source_table, rejection_reason
ORDER BY source_table, rows_in_quarantine DESC;

select * from clean_customers;
select count(*) from quarantine.quarantine_records
where source_table = 'RAW_CUSTOMERS';

select *  from quarantine.quarantine_records;