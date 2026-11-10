# Snowflake row-count anomaly detection and email alert

A GitHub-ready example for `APM.PROCESSED.X`, using a **manual** Snowflake SQL stored procedure and Snowflake email notification integration. No scheduler or task is required.

## What it does

- Counts rows in `APM.PROCESSED.X` when you call the procedure.
- Compares the count with an expected baseline and a tolerance percentage.
- Sends an email to `vduppuluri@xyz.com` when the count is outside the allowed range.
- Includes a **commented optional custom DMF** template for later scheduled monitoring.

> **Important:** The working manual check uses `COUNT(*)` inside a procedure. It does **not** run Snowflake's automatic ML anomaly detection or collect scheduled DMF history. The optional DMF is not active. This distinction matters when presenting the example as a DMF project.

## Prerequisites

1. A Snowflake role with appropriate access to `APM.PROCESSED.X`, `APM.PROCESSED`, and procedure creation.
2. A role with `CREATE INTEGRATION` privilege for creating the email notification integration.
3. The recipient email must be verified on a Snowflake user in the account; Snowflake email notification restrictions apply.
4. Grant `USAGE` on `APM_DQ_EMAIL` to the procedure owner role.

## Setup

Open `anomaly_detection.sql` in a Snowflake worksheet. Review the recipient and expected baseline, then run the statements in order. If the integration creation is managed by a different administrator, ask them to run that statement separately.

## Run

```sql
CALL APM.PROCESSED.SP_CHECK_X_ANOMALY(10000, 20);
```

The acceptable range is 8,000–12,000 rows (inclusive). For example, 7,000 rows triggers an alert, while 9,000 does not.

## GitHub publishing notes

- This repository contains **no credentials or private keys**.
- The sample recipient email is visible to anyone in a public repository. Replace it with a placeholder or a generic team address before publishing if privacy matters.
- The integration is an account-level Snowflake object. Obtain your administrator's approval before creating it.
- This example uses a fixed baseline; production implementations should use a well-defined reference baseline and consider false positives, audit logging, and alert deduplication.

## Further reading

- [Snowflake data quality monitoring](https://docs.snowflake.com/en/user-guide/data-quality-intro)
- [Snowflake email notifications](https://docs.snowflake.com/en/user-guide/notifications/email-notifications)
