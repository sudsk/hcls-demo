#!/usr/bin/env bash
# ============================================================
# KFUPM Pilot 1 POC — 00_setup.sh
# One-time environment setup. Edit the vars, then `source` this file
# before running the numbered scripts:  source 00_setup.sh
# ============================================================

# ---- EDIT THESE ----
export PROJECT_ID="<PROJECT_ID>"          # your GCP project
export REGION="us-central1"                # POC region (see note on in-Kingdom below)
export BUCKET="${PROJECT_ID}-kfupm-poc"    # GCS landing bucket (must be globally unique)
export HC_DATASET="kfupm_poc"              # Cloud Healthcare API dataset
export FHIR_STORE="epic_fhir"              # FHIR store id
export BQ_RAW="kfupm_poc_raw"              # BigQuery dataset for raw (SQL-on-FHIR) tables
export BQ_OMOP="kfupm_poc_omop"            # BigQuery dataset for OMOP + features + models
# --------------------

# NOTE on region: for the real engagement use an in-Kingdom region
# (me-central1 Doha / me-central2 Dammam). For a throwaway POC us-central1
# is fine and has the widest feature availability. Healthcare API + BQML
# must be in the SAME region as their datasets.

echo "Project:   $PROJECT_ID"
echo "Region:    $REGION"
echo "Bucket:    gs://$BUCKET"
echo "FHIR:      $HC_DATASET/$FHIR_STORE"
echo "BQ:        $BQ_RAW (raw) / $BQ_OMOP (omop)"

# ---- one-time enablement + resource creation (safe to re-run) ----
setup_gcp () {
  gcloud config set project "$PROJECT_ID"

  echo ">> enabling APIs..."
  gcloud services enable healthcare.googleapis.com bigquery.googleapis.com \
    storage.googleapis.com --project "$PROJECT_ID"

  echo ">> creating GCS landing bucket..."
  gcloud storage buckets create "gs://$BUCKET" --location="$REGION" \
    --uniform-bucket-level-access --public-access-prevention 2>/dev/null || echo "   (bucket exists)"

  echo ">> creating Healthcare dataset + FHIR store (R4, streaming to BigQuery)..."
  gcloud healthcare datasets create "$HC_DATASET" --location="$REGION" 2>/dev/null || echo "   (dataset exists)"

  # FHIR store with BigQuery streaming configured AT CREATION (required for streaming)
  gcloud healthcare fhir-stores create "$FHIR_STORE" \
    --dataset="$HC_DATASET" --location="$REGION" --version=R4 2>/dev/null || echo "   (fhir store exists)"

  echo ">> creating BigQuery datasets..."
  bq --location="$REGION" mk -d "${PROJECT_ID}:${BQ_RAW}" 2>/dev/null || echo "   (raw dataset exists)"
  bq --location="$REGION" mk -d "${PROJECT_ID}:${BQ_OMOP}" 2>/dev/null || echo "   (omop dataset exists)"

  echo ">> granting the Healthcare Service Agent permission to write to BigQuery..."
  # find the Healthcare service agent and give it BQ dataEditor + jobUser
  PROJ_NUM=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
  HC_SA="service-${PROJ_NUM}@gcp-sa-healthcare.iam.gserviceaccount.com"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${HC_SA}" --role="roles/bigquery.dataEditor" --condition=None --quiet >/dev/null
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${HC_SA}" --role="roles/bigquery.jobUser" --condition=None --quiet >/dev/null
  # also allow it to read the import bucket
  gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
    --member="serviceAccount:${HC_SA}" --role="roles/storage.objectViewer" --condition=None --quiet >/dev/null

  echo ">> setup complete."
}

echo ""
echo "Run:  setup_gcp    # to enable APIs and create bucket / dataset / FHIR store / BQ datasets"
