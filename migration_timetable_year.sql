-- ==================================================================================
-- MIGRATION: Add academic_year_id to timetable_slots
-- ==================================================================================
-- Why: the app code now filters every timetable read/write by academic_year_id
-- (Class Timetable, Staff Timetable, auto-generate, conflict checker, CSV import).
-- Without this column, Next Year would keep showing Last Year's timetable.

ALTER TABLE timetable_slots ADD COLUMN IF NOT EXISTS academic_year_id INTEGER;

-- Backfill: every existing timetable_slots row predates this feature, so it belongs
-- to the year that was active when it was created. If you know all your current rows
-- are for 2025-2026 (id 1), run this. Adjust the id if your "last year" is a
-- different academic_years.id.
UPDATE timetable_slots SET academic_year_id = 1 WHERE academic_year_id IS NULL;

-- New rows default to the "current/next" year (id 2 = 2026-2027) going forward.
ALTER TABLE timetable_slots ALTER COLUMN academic_year_id SET DEFAULT 2;

CREATE INDEX IF NOT EXISTS idx_timetable_slots_academic_year_id ON timetable_slots(academic_year_id);
