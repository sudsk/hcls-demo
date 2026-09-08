-- ============================================================
-- 02b_fhir_to_omop.sql  —  RAW (SQL-on-FHIR) -> OMOP CDM  (SILVER)
-- Builds OMOP-STRUCTURED tables in ${BQ_OMOP}: person, measurement,
-- condition_occurrence, drug_exposure, visit_occurrence, observation_period.
--
-- NOTE ON CONCEPT MAPPING (honest POC scope):
--   True OMOP requires mapping every source code to an OMOP standard
--   concept_id via the OMOP vocabulary (SNOMED/LOINC/RxNorm -> concept).
--   That needs the OMOP vocabulary reference loaded (large). For this POC we
--   build the correct OMOP TABLE STRUCTURE with *_source_value populated and
--   *_concept_id left as 0 (placeholder). Production loads the vocabulary and
--   fills concept_id. This gives the real OMOP shape without the vocab load.
--
--   This layer is STUDY-AGNOSTIC and reusable — the diabetes/obesity cohort
--   (Gold) is built FROM it, not in it.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS `${PROJECT_ID}.${BQ_OMOP}`;

-- ---------- PERSON ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_OMOP}.person` AS
SELECT
  p.id                                        AS person_id,          -- pseudonymised patient id
  SAFE_CAST(SUBSTR(p.birthDate,1,4)  AS INT64) AS year_of_birth,
  SAFE_CAST(SUBSTR(p.birthDate,6,2)  AS INT64) AS month_of_birth,
  p.birthDate                                 AS birth_datetime,
  CASE p.gender WHEN 'male' THEN 8507 WHEN 'female' THEN 8532 ELSE 0 END AS gender_concept_id,
  p.gender                                    AS gender_source_value,
  0 AS race_concept_id, 0 AS ethnicity_concept_id
FROM `${PROJECT_ID}.${BQ_RAW}.Patient` p;

-- ---------- VISIT_OCCURRENCE ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_OMOP}.visit_occurrence` AS
SELECT
  ROW_NUMBER() OVER()                         AS visit_occurrence_id,
  e.subject.patientId                         AS person_id,
  DATE(e.period.start)                        AS visit_start_date,
  DATE(e.period.`end`)                         AS visit_end_date,
  9202                                         AS visit_concept_id,   -- outpatient (POC default)
  e.class.code                                AS visit_source_value
FROM `${PROJECT_ID}.${BQ_RAW}.Encounter` e
WHERE e.subject.patientId IS NOT NULL;

-- ---------- OBSERVATION_PERIOD (min->max activity per person) ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_OMOP}.observation_period` AS
SELECT
  ROW_NUMBER() OVER()                         AS observation_period_id,
  person_id,
  MIN(visit_start_date)                       AS observation_period_start_date,
  MAX(COALESCE(visit_end_date, visit_start_date)) AS observation_period_end_date,
  44814724                                    AS period_type_concept_id
FROM `${PROJECT_ID}.${BQ_OMOP}.visit_occurrence`
GROUP BY person_id;

-- ---------- CONDITION_OCCURRENCE ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_OMOP}.condition_occurrence` AS
SELECT
  ROW_NUMBER() OVER()                         AS condition_occurrence_id,
  c.subject.patientId                         AS person_id,
  DATE(c.onset.dateTime)                      AS condition_start_date,
  0                                           AS condition_concept_id,      -- (vocab maps in prod)
  c.code.coding[SAFE_OFFSET(0)].code          AS condition_source_value,    -- SNOMED code
  c.code.coding[SAFE_OFFSET(0)].display       AS condition_source_name
FROM `${PROJECT_ID}.${BQ_RAW}.Condition` c
WHERE c.subject.patientId IS NOT NULL;

-- ---------- MEASUREMENT (labs + vitals from Observation) ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_OMOP}.measurement` AS
SELECT
  ROW_NUMBER() OVER()                         AS measurement_id,
  o.subject.patientId                         AS person_id,
  DATE(o.effective.dateTime)                  AS measurement_date,
  0                                           AS measurement_concept_id,    -- (LOINC->concept in prod)
  o.code.coding[SAFE_OFFSET(0)].code          AS measurement_source_value,  -- LOINC code
  o.code.coding[SAFE_OFFSET(0)].display       AS measurement_source_name,
  o.value.quantity.value                      AS value_as_number,
  o.value.quantity.unit                       AS unit_source_value
FROM `${PROJECT_ID}.${BQ_RAW}.Observation` o
WHERE o.subject.patientId IS NOT NULL
  AND o.value.quantity.value IS NOT NULL;

-- ---------- DRUG_EXPOSURE ----------
CREATE OR REPLACE TABLE `${PROJECT_ID}.${BQ_OMOP}.drug_exposure` AS
SELECT
  ROW_NUMBER() OVER()                         AS drug_exposure_id,
  m.subject.patientId                         AS person_id,
  DATE(m.authoredOn)                          AS drug_exposure_start_date,
  0                                           AS drug_concept_id,
  m.medication.codeableConcept.coding[SAFE_OFFSET(0)].code    AS drug_source_value,
  m.medication.codeableConcept.text                          AS drug_source_name
FROM `${PROJECT_ID}.${BQ_RAW}.MedicationRequest` m
WHERE m.subject.patientId IS NOT NULL;

-- ---------- summary ----------
SELECT 'person' t, COUNT(*) n FROM `${PROJECT_ID}.${BQ_OMOP}.person`
UNION ALL SELECT 'measurement', COUNT(*) FROM `${PROJECT_ID}.${BQ_OMOP}.measurement`
UNION ALL SELECT 'condition_occurrence', COUNT(*) FROM `${PROJECT_ID}.${BQ_OMOP}.condition_occurrence`
UNION ALL SELECT 'visit_occurrence', COUNT(*) FROM `${PROJECT_ID}.${BQ_OMOP}.visit_occurrence`
UNION ALL SELECT 'drug_exposure', COUNT(*) FROM `${PROJECT_ID}.${BQ_OMOP}.drug_exposure`
ORDER BY n DESC;
