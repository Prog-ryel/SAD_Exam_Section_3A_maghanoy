-- 1) Create the scholar profile at sign-up time (works even when email confirmation is on).
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.raw_user_meta_data->>'student_id','') <> '' then
    insert into profiles(id, role, student_id, full_name)
    values (new.id, 'scholar', new.raw_user_meta_data->>'student_id',
            coalesce(new.raw_user_meta_data->>'full_name', new.email))
    on conflict (id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- 2) Backfill users who already registered but have no profile.
insert into profiles(id, role, student_id, full_name)
select id, 'scholar', raw_user_meta_data->>'student_id', coalesce(raw_user_meta_data->>'full_name', email)
from auth.users
where coalesce(raw_user_meta_data->>'student_id','') <> ''
on conflict (id) do nothing;

-- 3) Staff assign a program to an already-registered scholar (by profile id).
create or replace function assign_program(p_scholar uuid, p_program text)
returns void language plpgsql security definer set search_path = public as $$
declare pid int;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  select id into pid from programs where name = p_program;
  if pid is null then raise exception 'Unknown program'; end if;
  if not exists (select 1 from profiles where id = p_scholar and role = 'scholar') then raise exception 'Not a scholar'; end if;
  insert into scholar_assignments(scholar_id, program_id) values (p_scholar, pid)
    on conflict (scholar_id) do update set program_id = excluded.program_id;
end $$;
grant execute on function assign_program to authenticated;
