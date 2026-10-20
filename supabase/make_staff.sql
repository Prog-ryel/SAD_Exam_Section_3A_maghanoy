-- Make an existing account a STAFF user (run in Supabase SQL editor, which bypasses RLS).
-- 1) Register the account first (Register screen, or Authentication > Users > Add user with "Auto Confirm").
-- 2) Replace the email below and run.
insert into profiles(id, role, student_id, full_name)
select id, 'staff', null, 'Scholarship Staff'
from auth.users where email = 'staff@example.test'
on conflict (id) do update set role = 'staff';

-- If login says "Email not confirmed", confirm the user manually:
-- update auth.users set email_confirmed_at = now() where email = 'staff@example.test';
