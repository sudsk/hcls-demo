#!/usr/bin/env bash
# ============================================================
# 03_build_omop_and_features.sh
# Substitutes env vars into the SQL and runs: features -> models -> eval.
# ============================================================
set -e
: "${PROJECT_ID:?run: source 00_setup.sh first}"

run_sql () {
  local f="$1"
  echo ">> running $f ..."
  sed -e "s/\${PROJECT_ID}/${PROJECT_ID}/g" \
      -e "s/\${BQ_RAW}/${BQ_RAW}/g" \
      -e "s/\${BQ_OMOP}/${BQ_OMOP}/g" "$f" \
  | bq query --use_legacy_sql=false --project_id="$PROJECT_ID" --format=pretty
}

run_sql 03a_features.sql
echo ""
echo ">> features built. Training models (both approaches) + evaluating..."
run_sql 03b_models.sql

echo ""
echo ">> done. Models + predictions are in ${BQ_OMOP}."
echo "   - m_obesity, m_diabetes  (Approach A: separate)"
echo "   - m_combined             (Approach B: multiclass, 4 states)"
echo "   - predictions            (per-patient obesity_risk + diabetes_risk)"
