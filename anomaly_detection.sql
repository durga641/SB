-- Snowflake data-quality anomaly alert: manual execution, no scheduler.
-- Target: APM.PROCESSED.X
-- Public-repo safe: replace the example recipient before deployment.
-- Requires privileges to create procedures and notification integrations.
-- Email recipient must be a verified email address for a Snowflake user.

-- 1. ACCOUNTADMIN (or a role granted CREATE INTEGRATION): run once.
-- Change this example recipient for your environment.
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS APM_DQ_EMAIL
  TYPE = EMAIL
  ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('vduppuluri@xyz.com');

-- 2. Create a custom DMF for future scheduled monitoring.
-- Snowflake requires at least one table column in a custom DMF signature.
-- Replace <NUMERIC_COLUMN> with a real NUMBER column in APM.PROCESSED.X.
-- This optional block is commented out because table schema is unknown.
/*
CREATE OR REPLACE DATA METRIC FUNCTION APM.PROCESSED.DMF_X_ROW_COUNT(
    T TABLE(MARKER NUMBER)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT(*) FROM T
$$;

ALTER TABLE APM.PROCESSED.X
  ADD DATA METRIC FUNCTION APM.PROCESSED.DMF_X_ROW_COUNT
  ON (<NUMERIC_COLUMN>);
-- Scheduled DMF evaluation is NOT enabled in this example.
*/

-- 3. Immediate manual anomaly check, independent of DMF scheduling.
-- Rule: email when current row count deviates more than tolerance_pct
-- from expected_count. This is threshold detection, NOT Snowflake ML anomaly detection.
CREATE OR REPLACE PROCEDURE APM.PROCESSED.SP_CHECK_X_ANOMALY(
    EXPECTED_COUNT NUMBER,
    TOLERANCE_PCT FLOAT
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_COUNT NUMBER;
    V_MIN FLOAT;
    V_MAX FLOAT;
    V_BODY VARCHAR;
BEGIN
    IF (EXPECTED_COUNT < 0 OR TOLERANCE_PCT < 0 OR TOLERANCE_PCT > 100) THEN
        RETURN 'ERROR: expected_count must be >= 0 and tolerance_pct between 0 and 100';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM APM.PROCESSED.X;
    V_MIN := EXPECTED_COUNT * (1 - TOLERANCE_PCT / 100);
    V_MAX := EXPECTED_COUNT * (1 + TOLERANCE_PCT / 100);

    IF (V_COUNT < V_MIN OR V_COUNT > V_MAX) THEN
        V_BODY := 'Row-count anomaly in APM.PROCESSED.X'
            || '\nActual count: ' || V_COUNT
            || '\nExpected count: ' || EXPECTED_COUNT
            || '\nAccepted range: ' || V_MIN || ' to ' || V_MAX
            || '\nChecked at: ' || CURRENT_TIMESTAMP()::VARCHAR;

        CALL SYSTEM$SEND_EMAIL(
            'APM_DQ_EMAIL',
            'vduppuluri@xyz.com',
            'Snowflake anomaly alert: APM.PROCESSED.X',
            :V_BODY
        );
        RETURN 'ANOMALY DETECTED: email request submitted; actual count = ' || V_COUNT;
    END IF;

    RETURN 'NORMAL: actual count = ' || V_COUNT;
END;
$$;

-- 4. Run manually (sample expected count: 10,000 +/- 20%).
CALL APM.PROCESSED.SP_CHECK_X_ANOMALY(10000, 20);

-- Optional: grant USAGE on integration to the procedure-owning role.
-- GRANT USAGE ON INTEGRATION APM_DQ_EMAIL TO ROLE <PROCEDURE_OWNER_ROLE>;
