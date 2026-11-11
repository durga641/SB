-- ============================================================================
-- Snowflake native DMF anomaly detection: APM.PROCESSED.X
-- Public GitHub-safe template (no credentials, email addresses, or secrets).
-- Reference: https://docs.snowflake.com/en/user-guide/data-quality-anomaly
-- Requires Snowflake Enterprise Edition or higher and suitable privileges.
--
-- BEFORE RUNNING:
--   1. Replace YOUR_WAREHOUSE and alerts@example.com below.
--   2. Recipient must be a verified email for a Snowflake user.
--   3. Run as a role authorized to alter the table, create alerts/integrations,
--      and access Snowflake data-quality monitoring results.
--   4. Execute the ADD association only if ROW_COUNT is not already attached.
--   5. Run the sections in order. RESUME is deliberately last.
-- ============================================================================

-- 01. Preflight checks
SELECT CURRENT_ROLE() AS CURRENT_ROLE, CURRENT_WAREHOUSE() AS CURRENT_WAREHOUSE;
DESCRIBE TABLE APM.PROCESSED.X;
SELECT COUNT(*) AS CURRENT_ROW_COUNT FROM APM.PROCESSED.X;

-- 02. Schedule measurements hourly (changes the table's existing DMF schedule)
ALTER TABLE APM.PROCESSED.X
  SET DATA_METRIC_SCHEDULE = '60 MINUTE';

-- 03. Enable built-in ML anomaly detection on ROW_COUNT.
-- Run this ADD only when no association exists for ROW_COUNT ON ().
ALTER TABLE APM.PROCESSED.X
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
  ANOMALY_DETECTION = TRUE;

-- ALTERNATIVE (do not run if you successfully ran ADD above):
-- ALTER TABLE APM.PROCESSED.X
--   MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
--   SET ANOMALY_DETECTION = TRUE;

-- 04. Inspect DMF association
SELECT *
FROM TABLE(APM.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  REF_ENTITY_NAME => 'APM.PROCESSED.X',
  REF_ENTITY_DOMAIN => 'TABLE'
));

-- 05. Create an email notification integration.
-- Requires CREATE INTEGRATION privilege. Reuse an existing approved integration
-- instead if your organization restricts integration creation.
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS APM_DMF_ANOMALY_EMAIL_INT
  TYPE = EMAIL
  ENABLED = TRUE;

-- 06. View results; anomaly verdicts may be NULL during model training.
-- Access requires SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER or ADMIN app role.
SELECT MEASUREMENT_TIME, TABLE_DATABASE, TABLE_SCHEMA, TABLE_NAME,
       METRIC_NAME, VALUE AS OBSERVED_ROW_COUNT, FORECAST,
       LOWERBOUND, UPPERBOUND, IS_ANOMALY
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_ANOMALY_DETECTION_STATUS
WHERE TABLE_DATABASE = 'APM'
  AND TABLE_SCHEMA = 'PROCESSED'
  AND TABLE_NAME = 'X'
  AND METRIC_NAME = 'ROW_COUNT'
ORDER BY MEASUREMENT_TIME DESC
LIMIT 20;

-- 07. Create hourly alert for newly measured anomalies.
-- Replace YOUR_WAREHOUSE with a valid warehouse identifier and replace the email.
-- This simple rolling-window approach may notify twice for a result when the
-- DMF/alert schedules drift. Use a processed-measurement watermark for strict
-- exactly-once notifications in production.
CREATE OR REPLACE ALERT APM.PROCESSED.X_ROW_COUNT_ANOMALY_ALERT
  WAREHOUSE = YOUR_WAREHOUSE
  SCHEDULE = '60 MINUTE'
  IF (EXISTS (
    SELECT 1
    FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_ANOMALY_DETECTION_STATUS
    WHERE TABLE_DATABASE = 'APM'
      AND TABLE_SCHEMA = 'PROCESSED'
      AND TABLE_NAME = 'X'
      AND METRIC_NAME = 'ROW_COUNT'
      AND IS_ANOMALY = TRUE
      AND MEASUREMENT_TIME >= DATEADD('MINUTE', -60, CURRENT_TIMESTAMP())
  ))
  THEN CALL SYSTEM$SEND_EMAIL(
    'APM_DMF_ANOMALY_EMAIL_INT',
    'alerts@example.com',
    'Snowflake DMF anomaly: APM.PROCESSED.X',
    'A row-count anomaly was detected for APM.PROCESSED.X. Query SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_ANOMALY_DETECTION_STATUS for measurement time, actual value, forecast, and bounds.'
  );

-- 08. Activate after validating configuration and email integration
ALTER ALERT APM.PROCESSED.X_ROW_COUNT_ANOMALY_ALERT RESUME;

-- 09. Verify alert
SHOW ALERTS LIKE 'X_ROW_COUNT_ANOMALY_ALERT' IN SCHEMA APM.PROCESSED;

-- 10. Optional manual email test (uncomment only after replacing the address)
-- CALL SYSTEM$SEND_EMAIL(
--   'APM_DMF_ANOMALY_EMAIL_INT',
--   'alerts@example.com',
--   'Snowflake DMF test',
--   'Test message from the APM row-count anomaly monitoring deployment.'
-- );

-- NOTES:
-- * This detects unusual TOTAL table row counts, not individual anomalous rows.
-- * Frequent DMF schedules require at least ~2 weeks of historical measurements
--   for Snowflake's anomaly model to begin producing meaningful verdicts.
-- * A stable row count on an append-only table may be unsuitable for detecting
--   daily ingestion anomalies; consider a per-day volume design instead.
-- * Do not publish account-specific emails, integration details or secrets.
