#!/usr/bin/env bash
# ============================================================
# 02_export_to_bigquery.sh
# Native FHIR store -> BigQuery export (SQL-on-FHIR / Analytics V2 schema).
# One BigQuery table per FHIR resource type. No pipeline/build.
# ============================================================
set -e
: "${PROJECT_ID:?run: source 00_setup.sh first}"

echo ">> exporting FHIR store -> BigQuery ($BQ_RAW) with Analytics V2 schema..."
gcloud healthcare fhir-stores export bq "$FHIR_STORE" \
  --dataset="$HC_DATASET" --location="$REGION" \
  --bq-dataset="bq://${PROJECT_ID}.${BQ_RAW}" \
  --schema-type=analytics_v2 \
  --recursive-depth=3 \
  --write-disposition=write-truncate

echo ">> done. Raw SQL-on-FHIR tables now in ${BQ_RAW}:"
echo "   (Patient, Observation, Condition, Encounter, MedicationRequest, ...)"
echo ""
echo "   Peek at what landed:"
bq query --use_legacy_sql=false --project_id="$PROJECT_ID" \
  "SELECT table_id, row_count FROM \`${PROJECT_ID}.${BQ_RAW}.__TABLES__\` ORDER BY row_count DESC LIMIT 15" 2>/dev/null || true
echo ""
echo "   next: ./03_build_omop_and_features.sh"
