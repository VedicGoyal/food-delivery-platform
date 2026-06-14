USE SCHEMA FOOD_PLATFORM.BRONZE;

-- Task: load new orders files every hour
CREATE TASK IF NOT EXISTS TASK_INGEST_ORDERS
  WAREHOUSE = INGEST_WH
  SCHEDULE  = '60 MINUTE'
AS
COPY INTO BRONZE.RAW_ORDERS (
    order_id, customer_id, restaurant_id, agent_id,
    order_placed_at, order_accepted_at, order_delivered_at,
    order_status, total_amount, discount_amount, delivery_fee,
    tax_amount, final_amount, delivery_distance_km,
    estimated_delivery_time, actual_delivery_time,
    delivery_city, delivery_pincode, order_source, promo_code,
    _file_name
)
FROM (
    SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,
           $11,$12,$13,$14,$15,$16,$17,$18,$19,$20,
           METADATA$FILENAME
    FROM @BRONZE.ADLS_RAW_STAGE/orders/
)
FILE_FORMAT = (FORMAT_NAME = FF_CSV)
ON_ERROR    = CONTINUE;

-- Task: load new order_items files every hour
CREATE TASK IF NOT EXISTS TASK_INGEST_ORDER_ITEMS
  WAREHOUSE = INGEST_WH
  SCHEDULE  = '60 MINUTE'
AS
COPY INTO BRONZE.RAW_ORDER_ITEMS (
    order_item_id, order_id, item_name, category,
    quantity, unit_price, total_price, is_veg, _file_name
)
FROM (
    SELECT $1,$2,$3,$4,$5,$6,$7,$8, METADATA$FILENAME
    FROM @BRONZE.ADLS_RAW_STAGE/order_items/
)
FILE_FORMAT = (FORMAT_NAME = FF_CSV)
ON_ERROR    = CONTINUE;

-- Task: load new payments files every hour
CREATE TASK IF NOT EXISTS TASK_INGEST_PAYMENTS
  WAREHOUSE = INGEST_WH
  SCHEDULE  = '60 MINUTE'
AS
COPY INTO BRONZE.RAW_PAYMENTS (
    payment_id, order_id, amount, payment_method,
    payment_gateway, payment_status, payment_timestamp,
    refund_status, refund_amount, card_last4, _file_name
)
FROM (
    SELECT
        $1:payment_id::VARCHAR,    $1:order_id::VARCHAR,
        $1:amount::VARCHAR,        $1:payment_method::VARCHAR,
        $1:payment_gateway::VARCHAR, $1:payment_status::VARCHAR,
        $1:payment_timestamp::VARCHAR, $1:refund_status::VARCHAR,
        $1:refund_amount::VARCHAR, $1:card_last4::VARCHAR,
        METADATA$FILENAME
    FROM @BRONZE.ADLS_RAW_STAGE/payments/
)
FILE_FORMAT = (FORMAT_NAME = FF_PARQUET)
ON_ERROR    = CONTINUE;

-- Task: load customers (monthly delta)
CREATE TASK IF NOT EXISTS TASK_INGEST_CUSTOMERS
  WAREHOUSE = INGEST_WH
  SCHEDULE  = '60 MINUTE'
AS
COPY INTO BRONZE.RAW_CUSTOMERS (
    customer_id, first_name, last_name, email, phone_number,
    date_of_birth, gender, address_line1, city, state, pincode,
    signup_date, customer_segment, is_active, last_order_date,
    updated_at, _file_name
)
FROM (
    SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,
           $11,$12,$13,$14,$15,$16, METADATA$FILENAME
    FROM @BRONZE.ADLS_RAW_STAGE/customers/
)
FILE_FORMAT = (FORMAT_NAME = FF_CSV)
ON_ERROR    = CONTINUE;

-- Task: load restaurants (quarterly delta)
CREATE TASK IF NOT EXISTS TASK_INGEST_RESTAURANTS
  WAREHOUSE = INGEST_WH
  SCHEDULE  = '60 MINUTE'
AS
COPY INTO BRONZE.RAW_RESTAURANTS (raw_json, _file_name)
FROM (
    SELECT $1, METADATA$FILENAME
    FROM @BRONZE.ADLS_RAW_STAGE/restaurants/
)
FILE_FORMAT = (FORMAT_NAME = FF_JSON)
ON_ERROR    = CONTINUE;

-- Task: load agents (monthly delta)
CREATE TASK IF NOT EXISTS TASK_INGEST_AGENTS
  WAREHOUSE = INGEST_WH
  SCHEDULE  = '60 MINUTE'
AS
COPY INTO BRONZE.RAW_AGENTS (
    agent_id, agent_name, phone_number, city, vehicle_type,
    joining_date, agent_rating, availability_status, updated_at, _file_name
)
FROM (
    SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9, METADATA$FILENAME
    FROM @BRONZE.ADLS_RAW_STAGE/agents/
)
FILE_FORMAT = (FORMAT_NAME = FF_CSV)
ON_ERROR    = CONTINUE;