USE ROLE SYSADMIN;
USE DATABASE FOOD_PLATFORM;
USE SCHEMA SILVER;
USE WAREHOUSE TRANSFORM_WH;

CREATE TABLE IF NOT EXISTS CLEAN_ORDERS (
    order_id                VARCHAR       NOT NULL,
    customer_id             VARCHAR       NOT NULL,
    restaurant_id           VARCHAR       NOT NULL,
    agent_id                VARCHAR,
    order_placed_at         TIMESTAMP_NTZ NOT NULL,
    order_accepted_at       TIMESTAMP_NTZ,
    order_delivered_at      TIMESTAMP_NTZ,
    order_status            VARCHAR       NOT NULL,
    total_amount            NUMBER(10,2)  NOT NULL,
    discount_amount         NUMBER(10,2),
    delivery_fee            NUMBER(10,2),
    tax_amount              NUMBER(10,2),
    final_amount            NUMBER(10,2),
    delivery_distance_km    NUMBER(8,2),
    estimated_delivery_time NUMBER,
    actual_delivery_time    NUMBER,
    delivery_city           VARCHAR,
    delivery_pincode        VARCHAR,
    order_source            VARCHAR,
    promo_code              VARCHAR,
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source                 VARCHAR,
    _file_name              VARCHAR
);

CREATE TABLE IF NOT EXISTS CLEAN_ORDER_ITEMS (
    order_item_id   VARCHAR      NOT NULL,
    order_id        VARCHAR      NOT NULL,
    item_name       VARCHAR,
    category        VARCHAR,
    quantity        NUMBER       NOT NULL,
    unit_price      NUMBER(10,2) NOT NULL,
    total_price     NUMBER(10,2),
    is_veg          BOOLEAN,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source         VARCHAR,
    _file_name      VARCHAR
);

CREATE TABLE IF NOT EXISTS CLEAN_PAYMENTS (
    payment_id        VARCHAR      NOT NULL,
    order_id          VARCHAR      NOT NULL,
    amount            NUMBER(10,2) NOT NULL,
    payment_method    VARCHAR,
    payment_gateway   VARCHAR,
    payment_status    VARCHAR,
    payment_timestamp TIMESTAMP_NTZ,
    refund_status     VARCHAR,
    refund_amount     NUMBER(10,2),
    card_last4        VARCHAR,
    _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source           VARCHAR,
    _file_name        VARCHAR
);

CREATE TABLE IF NOT EXISTS CLEAN_CUSTOMERS (
    customer_id       VARCHAR NOT NULL,
    first_name        VARCHAR,
    last_name         VARCHAR,
    email             VARCHAR,
    phone_number      VARCHAR,
    date_of_birth     DATE,
    gender            VARCHAR,
    address_line1     VARCHAR,
    city              VARCHAR,
    state             VARCHAR,
    pincode           VARCHAR,
    signup_date       DATE,
    customer_segment  VARCHAR,
    is_active         BOOLEAN,
    last_order_date   DATE,
    updated_at        TIMESTAMP_NTZ,
    _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source           VARCHAR,
    _file_name        VARCHAR
);

CREATE TABLE IF NOT EXISTS CLEAN_RESTAURANTS (
    restaurant_id       VARCHAR      NOT NULL,
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
    updated_at          TIMESTAMP_NTZ,
    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source             VARCHAR,
    _file_name          VARCHAR
);

CREATE TABLE IF NOT EXISTS CLEAN_AGENTS (
    agent_id            VARCHAR      NOT NULL,
    agent_name          VARCHAR,
    phone_number        VARCHAR,
    city                VARCHAR,
    vehicle_type        VARCHAR,
    joining_date        DATE,
    agent_rating        NUMBER(3,1),
    availability_status VARCHAR,
    updated_at          TIMESTAMP_NTZ,
    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source             VARCHAR,
    _file_name          VARCHAR
);

SHOW TABLES IN SCHEMA FOOD_PLATFORM.SILVER;