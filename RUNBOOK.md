# Runbook — Paediatric Diabetes & Obesity Risk POC

Full GCP path on synthetic data, predicting **both** diabetes and obesity risk in
children/adolescents (8–18), built through a medallion architecture
(Bronze → Silver/OMOP → Gold/cohort → models).

Everything is synthetic — proves method and pipeline, not clinical validity.

---

## Prerequisites
- A GCP project you own, with billing enabled
- `gcloud`, `bq`, `gcloud storage` installed and authenticated (`gcloud auth login`)
- Java 17+ (for Synthea) — only on the machine that generates data
- `custom_modules/paediatric_glycemic.json` present (injects HbA1c + glucose)

---

## Steps

### 0. Setup
```bash
cp 00_setup.sh setup_local.sh      # gitignored; holds your real values
nano setup_local.sh                # PROJECT_ID, REGION, dataset names
source setup_local.sh
setup_gcp                          # APIs, bucket, FHIR store, 4 BQ datasets, IAM
```
Region: for a throwaway POC `us-central1` is simplest. For in-Kingdom use
`me-central1/2` — but confirm Healthcare API + BQML feature availability there first.

### 1. Generate + ingest (Bronze in)
```bash
chmod +x *.sh
./01_generate_and_ingest.sh 500    # Synthea (NDJSON) -> GCS -> fhirStores.import
```
Verify (the `_summary=count` FHIR param is NOT supported; use the import counter):
```bash
gcloud healthcare operations describe <OP_ID> \
  --dataset="$HC_DATASET" --location="$REGION" --format="yaml(metadata)"
# look for counter.success (~150k resources for 500 patients)
```

### 2. FHIR store → BigQuery (Bronze)
```bash
./02_export_to_bigquery.sh
```
Prints table row counts. Observation should be the largest (tens of thousands).

Sanity-check the key LOINC codes are present before building features:
```bash
bq query --use_legacy_sql=false --project_id="$PROJECT_ID" "
SELECT o.code.coding[SAFE_OFFSET(0)].code AS loinc, COUNT(*) n,
       ROUND(AVG(o.value.quantity.value),1) avg_val
FROM \`${PROJECT_ID}.${BQ_RAW}.Observation\` o
WHERE o.code.coding[SAFE_OFFSET(0)].code IN ('4548-4','1558-6','59576-9','29463-7','8302-2')
GROUP BY loinc ORDER BY n DESC"
```
Expect: 4548-4 (HbA1c ~5.3%), 1558-6 (glucose ~90), 59576-9 (BMI-pct), 29463-7 (weight), 8302-2 (height).

### 3. OMOP → cohort → models (Silver, Gold, models)
```bash
./03_build_pipeline.sh
```
Runs, in order:
- `02b_fhir_to_omop.sql` — OMOP tables (person, measurement, …) + counts
- `03a_cohort.sql` — cohort + features + **class balance**
- `03b_models.sql` — train A (separate) + B (combined), evaluate, explain, predict

---

## What you get

**OMOP (Silver, `..._omop`):** person, measurement, condition_occurrence,
visit_occurrence, observation_period, drug_exposure — correct OMOP structure,
`*_concept_id` = 0 placeholder (vocabulary mapping is production work).

**Gold (`..._curated`):** `cohort` (8–18 study population) + `features`
(variables + `label_obese`, `label_diabetes`, `label_prediabetes`).

**Models (`..._models`):**
- `m_obesity`, `m_diabetes` (Approach A — separate binary)
- `m_combined` (Approach B — multiclass: neither / obese / diabetic / both)
- `predictions` (per-patient `obesity_risk` + `diabetes_risk`)
- `ML.EVALUATE` (roc_auc, precision, recall, …) and `ML.GLOBAL_EXPLAIN` per model

---

## Sanity checks (synthetic data has quirks)

1. **Class balance** — printed by `03a`. With avg HbA1c ~5.3%, the diabetic class
   (HbA1c ≥ 6.5) may be small. If diabetes positives are in single digits, the
   diabetes model is noisy — generate more patients (`./01_... 1000`) or widen the
   module's high-weight HbA1c band. `auto_class_weights=TRUE` handles moderate imbalance.

2. **Feature nulls** — Synthea uses several LOINC codes for weight/height by age.
   If features are mostly null, add codes to the `AVG(IF(...))` lines in `03a_cohort.sql`
   (weight seen: 29463-7; height: 8302-2).

3. **No target leakage** — features exclude BMI-percentile (obesity label source) and
   HbA1c (diabetes label source). `bmi_ratio` is kept; drop it from the obesity model
   in `03b` if you consider it too close to the label.

---

## Cleanup (avoid ongoing cost)
```bash
gcloud healthcare fhir-stores delete "$FHIR_STORE" --dataset="$HC_DATASET" --location="$REGION" --quiet
gcloud healthcare datasets delete "$HC_DATASET" --location="$REGION" --quiet
bq rm -r -f -d "${PROJECT_ID}:${BQ_RAW}"
bq rm -r -f -d "${PROJECT_ID}:${BQ_OMOP}"
bq rm -r -f -d "${PROJECT_ID}:${BQ_CURATED}"
bq rm -r -f -d "${PROJECT_ID}:${BQ_MODELS}"
gcloud storage rm -r "gs://$BUCKET"
```
