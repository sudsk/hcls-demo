-- ============================================================
-- 03a_features.sql  —  Raw SQL-on-FHIR -> feature table (BigQuery)
-- Builds a per-patient feature/label table for BOTH outcomes:
--   label_obese     = max BMI percentile-for-age >= 95
--   label_diabetes  = max HbA1c >= 6.5  (prediabetes flag also provided >=5.7)
-- Features EXCLUDE the BMI-percentile and HbA1c that define the labels
-- (avoids target leakage): predict from weight, height, age, BP, glucose-trend, etc.
--
-- Replace ${BQ_RAW} / ${BQ_OMOP} / ${PROJECT_ID} or run via 03_build script which sed-substitutes.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS `${PROJECT_ID}.${BQ_OMOP}`;

CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_OMOP}.features` AS
WITH obs AS (
  -- flatten Observation: one row per (patient, loinc, value, date)
  SELECT
    o.subject.patientId AS person_id,
    o.code.coding[SAFE_OFFSET(0)].code AS loinc,
    o.value.quantity.value AS val
  FROM `${PROJECT_ID}.${BQ_RAW}.Observation` o
  WHERE o.code.coding[SAFE_OFFSET(0)].system = 'http://loinc.org'
),
pat AS (
  SELECT
    p.id AS person_id,
    p.gender AS gender,
    SAFE_CAST(SUBSTR(p.birthDate,1,4) AS INT64) AS birth_year
  FROM `${PROJECT_ID}.${BQ_RAW}.Patient` p
),
agg AS (
  SELECT
    person_id,
    -- label sources (kept separate from features)
    MAX(IF(loinc='59576-9', val, NULL)) AS max_bmi_pct,      -- BMI percentile-for-age
    MAX(IF(loinc='4548-4',  val, NULL)) AS max_hba1c,        -- HbA1c %
    -- features (NOT used to derive labels)
    AVG(IF(loinc='29463-7' OR loinc='3141-9', val, NULL)) AS weight_kg,   -- Body weight
    AVG(IF(loinc='8302-2',  val, NULL)) AS height_cm,        -- Body height
    AVG(IF(loinc='39156-5', val, NULL)) AS bmi_ratio,        -- BMI value (not percentile)
    AVG(IF(loinc='8462-4',  val, NULL)) AS bp_diastolic,
    AVG(IF(loinc='8480-6',  val, NULL)) AS bp_systolic,
    AVG(IF(loinc='1558-6',  val, NULL)) AS fasting_glucose,  -- fasting glucose mg/dL
    COUNT(*) AS n_obs
  FROM obs
  GROUP BY person_id
)
SELECT
  a.person_id,
  IF(pat.gender='male',1,0) AS gender_male,
  (2026 - pat.birth_year)   AS age_years,
  a.weight_kg, a.height_cm, a.bmi_ratio,
  a.bp_diastolic, a.bp_systolic, a.fasting_glucose, a.n_obs,
  -- labels
  IF(a.max_bmi_pct >= 95, 1, 0)   AS label_obese,
  IF(a.max_hba1c   >= 6.5, 1, 0)  AS label_diabetes,
  IF(a.max_hba1c   >= 5.7, 1, 0)  AS label_prediabetes
FROM agg a
JOIN pat USING (person_id)
WHERE a.max_bmi_pct IS NOT NULL OR a.max_hba1c IS NOT NULL;

-- quick class balance check
SELECT
  COUNT(*) AS n,
  SUM(label_obese)       AS obese,
  SUM(label_diabetes)    AS diabetes,
  SUM(label_prediabetes) AS prediabetes
FROM `${PROJECT_ID}.${BQ_OMOP}.features`;
