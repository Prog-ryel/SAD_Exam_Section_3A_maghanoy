-- Seed: run AFTER 001-004 migrations. Run in the Supabase SQL editor.
-- (auth.uid() is null there, so the guard trigger allows these privileged inserts.)

-- 0) Create any missing demo scholar auth users (confirmed, with a RANDOM unusable password;
--    no password is stored in this file).
do $$
declare e text; uid uuid;
begin
  foreach e in array array['a01@example.test','a02@example.test','a03@example.test','a04@example.test','a05@example.test','a06@example.test'] loop
    if not exists (select 1 from auth.users where email = e) then
      uid := gen_random_uuid();
      insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
        raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change,email_change_token_new)
      values ('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',e,
        crypt(gen_random_uuid()::text, gen_salt('bf')),now(),
        '{"provider":"email","providers":["email"]}','{}',now(),now(),'','','','');
      insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
      values (gen_random_uuid(),uid,uid::text,jsonb_build_object('sub',uid::text,'email',e),'email',now(),now(),now());
    end if;
  end loop;
end $$;
-- To LOG IN as a demo scholar, run once with a password you choose (never commit it):
--   update auth.users set encrypted_password = crypt('YOUR_PASSWORD', gen_salt('bf')) where email like 'a0%@example.test';

-- 1) Staff profile: change the email to your registered staff account.
insert into profiles(id,role,full_name) select id,'staff','Scholarship Staff' from auth.users where email='ryellmaghanoy@gmail.com'
  on conflict (id) do nothing;

-- 2) Six fictional scholars, assignments and AY 2026-2027 Sem 1 submissions.
with d(email,sid,name,prog,gwa,units,f,i,dr,sub_at,status) as (values
 ('a01@example.test','A01','Ana Reyes','Merit',1.75,18,0,0,0,timestamptz '2026-10-30 17:00:00+08','Verified'),
 ('a02@example.test','A02','Ben Cruz','Merit',1.76,18,0,0,0,timestamptz '2026-10-29 17:00:00+08','Verified'),
 ('a03@example.test','A03','Cara Santos','Community',2.25,15,0,0,1,timestamptz '2026-10-29 17:00:00+08','Verified'),
 ('a04@example.test','A04','Dan Lopez','Community',2.25,14,0,1,0,timestamptz '2026-10-29 17:00:00+08','Verified'),
 ('a05@example.test','A05','Eva Tan','Merit',1.50,18,1,0,0,timestamptz '2026-10-30 17:01:00+08','Verified'),
 ('a06@example.test','A06','Finn Uy','Community',2.00,15,0,0,0,timestamptz '2026-10-29 17:00:00+08','Pending'))
, p as (insert into profiles(id,role,student_id,full_name)
        select u.id,'scholar',d.sid,d.name from d join auth.users u on u.email=d.email
        on conflict (id) do nothing returning id)
, a as (insert into scholar_assignments(scholar_id,program_id)
        select u.id,pr.id from d join auth.users u on u.email=d.email join programs pr on pr.name=d.prog
        on conflict do nothing returning scholar_id)
insert into submissions(scholar_id,academic_year,semester,gwa,units,failed_count,incomplete_count,dropped_count,evidence_ref,submitted_at,verification_status)
select u.id,'2026-2027',1,d.gwa,d.units,d.f,d.i,d.dr,'registrar-ref-'||d.sid,d.sub_at,d.status
from d join auth.users u on u.email=d.email
on conflict (scholar_id,academic_year,semester) do nothing;

-- 3) Check the result:
select p.student_id, p.full_name, p.role, pr.name as program from profiles p
left join scholar_assignments a on a.scholar_id = p.id left join programs pr on pr.id = a.program_id order by p.student_id;
