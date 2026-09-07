#!/usr/bin/env bash
# ============================================================
# 01_generate_and_ingest.sh
# Generate paediatric FHIR data (with the HbA1c/glucose module),
# land it in GCS, and import into the Cloud Healthcare API FHIR store.
# Prereq:  source 00_setup.sh   (and run setup_gcp once)
# ============================================================
set -e

: "${PROJECT_ID:?run: source 00_setup.sh first}"
N_PATIENTS="${1:-500}"     # cohort size (default 500)

# ---- 1. get Synthea jar (prebuilt, no build) ----
if [ ! -f synthea.jar ]; then
  echo ">> downloading Synthea..."
  curl -sL -o synthea.jar \
    https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar
fi

# ---- 2. generate FHIR R4 with the custom glycemic module ----
# custom_modules/paediatric_glycemic.json injects HbA1c + fasting glucose (age 8-18),
# correlated to weight so an obesity->dysglycemia signal exists.
echo ">> generating $N_PATIENTS paediatric patients (8-18) with glycemic module..."
rm -rf output
java -jar synthea.jar -p "$N_PATIENTS" -a 8-18 -d custom_modules \
  --exporter.fhir.export true \
  --exporter.fhir.bulk_data true \
  --exporter.hospital.fhir.export false \
  --exporter.practitioner.fhir.export false \
  --generate.only_alive_patients true >/dev/null
echo "   generated: $(ls output/fhir/*.json | wc -l) bundles"

# ---- 3. land raw FHIR files in the GCS bucket ----
echo ">> uploading FHIR bundles to gs://$BUCKET/fhir-import/ ..."
gcloud storage cp output/fhir/*.ndjson "gs://$BUCKET/fhir-import/" --quiet

# ---- 4. native bulk import: GCS -> Cloud Healthcare API FHIR store ----
# This is the managed fhirStores.import (no pipeline). content-structure=BUNDLE
# because Synthea emits transaction Bundles.
echo ">> importing into FHIR store $FHIR_STORE (this can take a few minutes)..."
gcloud healthcare fhir-stores import gcs "$FHIR_STORE" \
  --dataset="$HC_DATASET" --location="$REGION" \
  --gcs-uri="gs://$BUCKET/fhir-import/*.ndjson" \
  --content-structure=RESOURCE

echo ">> import complete. FHIR data now in the store."
echo "   next: ./02_export_to_bigquery.sh"
