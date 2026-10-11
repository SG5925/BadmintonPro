-- =============================================================================
-- Badminton Pro — Phase 2: login linking (coach code + verified email/phone)
-- =============================================================================
-- Supabase OTP proves the user controls an email/phone. These functions then
-- prove that email/phone belongs to the coach code entered, and link the auth
-- user to the right tenant + role. Role/tenant can't be set by the client
-- directly (Phase 1 trigger), so this is the only self-service path.
--
-- Matching rules
--   coach   : verified email = tenants.email  OR verified phone = tenants.phone
--   student : verified phone = students.phone (active, same tenant). Every
--             matching student is linked, so a parent's number covers siblings.
--   guest   : any account; a verified phone also links matching guests rows,
--             or creates one. Anonymous guests only get the tenant (no rows).
-- =============================================================================

-- Phone numbers are compared as digits with country code. Bare 10-digit and
-- 0-prefixed numbers are treated as Indian (+91), the default market.
create or replace function private.normalize_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  d text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  if d = '' then
    return null;
  elsif length(d) = 10 then
    return '91' || d;
  elsif length(d) = 11 and left(d, 1) = '0' then
    return '91' || substr(d, 2);
  end if;
  return d;
end;
$$;

-- Accepts "BP-COACH-0042", "bp-coach-42" or just "42".
create or replace function private.normalize_coach_code(p_code text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  c text := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  n text;
begin
  if c ~ '^[0-9]+$' then
    n := ltrim(c, '0');
  elsif c ~ '^BP-COACH-[0-9]+$' then
    n := ltrim(substr(c, 10), '0');
  else
    return c;
  end if;
  if n = '' then n := '0'; end if;
  return 'BP-COACH-' || lpad(n, greatest(4, length(n)), '0');
end;
$$;

create index students_tenant_phone_idx on public.students (tenant_id, private.normalize_phone(phone));
create index guests_tenant_phone_idx   on public.guests   (tenant_id, private.normalize_phone(phone));
create index tenants_email_lower_idx   on public.tenants  (lower(email));

-- Can this account be (re)linked as p_role in p_tenant? One account belongs to
-- one academy with one role; only a guest may move on to another role/academy.
create or replace function private.assert_can_link(p_uid uuid, p_role public.user_role, p_tenant uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  u public.users;
begin
  select * into u from public.users where id = p_uid;
  if not found then
    raise exception 'Your account profile is missing. Please contact support.';
  end if;
  if not u.is_active then
    raise exception 'This account has been deactivated. Please contact your coach.';
  end if;
  if u.role = 'developer' then
    raise exception 'Developer accounts cannot sign in here.';
  end if;
  if u.role = p_role and u.tenant_id = p_tenant then
    return;  -- already linked: returning user
  end if;
  if u.role <> 'guest' then
    if u.tenant_id = p_tenant then
      raise exception 'This account is registered as a % with this academy. Please use the % login.', u.role, u.role;
    end if;
    raise exception 'This account is already registered as a % with another academy.', u.role;
  end if;
end;
$$;

create or replace function private.get_active_tenant(p_coach_code text)
returns public.tenants
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  t public.tenants;
begin
  select * into t from public.tenants
  where coach_code = private.normalize_coach_code(p_coach_code);
  if not found then
    raise exception 'Invalid coach code. Please check and try again.';
  end if;
  if t.status <> 'active' then
    raise exception 'This academy is not active right now. Please contact your coach.';
  end if;
  return t;
end;
$$;

revoke execute on function
  private.normalize_phone(text), private.normalize_coach_code(text),
  private.assert_can_link(uuid, public.user_role, uuid), private.get_active_tenant(text)
from public, anon;
grant execute on function private.normalize_phone(text), private.normalize_coach_code(text)
  to authenticated;

-- =============================================================================
-- Public RPCs (called from the app)
-- =============================================================================

-- Pre-login check so the app can show "Signing in to <academy>" before sending
-- an OTP. Reveals only the display name of an active academy.
create or replace function public.lookup_coach_code(p_coach_code text)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  t public.tenants;
begin
  select * into t from public.tenants
  where coach_code = private.normalize_coach_code(p_coach_code) and status = 'active';
  if not found then
    return null;
  end if;
  return json_build_object(
    'coach_code', t.coach_code,
    'academy_name', coalesce(t.academy_name, t.name));
end;
$$;

create or replace function public.claim_coach_access(p_coach_code text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  t public.tenants;
  a auth.users;
  v_email text;
  v_phone text;
begin
  if v_uid is null then
    raise exception 'Please sign in first.' using errcode = '28000';
  end if;
  t := private.get_active_tenant(p_coach_code);

  select * into a from auth.users where id = v_uid;
  v_email := case when a.email_confirmed_at is not null then lower(a.email) end;
  v_phone := case when a.phone_confirmed_at is not null then private.normalize_phone(a.phone) end;

  if not ((v_email is not null and v_email = lower(t.email))
       or (v_phone is not null and v_phone = private.normalize_phone(t.phone))) then
    raise exception 'This email or mobile number is not registered as the coach for %.', t.coach_code;
  end if;
  if t.owner_user_id is not null and t.owner_user_id <> v_uid then
    raise exception 'This academy is already linked to a different coach account.';
  end if;

  perform private.assert_can_link(v_uid, 'coach', t.id);

  update public.users
     set role = 'coach', tenant_id = t.id,
         email = coalesce(email, a.email), phone = coalesce(phone, a.phone)
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
  a auth.users;
  v_phone text;
  v_linked int;
begin
  if v_uid is null then
    raise exception 'Please sign in first.' using errcode = '28000';
  end if;
  t := private.get_active_tenant(p_coach_code);
  perform private.assert_can_link(v_uid, 'student', t.id);

  select * into a from auth.users where id = v_uid;
  v_phone := case when a.phone_confirmed_at is not null then private.normalize_phone(a.phone) end;
  if v_phone is null then
    raise exception 'Students must sign in with a verified mobile number.';
  end if;

  update public.students
     set user_id = v_uid
   where tenant_id = t.id
     and status = 'active'
     and private.normalize_phone(phone) = v_phone
     and (user_id is null or user_id = v_uid);
  get diagnostics v_linked = row_count;

  if v_linked = 0 then
    if exists (select 1 from public.students
               where tenant_id = t.id and private.normalize_phone(phone) = v_phone
                 and status = 'active') then
      raise exception 'This mobile number is already linked to another account. Please contact your coach.';
    end if;
    raise exception 'No active student with this mobile number is registered with this coach. Ask your coach to add you.';
  end if;

  update public.users
     set role = 'student', tenant_id = t.id, phone = coalesce(phone, a.phone)
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
  a auth.users;
  v_phone text;
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
begin
  if v_uid is null then
    raise exception 'Please sign in first.' using errcode = '28000';
  end if;
  t := private.get_active_tenant(p_coach_code);
  perform private.assert_can_link(v_uid, 'guest', t.id);

  select * into a from auth.users where id = v_uid;
  v_phone := case when a.phone_confirmed_at is not null then private.normalize_phone(a.phone) end;

  update public.users
     set role = 'guest', tenant_id = t.id,
         full_name = coalesce(v_name, full_name), phone = coalesce(phone, a.phone)
   where id = v_uid;

  -- Only a verified phone may claim or create guest records; anonymous guests
  -- just get read access to the academy's public info.
  if v_phone is not null then
    update public.guests
       set user_id = v_uid
     where tenant_id = t.id and user_id is null
       and private.normalize_phone(phone) = v_phone;

    if not exists (select 1 from public.guests where tenant_id = t.id and user_id = v_uid) then
      insert into public.guests (tenant_id, user_id, full_name, phone)
      values (t.id, v_uid, coalesce(v_name, 'Guest'), a.phone);
    end if;
  end if;

  return json_build_object('role', 'guest', 'tenant_id', t.id, 'verified', v_phone is not null);
end;
$$;

revoke execute on function
  public.lookup_coach_code(text), public.claim_coach_access(text),
  public.claim_student_access(text), public.claim_guest_access(text, text)
from public, anon, authenticated;
grant execute on function public.lookup_coach_code(text) to anon, authenticated;
grant execute on function
  public.claim_coach_access(text), public.claim_student_access(text),
  public.claim_guest_access(text, text)
to authenticated;
