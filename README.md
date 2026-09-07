# Paediatric Diabetes & Obesity Risk — Bio-Data Platform POC (synthetic data)

Proof-of-concept for a clinical bio-data platform on Google Cloud: paediatric
**diabetes & obesity risk prediction** (ages 8–18), delivered end-to-end using
**synthetic data only** (no PHI, no real patient data).

It proves the full medallion pipeline:

```
Synthea FHIR → GCS → Cloud Healthcare API (native import)
→ BigQuery (native SQL-on-FHIR export) [Bronze]
→ OMOP CDM [Silver]
→ curated cohort + features [Gold]
→ BigQuery ML (both model structures) → evaluate / explain / predict
```


> **Synthetic only.** This proves the *method and pipeline*, not clinical validity.
> Real predictive performance comes only from real data. All data here is generated
> by [Synthea](https://github.com/synthetichealth/synthea).

---

## Medallion layers (BigQuery datasets)

| Dataset (`*_raw`, `*_omop`, ...) | Layer | Contents |
|---|---|---|
| `..._raw` | **Bronze** | SQL-on-FHIR tables (Patient, Observation, Condition, …) — as exported |
| `..._omop` | **Silver** | OMOP CDM — person, measurement, condition_occurrence, visit_occurrence, drug_exposure. **Study-agnostic, reusable.** |
| `..._curated` | **Gold** | `cohort` (study population) + `features` (variables + both labels). Study-specific. |
| `..._models` | — | trained BQML models + predictions |

**Why the split:** OMOP (Silver) stays reusable across studies; the cohort/features
(Gold) are one study's product built *from* OMOP. Curate once, serve many.

---

## What's here

| File | Purpose |
|---|---|
| `00_setup.sh` | Edit vars; enables APIs, creates bucket / FHIR store / BQ datasets / IAM |
| `01_generate_and_ingest.sh` | Synthea (NDJSON bulk) → GCS → `fhirStores.import` |
| `02_export_to_bigquery.sh` | Native FHIR store → BigQuery (Analytics V2 / SQL-on-FHIR) — Bronze |
| `02b_fhir_to_omop.sql` | Bronze → OMOP CDM — Silver |
| `03a_cohort.sql` | OMOP → cohort + features (both labels) — Gold |
| `03b_models.sql` | BigQuery ML — separate models (A) + combined multiclass (B) + eval/explain/predict |
| `03_build_pipeline.sh` | Runs 02b → 03a → 03b |
| `custom_modules/paediatric_glycemic.json` | Synthea module injecting HbA1c + fasting glucose (age 8–18), correlated to weight |
| `RUNBOOK.md` | Full step-by-step runbook + sanity checks |

**Not committed** (see `.gitignore`): the Synthea jar, generated `output/`,
NDJSON/CSV data, and any local config with real project IDs.

---

## Quickstart

```bash
# 1. copy the template; put real values in a LOCAL (gitignored) file
cp 00_setup.sh setup_local.sh
nano setup_local.sh              # set PROJECT_ID, REGION, ...
source setup_local.sh
setup_gcp                        # one-time: APIs, bucket, FHIR store, BQ datasets, IAM

# 2. generate synthetic data + ingest to Cloud Healthcare API
chmod +x *.sh
./01_generate_and_ingest.sh 500

# 3. FHIR store -> BigQuery (Bronze)
./02_export_to_bigquery.sh

# 4. OMOP (Silver) -> cohort+features (Gold) -> models
./03_build_pipeline.sh
```

See `RUNBOOK.md` for detail and troubleshooting.

---

## The two outcomes

A locally developed and validated model predicting the risk of **diabetes mellitus
and obesity** in children and adolescents aged 8–18.

- `label_obese`    = BMI percentile-for-age ≥ 95
- `label_diabetes` = HbA1c ≥ 6.5 (prediabetes flag ≥ 5.7 also provided)

Two model structures, to compare:
- **A — separate** binary models (`m_obesity`, `m_diabetes`) — recommended for clinical
  use (each risk is its own explainable score).
- **B — combined** multiclass (`m_combined`) — one model over 4 states (neither / obese
  / diabetic / both).

---

## Key implementation notes (learned the hard way)

- **Synthea must output NDJSON bulk data** (`--exporter.fhir.bulk_data true`) and be
  imported with `--content-structure=RESOURCE`. Transaction-bundle JSON with
  `content-structure=BUNDLE` fails import at scale.
- **FHIR store → BigQuery is native** (`fhir-stores export bq`, schema `analytics_v2`)
  — no pipeline. The **FHIR→OMOP** mapping (`02b`) is the custom-built part.
- **OMOP concept mapping:** this POC builds correct OMOP **structure** with
  `*_source_value` populated and `*_concept_id` = 0 (placeholder). Production loads
  the OMOP vocabulary (SNOMED/LOINC/RxNorm → concept) to fill `concept_id`.
- On managed GCP projects with conditional IAM policies, `add-iam-policy-binding`
  needs `--condition=None` (already in `00_setup.sh`).
- Cloud Shell has ~5 GB disk — delete `output/` after upload; the import runs
  server-side from GCS.

---

## Security / data

- **No real patient data. No PHI.** 100% Synthea-generated synthetic data.
- Do not commit real project IDs, service-account keys, or `.env` files
  (see `.gitignore`). Keep real config in a gitignored `setup_local.sh`.
