-- ============================================================
-- 03b_models.sql  —  BigQuery ML: BOTH structures, for comparison
--
-- APPROACH A: two separate binary models (diabetes, obesity)
-- APPROACH B: one shared feature set, both labels — trained as two
--             models but from the same features (BQML has no native
--             multi-label; the "single multi-outcome" pattern in BQML
--             is two label columns trained separately OR a multiclass
--             combined-state target). We provide both: A (separate) and
--             B (multiclass combined state) so you can compare.
--
-- All models are explainable (enable_global_explain) and class-weighted.
-- Features exclude the label-defining measurements (no leakage).
-- ============================================================

-- feature columns shared by all models (exclude labels + label sources)
-- gender_male, age_years, weight_kg, height_cm, bmi_ratio,
-- bp_diastolic, bp_systolic, fasting_glucose, n_obs

-- ---------- APPROACH A1 : Obesity model ----------
CREATE OR REPLACE MODEL `${PROJECT_ID}.${BQ_OMOP}.m_obesity`
OPTIONS(model_type='LOGISTIC_REG', input_label_cols=['label_obese'],
        auto_class_weights=TRUE, enable_global_explain=TRUE,
        data_split_method='RANDOM', data_split_eval_fraction=0.2) AS
SELECT gender_male, age_years, weight_kg, height_cm, bmi_ratio,
       bp_diastolic, bp_systolic, fasting_glucose, n_obs, label_obese
FROM `${PROJECT_ID}.${BQ_OMOP}.features`;

-- ---------- APPROACH A2 : Diabetes model ----------
CREATE OR REPLACE MODEL `${PROJECT_ID}.${BQ_OMOP}.m_diabetes`
OPTIONS(model_type='LOGISTIC_REG', input_label_cols=['label_diabetes'],
        auto_class_weights=TRUE, enable_global_explain=TRUE,
        data_split_method='RANDOM', data_split_eval_fraction=0.2) AS
SELECT gender_male, age_years, weight_kg, height_cm, bmi_ratio,
       bp_diastolic, bp_systolic, fasting_glucose, n_obs, label_diabetes
FROM `${PROJECT_ID}.${BQ_OMOP}.features`;

-- ---------- APPROACH B : combined multiclass (one model, four states) ----------
-- state: 0=neither, 1=obese only, 2=diabetic only, 3=both
CREATE OR REPLACE MODEL `${PROJECT_ID}.${BQ_OMOP}.m_combined`
OPTIONS(model_type='LOGISTIC_REG', input_label_cols=['state'],
        auto_class_weights=TRUE, enable_global_explain=TRUE,
        data_split_method='RANDOM', data_split_eval_fraction=0.2) AS
SELECT gender_male, age_years, weight_kg, height_cm, bmi_ratio,
       bp_diastolic, bp_systolic, fasting_glucose, n_obs,
       CAST(label_obese*1 + label_diabetes*2 AS STRING) AS state
FROM `${PROJECT_ID}.${BQ_OMOP}.features`;

-- ---------- EVALUATE all three ----------
SELECT 'obesity'  AS model, * FROM ML.EVALUATE(MODEL `${PROJECT_ID}.${BQ_OMOP}.m_obesity`);
SELECT 'diabetes' AS model, * FROM ML.EVALUATE(MODEL `${PROJECT_ID}.${BQ_OMOP}.m_diabetes`);
SELECT 'combined' AS model, * FROM ML.EVALUATE(MODEL `${PROJECT_ID}.${BQ_OMOP}.m_combined`);

-- ---------- EXPLAINABILITY (feature drivers) ----------
SELECT 'obesity'  AS model, * FROM ML.GLOBAL_EXPLAIN(MODEL `${PROJECT_ID}.${BQ_OMOP}.m_obesity`);
SELECT 'diabetes' AS model, * FROM ML.GLOBAL_EXPLAIN(MODEL `${PROJECT_ID}.${BQ_OMOP}.m_diabetes`);

-- ---------- PREDICT (per-patient risk, both outcomes) ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_OMOP}.predictions` AS
SELECT
  f.person_id,
  ob.predicted_label_obese,
  (SELECT prob FROM UNNEST(ob.predicted_label_obese_probs) WHERE label=1)    AS obesity_risk,
  di.predicted_label_diabetes,
  (SELECT prob FROM UNNEST(di.predicted_label_diabetes_probs) WHERE label=1) AS diabetes_risk
FROM `${PROJECT_ID}.${BQ_OMOP}.features` f
JOIN ML.PREDICT(MODEL `${PROJECT_ID}.${BQ_OMOP}.m_obesity`,
      (SELECT * FROM `${PROJECT_ID}.${BQ_OMOP}.features`)) ob USING(person_id)
JOIN ML.PREDICT(MODEL `${PROJECT_ID}.${BQ_OMOP}.m_diabetes`,
      (SELECT * FROM `${PROJECT_ID}.${BQ_OMOP}.features`)) di USING(person_id);
