-- =============================================================================
-- Badminton Pro — Phase 1: core multi-tenant schema + Row Level Security
-- =============================================================================
-- Tenancy model
--   * One tenant = one coach's academy. Every business row carries tenant_id.
--   * public.users mirrors auth.users and holds role + tenant_id. Role/tenant are
--     assigned server-side (app_metadata / service role), never by the client.
--   * RLS helpers live in the unexposed `private` schema (not callable via the
--     Data API) and are SECURITY DEFINER so they can read public.users without
--     recursing into its own RLS.
-- =============================================================================

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------
create type public.user_role as enum ('developer', 'coach', 'student', 'guest');

-- -----------------------------------------------------------------------------
-- Generic helpers
-- -----------------------------------------------------------------------------
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Coach codes: BP-COACH-0001 … BP-COACH-9999, then BP-COACH-10000 …
-- A sequence never hands out the same number twice, so codes are never reused.
create sequence private.coach_code_seq;

create or replace function private.next_coach_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  n bigint := nextval('private.coach_code_seq');
begin
  return 'BP-COACH-' || lpad(n::text, greatest(4, length(n::text)), '0');
end;
$$;

-- =============================================================================
-- Tables
-- =============================================================================

-- tenants (one per coach / academy) ------------------------------------------
create table public.tenants (
  id                      uuid primary key default gen_random_uuid(),
  coach_code              text not null unique default private.next_coach_code()
                            check (coach_code ~ '^BP-COACH-[0-9]{4,}$'),
  name                    text not null check (length(trim(name)) > 0),
  academy_name            text,
  owner_user_id           uuid references auth.users (id) on delete set null,
  email                   text,
  phone                   text,
  address                 text,
  logo_url                text,
  status                  text not null default 'active'
                            check (status in ('active', 'suspended', 'retired')),
  subscription_plan       text not null default 'trial',
  subscription_expires_at timestamptz,
  settings                jsonb not null default '{}'::jsonb,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- users (profile + authorization data for every auth user) -------------------
create table public.users (
  id          uuid primary key references auth.users (id) on delete cascade,
  tenant_id   uuid references public.tenants (id) on delete restrict,
  role        public.user_role not null default 'guest',
  full_name   text,
  email       text,
  phone       text,
  avatar_url  text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Everyone except the developer belongs to exactly one tenant.
  constraint users_tenant_required
    check (role = 'developer' or role = 'guest' or tenant_id is not null)
);

-- students -------------------------------------------------------------------
create table public.students (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants (id) on delete restrict,
  user_id         uuid references public.users (id) on delete set null,
  full_name       text not null check (length(trim(full_name)) > 0),
  phone           text,
  email           text,
  date_of_birth   date,
  gender          text check (gender in ('male', 'female', 'other')),
  guardian_name   text,
  guardian_phone  text,
  batch           text,
  skill_level     text check (skill_level in ('beginner', 'intermediate', 'advanced', 'professional')),
  joined_on       date not null default current_date,
  monthly_fee     numeric(12, 2) not null default 0 check (monthly_fee >= 0),
  status          text not null default 'active'
                    check (status in ('active', 'inactive', 'left')),
  notes           text,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- Target for composite FKs so child rows can't point at another tenant's student.
  unique (id, tenant_id)
);

-- guests (drop-in / trial players) -------------------------------------------
create table public.guests (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants (id) on delete restrict,
  user_id     uuid references public.users (id) on delete set null,
  full_name   text not null check (length(trim(full_name)) > 0),
  phone       text,
  email       text,
  visit_date  date not null default current_date,
  fee_amount  numeric(12, 2) not null default 0 check (fee_amount >= 0),
  is_paid     boolean not null default false,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, tenant_id)
);

-- attendance -----------------------------------------------------------------
create table public.attendance (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants (id) on delete restrict,
  student_id    uuid,
  guest_id      uuid,
  session_date  date not null default current_date,
  status        text not null default 'present'
                  check (status in ('present', 'absent', 'late', 'excused')),
  check_in_at   timestamptz,
  marked_by     uuid references public.users (id) on delete set null,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  foreign key (student_id, tenant_id) references public.students (id, tenant_id) on delete cascade,
  foreign key (guest_id, tenant_id)   references public.guests (id, tenant_id)   on delete cascade,
  constraint attendance_one_person check (num_nonnulls(student_id, guest_id) = 1)
);

-- fee_payments (student fees received by the coach) ---------------------------
create table public.fee_payments (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants (id) on delete restrict,
  student_id      uuid not null,
  amount          numeric(12, 2) not null check (amount > 0),
  payment_date    date not null default current_date,
  period_month    date check (period_month = date_trunc('month', period_month)::date),
  method          text not null default 'cash'
                    check (method in ('cash', 'upi', 'card', 'bank_transfer', 'other')),
  reference       text,
  recorded_by     uuid references public.users (id) on delete set null,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (student_id, tenant_id) references public.students (id, tenant_id) on delete restrict
);

-- expenses -------------------------------------------------------------------
create table public.expenses (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants (id) on delete restrict,
  category      text not null,
  amount        numeric(12, 2) not null check (amount > 0),
  expense_date  date not null default current_date,
  description   text,
  receipt_url   text,
  recorded_by   uuid references public.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- inventory_items ------------------------------------------------------------
create table public.inventory_items (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants (id) on delete restrict,
  name              text not null check (length(trim(name)) > 0),
  category          text,
  sku               text,
  unit              text not null default 'pcs',
  quantity_on_hand  integer not null default 0 check (quantity_on_hand >= 0),
  unit_cost         numeric(12, 2) check (unit_cost >= 0),
  sale_price        numeric(12, 2) check (sale_price >= 0),
  reorder_level     integer not null default 0 check (reorder_level >= 0),
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (id, tenant_id),
  unique (tenant_id, sku)
);

-- stock_transactions (append-only ledger; drives quantity_on_hand) ------------
create table public.stock_transactions (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants (id) on delete restrict,
  item_id      uuid not null,
  txn_type     text not null check (txn_type in ('purchase', 'sale', 'issue', 'return', 'adjustment')),
  -- Signed change in stock: purchases/returns add, sales/issues remove.
  quantity     integer not null,
  unit_price   numeric(12, 2) check (unit_price >= 0),
  student_id   uuid,
  notes        text,
  recorded_by  uuid references public.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  foreign key (item_id, tenant_id)    references public.inventory_items (id, tenant_id) on delete restrict,
  foreign key (student_id, tenant_id) references public.students (id, tenant_id)        on delete restrict,
  constraint stock_txn_quantity_sign check (
    (txn_type in ('purchase', 'return') and quantity > 0) or
    (txn_type in ('sale', 'issue')      and quantity < 0) or
    (txn_type = 'adjustment'            and quantity <> 0)
  )
);

-- tickets (support / issues raised inside a tenant, visible to the developer) --
create table public.tickets (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants (id) on delete restrict,
  created_by   uuid references public.users (id) on delete set null,
  assigned_to  uuid references public.users (id) on delete set null,
  subject      text not null check (length(trim(subject)) > 0),
  description  text,
  category     text not null default 'general'
                 check (category in ('general', 'billing', 'bug', 'feature_request', 'account')),
  priority     text not null default 'normal'
                 check (priority in ('low', 'normal', 'high', 'urgent')),
  status       text not null default 'open'
                 check (status in ('open', 'in_progress', 'resolved', 'closed')),
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- subscription_payments (coach → platform) ------------------------------------
create table public.subscription_payments (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants (id) on delete restrict,
  plan             text not null,
  amount           numeric(12, 2) not null check (amount > 0),
  currency         text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  period_start     date not null,
  period_end       date not null,
  payment_date     date not null default current_date,
  method           text not null default 'upi'
                     check (method in ('cash', 'upi', 'card', 'bank_transfer', 'other')),
  transaction_ref  text,
  status           text not null default 'pending'
                     check (status in ('pending', 'verified', 'rejected')),
  verified_by      uuid references public.users (id) on delete set null,
  verified_at      timestamptz,
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint subscription_period_valid check (period_end > period_start)
);

-- retired_coach_codes (codes that may never be issued again) ------------------
create table public.retired_coach_codes (
  coach_code        text primary key check (coach_code ~ '^BP-COACH-[0-9]{4,}$'),
  former_tenant_id  uuid references public.tenants (id) on delete set null,
  reason            text,
  retired_by        uuid references public.users (id) on delete set null,
  retired_at        timestamptz not null default now()
);

-- =============================================================================
-- Indexes (tenant_id, foreign keys, common filters)
-- =============================================================================
create index tenants_owner_user_id_idx           on public.tenants (owner_user_id);
create index tenants_status_idx                  on public.tenants (status);

create index users_tenant_id_role_idx            on public.users (tenant_id, role);

create index students_tenant_id_status_idx       on public.students (tenant_id, status);
create index students_user_id_idx                on public.students (user_id) where user_id is not null;

create index guests_tenant_id_visit_date_idx     on public.guests (tenant_id, visit_date desc);
create index guests_user_id_idx                  on public.guests (user_id) where user_id is not null;

create index attendance_tenant_id_date_idx       on public.attendance (tenant_id, session_date desc);
create unique index attendance_student_day_uidx  on public.attendance (student_id, session_date) where student_id is not null;
create unique index attendance_guest_day_uidx    on public.attendance (guest_id, session_date)   where guest_id is not null;
create index attendance_marked_by_idx            on public.attendance (marked_by);

create index fee_payments_tenant_id_date_idx     on public.fee_payments (tenant_id, payment_date desc);
create index fee_payments_student_id_idx         on public.fee_payments (student_id, payment_date desc);
create index fee_payments_recorded_by_idx        on public.fee_payments (recorded_by);

create index expenses_tenant_id_date_idx         on public.expenses (tenant_id, expense_date desc);
create index expenses_recorded_by_idx            on public.expenses (recorded_by);

create index inventory_items_tenant_id_idx       on public.inventory_items (tenant_id) where is_active;

create index stock_txn_tenant_id_created_idx     on public.stock_transactions (tenant_id, created_at desc);
create index stock_txn_item_id_idx               on public.stock_transactions (item_id, created_at desc);
create index stock_txn_student_id_idx            on public.stock_transactions (student_id) where student_id is not null;
create index stock_txn_recorded_by_idx           on public.stock_transactions (recorded_by);

create index tickets_tenant_id_status_idx        on public.tickets (tenant_id, status);
create index tickets_created_by_idx              on public.tickets (created_by);
create index tickets_assigned_to_idx             on public.tickets (assigned_to);
create index tickets_open_idx                    on public.tickets (created_at desc) where status in ('open', 'in_progress');

create index sub_payments_tenant_id_date_idx     on public.subscription_payments (tenant_id, payment_date desc);
create index sub_payments_pending_idx            on public.subscription_payments (created_at) where status = 'pending';
create index sub_payments_verified_by_idx        on public.subscription_payments (verified_by);

create index retired_codes_former_tenant_id_idx  on public.retired_coach_codes (former_tenant_id);
create index retired_codes_retired_by_idx        on public.retired_coach_codes (retired_by);

-- =============================================================================
-- RLS helper functions
-- =============================================================================

-- Tenant of the signed-in user (any role). NULL for the developer / unassigned.
create or replace function private.get_my_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.tenant_id
  from public.users u
  where u.id = (select auth.uid()) and u.is_active;
$$;

create or replace function private.get_my_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select u.role
  from public.users u
  where u.id = (select auth.uid()) and u.is_active;
$$;

create or replace function private.is_developer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select u.role = 'developer'
     from public.users u
     where u.id = (select auth.uid()) and u.is_active),
    false);
$$;

-- Tenant the user manages as a coach; NULL for every other role. Using this
-- instead of get_my_tenant_id() in write policies stops a student from getting
-- coach powers just because they share the tenant_id.
create or replace function private.get_my_coach_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.tenant_id
  from public.users u
  where u.id = (select auth.uid()) and u.is_active and u.role = 'coach';
$$;

revoke execute on function
  private.get_my_tenant_id(), private.get_my_role(), private.is_developer(),
  private.get_my_coach_tenant_id(), private.next_coach_code(), private.set_updated_at()
from public, anon;
grant execute on function
  private.get_my_tenant_id(), private.get_my_role(), private.is_developer(),
  private.get_my_coach_tenant_id(), private.next_coach_code()
to authenticated;

-- =============================================================================
-- Triggers
-- =============================================================================

-- updated_at on every mutable table
do $$
declare t text;
begin
  foreach t in array array[
    'tenants', 'users', 'students', 'guests', 'attendance', 'fee_payments',
    'expenses', 'inventory_items', 'tickets', 'subscription_payments'
  ] loop
    execute format(
      'create trigger set_updated_at before update on public.%I
         for each row execute function private.set_updated_at()', t);
  end loop;
end;
$$;

-- Create a public.users row for every new auth user. Role and tenant come from
-- app_metadata (only settable server-side), never from user_metadata.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, email, full_name, role, tenant_id)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name',
    coalesce((new.raw_app_meta_data ->> 'role')::public.user_role, 'guest'),
    (new.raw_app_meta_data ->> 'tenant_id')::uuid
  );
  return new;
end;
$$;
revoke execute on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Non-developers may edit their profile, but never their role or tenant.
create or replace function private.protect_user_authz_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' and not private.is_developer()
     and (new.role is distinct from old.role
          or new.tenant_id is distinct from old.tenant_id
          or new.id is distinct from old.id) then
    raise exception 'Only the developer can change role or tenant'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger protect_authz_columns before update on public.users
  for each row execute function private.protect_user_authz_columns();

-- Coaches may edit their academy profile, but not code/status/subscription.
create or replace function private.protect_tenant_admin_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' and not private.is_developer()
     and (new.coach_code is distinct from old.coach_code
          or new.status is distinct from old.status
          or new.subscription_plan is distinct from old.subscription_plan
          or new.subscription_expires_at is distinct from old.subscription_expires_at
          or new.owner_user_id is distinct from old.owner_user_id) then
    raise exception 'Only the developer can change coach code, status or subscription'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger protect_admin_columns before update on public.tenants
  for each row execute function private.protect_tenant_admin_columns();

-- A retired coach code can never be assigned to a tenant again.
create or replace function private.reject_retired_coach_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.retired_coach_codes r where r.coach_code = new.coach_code) then
    raise exception 'Coach code % is retired and cannot be reused', new.coach_code
      using errcode = '23505';
  end if;
  return new;
end;
$$;

create trigger reject_retired_code before insert or update of coach_code on public.tenants
  for each row execute function private.reject_retired_coach_code();

-- Keep inventory_items.quantity_on_hand in sync with the ledger.
create or replace function private.apply_stock_transaction()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.inventory_items
     set quantity_on_hand = quantity_on_hand + new.quantity
   where id = new.item_id and tenant_id = new.tenant_id;
  return new;
end;
$$;

create trigger apply_stock_transaction after insert on public.stock_transactions
  for each row execute function private.apply_stock_transaction();

revoke execute on function
  private.protect_user_authz_columns(), private.protect_tenant_admin_columns(),
  private.reject_retired_coach_code(), private.apply_stock_transaction()
from public, anon;

-- =============================================================================
-- Privileges: API access for signed-in users only; RLS decides which rows.
-- =============================================================================
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- =============================================================================
-- Row Level Security
-- =============================================================================
alter table public.tenants               enable row level security;
alter table public.users                 enable row level security;
alter table public.students              enable row level security;
alter table public.guests                enable row level security;
alter table public.attendance            enable row level security;
alter table public.fee_payments          enable row level security;
alter table public.expenses              enable row level security;
alter table public.inventory_items       enable row level security;
alter table public.stock_transactions    enable row level security;
alter table public.tickets               enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.retired_coach_codes   enable row level security;

-- tenants --------------------------------------------------------------------
-- Every member can read their own academy; only the developer creates/deletes.
create policy tenants_select on public.tenants for select to authenticated
  using ((select private.is_developer()) or id = (select private.get_my_tenant_id()));
create policy tenants_insert on public.tenants for insert to authenticated
  with check ((select private.is_developer()));
create policy tenants_update on public.tenants for update to authenticated
  using ((select private.is_developer()) or id = (select private.get_my_coach_tenant_id()))
  with check ((select private.is_developer()) or id = (select private.get_my_coach_tenant_id()));
create policy tenants_delete on public.tenants for delete to authenticated
  using ((select private.is_developer()));

-- users ----------------------------------------------------------------------
-- Self, coach of the same tenant, or developer. Rows are created by trigger.
create policy users_select on public.users for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.is_developer())
    or tenant_id = (select private.get_my_coach_tenant_id())
  );
create policy users_insert on public.users for insert to authenticated
  with check ((select private.is_developer()));
create policy users_update on public.users for update to authenticated
  using (
    id = (select auth.uid())
    or (select private.is_developer())
    or tenant_id = (select private.get_my_coach_tenant_id())
  )
  with check (
    id = (select auth.uid())
    or (select private.is_developer())
    or tenant_id = (select private.get_my_coach_tenant_id())
  );
create policy users_delete on public.users for delete to authenticated
  using ((select private.is_developer()));

-- students -------------------------------------------------------------------
create policy students_select on public.students for select to authenticated
  using (
    (select private.is_developer())
    or tenant_id = (select private.get_my_coach_tenant_id())
    or (user_id = (select auth.uid()) and tenant_id = (select private.get_my_tenant_id()))
  );
create policy students_insert on public.students for insert to authenticated
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy students_update on public.students for update to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()))
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy students_delete on public.students for delete to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));

-- guests ---------------------------------------------------------------------
create policy guests_select on public.guests for select to authenticated
  using (
    (select private.is_developer())
    or tenant_id = (select private.get_my_coach_tenant_id())
    or (user_id = (select auth.uid()) and tenant_id = (select private.get_my_tenant_id()))
  );
create policy guests_insert on public.guests for insert to authenticated
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy guests_update on public.guests for update to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()))
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy guests_delete on public.guests for delete to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));

-- attendance -----------------------------------------------------------------
-- Students/guests read only their own attendance.
create policy attendance_select on public.attendance for select to authenticated
  using (
    (select private.is_developer())
    or tenant_id = (select private.get_my_coach_tenant_id())
    or student_id in (select s.id from public.students s where s.user_id = (select auth.uid()))
    or guest_id   in (select g.id from public.guests g   where g.user_id = (select auth.uid()))
  );
create policy attendance_insert on public.attendance for insert to authenticated
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy attendance_update on public.attendance for update to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()))
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy attendance_delete on public.attendance for delete to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));

-- fee_payments ---------------------------------------------------------------
-- Students read only their own payment history.
create policy fee_payments_select on public.fee_payments for select to authenticated
  using (
    (select private.is_developer())
    or tenant_id = (select private.get_my_coach_tenant_id())
    or student_id in (select s.id from public.students s where s.user_id = (select auth.uid()))
  );
create policy fee_payments_insert on public.fee_payments for insert to authenticated
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy fee_payments_update on public.fee_payments for update to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()))
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy fee_payments_delete on public.fee_payments for delete to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));

-- expenses / inventory_items: coach + developer only ---------------------------
create policy expenses_select on public.expenses for select to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy expenses_insert on public.expenses for insert to authenticated
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy expenses_update on public.expenses for update to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()))
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy expenses_delete on public.expenses for delete to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));

create policy inventory_items_select on public.inventory_items for select to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy inventory_items_insert on public.inventory_items for insert to authenticated
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy inventory_items_update on public.inventory_items for update to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()))
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy inventory_items_delete on public.inventory_items for delete to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));

-- stock_transactions: append-only ledger (no update; delete developer only) ----
create policy stock_txn_select on public.stock_transactions for select to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy stock_txn_insert on public.stock_transactions for insert to authenticated
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy stock_txn_delete on public.stock_transactions for delete to authenticated
  using ((select private.is_developer()));

-- tickets --------------------------------------------------------------------
-- Anyone in a tenant can raise a ticket and read their own; the coach sees all
-- of their tenant's tickets; the developer sees everything.
create policy tickets_select on public.tickets for select to authenticated
  using (
    (select private.is_developer())
    or tenant_id = (select private.get_my_coach_tenant_id())
    or (created_by = (select auth.uid()) and tenant_id = (select private.get_my_tenant_id()))
  );
create policy tickets_insert on public.tickets for insert to authenticated
  with check (
    (select private.is_developer())
    or (created_by = (select auth.uid()) and tenant_id = (select private.get_my_tenant_id()))
  );
create policy tickets_update on public.tickets for update to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()))
  with check ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy tickets_delete on public.tickets for delete to authenticated
  using ((select private.is_developer()));

-- subscription_payments ------------------------------------------------------
-- Coach submits a payment (always 'pending') and reads their own; only the
-- developer verifies, edits or deletes.
create policy sub_payments_select on public.subscription_payments for select to authenticated
  using ((select private.is_developer()) or tenant_id = (select private.get_my_coach_tenant_id()));
create policy sub_payments_insert on public.subscription_payments for insert to authenticated
  with check (
    (select private.is_developer())
    or (tenant_id = (select private.get_my_coach_tenant_id())
        and status = 'pending' and verified_by is null and verified_at is null)
  );
create policy sub_payments_update on public.subscription_payments for update to authenticated
  using ((select private.is_developer()))
  with check ((select private.is_developer()));
create policy sub_payments_delete on public.subscription_payments for delete to authenticated
  using ((select private.is_developer()));

-- retired_coach_codes: developer only ----------------------------------------
create policy retired_codes_all on public.retired_coach_codes for all to authenticated
  using ((select private.is_developer()))
  with check ((select private.is_developer()));
