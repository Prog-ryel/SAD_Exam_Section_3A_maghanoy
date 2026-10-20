-- Scholarship Monitoring MVP: schema, triggers, RLS, RPCs. Run in Supabase SQL editor.
create extension if not exists pgcrypto;

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('scholar','staff')),
  student_id text unique,
  full_name text not null
);

create table programs (
  id serial primary key,
  name text unique not null,
  max_gwa numeric(3,2) not null check (max_gwa between 1 and 5),
  min_units int not null check (min_units >= 0),
  max_failed int not null check (max_failed >= 0),
  max_incomplete int not null check (max_incomplete >= 0),
  max_dropped int not null check (max_dropped >= 0),
  deadline timestamptz not null
);

insert into programs (name,max_gwa,min_units,max_failed,max_incomplete,max_dropped,deadline) values
 ('Merit',1.75,18,0,0,0,'2026-10-30 17:00:00+08'),
 ('Community',2.25,15,0,0,1,'2026-10-30 17:00:00+08');

create table scholar_assignments (
  scholar_id uuid primary key references profiles(id) on delete cascade, -- one program per scholar (BR duplicate prevention)
  program_id int not null references programs(id),
  award_status text not null default 'Active' check (award_status in ('Active','Probation','Suspended','Terminated','Graduated'))
);

create table submissions (
  id uuid primary key default gen_random_uuid(),
  scholar_id uuid not null references profiles(id) on delete cascade,
  academic_year text not null,
  semester int not null check (semester in (1,2)),
  gwa numeric(3,2) not null check (gwa between 1.00 and 5.00),
  units int not null check (units >= 0),
  failed_count int not null default 0 check (failed_count >= 0),
  incomplete_count int not null default 0 check (incomplete_count >= 0),
  dropped_count int not null default 0 check (dropped_count >= 0),
  evidence_ref text,
  submitted_at timestamptz not null default now(),
  verification_status text not null default 'Pending' check (verification_status in ('Pending','Verified','Returned')),
  return_reason text,
  compliance_result text not null default 'Not Evaluated' check (compliance_result in ('Not Evaluated','Compliant','With Deficiency')),
  deficiency_reasons text[],
  renewal_decision text not null default 'None' check (renewal_decision in ('None','Approved','Held')),
  decision_note text,
  unique (scholar_id, academic_year, semester),
  check (verification_status <> 'Returned' or coalesce(return_reason,'') <> ''),
  check (renewal_decision <> 'Approved' or compliance_result = 'Compliant')
);

create table audit_log (
  id bigserial primary key,
  submission_id uuid references submissions(id) on delete cascade,
  actor_id uuid,
  action text not null,
  old_value text,
  new_value text,
  note text,
  created_at timestamptz not null default now()
);

create or replace function is_staff() returns boolean
language sql security definer stable set search_path = public as
$$ select exists (select 1 from profiles where id = auth.uid() and role = 'staff') $$;

-- Guard: scholars cannot touch verification/compliance/renewal columns.
create or replace function guard_submission() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or is_staff() then   -- null = SQL editor/seed (privileged)
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.scholar_id := auth.uid();
  else
    if old.verification_status <> 'Returned' then
      raise exception 'Only Returned submissions can be resubmitted';
    end if;
    new.scholar_id := old.scholar_id; new.academic_year := old.academic_year; new.semester := old.semester;
  end if;
  new.submitted_at := now();
  new.verification_status := 'Pending'; new.return_reason := null;
  new.compliance_result := 'Not Evaluated'; new.deficiency_reasons := null;
  new.renewal_decision := 'None'; new.decision_note := null;
  return new;
end $$;
create trigger trg_guard before insert or update on submissions
  for each row execute function guard_submission();

create or replace function log_submission() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into audit_log(submission_id,actor_id,action,new_value) values (new.id,auth.uid(),'Submitted',new.verification_status);
    return new;
  end if;
  if new.verification_status is distinct from old.verification_status then
    insert into audit_log(submission_id,actor_id,action,old_value,new_value,note)
    values (new.id,auth.uid(),'Verification',old.verification_status,new.verification_status,new.return_reason);
  end if;
  if new.compliance_result is distinct from old.compliance_result then
    insert into audit_log(submission_id,actor_id,action,old_value,new_value,note)
    values (new.id,auth.uid(),'Compliance',old.compliance_result,new.compliance_result,array_to_string(new.deficiency_reasons,'; '));
  end if;
  if new.renewal_decision is distinct from old.renewal_decision then
    insert into audit_log(submission_id,actor_id,action,old_value,new_value,note)
    values (new.id,auth.uid(),'Renewal',old.renewal_decision,new.renewal_decision,new.decision_note);
  end if;
  return new;
end $$;
create trigger trg_log after insert or update on submissions
  for each row execute function log_submission();

-- RLS
alter table profiles enable row level security;
alter table programs enable row level security;
alter table scholar_assignments enable row level security;
alter table submissions enable row level security;
alter table audit_log enable row level security;

create policy profiles_read on profiles for select using (id = auth.uid() or is_staff());
create policy programs_read on programs for select using (auth.uid() is not null);
create policy assign_read on scholar_assignments for select using (scholar_id = auth.uid() or is_staff());
create policy sub_read on submissions for select using (scholar_id = auth.uid() or is_staff());
create policy sub_insert on submissions for insert with check (
  scholar_id = auth.uid() and exists (select 1 from scholar_assignments a where a.scholar_id = auth.uid()));
create policy sub_update_scholar on submissions for update
  using (scholar_id = auth.uid() and verification_status = 'Returned')
  with check (scholar_id = auth.uid());
create policy sub_update_staff on submissions for update using (is_staff()) with check (is_staff());
create policy audit_read on audit_log for select using (
  is_staff() or exists (select 1 from submissions s where s.id = submission_id and s.scholar_id = auth.uid()));
-- No insert/update/delete policies on audit_log: written only by security-definer triggers.

-- RPCs (staff only)
create or replace function register_scholar(p_email text, p_student_id text, p_full_name text, p_program text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid; pid int;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then raise exception 'No auth user with that email. Ask the scholar to sign up first.'; end if;
  select id into pid from programs where name = p_program;
  if pid is null then raise exception 'Unknown program'; end if;
  insert into profiles(id,role,student_id,full_name) values (uid,'scholar',p_student_id,p_full_name)
    on conflict (id) do update set student_id = excluded.student_id, full_name = excluded.full_name
    where profiles.role = 'scholar';
  insert into scholar_assignments(scholar_id,program_id) values (uid,pid)
    on conflict (scholar_id) do update set program_id = excluded.program_id;
end $$;

create or replace function verify_submission(p_id uuid, p_action text, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  if p_action = 'Returned' and coalesce(trim(p_reason),'') = '' then raise exception 'Return reason required'; end if;
  if p_action not in ('Verified','Returned') then raise exception 'Invalid action'; end if;
  update submissions set verification_status = p_action,
    return_reason = case when p_action='Returned' then p_reason else null end,
    compliance_result = 'Not Evaluated', deficiency_reasons = null, renewal_decision = 'None', decision_note = null
  where id = p_id and verification_status = 'Pending';
  if not found then raise exception 'Submission not found or not Pending'; end if;
end $$;

create or replace function evaluate_submission(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s submissions; p programs; reasons text[] := '{}'; checks jsonb := '[]'::jsonb; ok boolean;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  select * into s from submissions where id = p_id;
  if not found then raise exception 'Submission not found'; end if;
  if s.verification_status <> 'Verified' then raise exception 'Only Verified submissions can be evaluated'; end if;
  select pr.* into p from programs pr join scholar_assignments a on a.program_id = pr.id where a.scholar_id = s.scholar_id;
  if not found then raise exception 'Scholar has no program'; end if;

  ok := s.gwa <= p.max_gwa;
  checks := checks || jsonb_build_object('check','GWA','rule','<= '||p.max_gwa,'actual',s.gwa,'pass',ok);
  if not ok then reasons := reasons || format('GWA %s exceeds max %s', s.gwa, p.max_gwa); end if;
  ok := s.units >= p.min_units;
  checks := checks || jsonb_build_object('check','Units','rule','>= '||p.min_units,'actual',s.units,'pass',ok);
  if not ok then reasons := reasons || format('Units %s below min %s', s.units, p.min_units); end if;
  ok := s.failed_count <= p.max_failed;
  checks := checks || jsonb_build_object('check','Failed','rule','<= '||p.max_failed,'actual',s.failed_count,'pass',ok);
  if not ok then reasons := reasons || format('Failed subjects %s exceeds max %s', s.failed_count, p.max_failed); end if;
  ok := s.incomplete_count <= p.max_incomplete;
  checks := checks || jsonb_build_object('check','INC','rule','<= '||p.max_incomplete,'actual',s.incomplete_count,'pass',ok);
  if not ok then reasons := reasons || format('INC %s exceeds max %s', s.incomplete_count, p.max_incomplete); end if;
  ok := s.dropped_count <= p.max_dropped;
  checks := checks || jsonb_build_object('check','Dropped','rule','<= '||p.max_dropped,'actual',s.dropped_count,'pass',ok);
  if not ok then reasons := reasons || format('Dropped %s exceeds max %s', s.dropped_count, p.max_dropped); end if;
  ok := s.submitted_at <= p.deadline;  -- exactly at deadline = on time
  checks := checks || jsonb_build_object('check','Deadline','rule','<= '||to_char(p.deadline at time zone 'Asia/Manila','YYYY-MM-DD HH24:MI')||' Manila','actual',to_char(s.submitted_at at time zone 'Asia/Manila','YYYY-MM-DD HH24:MI:SS'),'pass',ok);
  if not ok then reasons := reasons || 'Late submission'; end if;

  update submissions set compliance_result = case when cardinality(reasons)=0 then 'Compliant' else 'With Deficiency' end,
    deficiency_reasons = reasons, renewal_decision = 'None', decision_note = null where id = p_id;
  -- Award status is deliberately NOT changed: a deficiency never auto-disqualifies.
  return jsonb_build_object('result', case when cardinality(reasons)=0 then 'Compliant' else 'With Deficiency' end,
    'reasons', to_jsonb(reasons), 'checks', checks);
end $$;

create or replace function record_decision(p_id uuid, p_decision text, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  if p_decision not in ('Approved','Held') then raise exception 'Invalid decision'; end if;
  if coalesce(trim(p_note),'') = '' then raise exception 'Note required'; end if;
  select compliance_result into c from submissions where id = p_id and verification_status = 'Verified';
  if c is null then raise exception 'Submission not found or not Verified'; end if;
  if c = 'Not Evaluated' then raise exception 'Evaluate first'; end if;
  if p_decision = 'Approved' and c <> 'Compliant' then raise exception 'Approval blocked: compliance_result is not Compliant'; end if;
  update submissions set renewal_decision = p_decision, decision_note = p_note where id = p_id;
end $$;

grant execute on function register_scholar, verify_submission, evaluate_submission, record_decision to authenticated;
