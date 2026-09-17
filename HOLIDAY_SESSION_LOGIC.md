# Holiday Session & Period Switcher — Implementation Notes

This document describes the logic added to the school management app during the Holiday
Session / multi-year rebuild, so it can be re-applied or reviewed against
`https://github.com/Natsonuwayezu/La-Fontaine-v2`. It's written as a reference for a
developer (or a future AI session) picking this codebase back up — it explains *why*
things work the way they do, not just what changed.

---

## 1. Core Concept: The Global Period Selector

Everything in this system hangs off one idea: **there is a single, global "period"
selector that determines which data the entire app reads and writes.** It lives in the
topbar and has three states:

| Period | id | Maps to `academic_year_id` | Uses |
|---|---|---|---|
| 🏖️ Holiday | `holiday` | `2` (current/next year) | `session_*` tables for academics, regular tables for finance |
| 📚 Last Year | `last_year` | `1` | Regular tables, read-mostly (archived) |
| 📖 Next Year | `next_year` | `2` | Regular tables |

```js
const PERIODS = {
    holiday:   { id: 'holiday',   label: '🏖️ Holiday 2026', yearId: 2, theme: 'theme-holiday' },
    last_year: { id: 'last_year', label: '📚 2025-2026',     yearId: 1, theme: 'theme-lastyear' },
    next_year: { id: 'next_year', label: '📖 2026-2027',     yearId: 2, theme: 'theme-nextyear' }
};

function getCurrentPeriod()   { return PERIODS[localStorage.getItem('elf_period')] || PERIODS.holiday; }
function getCurrentPeriodId() { return getCurrentPeriod().id; }
function getCurrentYearId()   { return getCurrentPeriod().yearId; }
function isHolidayMode()      { return getCurrentPeriodId() === 'holiday'; }
```

**Every other rule in this document follows from these four functions.** If you're
debugging "why does X show data from the wrong year," start here — check what
`getCurrentYearId()` resolves to and trace forward.

### Switching periods

`setCurrentPeriod(periodId)`:
1. Saves the new period to `localStorage`.
2. **If switching TO Holiday**: forces a full logout (`clearSession()`) + page reload, so
   the whole app boots clean into holiday mode. This was a deliberate requirement — Holiday
   mode changes so much (sidebar, classes, staff assignments) that a soft in-place switch
   was too risky.
3. **If switching between Last Year / Next Year**: re-applies the theme, **rebuilds the
   sidebar** (`buildSidebar(role)` — this was the single most important fix; earlier
   versions updated the theme/badge but never re-ran sidebar construction, so nav items
   silently stayed frozen from login), reloads data for the new year, and re-renders the
   current module.

### Data loading is period-scoped at the *query* level, not client-filtered

`loadDataForPeriod(periodId)` re-fetches from Supabase with `{ academic_year_id: yearId }`
filters baked into the request — it does **not** load everything and filter in memory.
This means Last Year's data is never even sitting in browser memory while you're in
Holiday/Next Year mode, and vice versa. This is the mechanism that satisfies "finance must
not use data from previous year."

```js
async function loadDataForPeriod(periodId) {
    const yearId = PERIODS[periodId].yearId;
    if (periodId === 'holiday') {
        // students/teachers/classes/subjects: unfiltered (shared across years)
        // session_classes, session_subjects, session_enrollments, session_assessments,
        // session_marks, session_teacher_assignments: loaded fresh, no year filter needed
        // (there's only ever one active holiday session)
        // fee_amounts, payments, student_fees: filtered by academic_year_id = yearId
    } else {
        // assessments, marks, payments, student_fees, fee_amounts:
        // getAll(table, { academic_year_id: yearId })
        // classes assignments (teacher_assignments): also filtered by academic_year_id
    }
    // terms: filtered too — state.terms only ever contains the selected year's terms
}
```

---

## 2. Database Schema Changes

Run in this order. All are idempotent (`IF NOT EXISTS` / `ON CONFLICT` safe to re-run).

### 2.1 `academic_year_id` added to existing tables
```sql
ALTER TABLE marks             ADD COLUMN IF NOT EXISTS academic_year_id INTEGER DEFAULT 2;
ALTER TABLE assessments       ADD COLUMN IF NOT EXISTS academic_year_id INTEGER DEFAULT 2;
ALTER TABLE payments          ADD COLUMN IF NOT EXISTS academic_year_id INTEGER DEFAULT 2;
ALTER TABLE student_fees      ADD COLUMN IF NOT EXISTS academic_year_id INTEGER DEFAULT 2;
ALTER TABLE teacher_assignments ADD COLUMN IF NOT EXISTS academic_year_id INTEGER DEFAULT 2;
ALTER TABLE timetable_slots   ADD COLUMN IF NOT EXISTS academic_year_id INTEGER DEFAULT 2;
```
Backfill existing rows to `1` (last year) if they predate the cutover, then let new rows
default to `2`. `fee_categories` deliberately does **NOT** get this column — categories
(Tuition, Uniform, Holiday Coaching...) are shared definitions across years; only
`fee_amounts` (the per-class-per-year price) is year-scoped.

### 2.2 New tables for the Holiday session
```sql
CREATE TABLE session_classes (
    id SERIAL PRIMARY KEY, name VARCHAR, is_free BOOLEAN DEFAULT false,
    academic_year_id INTEGER
);
CREATE TABLE session_subjects (
    id SERIAL PRIMARY KEY, name VARCHAR, session_class_id INTEGER REFERENCES session_classes(id),
    is_active BOOLEAN DEFAULT true
);
CREATE TABLE session_enrollments (
    id SERIAL PRIMARY KEY, student_id INTEGER, session_class_id INTEGER,
    enrolled_at TIMESTAMP, is_active BOOLEAN DEFAULT true
);
CREATE TABLE session_teacher_assignments (
    id SERIAL PRIMARY KEY, teacher_id INTEGER, session_class_id INTEGER,
    session_subject_id INTEGER, academic_year_id INTEGER
);
CREATE TABLE session_assessments (
    id SERIAL PRIMARY KEY, session_class_id INTEGER, session_subject_id INTEGER,
    name VARCHAR, max_marks NUMERIC DEFAULT 100, date DATE
);
CREATE TABLE session_marks (
    id SERIAL PRIMARY KEY, session_assessment_id INTEGER, student_id INTEGER,
    score NUMERIC, entered_by INTEGER, entered_at TIMESTAMP
);
```

> **Important, explicitly requested**: there are **no exempt/free holiday classes**.
> `is_free` exists as a column but the app-level exemption check was removed — every
> holiday class, including Holiday Primary 1, gets the Holiday Coaching fee applied.

### 2.3 `fee_approval_requests` — created but not actually used
The schema has this table, but the working implementation uses a simpler pattern instead:
a boolean `is_approved` flag directly on `student_fees` (see §4). The
`fee_approval_requests` table can be dropped or ignored; don't build against it without
also migrating the approval-reading code.

### 2.4 Enrollment/promotion history (created, partially wired)
```sql
CREATE TABLE class_enrollments (
    id SERIAL PRIMARY KEY, student_id INTEGER, class_id INTEGER, academic_year_id INTEGER,
    term_id INTEGER, enrollment_date DATE, is_active BOOLEAN DEFAULT true,
    promoted_from_id INTEGER, promoted_to_id INTEGER, status VARCHAR, notes TEXT
);
```
This table exists in the schema but is **not populated or read anywhere in the app**.
See §6 "Historical Roster Derivation" for what was actually used instead.

### 2.5 Timetable year column (added late — see §7 bug list)
```sql
ALTER TABLE timetable_slots ADD COLUMN IF NOT EXISTS academic_year_id INTEGER DEFAULT 2;
UPDATE timetable_slots SET academic_year_id = 1 WHERE academic_year_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_timetable_slots_academic_year_id ON timetable_slots(academic_year_id);
```

---

## 3. Sidebar / Navigation Rules

`getNavConfig(role)` builds the sidebar dynamically per role **and** per period. Rules,
in order of how surprising they are:

- **Finance section never changes with period.** Fee Structure, Payment History, Record
  Payment, Financial Reports, Overdue Payments, Fee Waivers, Fee Approvals, Receipts —
  identical for admin and accountant regardless of Holiday/Last Year/Next Year. This was
  an explicit requirement: "except the finance section, other things change."
- **Academics section swaps entirely based on `isHolidayMode()`**: Holiday shows
  `holiday-marks-entry` / `holiday-class-register` / etc. (session tables); anything else
  shows the regular `marks-entry` / `class-register` (regular tables, filtered by
  `getCurrentYearId()`).
- **Accountant never sees Academics, holiday or otherwise.** Wrap both branches in
  `if (role !== 'accountant')`.
- **Teacher's Academics list is shorter during Holiday** (Marks Entry, Marks Database,
  Class Register, Reports only — no Statistics/Timetable/Assessments) and reverts to the
  full list outside Holiday mode.
- **Fee Approvals lives in the shared Finance section**, not gated by period — it needs
  to be reachable in every mode since new-registration fees also go through approval now
  (see §4).
- **Student List always shows real classes**, never holiday classes, in every period.
- **New student registration always uses real classes** — holiday classes are for
  academics/assignments only, never enrollment or finance.

---

## 4. Fee Approval Workflow

Pattern used: a boolean flag directly on the fee record, not a separate request table.

```js
// Creating a fee that needs admin sign-off:
await insert('student_fees', {
    student_id, fee_category_id, academic_year_id: getCurrentYearId(),
    amount, paid_amount: 0, is_paid: false,
    is_approved: false,   // <-- pending
    is_waived: false, notes: '...'
});
```

- **Holiday Coaching** (auto-applied on holiday enrollment): fixed lookup for a fee
  category literally named `"Holiday Coaching"` (case-insensitive), defaults to **20,000**
  if no class-specific override exists in `fee_amounts`. It does **not** loop over every
  `termly`-frequency category — that was a real bug (it was applying every recurring fee,
  not just coaching).
- **New student registration**: also creates fees with `is_approved: false` now (this
  wasn't true originally — new-registration fees used to skip approval entirely).
- Anywhere a total/expected/dashboard figure is computed, it must filter
  `f.is_approved !== false` — otherwise unapproved (phantom) fees inflate "Total Expected"
  before an admin has confirmed anything. This was a confirmed, fixed bug in multiple
  dashboards and reports.
- **Bulk actions** on the Fee Approvals page: Accept All / Reject All / Accept Selected /
  Reject Selected, via checkboxes. Approve sets `is_approved: true, approved_at, approved_by`.
  Reject sets `is_waived: true, waiver_reason: 'Rejected: ...', manually_deleted: true`
  (there's no hard delete of fee records — rejection is a waiver with a reason).

### Discount / partial-charge pattern (new student registration)

The enrollment fee-selection UI lets you type a lower amount than the catalog price. If
Registration Fee is normally 10,000 and you type 6,000:
```js
const discount = originalCatalogAmount - typedAmount; // 4,000
insert('student_fees', {
    amount: typedAmount,       // 6,000 — this is what the student is actually charged
    waived_amount: discount,   // 4,000 — recorded, not silently dropped
    waiver_reason: `Enrollment discount (normally ${fmtCurrency(originalCatalogAmount)})`,
    is_waived: false           // NOT fully waived, just discounted — is_waived stays false
});
```
A selected fee with the amount set to **0** still creates the record (assignment without
a charge) — earlier code silently skipped anything ≤ 0, which was wrong; a checked box
always means "assign this fee," regardless of amount.

---

## 5. Holiday Academics

### Classes, subjects, assignments (per the original spec)
- Classes: Holiday Primary 1, 3, 4, 5, 6, Special Class. **All pay** — no free classes.
- Subjects: Mathematics, English, Kinyarwanda for most classes; Special Class is English
  only; P5/P6 can add SSRE and SET.
- Teacher assignments use `session_teacher_assignments`, scoped by `session_class_id` +
  `session_subject_id`. When *saving* a teacher's assignments, only clear that teacher's
  **current-year** rows before re-inserting — a real bug had this wiping a teacher's
  entire assignment history across every year on every save.

### Scoring convention — this is a common point of confusion, read carefully
- An assessment (a "test") can be **out of any total** — 20, 50, whatever the teacher
  actually used. `max_marks` is fully editable, not locked to 100.
- Marks Entry records the **raw score** against that raw max (e.g. 18/20).
- **Class Register and Report Cards display the /100-scaled equivalent**, not the raw
  score. 18/20 → shows as **90**. This matches the "pre-midterm" convention used in the
  regular (non-holiday) term system.
  ```js
  const percentage = subMax > 0 ? (subTotal / subMax) * 100 : null;
  // Class Register cell:
  `${percentage !== null ? Math.round(percentage) : '—'}`   // NOT the raw score
  ```
- Holiday Report Cards must show a **rank** (student's position among classmates in the
  same holiday class, computed from the same /100-scaled percentages). This was
  previously hardcoded to `—` and never actually calculated — it needs a loop over every
  student in `session_enrollments` for that class, computing each one's overall
  percentage the same way, then finding where the current student lands.

---

## 6. Historical Roster Derivation (Last Year fixes)

**The problem**: `student.class_id` gets overwritten every time a student is promoted.
Filtering "students where class_id = X" always reflects the student's *current* class —
never a past year's. So viewing "Last Year" in Class Register showed either nobody (if you
picked their old class) or the wrong students mixed with new marks (if you picked their
current class).

**The fix actually used** (not the `class_enrollments` table, which exists but isn't
populated): derive historical rosters from `assessments`, which carry `class_id` at the
time they were created — a reliable snapshot of "who this assessment was actually for."

```js
function getRosterForClassAndYear(classId, yearId) {
    const isPastYear = yearId === getPreviousAcademicYearId();
    if (!isPastYear) {
        return state.students.filter(s => s.class_id == classId && s.status === 'Active');
    }
    // Historical: find every student with a mark tied to an assessment for this class+year
    const classAssessments = state.assessments.filter(a => a.class_id == classId && a.academic_year_id == yearId);
    const assessmentIds = classAssessments.map(a => a.id);
    const studentIds = [...new Set(
        state.marks.filter(m => assessmentIds.includes(m.assessment_id)).map(m => m.student_id)
    )];
    return state.students.filter(s => studentIds.includes(s.id));
}
```

Use this everywhere a class roster is needed for a *possibly-past* year: Class Register,
Report Cards, Marks Database, the report-card student picker, `generateAllReports`,
`calculateStudentRank`/`calculateStudentRankFull`, and the Statistics class-average/
grade-distribution calculators. **Caveat**: a student with zero marks that year won't
appear (there's no other reliable signal without populating `class_enrollments`).

If you do decide to build out `class_enrollments` properly later, this whole function
becomes a straightforward query against that table instead — the interface
(`getRosterForClassAndYear(classId, yearId)`) doesn't need to change for callers.

---

## 7. Bug Fixes Worth Knowing About (regression list)

If re-implementing any of this from an older branch, watch for these — they were each
real, confirmed bugs found during this rebuild:

- **`calculateStudentRank` vs `calculateStudentRankFull` name mismatch**: one call site
  called the 2-argument version by name while passing 5 arguments (JS silently ignores
  extras) — meaning the *wrong* function ran and rank always showed 0/— for past years.
  Both now correctly use `getRosterForClassAndYear`.
- **Undeclared chart variables**: `statsChart`, `monthlyChart`, `methodChart` were
  referenced (`if (chartVar) chartVar.destroy()`) without ever being declared —
  `ReferenceError` on first use. Declare as `let x = null;` at module scope.
- **`getTermById` / `getSessionSubjectsForClass` referenced but never defined** —
  straightforward lookups against `state.terms` / `state.sessionSubjects`.
- **Enrollment receipt downloaded empty**: the code looked up the just-created payment
  from `state.payments` *before* that array had been refreshed from the DB — always found
  nothing. Fix: pass the created payment object directly into the receipt function instead
  of re-fetching it from state.
- **`state.terms` loaded unfiltered across every year** — same bug pattern as everything
  else; fix by filtering to `academic_year_id == yearId` when assigning to `state.terms`.
- **Financial dashboards computing "Total Expected" from the fee-structure catalog**
  (`state.feeAmounts`, i.e. every possible price regardless of whether it was ever charged)
  instead of from actually-assigned fees. Always derive expected/collected totals from
  `state.studentFees`, filtered by `is_approved !== false`.
- **Timetable had zero year-scoping and no `academic_year_id` column** — 8 separate call
  sites (class view, staff view, single-slot editor, conflict checker, auto-generator, CSV
  import) needed both the schema column and query filters added together.

---

## 8. Codes, Numbers & Filenames

```
Student code:   STU-YYYY-NNNN   (sequential per calendar year, school-wide — not per class)
Receipt number: RCT-YYYY-NNNN   (same pattern)
Downloaded file: FirstLast_DocType_YYMMDD_NN.pdf
                 e.g. JeanUwimana_PaymentReceipt_260729_14.pdf
```

Shared generator functions: `generateStudentCode()`, `generateReceiptNumber()`,
`buildDocFilename(student, docType)` — use these everywhere instead of ad-hoc formats;
there were previously four different receipt-number formats scattered across the file
(`RCP-`, `CRD-`, `ADJ-`, plus the "real" one).

**Sort/display order**: always **First name, then Last name** — both for display
(`studentFullName`) and for alphabetical sort order (`sortStudentsAlpha`,
`sortStudentsAlphabetically`). Sorting used to be last-name-primary; every call site that
does `.sort((a,b) => a.last_name.localeCompare(b.last_name))` needs to become
`a.first_name.localeCompare(b.first_name) || a.last_name.localeCompare(b.last_name)`.

---

## 9. Receipts Are Non-Blocking

Saving a record (payment, enrollment) must feel instant. Receipt/PDF generation is
comparatively slow, so it's decoupled from the save path:

```js
// 1. Do the actual DB writes (insert/update), await them — this is the part that must be fast.
// 2. Refresh the relevant state tables.
// 3. Re-enable the button, show a success toast, navigate away — don't wait on anything else.
// 4. Kick off the receipt in the background, NOT awaited:
showToast('🧾 Preparing receipt for download…', 'info');
setTimeout(() => downloadPaymentReceipt(payment, student, feeRecords), 2000);
```
The receipt functions build an off-screen HTML node and run it through `html2pdf()`
(auto-`.save()`, no click required). Reused for Record Payment, Enrollment, and
Enrollment Confirmation (zero-payment case) via one shared template function
(`generateEnrollmentReceiptHTML(payment, student, feeRecords, title)`).

---

## 10. Known Gaps (deliberately not built / not finished)

- **No real push-notification system.** Fee approvals surface on the Fee Approvals page
  and a dashboard count — nothing pings the admin proactively.
- **`class_enrollments` table exists but is unused.** §6 explains the workaround actually
  in place. Worth revisiting if you need reliable historical rosters for students with
  zero marks in a given year.
- **Auto-backup scheduling was fake for a while** (settings saved, nothing read them) —
  fixed with a real `setInterval`-driven `checkAndRunAutoBackup()`, but it's a simple
  hourly-check-against-a-timestamp approach, not a robust job scheduler.
- **`manifest.json` vs `site.webmanifest`** — the HTML links `site.webmanifest` (complete,
  correct); `manifest.json` is an orphaned duplicate with placeholder icon paths that don't
  exist. Not referenced anywhere — safe to delete. `sw.js` was fixed to cache
  `site.webmanifest`, not `manifest.json`.
