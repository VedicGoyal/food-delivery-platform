USE ROLE SYSADMIN;
USE DATABASE FOOD_PLATFORM;
USE SCHEMA BRONZE;
USE WAREHOUSE INGEST_WH;

CREATE TABLE IF NOT EXISTS RAW_ORDERS (
    order_id                VARCHAR,
    customer_id             VARCHAR,
    restaurant_id           VARCHAR,
    agent_id                VARCHAR,
    order_placed_at         VARCHAR,
    order_accepted_at       VARCHAR,
    order_delivered_at      VARCHAR,
    order_status            VARCHAR,
    total_amount            VARCHAR,
    discount_amount         VARCHAR,
    delivery_fee            VARCHAR,
    tax_amount              VARCHAR,
    final_amount            VARCHAR,
    delivery_distance_km    VARCHAR,
    estimated_delivery_time VARCHAR,
    actual_delivery_time    VARCHAR,
    delivery_city           VARCHAR,
    delivery_pincode        VARCHAR,
    order_source            VARCHAR,
    promo_code              VARCHAR,
    _loaded_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source      VARCHAR       DEFAULT 'snowpipe_batch',
    _file_name   VARCHAR
);

CREATE TABLE IF NOT EXISTS RAW_ORDER_ITEMS (
    order_item_id   VARCHAR,
    order_id        VARCHAR,
    item_name       VARCHAR,
    category        VARCHAR,
    quantity        VARCHAR,
    unit_price      VARCHAR,
    total_price     VARCHAR,
    is_veg          VARCHAR,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source         VARCHAR       DEFAULT 'snowpipe_batch',
    _file_name      VARCHAR
);

CREATE TABLE IF NOT EXISTS RAW_PAYMENTS (
    payment_id        VARCHAR,
    order_id          VARCHAR,
    amount            VARCHAR,
    payment_method    VARCHAR,
    payment_gateway   VARCHAR,
    payment_status    VARCHAR,
    payment_timestamp VARCHAR,
    refund_status     VARCHAR,
    refund_amount     VARCHAR,
    card_last4        VARCHAR,
    _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source           VARCHAR       DEFAULT 'snowpipe_batch',
    _file_name        VARCHAR
);

CREATE TABLE IF NOT EXISTS RAW_CUSTOMERS (
    customer_id       VARCHAR,
    first_name        VARCHAR,
    last_name         VARCHAR,
    email             VARCHAR,
    phone_number      VARCHAR,
    date_of_birth     VARCHAR,
    gender            VARCHAR,
    address_line1     VARCHAR,
    city              VARCHAR,
    state             VARCHAR,
    pincode           VARCHAR,
    signup_date       VARCHAR,
    customer_segment  VARCHAR,
    is_active         VARCHAR,
    last_order_date   VARCHAR,
    updated_at        VARCHAR,
    _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source           VARCHAR       DEFAULT 'snowpipe_batch',
    _file_name        VARCHAR
);

CREATE TABLE IF NOT EXISTS RAW_RESTAURANTS (
    raw_json    VARIANT,
    _loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source     VARCHAR       DEFAULT 'snowpipe_batch',
    _file_name  VARCHAR
);

CREATE TABLE IF NOT EXISTS RAW_AGENTS (
    agent_id            VARCHAR,
    agent_name          VARCHAR,
    phone_number        VARCHAR,
    city                VARCHAR,
    vehicle_type        VARCHAR,
    joining_date        VARCHAR,
    agent_rating        VARCHAR,
    availability_status VARCHAR,
    updated_at          VARCHAR,
    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source             VARCHAR       DEFAULT 'snowpipe_batch',
    _file_name          VARCHAR
);

CREATE TABLE IF NOT EXISTS RAW_REVIEWS (
    raw_json    VARIANT,
    _loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source     VARCHAR       DEFAULT 'streaming',
    _file_name  VARCHAR
);

CREATE TABLE IF NOT EXISTS RAW_ORDER_EVENTS (
    raw_json    VARIANT,
    _loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source     VARCHAR       DEFAULT 'streaming',
    _file_name  VARCHAR
);

SHOW TABLES IN SCHEMA FOOD_PLATFORM.BRONZE;

SELECT table_name, row_count, created
FROM FOOD_PLATFORM.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'BRONZE'
ORDER BY created;

USE SCHEMA QUARANTINE;

CREATE TABLE IF NOT EXISTS QUARANTINE_RECORDS (
    source_table      VARCHAR       NOT NULL,
    rejection_reason  VARCHAR       NOT NULL,
    raw_record        VARIANT,
    rejected_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    rejected_by       VARCHAR
);

