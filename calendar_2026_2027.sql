-- ==================================================================================
-- 2026-2027 ACADEMIC YEAR CALENDAR
-- ==================================================================================
-- Assumes academic_years.id = 2 is "2026-2027" (the convention used throughout the
-- app all along). Check that first if you're not sure:
--   SELECT id, name FROM academic_years;

-- ----------------------------------------------------------------------------------
-- 1. TERMS
-- ----------------------------------------------------------------------------------
-- midterm_date below is an ESTIMATE (the midpoint of each term) — replace with your
-- real midterm exam dates if you already have them scheduled.

INSERT INTO terms (academic_year_id, name, start_date, end_date, midterm_date, is_locked)
VALUES
    (2, 'First Term',  '2026-09-07', '2026-12-18', '2026-10-28', false),
    (2, 'Second Term', '2027-01-04', '2027-04-02', '2027-02-17', false),
    (2, 'Third Term',  '2027-04-19', '2027-07-02', '2027-05-26', false);

-- ----------------------------------------------------------------------------------
-- 2. HOLIDAY PERIODS (the gaps between terms)
-- ----------------------------------------------------------------------------------
-- These give the app an explicit record of "we are currently in a holiday between
-- terms" rather than having to guess from term start/end dates alone.

INSERT INTO holidays (academic_year_id, name, start_date, end_date, type, description)
VALUES
    (2, 'Term 1 Holiday', '2026-12-19', '2027-01-03', 'term_break', 'Break between First Term and Second Term'),
    (2, 'Term 2 Holiday', '2027-04-03', '2027-04-18', 'term_break', 'Break between Second Term and Third Term'),
    -- Long holiday after Third Term ends — end date is a PLACEHOLDER (mirrors how the
    -- current 2026 long holiday has no fixed end date yet). Update this once you know
    -- when the 2027-2028 year will actually start.
    (2, 'Long Holiday (Post Third Term)', '2027-07-03', '2027-09-05', 'long_break', 'End date is provisional — adjust once next year''s start date is confirmed');

-- ----------------------------------------------------------------------------------
-- 3. VERIFY
-- ----------------------------------------------------------------------------------
SELECT * FROM terms WHERE academic_year_id = 2 ORDER BY start_date;
SELECT * FROM holidays WHERE academic_year_id = 2 ORDER BY start_date;
