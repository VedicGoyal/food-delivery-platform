-- Wrapper procedure: calls all Gold procedures in order
CREATE OR REPLACE PROCEDURE GOLD.SP_LOAD_ALL_GOLD()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- 1. Dimensions first (SCD Type 2)
    CALL GOLD.SP_LOAD_DIM_CUSTOMER();
    CALL GOLD.SP_LOAD_DIM_RESTAURANT();
    CALL GOLD.SP_LOAD_DIM_DELIVERY();

    -- 2. Facts (need dimension SKs)
    CALL GOLD.SP_LOAD_FACT_ORDERS();
    CALL GOLD.SP_LOAD_FACT_PAYMENTS();

    -- 3. Aggregations (need fact data)
    CALL GOLD.SP_AGG_HOURLY_KPI();
    CALL GOLD.SP_AGG_CITY_DAILY();
    CALL GOLD.SP_AGG_PAYMENT_MIX();

    RETURN 'Gold layer fully refreshed';
END;
$$;

-- Task: fires every 30 min when Silver orders stream has new data
-- Orders stream is the primary indicator that new data arrived
CREATE TASK IF NOT EXISTS BRONZE.TASK_LOAD_GOLD
  WAREHOUSE = TRANSFORM_WH
  SCHEDULE  = '30 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('FOOD_PLATFORM.SILVER.STREAM_CLEAN_ORDERS')
AS
  CALL GOLD.SP_LOAD_ALL_GOLD();