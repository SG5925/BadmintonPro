-- =============================================================================
-- Badminton Pro — Phase 2b: email-only login
-- =============================================================================
-- Login is now Email + OTP for every role (no SMS, no anonymous guests).
-- Linking matches the verified email instead of a phone number:
--   coach   : verified email = tenants.email
--   student : verified email = students.email (active, same tenant). Every
--             matching student is linked, so a parent's email covers siblings.
--   guest   : verified email links matching guests rows, or creates one.
-- Function signatures are unchanged, so existing grants carry over.
-- =============================================================================

drop index if exists public.students_tenant_phone_idx;
drop index if exists public.guests_tenant_phone_idx;
drop function if exists private.normalize_phone(text);

create index students_tenant_email_idx on public.students (tenant_id, lower(email));
create index guests_tenant_email_idx   on public.guests   (tenant_id, lower(email));

-- Verified email of the signed-in user, lower-cased; NULL if unverified/absent.
create or replace function private.get_my_verified_email()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select lower(a.email)
  from auth.users a
  where a.id = (select auth.uid()) and a.email_confirmed_at is not null;
$$;
revoke execute on function private.get_my_verified_email() from public, anon, authenticated;

create or replace function public.claim_coach_access(p_coach_code text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  t public.tenants;
  v_email text;
begin
  if v_uid is null then
    raise exception 'Please sign in first.' using errcode = '28000';
  end if;
  t := private.get_active_tenant(p_coach_code);
  v_email := private.get_my_verified_email();

  if v_email is null or v_email is distinct from lower(t.email) then
    raise exception 'This email is not registered as the coach for %.', t.coach_code;
  end if;
  if t.owner_user_id is not null and t.owner_user_id <> v_uid then
    raise exception 'This academy is already linked to a different coach account.';
  end if;

  perform private.assert_can_link(v_uid, 'coach', t.id);

  update public.users
     set role = 'coach', tenant_id = t.id, email = coalesce(email, v_email)
   where id = v_uid;
  update public.tenants set owner_user_id = v_uid where id = t.id and owner_user_id is null;

  return json_build_object('role', 'coach', 'tenant_id', t.id);
end;
$$;

create or replace function public.claim_student_access(p_coach_code text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  t public.tenants;
  v_email text;
  v_linked int;
begin
  if v_uid is null then
    raise exception 'Please sign in first.' using errcode = '28000';
  end if;
  t := private.get_active_tenant(p_coach_code);
  perform private.assert_can_link(v_uid, 'student', t.id);

  v_email := private.get_my_verified_email();
  if v_email is null then
    raise exception 'Please sign in with a verified email address.';
  end if;

  update public.students
     set user_id = v_uid
   where tenant_id = t.id
     and status = 'active'
     and lower(email) = v_email
     and (user_id is null or user_id = v_uid);
  get diagnostics v_linked = row_count;

  if v_linked = 0 then
    if exists (select 1 from public.students
               where tenant_id = t.id and lower(email) = v_email and status = 'active') then
      raise exception 'This email is already linked to another account. Please contact your coach.';
    end if;
    raise exception 'No active student with this email is registered with this coach. Ask your coach to add your email.';
  end if;

  update public.users
     set role = 'student', tenant_id = t.id, email = coalesce(email, v_email)
   where id = v_uid;

  return json_build_object('role', 'student', 'tenant_id', t.id, 'students_linked', v_linked);
end;
$$;

create or replace function public.claim_guest_access(p_coach_code text, p_full_name text default null)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  t public.tenants;
  v_email text;
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
begin
  if v_uid is null then
    raise exception 'Please sign in first.' using errcode = '28000';
  end if;
  t := private.get_active_tenant(p_coach_code);
  perform private.assert_can_link(v_uid, 'guest', t.id);

  v_email := private.get_my_verified_email();
  if v_email is null then
    raise exception 'Please sign in with a verified email address.';
  end if;

  update public.users
     set role = 'guest', tenant_id = t.id,
         full_name = coalesce(v_name, full_name), email = coalesce(email, v_email)
   where id = v_uid;

  update public.guests
     set user_id = v_uid
   where tenant_id = t.id and user_id is null and lower(email) = v_email;

  if not exists (select 1 from public.guests where tenant_id = t.id and user_id = v_uid) then
    insert into public.guests (tenant_id, user_id, full_name, email)
    values (t.id, v_uid, coalesce(v_name, 'Guest'), v_email);
  end if;

  return json_build_object('role', 'guest', 'tenant_id', t.id);
end;
$$;
