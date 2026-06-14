USE ROLE SYSADMIN;
USE SCHEMA FOOD_PLATFORM.BRONZE;

CREATE STAGE IF NOT EXISTS ADLS_RAW_STAGE
    URL = 'azure://foodplatformvedic.blob.core.windows.net/raw-data/'
    CREDENTIALS = (
        AZURE_SAS_TOKEN = '?sv=2026-02-06&ss=b&srt=co&sp=rlx&se=2028-03-10T14:48:22Z&st=2026-05-21T06:33:22Z&spr=https&sig=HX9zjga1tWV6s8%2BOqbIaFwea2V2cOidx6Lcsug6dx7k%3D'
    );

LIST @BRONZE.ADLS_RAW_STAGE;

SELECT $1, $2, $3
FROM @BRONZE.ADLS_RAW_STAGE/orders/
(FILE_FORMAT => FF_CSV)
LIMIT 5;