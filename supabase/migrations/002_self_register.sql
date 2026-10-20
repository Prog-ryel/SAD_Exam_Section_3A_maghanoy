-- Self-registration: an authenticated user may create ONLY their own scholar profile.
-- Staff accounts can never be self-created (role must be 'scholar'); staff assign the program.
create policy profiles_self_insert on profiles for insert
  with check (id = auth.uid() and role = 'scholar');
