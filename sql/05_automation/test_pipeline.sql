USE WAREHOUSE TRANSFORM_WH;

-- 1. Check if Bronze streams have data
-- (they should be EMPTY since all data was loaded before streams existed)
SELECT SYSTEM$STREAM_HAS_DATA('FOOD_PLATFORM.BRONZE.STREAM_RAW_ORDERS');
-- Returns FALSE — expected, backfill data predates the stream

-- 2. Simulate new data arriving: upload a new file to ADLS
-- OR manually insert a test row to trigger the stream:
INSERT INTO BRONZE.RAW_ORDERS (
    order_id, customer_id, restaurant_id, agent_id,
    order_placed_at, order_status, total_amount,
    delivery_fee, order_source, _source
) VALUES (
    'ORD_TEST_001', 'CUST_99999', 'REST_99999', 'AGT_99999',
    '2026-05-20 10:00:00', 'DELIVERED', 550.00,
    30.00, 'APP', 'manual_test'
);

-- 3. Check stream now has data
SELECT SYSTEM$STREAM_HAS_DATA('FOOD_PLATFORM.BRONZE.STREAM_RAW_ORDERS');
-- Should return TRUE

-- 4. Manually trigger the Silver task
EXECUTE TASK BRONZE.TASK_CLEAN_ORDERS;

-- 5. Wait 10 seconds, check if test order landed in Silver
SELECT * FROM SILVER.CLEAN_ORDERS WHERE order_id = 'ORD_TEST_001';

-- 6. Manually trigger Gold task
EXECUTE TASK BRONZE.TASK_LOAD_GOLD;

-- 7. Check if test order appears in FACT_ORDERS
SELECT * FROM GOLD.FACT_ORDERS WHERE order_id = 'ORD_TEST_001';

-- 8. Check task run history
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP())
))
ORDER BY scheduled_time DESC;