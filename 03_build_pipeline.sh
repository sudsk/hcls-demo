#!/usr/bin/env bash
# ============================================================
# 03_build_pipeline.sh
# Runs the medallion transform chain:
#   02b_fhir_to_omop.sql  (RAW/Bronze -> OMOP/Silver)
#   03a_cohort.sql        (OMOP/Silver -> CURATED cohort+features / Gold)
#   03b_models.sql        (CURATED -> BQ_MODELS: train + evaluate + explain + predict)
# ============================================================
set -e
: "${PROJECT_ID:?run: source 00_setup.sh first}"

run_sql () {
  local f="$1"
  echo ">> running $f ..."
  sed -e "s/\${PROJECT_ID}/${PROJECT_ID}/g" \
      -e "s/\${BQ_RAW}/${BQ_RAW}/g" \
      -e "s/\${BQ_OMOP}/${BQ_OMOP}/g" \
      -e "s/\${BQ_CURATED}/${BQ_CURATED}/g" \
      -e "s/\${BQ_MODELS}/${BQ_MODELS}/g" "$f" \
  | bq query --use_legacy_sql=false --project_id="$PROJECT_ID" --format=pretty
}

echo "=== SILVER: FHIR -> OMOP CDM ==="
run_sql 02b_fhir_to_omop.sql

echo ""
echo "=== GOLD: OMOP -> cohort + features ==="
run_sql 03a_cohort.sql

echo ""
echo "=== MODELS: train + evaluate + explain + predict ==="
run_sql 03b_models.sql

echo ""
echo ">> done. Datasets:"
echo "   ${BQ_RAW}      (Bronze)  — SQL-on-FHIR"
echo "   ${BQ_OMOP}     (Silver)  — OMOP CDM: person, measurement, condition_occurrence, ..."
echo "   ${BQ_CURATED}  (Gold)    — cohort + features (both labels)"
echo "   ${BQ_MODELS}             — m_obesity, m_diabetes, m_combined, predictions"
