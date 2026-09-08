-- (1) per-patient dual risk, top 20
SELECT person_id, ROUND(obesity_risk,3) obesity_risk, ROUND(diabetes_risk,3) diabetes_risk,
  ROUND((obesity_risk+diabetes_risk)/2,3) combined_risk,
  CASE WHEN obesity_risk>=0.5 AND diabetes_risk>=0.5 THEN 'BOTH - high priority'
       WHEN obesity_risk>=0.5 THEN 'Obesity risk'
       WHEN diabetes_risk>=0.5 THEN 'Diabetes risk' ELSE 'Lower risk' END flag
FROM `PROJECT.kfupm_poc_models.predictions`
ORDER BY combined_risk DESC LIMIT 20;

-- (2) risk distribution
SELECT CASE WHEN obesity_risk>=0.5 AND diabetes_risk>=0.5 THEN '1. Both high'
            WHEN obesity_risk>=0.5 THEN '2. Obesity high'
            WHEN diabetes_risk>=0.5 THEN '3. Diabetes high' ELSE '4. Neither high' END risk_group,
  COUNT(*) patients, ROUND(AVG(obesity_risk),3) avg_ob, ROUND(AVG(diabetes_risk),3) avg_di
FROM `PROJECT.kfupm_poc_models.predictions` GROUP BY risk_group ORDER BY risk_group;

-- (3) model scorecard
SELECT 'obesity' model, ROUND(roc_auc,3) roc_auc, ROUND(f1_score,3) f1 FROM ML.EVALUATE(MODEL `PROJECT.kfupm_poc_models.m_obesity`)
UNION ALL SELECT 'diabetes', ROUND(roc_auc,3), ROUND(f1_score,3) FROM ML.EVALUATE(MODEL `PROJECT.kfupm_poc_models.m_diabetes`)
UNION ALL SELECT 'combined', ROUND(roc_auc,3), ROUND(f1_score,3) FROM ML.EVALUATE(MODEL `PROJECT.kfupm_poc_models.m_combined`) ORDER BY model;

-- (4) cohort summary
SELECT COUNT(*) cohort_size, ROUND(AVG(age_years),1) avg_age,
  SUM(label_obese) obese, SUM(label_diabetes) diabetic, SUM(label_prediabetes) prediabetic
FROM `PROJECT.kfupm_poc_curated.features`;
