-- ==================================================================================
-- DIAGNOSTIC: Find payments/fees that may be tagged with the wrong academic year
-- ==================================================================================
-- Run this FIRST and look at the results before changing anything. This does not
-- modify any data — it's read-only.

-- 1. How many payments exist per academic_year_id (and how many have none at all)?
SELECT academic_year_id, COUNT(*) AS payment_count, SUM(amount) AS total_amount,
       MIN(payment_date) AS earliest, MAX(payment_date) AS latest
FROM payments
GROUP BY academic_year_id
ORDER BY academic_year_id NULLS FIRST;

-- 2. Same for student_fees
SELECT academic_year_id, COUNT(*) AS fee_count, SUM(amount) AS total_amount
FROM student_fees
GROUP BY academic_year_id
ORDER BY academic_year_id NULLS FIRST;

-- 3. Payments created recently (last 30 days) but tagged as academic_year_id = 1
--    (2025-2026) — these are the most likely candidates for "should be year 2 but
--    got tagged year 1" from before the fix.
SELECT id, student_id, amount, payment_date, payment_method, receipt_number, created_at, academic_year_id
FROM payments
WHERE academic_year_id = 1
  AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC;

-- 4. Same check for student_fees
SELECT id, student_id, fee_category_id, amount, created_at, academic_year_id
FROM student_fees
WHERE academic_year_id = 1
  AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC;

-- ==================================================================================
-- If queries 3 and 4 show real recent records that should belong to this year,
-- send me the results (or just tell me the counts) and I'll give you the exact
-- corrective UPDATE to run — I'm not running a blind UPDATE against your real
-- financial data without seeing what's actually there first.
-- ==================================================================================
