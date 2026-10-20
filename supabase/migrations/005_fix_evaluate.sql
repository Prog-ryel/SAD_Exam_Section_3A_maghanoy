-- Fix: "malformed array literal: Late submission" (text[] || 'literal' was parsed as an array literal).
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
  checks := checks || jsonb_build_object('check','GWA','rule','<= '||p.max_gwa::text,'actual',s.gwa,'pass',ok);
  if not ok then reasons := array_append(reasons, format('GWA %s exceeds max %s', s.gwa, p.max_gwa)); end if;
  ok := s.units >= p.min_units;
  checks := checks || jsonb_build_object('check','Units','rule','>= '||p.min_units::text,'actual',s.units,'pass',ok);
  if not ok then reasons := array_append(reasons, format('Units %s below min %s', s.units, p.min_units)); end if;
  ok := s.failed_count <= p.max_failed;
  checks := checks || jsonb_build_object('check','Failed','rule','<= '||p.max_failed::text,'actual',s.failed_count,'pass',ok);
  if not ok then reasons := array_append(reasons, format('Failed subjects %s exceeds max %s', s.failed_count, p.max_failed)); end if;
  ok := s.incomplete_count <= p.max_incomplete;
  checks := checks || jsonb_build_object('check','INC','rule','<= '||p.max_incomplete::text,'actual',s.incomplete_count,'pass',ok);
  if not ok then reasons := array_append(reasons, format('INC %s exceeds max %s', s.incomplete_count, p.max_incomplete)); end if;
  ok := s.dropped_count <= p.max_dropped;
  checks := checks || jsonb_build_object('check','Dropped','rule','<= '||p.max_dropped::text,'actual',s.dropped_count,'pass',ok);
  if not ok then reasons := array_append(reasons, format('Dropped %s exceeds max %s', s.dropped_count, p.max_dropped)); end if;
  ok := s.submitted_at <= p.deadline;  -- exactly at deadline = on time
  checks := checks || jsonb_build_object('check','Deadline','rule','<= '||to_char(p.deadline at time zone 'Asia/Manila','YYYY-MM-DD HH24:MI')||' Manila','actual',to_char(s.submitted_at at time zone 'Asia/Manila','YYYY-MM-DD HH24:MI:SS'),'pass',ok);
  if not ok then reasons := array_append(reasons, 'Late submission'::text); end if;

  update submissions set compliance_result = case when cardinality(reasons)=0 then 'Compliant' else 'With Deficiency' end,
    deficiency_reasons = reasons, renewal_decision = 'None', decision_note = null where id = p_id;
  -- Award status is deliberately NOT changed: a deficiency never auto-disqualifies.
  return jsonb_build_object('result', case when cardinality(reasons)=0 then 'Compliant' else 'With Deficiency' end,
    'reasons', to_jsonb(reasons), 'checks', checks);
end $$;
