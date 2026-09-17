-- ==================================================================================
-- 012_add_welcoming_test.sql
-- ==================================================================================
-- Adds "Welcoming Test" as a valid assessment_type. It's treated exactly like
-- Mid-term for scoring purposes — the app's calculation logic buckets any
-- assessment type that isn't "Exam"/"Final Exam" into the continuous-assessment
-- ("MG") score, scaled against each subject's configured max — so this needs no
-- separate calculation code, only a valid type string to select in Marks Entry.
-- ==================================================================================

ALTER TABLE assessments DROP CONSTRAINT IF EXISTS assessments_assessment_type_check;
ALTER TABLE assessments ADD CONSTRAINT assessments_assessment_type_check
    CHECK (assessment_type::text = ANY (ARRAY[
        'Quiz'::character varying, 'Assignment'::character varying, 'Mid-term'::character varying,
        'Welcoming Test'::character varying, 'Exam'::character varying, 'Final Exam'::character varying
    ]::text[]));

SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'assessments'::regclass AND conname = 'assessments_assessment_type_check';
