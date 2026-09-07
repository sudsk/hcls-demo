# KFUPM Pilot 1 — GCP POC Runbook (both diabetes + obesity)

Runs the **full GCP path** on synthetic data, predicting **both** diabetes and
obesity risk in children/adolescents (8–18) — matching KFUPM's stated target:
*"a locally developed and validated model that predicts the risk of diabetes
mellitus and obesity in children and adolescents aged 8–18."*

Flow:  Synthea FHIR → GCS → **Cloud Healthcare API** (native import) →
**BigQuery** (native SQL-on-FHIR export) → OMOP-style features →
**BigQuery ML** (both model structures) → evaluate + explain + predict.

Everything is synthetic — proves method and pipeline, not clinical validity.

---

## Prerequisites
- A GCP project you own, with billing enabled
- `gcloud`, `bq`, `gcloud storage` installed and authenticated (`gcloud auth login`)
- Java 17+ (for Synthea) — only needed on the machine that generates data
- The `custom_modules/paediatric_glycemic.json` file (injects HbA1c + glucose)

## Files
| File | Does |
|---|---|
| `00_setup.sh` | Edit vars; enables APIs, creates bucket / dataset / FHIR store / BQ datasets / IAM |
| `01_generate_and_ingest.sh` | Synthea (with glycemic module) → GCS → `fhirStores.import` |
| `02_export_to_bigquery.sh` | Native FHIR store → BigQuery (Analytics V2) |
| `03a_features.sql` | Raw SQL-on-FHIR → feature table with **both** labels |
| `03b_models.sql` | BigQuery ML — Approach A (separate) + Approach B (combined) + eval/explain/predict |
| `03_build_omop_and_features.sh` | Substitutes vars and runs 03a + 03b |
| `custom_modules/paediatric_glycemic.json` | The HbA1c/glucose module |

---

## Run it (in order)

```bash
# 0. edit the vars at the top of 00_setup.sh (PROJECT_ID, REGION, ...)
nano 00_setup.sh
source 00_setup.sh
setup_gcp                      # one-time: APIs, bucket, FHIR store, BQ datasets, IAM

# 1. generate + ingest (default 500 patients; pass a number to change)
chmod +x *.sh
./01_generate_and_ingest.sh 500

# 2. FHIR store -> BigQuery (native, SQL-on-FHIR)
./02_export_to_bigquery.sh

# 3. build features (both labels) + train/evaluate both model structures
./03_build_omop_and_features.sh
```

---

## What you get

**Two label columns**, both from KFUPM's ask:
- `label_obese`    = BMI percentile-for-age ≥ 95
- `label_diabetes` = HbA1c ≥ 6.5  (plus `label_prediabetes` ≥ 5.7)

**Two model structures, to compare:**
- **Approach A** — `m_obesity` and `m_diabetes`: two separate binary models (cleanest, most interpretable; recommended for clinical use — each risk is its own explainable score).
- **Approach B** — `m_combined`: one multiclass model over 4 states (neither / obese / diabetic / both). Useful to see joint patterns, but harder to threshold clinically.

**Outputs in BigQuery** (`${BQ_OMOP}`):
- `ML.EVALUATE` → precision, recall, accuracy, f1, log_loss, **roc_auc** per model
- `ML.GLOBAL_EXPLAIN` → feature drivers (which vitals/labs push risk)
- `predictions` table → per-patient `obesity_risk` and `diabetes_risk` scores

---

## IMPORTANT sanity checks (do these — synthetic data has quirks)

1. **Class balance** — the last query in `03a` prints counts. If `diabetes` is tiny
   (few HbA1c ≥ 6.5), increase patients (`./01_... 1000`) or raise the module's
   high-weight HbA1c range. `auto_class_weights=TRUE` handles moderate imbalance.

2. **Feature nulls** — Synthea uses several LOINC codes for weight/height by age.
   Check the feature table isn't mostly null:
   ```sql
   SELECT COUNTIF(weight_kg IS NULL) n_wt_null, COUNTIF(height_cm IS NULL) n_ht_null,
          COUNTIF(fasting_glucose IS NULL) n_glu_null, COUNT(*) n
   FROM `PROJECT.kfupm_poc_omop.features`;
   ```
   If weight/height are mostly null, add the missing LOINC codes to the `AVG(IF(...))`
   lines in `03a_features.sql` (Synthea weight codes seen: 29463-7, 3141-9; height: 8302-2).

3. **No target leakage** — features deliberately EXCLUDE BMI-percentile (obesity label
   source) and HbA1c (diabetes label source). `bmi_ratio` (the raw BMI value) is kept —
   if you consider that too close to the obesity label, drop it from `03b` obesity model.

---

## How this maps to the real Pilot 1

| POC (synthetic) | Real Pilot 1 (JHAH) |
|---|---|
| Synthea FHIR + glycemic module | Epic Bulk FHIR ($export) NDJSON → GCS |
| `fhirStores.import` | same — native import (no build) |
| FHIR→BigQuery Analytics V2 | same — native export/streaming (no build) |
| `03a` feature SQL | FHIR→OMOP mapping (Whistle/Dataflow) — the EPAM build |
| labels from HbA1c / BMI-pct | clinician-defined diabetes & obesity criteria |
| BigQuery ML both structures | BigQuery ML / Agent Platform, validated on prospective set |
| synthetic metrics | real retrospective validation, then prospective in JHAH clinics |

**Two-stage framing (matches KFUPM's words):** this POC is the *first stage* —
"research-ready historical cohort + develop and retrospectively validate the
algorithms." The *second stage* (limited prospective clinical validation in JHAH
clinics) comes after real-data performance and approvals.

## Cleanup (avoid ongoing cost)
```bash
gcloud healthcare fhir-stores delete "$FHIR_STORE" --dataset="$HC_DATASET" --location="$REGION" --quiet
gcloud healthcare datasets delete "$HC_DATASET" --location="$REGION" --quiet
bq rm -r -f -d "${PROJECT_ID}:${BQ_RAW}"
bq rm -r -f -d "${PROJECT_ID}:${BQ_OMOP}"
gcloud storage rm -r "gs://$BUCKET"
```
