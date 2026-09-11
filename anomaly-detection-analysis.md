# Anomaly Detection Failure — Root Cause Analysis & Remediation

**Subject:** APPLESUB — Sum of File Row Count, Quarterly Anomaly Detection
**Issue:** 2026Q2 was not flagged as an outlier despite a severe −39.45% QoQ decline

---

## Table of Contents

1. [Original Source Data](#1-original-source-data)
2. [Problem Statement](#2-problem-statement)
3. [Root Cause Analysis](#3-root-cause-analysis)
4. [Root Cause Confirmation — Simulation by Exclusion of Quarters](#4-root-cause-confirmation--simulation-by-exclusion-of-quarters)
5. [Proposed Remedies](#5-proposed-remedies)
6. [Simulation Results — All Remedies](#6-simulation-results--all-remedies)
7. [Conclusion](#7-conclusion)

---

## 1. Original Source Data

**Source:** Confluence chart data / `analysis.txt` — Supplier code `APPLESUB`, Performance quarter, Sum of file row count. 21 rows total.

| Supplier code | Performance quarter | Sum of file row count |
|---|---|---|
| APPLESUB | 2021Q3 | 324,707,947 |
| APPLESUB | 2021Q4 | 654,764,459 |
| APPLESUB | `202106` | 122,895,516 |
| APPLESUB | 2022Q1 | 408,940,767 |
| APPLESUB | 2022Q2 | 424,370,177 |
| APPLESUB | 2022Q3 | 427,676,794 |
| APPLESUB | 2022Q4 | 449,924,216 |
| APPLESUB | 2023Q1 | 463,641,638 |
| APPLESUB | 2023Q2 | 477,623,972 |
| APPLESUB | 2023Q3 | 491,766,367 |
| APPLESUB | 2023Q4 | 496,103,416 |
| APPLESUB | 2024Q1 | 517,829,803 |
| APPLESUB | 2024Q2 | 519,866,831 |
| APPLESUB | 2024Q3 | 528,602,201 |
| APPLESUB | 2024Q4 | 543,076,211 |
| APPLESUB | 2025Q1 | 555,738,322 |
| APPLESUB | 2025Q2 | 569,493,565 |
| APPLESUB | 2025Q3 | 575,829,649 |
| APPLESUB | 2025Q4 | 592,308,184 |
| APPLESUB | 2026Q1 | 601,587,964 |
| APPLESUB | 2026Q2 | 364,246,571 |

> **Note:** The row labeled `202106` does not match the expected `YYYYQ#` quarter format. This is flagged as a likely data quality defect (mislabeled month, partial period, or duplicate/backfill artifact) and is a key contributor to the root cause described in Section 3.

**Original outlier-detection calculation** (as documented in `Anomaly_Detection_Explanation.md`):

```python
group['rolling_mean'] = (
    group['SUM_FILEROWCOUNT']
    .rolling(window=20)
    .mean()
)

group['rolling_std'] = (
    group['SUM_FILEROWCOUNT']
    .rolling(window=20)
    .std(ddof=0)
)

group['z_score'] = (
    (group['SUM_FILEROWCOUNT'] - group['rolling_mean'])
    / group['rolling_std']
)

group['OUTLIER_STATUS'] = (
    (group['z_score'] > 2.5)
    | (group['z_score'] < -2.5)
)
```

For a row being evaluated, `rolling(window=20)` includes the current row and the previous 19 rows.

---

## 2. Problem Statement

The anomaly-detection logic failed to flag **2026Q2** as an outlier despite a severe decline in Sum of File Row Count:

- 2026Q1: 601,587,964
- 2026Q2: 364,246,571
- QoQ decline: `(364,246,571 − 601,587,964) / 601,587,964 × 100 = −39.45%`

**Current method:** Rolling mean and rolling standard deviation over a 20-quarter window on raw levels, converted to a z-score, flagged if `|z| > 2.5`.

**Actual result:**
- z-score on raw levels: **−1.66**
- z-score on QoQ% change: **−0.88**

Both are well inside the "normal" threshold, so the quarter was never flagged.

**Business impact:** A significant, genuine business anomaly went undetected, undermining confidence in the anomaly-detection pipeline for future quarters.

---

## 3. Root Cause Analysis

### 3.1 Initial hypothesis — trend contamination

The underlying data is a steadily growing series (from ~325M in 2021Q3 to ~601M in 2026Q1). A standard deviation computed on raw levels partly reflects this upward trend rather than pure noise, inflating the "normal" tolerance band. Converting to QoQ percentage change removes most of this effect — but testing showed this alone was **not sufficient** to catch the anomaly.

### 3.2 Actual root cause — the rolling window is contaminated by two historical anomalies

Reviewing the full 21-row source dataset revealed two problem periods sitting inside the rolling window used to define "normal":

| Period | Value | QoQ % Change | Nature of the issue |
|---|---|---|---|
| 2021Q4 | 654,764,459 | **+101.6%** | Genuine but extreme historical spike |
| `202106` | 122,895,516 | **−81.2%** | Invalid period label — likely a data quality defect |
| 2022Q1 | 408,940,767 | **+232.8%** | Statistical rebound artifact caused by the invalid prior row |

These extreme values inflate the rolling standard deviation wherever they fall inside the calculation window. A wider standard deviation produces a wider "acceptable" range — wide enough that even a genuine −39.45% drop in 2026Q2 falls within it and goes unflagged.

**Conclusion:** The anomaly-detection concept is not flawed. The failure occurred because the training data used to define "normal" was itself contaminated by unresolved historical anomalies — one of which (`202106`) appears to be an outright data quality defect rather than a real business event.

---

## 4. Root Cause Confirmation — Simulation by Exclusion of Quarters

To confirm the root cause, `202106` and 2021Q4 were excluded individually and together, across window sizes 12–20.

### 4.1 z-score for 2026Q2 by exclusion scenario

| Window | No exclusion | Exclude `202106` only | Exclude 2021Q4 only | Exclude BOTH |
|---|---|---|---|---|
| 12 | −3.30 | −3.30 | −3.30 | −3.30 |
| 13 | −3.45 | −3.45 | −3.45 | −3.45 |
| 14 | −3.59 | −3.59 | −3.59 | −3.59 |
| 15 | −3.72 | −3.72 | −3.72 | −3.72 |
| 16 | −3.84 | −3.84 | −3.84 | −3.84 |
| 17 | −3.97 | −3.97 | −3.97 | −3.97 |
| 18 | −0.97 | −2.89 | −0.97 | −3.60 |
| 19 | −0.84 | −1.62 | −0.87 | −3.60 |
| 20 (current) | −0.88 | −1.62 | −0.87 | −3.60 |

### 4.2 Flagged? (`|z| > 2.5`)

| Window | No exclusion | Exclude `202106` only | Exclude 2021Q4 only | Exclude BOTH |
|---|---|---|---|---|
| 12–17 | ✅ | ✅ | ✅ | ✅ |
| 18 | ❌ | ✅ | ❌ | ✅ |
| 19 | ❌ | ❌ | ❌ | ✅ |
| 20 | ❌ | ❌ | ❌ | ✅ |

### 4.3 Interpretation

- Windows 12–17 detect the anomaly regardless of exclusion — neither problem quarter is old enough to be inside the window at that length.
- **At window 18**, 2021Q4 enters the window; detection fails unless it (or `202106`) is removed.
- **At windows 19–20** (which includes the current production setting of 20), **both** problem quarters are inside the window simultaneously. Removing only one is insufficient — detection is restored only when **both** are excluded (z stabilizes at −3.60).
- This confirms the root cause: **the combined presence of 2021Q4 and `202106` inside the current 20-quarter training window** suppresses detection — not a flaw in the z-score concept itself.
- It also confirms a practical risk with exclusion-based fixes: the correct exclusion list is not fixed — it changes with window size, requiring ongoing manual maintenance and offering no protection against future, yet-undiscovered anomalies.

---

## 5. Proposed Remedies

Three statistically robust remedies were evaluated, tested on the **full, unmodified dataset**, with no quarters manually removed.

### 5.1 Remedy A — Winsorized Rolling Z-Score

**What it does:** Before calculating the rolling mean/standard deviation (the "baseline"), any QoQ% value beyond a fixed cap (e.g., ±15%) is capped down to that limit *only for the baseline calculation*. The actual, real value is still compared against this cleaned baseline to compute the final z-score. No data is deleted — extreme values are softened, not removed.

```python
cap = 15  # percentage points

df["qoq_pct"] = df["val"].pct_change() * 100
df["qoq_pct_for_training"] = df["qoq_pct"].clip(lower=-cap, upper=cap)

df["rolling_mean"] = df["qoq_pct_for_training"].rolling(window=12, min_periods=4).mean()
df["rolling_std"]  = df["qoq_pct_for_training"].rolling(window=12, min_periods=4).std(ddof=0)

df["z"] = (df["qoq_pct"] - df["rolling_mean"]) / df["rolling_std"]
df["is_outlier"] = df["z"].abs() > 2.5
```

**Why it works:** 2021Q4's +101.6% and `202106`'s −81.2% are pulled down to ±15% before they can inflate the standard deviation. The tolerance band shrinks back to a realistic size, and the −39.45% drop stands out clearly.

### 5.2 Remedy B — Robust Statistics (Median + MAD)

**What it does:** Replaces the rolling mean/standard deviation with the rolling median and Median Absolute Deviation (MAD) — measures naturally resistant to extreme values. A "modified z-score" is computed using the standard 0.6745 scaling constant.

```python
def rolling_mad(x):
    med = np.median(x)
    return np.median(np.abs(x - med))

roll_median = df["qoq_pct"].rolling(window=12, min_periods=4).median()
roll_mad    = df["qoq_pct"].rolling(window=12, min_periods=4).apply(rolling_mad, raw=True)

df["mod_z"] = 0.6745 * (df["qoq_pct"] - roll_median) / roll_mad
df["is_outlier"] = df["mod_z"].abs() > 3.5
```

**Why it works:** The median and MAD are effectively "outvoted" by the majority of ordinary quarters, so the extreme historical periods have almost no influence on the baseline — without needing to identify or remove them manually.

**Known limitation:** If MAD = 0 in a given window (can occur when several values are very close together), the calculation produces a division-by-zero (`NaN`). Observed once in testing at window=20. A fallback (e.g., default to standard deviation, or add a small epsilon) should be implemented in production.

### 5.3 Remedy C — Iterative Sigma-Clipping

**What it does:** Calculates mean/standard deviation from the window, removes values beyond a set number of standard deviations (e.g., 2.5), recalculates from what remains, and repeats (e.g., 2 iterations).

```python
def sigma_clip_mean_std(x, n_sigma=2.5, iterations=2):
    x = np.array(x, dtype=float)
    x = x[~np.isnan(x)]
    for _ in range(iterations):
        if len(x) == 0:
            return np.nan, np.nan
        m, s = np.mean(x), np.std(x)
        if s == 0:
            break
        mask = np.abs(x - m) <= n_sigma * s
        if mask.all():
            break
        x = x[mask]
    return np.mean(x), np.std(x)
```

**Why it works:** A single pass is sometimes insufficient when multiple extreme values sit close together (as here), because the first pass's statistics are still too contaminated to correctly identify all bad points at once. Iterating fully separates the anomalies from the normal quarters before finalizing the baseline.

**Known limitation:** z-score magnitude can shift abruptly at certain window sizes (still correctly flagged, but less predictable than winsorizing).

---

## 6. Simulation Results — All Remedies

Tested on the full 21-row dataset, no quarters removed, windows 12–20.

### 6.1 z-score for 2026Q2

| Window | Winsorized (cap ±15%) | Robust MAD | Sigma-clip (2.5σ, 2 iter) |
|---|---|---|---|
| 12 | −8.29 | −31.97 | −38.33 |
| 13 | −8.59 | −41.19 | −39.03 |
| 14 | −8.88 | −41.26 | −39.73 |
| 15 | −9.00 | −35.58 | −33.19 |
| 16 | −9.29 | −36.20 | −32.37 |
| 17 | −9.52 | −31.13 | −32.32 |
| 18 | −8.00 | −25.72 | −32.32 |
| 19 | −6.41 | −21.79 | −3.97 |
| 20 | −6.02 | −21.33 | −3.97 |

### 6.2 Flagged? (own standard threshold: Winsorized/Sigma-clip = `|z|>2.5`, MAD = `|mod-z|>3.5`)

| Window | Winsorized | Robust MAD | Sigma-clip |
|---|---|---|---|
| 12–20 (all) | ✅ True | ✅ True | ✅ True |

**All three remedies successfully flag the anomaly at every window size tested, with no manual data removal required.**

### 6.3 False-positive check — 2026Q1 (a genuinely normal +1.57% quarter)

| Window | Plain z-score | Winsorized | Robust MAD | Sigma-clip |
|---|---|---|---|---|
| 12–20 (all) | ❌ False | ❌ False | ❌ False | ❌ False |

**None of the remedies incorrectly flag a healthy quarter** — confirming they solve the missed-detection problem without introducing new false positives.

### 6.4 Consolidated comparison

| Method | Manual data removal required? | Detects 2026Q2 (windows 12–20)? | False positive on 2026Q1? | Known limitation |
|---|---|---|---|---|
| Current production method | No | ❌ Fails | No | Root cause of this issue |
| Exclude both anomalies manually | Yes | ✅ Passes | No | Fragile; requires maintaining an exclusion list; no protection against future unknown anomalies |
| **Winsorized z-score** | **No** | ✅ **Passes** | No | Requires choosing a cap % |
| Robust MAD | No | ✅ Passes | No | Division-by-zero edge case when MAD=0 |
| Sigma-clipping | No | ✅ Passes | No | Less predictable magnitude shifts at certain window sizes |

---

## 7. Conclusion

The failure to detect the 2026Q2 anomaly was not a defect in the underlying anomaly-detection concept, but a consequence of **an unvalidated, contaminated training baseline**. Two historical periods — a genuine but extreme spike in 2021Q4, and a data-quality defect (`202106`, an invalid period label) — sat inside the current 20-quarter rolling window and inflated the standard deviation enough to mask a real, severe decline.

Simulation confirmed this root cause directly: removing either problem quarter alone was insufficient at the current window size; only removing both restored detection, and even then only in a way that depends on knowing exactly which historical quarters are problematic — a fragile, manually maintained fix.

All three proposed statistically robust remedies (winsorizing, robust median/MAD, and iterative sigma-clipping) solved the problem **without requiring any manual identification or removal of historical data**, and did so without introducing false positives on genuinely normal quarters.

### Recommendation

1. **Winsorized rolling z-score** is recommended as the primary remedy, due to its simplicity, interpretability, and consistent, stable performance across every window size tested.
2. **Data validation rule:** Reject any period label that doesn't match the expected `YYYYQ#` format — this would have caught `202106` automatically at the source.
3. **Hard backstop rule:** Independently flag any quarter with a QoQ decline steeper than −25%, regardless of the statistical method's result, to guarantee detection of severe drops even if the statistical method is compromised in the future.

---

*Document prepared for internal review and GitHub archival — Anomaly Detection Explanation series.*
