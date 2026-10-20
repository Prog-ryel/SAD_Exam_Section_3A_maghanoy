# Test Results (TC01–TC10) — Section A

> Honest note: I could not execute these against your live Supabase project. Run each test, then write what you actually observe in **Actual** and **Pass/Fail**, and attach the screenshot as evidence. Expected results are derived from the policy and seed data.

| ID | Input / action | Expected | Actual | Pass/Fail | Evidence |
|---|---|---|---|---|---|
| TC01 Valid boundary | Staff evaluates A01 (Merit 1.75/18/0/0/0, submitted 17:00:00 exactly) | Compliant; GWA and Deadline checks PASS | | | shot-tc01 |
| TC02 GWA above limit | Evaluate A02 (1.76) | With Deficiency: "GWA 1.76 exceeds max 1.75" | | | shot-tc02 |
| TC03 Program variation | Evaluate A03 (Community 2.25/15/0/0/1 dropped) | Compliant (1 dropped allowed) | | | shot-tc03 |
| TC04 Multiple deficiencies | Evaluate A04 (14 units, 1 INC) | With Deficiency: units 14 below 15; INC 1 exceeds 0 | | | shot-tc04 |
| TC05 Failure and lateness | Evaluate A05 (1 failed, 17:01) | With Deficiency: failed 1 exceeds 0; Late submission | | | shot-tc05 |
| TC06 Verification gate | A06 (Pending): try Evaluate and Approve (also via console `sb.rpc('evaluate_submission')`, `sb.rpc('record_decision')`) | Evaluate button absent / RPC error "Only Verified…"; Approve blocked "Not Verified/Evaluate first" | | | shot-tc06 |
| TC07 Duplicate and invalid | As scholar: submit duplicate AY+semester; GWA 0.50; units/count -1 | Each rejected with clear message (UI duplicate message; DB CHECK for GWA/negative) | | | shot-tc07 |
| TC08 Role isolation | As scholar A01 in console: `sb.from('submissions').select()`; `sb.rpc('verify_submission',{p_id:<A02 id>,p_action:'Verified'})` | Only own row returned; verify RPC error "Staff only" | | | shot-tc08 |
| TC09 Persistence and correction | Staff Return a record with reason; scholar edits and resubmits; refresh | Status Pending; return reason cleared; history shows Pending→Returned→Pending; data persists after refresh | | | shot-tc09 |
| TC10 Renewal authority | Staff Approve a Compliant record, Hold a deficient one; scholar tries `update({renewal_decision:'Approved'})` | Approve OK, Hold OK, Approve on deficient blocked; scholar change has no effect (reset by trigger / 0 rows) | | | shot-tc10 |

## Known defects / limitations
- Not yet executed by me (see note above).
- Dashboard "Assigned" counts all assigned scholars, not only those with a submission in the selected semester.
- Staff accounts must be promoted with `supabase/make_staff.sql`; no in-app staff creation.
