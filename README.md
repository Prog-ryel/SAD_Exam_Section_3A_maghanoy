# Scholarship Monitoring MVP

HTML + CSS + vanilla JS + Supabase (no separate backend).

## Setup
1. Create a Supabase project.
2. SQL editor: run `supabase/migrations/001_schema.sql`.
3. Authentication > Users: add `staff@example.test` and `a01..a06@example.test` (choose your own passwords; do not commit them). Disable email confirmation for the demo.
4. SQL editor: run `supabase/seed.sql` (creates profiles, assignments, 6 submissions).
5. Edit `config.js` with the two env values below.

## Env var names (in `config.js`, `window.APP_CONFIG`)
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` (public anon key only; **never** the service-role key)

## Run
`C:\xampp\htdocs` is already served by XAMPP: open `http://localhost/sad%20exam/`.
Or: `npx serve .` / `python -m http.server`.

## Walkthrough
Log in as staff -> choose 2026-2027 / 1 -> Verify A06 (or leave Pending) -> Evaluate A01–A05 -> Approve/Hold with note -> History.

## Design notes
- Scholars cannot change status columns: `guard_submission` trigger resets them; RLS limits updates to own *Returned* rows.
- Staff actions go through RPCs (`verify_submission`, `evaluate_submission`, `record_decision`, `register_scholar`); thresholds and deadline are read from `programs`.
- Approval is blocked by RPC and by a CHECK constraint unless `compliance_result = 'Compliant'`.
- Deficiency never changes `scholar_assignments.award_status`.
- "Register scholar" links an existing auth user (they sign up first) because creating auth users needs a service-role key, which must not be in client code.

## Run order
Run in the Supabase SQL editor: 001_schema.sql, 002_self_register.sql, 003_auto_profile_assign.sql, 004_evidence_required.sql; register the staff and scholars; run make_staff.sql; run seed.sql.

## Known defects
See docs/test-results.md. Staff accounts are promoted by SQL; test-account credentials are given privately to the instructor (not in the repo). Submission folder name: SAD_Exam_Section_A_StudentID.
