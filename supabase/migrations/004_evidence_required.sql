-- Exam rule: "Missing evidence prevents final evaluation" -> evidence (grade-document reference) is mandatory.
alter table submissions add constraint evidence_required check (length(trim(coalesce(evidence_ref,''))) > 0);
