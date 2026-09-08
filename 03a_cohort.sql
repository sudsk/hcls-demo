-- ============================================================
-- 03a_cohort.sql  —  OMOP (Silver) -> CURATED cohort + features  (GOLD)
-- Built FROM the study-agnostic OMOP layer. Two tables in ${BQ_CURATED}:
--   cohort   — the study population (8-18) with key clinical summaries
--   features — modelling variables + BOTH labels (diabetes + obesity)
--
-- Labels (from OMOP measurement, by LOINC source value):
--   label_obese     = max BMI percentile-for-age (LOINC 59576-9) >= 95
--   label_diabetes  = max HbA1c (LOINC 4548-4) >= 6.5   (prediabetes >= 5.7)
-- Features EXCLUDE the label-defining measurements (no target leakage).
-- ============================================================

CREATE SCHEMA IF NOT EXISTS `${PROJECT_ID}.${BQ_CURATED}`;

-- ---------- per-person measurement pivot (from OMOP) ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_CURATED}._meas_pivot` AS
SELECT
  person_id,
  MAX(IF(measurement_source_value='59576-9', value_as_number, NULL)) AS max_bmi_pct,   -- label src (obese)
  MAX(IF(measurement_source_value='4548-4',  value_as_number, NULL)) AS max_hba1c,     -- label src (diabetes)
  -- features (not label sources)
  AVG(IF(measurement_source_value='29463-7', value_as_number, NULL)) AS weight_kg,
  AVG(IF(measurement_source_value='8302-2',  value_as_number, NULL)) AS height_cm,
  AVG(IF(measurement_source_value='39156-5', value_as_number, NULL)) AS bmi_ratio,
  AVG(IF(measurement_source_value='8462-4',  value_as_number, NULL)) AS bp_diastolic,
  AVG(IF(measurement_source_value='8480-6',  value_as_number, NULL)) AS bp_systolic,
  AVG(IF(measurement_source_value='1558-6',  value_as_number, NULL)) AS fasting_glucose,
  COUNT(*) AS n_measurements
FROM `${PROJECT_ID}.${BQ_OMOP}.measurement`
GROUP BY person_id;

-- ---------- COHORT: study population (ages 8-18) ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_CURATED}.cohort` AS
SELECT
  p.person_id,
  p.gender_source_value AS gender,
  (2026 - p.year_of_birth) AS age_years,
  mp.max_bmi_pct,
  mp.max_hba1c,
  mp.n_measurements
FROM `${PROJECT_ID}.${BQ_OMOP}.person` p
JOIN `${PROJECT_ID}.${BQ_CURATED}._meas_pivot` mp USING (person_id)
WHERE (2026 - p.year_of_birth) BETWEEN 8 AND 18
  AND (mp.max_bmi_pct IS NOT NULL OR mp.max_hba1c IS NOT NULL);

-- ---------- FEATURES: modelling variables + both labels ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_CURATED}.features` AS
SELECT
  c.person_id,
  IF(c.gender='male',1,0)          AS gender_male,
  c.age_years,
  mp.weight_kg, mp.height_cm, mp.bmi_ratio,
  mp.bp_diastolic, mp.bp_systolic, mp.fasting_glucose, mp.n_measurements,
  IF(c.max_bmi_pct >= 95, 1, 0)    AS label_obese,
  IF(c.max_hba1c   >= 6.5, 1, 0)   AS label_diabetes,
  IF(c.max_hba1c   >= 5.7, 1, 0)   AS label_prediabetes
FROM `${PROJECT_ID}.${BQ_CURATED}.cohort` c
JOIN `${PROJECT_ID}.${BQ_CURATED}._meas_pivot` mp USING (person_id);

-- ---------- class balance ----------
SELECT
  COUNT(*) AS cohort_n,
  SUM(label_obese)       AS obese,
  SUM(label_diabetes)    AS diabetes,
  SUM(label_prediabetes) AS prediabetes
FROM `${PROJECT_ID}.${BQ_CURATED}.features`;
