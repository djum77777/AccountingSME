begin;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create type public.organization_status as enum ('active', 'suspended', 'closed');
create type public.membership_role as enum ('owner', 'admin_accountant', 'staff');
create type public.membership_status as enum (
  'invited',
  'active',
  'suspended',
  'deactivated'
);

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  preferred_locale text not null default 'id'
    check (preferred_locale in ('id', 'en')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default extensions.gen_random_uuid(),
  legal_name text not null check (char_length(btrim(legal_name)) between 1 and 160),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 120),
  status public.organization_status not null default 'active',
  base_currency_code text not null default 'IDR'
    check (base_currency_code ~ '^[A-Z]{3}$'),
  timezone text not null default 'Asia/Makassar',
  default_locale text not null default 'id' check (default_locale in ('id', 'en')),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id)
);

create table public.organization_entitlements (
  organization_id uuid primary key references public.organizations(id),
  active_seat_limit integer not null default 3 check (active_seat_limit >= 1),
  source text not null default 'starter' check (source in ('starter', 'platform_override', 'billing')),
  effective_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create table public.organization_memberships (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  user_id uuid references auth.users(id),
  invite_email extensions.citext not null,
  role public.membership_role not null,
  status public.membership_status not null default 'invited',
  invited_at timestamptz not null default now(),
  invited_by uuid not null references auth.users(id),
  activated_at timestamptz,
  activated_by uuid references auth.users(id),
  deactivated_at timestamptz,
  deactivated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique (organization_id, invite_email)
);

create unique index organization_memberships_org_user_unique
  on public.organization_memberships (organization_id, user_id)
  where user_id is not null;
create index organization_memberships_user_status_idx
  on public.organization_memberships (user_id, status);
create index organization_memberships_org_status_idx
  on public.organization_memberships (organization_id, status);

create table public.organization_permission_grants (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  membership_id uuid not null references public.organization_memberships(id),
  permission_key text not null check (permission_key ~ '^[a-z]+(\.[a-z_]+)+$'),
  allowed boolean not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  unique (organization_id, membership_id, permission_key)
);

create table public.audit_events (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid references public.organizations(id),
  actor_user_id uuid references auth.users(id),
  action text not null,
  target_type text not null,
  target_id text not null,
  old_state jsonb,
  new_state jsonb,
  occurred_at timestamptz not null default now(),
  request_id text
);

create index audit_events_org_time_idx
  on public.audit_events (organization_id, occurred_at desc);

create function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.user_profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger auth_user_profile_created
after insert on auth.users
for each row execute function app_private.handle_new_user();

create function app_private.has_active_membership(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.organizations organization
      on organization.id = membership.organization_id
    where membership.organization_id = target_organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and organization.status = 'active'
  );
$$;

create function app_private.has_role(
  target_organization_id uuid,
  accepted_roles public.membership_role[]
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.organizations organization
      on organization.id = membership.organization_id
    where membership.organization_id = target_organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role = any(accepted_roles)
      and organization.status = 'active'
  );
$$;

create function app_private.has_permission(
  target_organization_id uuid,
  target_permission text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  current_membership public.organization_memberships%rowtype;
  explicit_grant boolean;
begin
  select * into current_membership
  from public.organization_memberships
  where organization_id = target_organization_id
    and user_id = auth.uid()
    and status = 'active';

  if not found then return false; end if;

  select allowed into explicit_grant
  from public.organization_permission_grants
  where organization_id = target_organization_id
    and membership_id = current_membership.id
    and permission_key = target_permission;

  if explicit_grant is not null then return explicit_grant; end if;
  if current_membership.role = 'owner' then return true; end if;
  if current_membership.role = 'admin_accountant' then
    return target_permission = any(array[
      'members.read', 'audit.read', 'storage.read', 'storage.write'
    ]);
  end if;
  return target_permission = any(array['storage.read', 'storage.write']);
end;
$$;

create function app_private.enforce_membership_seat_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  seat_limit integer;
  active_count integer;
begin
  if new.status <> 'active'
     or (tg_op = 'UPDATE' and old.status = 'active') then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.organization_id::text, 0));
  select active_seat_limit into seat_limit
  from public.organization_entitlements
  where organization_id = new.organization_id;

  if seat_limit is null then
    raise exception using errcode = 'P0001', message = 'organization_entitlement_missing';
  end if;

  select count(*) into active_count
  from public.organization_memberships
  where organization_id = new.organization_id
    and status = 'active'
    and id <> new.id;

  if active_count >= seat_limit then
    raise exception using errcode = 'P0001', message = 'active_seat_limit_reached';
  end if;
  return new;
end;
$$;

create trigger membership_seat_limit
before insert or update of status on public.organization_memberships
for each row execute function app_private.enforce_membership_seat_limit();

create function app_private.protect_membership_history_and_last_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  remaining_owner_count integer;
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = 'P0001', message = 'membership_deletion_forbidden';
  end if;

  if old.status = 'active' and old.role = 'owner'
     and (new.status <> 'active' or new.role <> 'owner') then
    perform pg_advisory_xact_lock(hashtextextended(old.organization_id::text, 1));
    select count(*) into remaining_owner_count
    from public.organization_memberships
    where organization_id = old.organization_id
      and status = 'active'
      and role = 'owner'
      and id <> old.id;

    if remaining_owner_count = 0 then
      raise exception using errcode = 'P0001', message = 'last_active_owner_required';
    end if;
  end if;
  return new;
end;
$$;

create trigger membership_history_and_owner_guard_update
before update of status, role on public.organization_memberships
for each row execute function app_private.protect_membership_history_and_last_owner();
create trigger membership_history_guard_delete
before delete on public.organization_memberships
for each row execute function app_private.protect_membership_history_and_last_owner();

create function app_private.protect_audit_event()
returns trigger
language plpgsql
as $$
begin
  raise exception using errcode = 'P0001', message = 'audit_event_immutable';
end;
$$;

create trigger audit_event_immutable
before update or delete on public.audit_events
for each row execute function app_private.protect_audit_event();

create function public.create_organization(
  organization_name text,
  currency_code text default 'IDR'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  actor uuid := auth.uid();
  created_organization_id uuid;
  actor_email text;
begin
  if actor is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
  if char_length(btrim(organization_name)) not between 1 and 120 then
    raise exception using errcode = '22023', message = 'invalid_organization_name';
  end if;
  currency_code := upper(btrim(currency_code));
  if currency_code !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'invalid_currency_code';
  end if;
  select email into actor_email from auth.users where id = actor;

  insert into public.organizations (
    legal_name, display_name, base_currency_code, created_by, updated_by
  ) values (
    btrim(organization_name), btrim(organization_name), currency_code, actor, actor
  ) returning id into created_organization_id;

  insert into public.organization_entitlements (organization_id, updated_by)
  values (created_organization_id, actor);

  insert into public.organization_memberships (
    organization_id, user_id, invite_email, role, status,
    invited_by, activated_at, activated_by, updated_by
  ) values (
    created_organization_id, actor, actor_email, 'owner', 'active',
    actor, now(), actor, actor
  );

  insert into public.audit_events (
    organization_id, actor_user_id, action, target_type, target_id, new_state
  ) values (
    created_organization_id, actor, 'organization.created', 'organization',
    created_organization_id::text,
    jsonb_build_object('name', btrim(organization_name), 'currency', currency_code)
  );
  return created_organization_id;
end;
$$;

create function public.invite_member(
  target_organization_id uuid,
  invited_user_id uuid,
  invited_email text,
  invited_role public.membership_role default 'staff'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  actor uuid := auth.uid();
  membership_id uuid;
begin
  if not app_private.has_permission(target_organization_id, 'members.invite') then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  insert into public.organization_memberships (
    organization_id, user_id, invite_email, role, status, invited_by, updated_by
  ) values (
    target_organization_id, invited_user_id, lower(btrim(invited_email)),
    invited_role, 'invited', actor, actor
  ) returning id into membership_id;

  insert into public.audit_events (
    organization_id, actor_user_id, action, target_type, target_id, new_state
  ) values (
    target_organization_id, actor, 'membership.invited', 'membership',
    membership_id::text,
    jsonb_build_object('email', lower(btrim(invited_email)), 'role', invited_role)
  );
  return membership_id;
end;
$$;

create function public.activate_member(target_membership_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
  target_membership public.organization_memberships%rowtype;
begin
  select * into target_membership from public.organization_memberships where id = target_membership_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'membership_not_found'; end if;
  if not app_private.has_permission(target_membership.organization_id, 'members.activate') then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  update public.organization_memberships
  set status = 'active', activated_at = now(), activated_by = actor,
      deactivated_at = null, deactivated_by = null, updated_at = now(), updated_by = actor
  where id = target_membership_id;

  insert into public.audit_events (organization_id, actor_user_id, action, target_type, target_id, new_state)
  values (target_membership.organization_id, actor, 'membership.activated', 'membership',
          target_membership_id::text, jsonb_build_object('status', 'active'));
end;
$$;

create function public.deactivate_member(target_membership_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
  target_membership public.organization_memberships%rowtype;
begin
  select * into target_membership from public.organization_memberships where id = target_membership_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'membership_not_found'; end if;
  if not app_private.has_permission(target_membership.organization_id, 'members.activate') then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  update public.organization_memberships
  set status = 'deactivated', deactivated_at = now(), deactivated_by = actor,
      updated_at = now(), updated_by = actor
  where id = target_membership_id;

  insert into public.audit_events (organization_id, actor_user_id, action, target_type, target_id, old_state, new_state)
  values (target_membership.organization_id, actor, 'membership.deactivated', 'membership',
          target_membership_id::text, jsonb_build_object('status', target_membership.status),
          jsonb_build_object('status', 'deactivated'));
end;
$$;

create function public.change_member_role(
  target_membership_id uuid,
  new_role public.membership_role
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
  target_membership public.organization_memberships%rowtype;
begin
  select * into target_membership from public.organization_memberships where id = target_membership_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'membership_not_found'; end if;
  if not app_private.has_permission(target_membership.organization_id, 'members.change_role') then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  if target_membership.user_id = actor then
    raise exception using errcode = 'P0001', message = 'self_role_change_requires_another_owner';
  end if;

  update public.organization_memberships
  set role = new_role, updated_at = now(), updated_by = actor
  where id = target_membership_id;

  insert into public.audit_events (organization_id, actor_user_id, action, target_type, target_id, old_state, new_state)
  values (target_membership.organization_id, actor, 'membership.role_changed', 'membership',
          target_membership_id::text, jsonb_build_object('role', target_membership.role),
          jsonb_build_object('role', new_role));
end;
$$;

create function public.set_organization_seat_entitlement(
  target_organization_id uuid,
  new_active_seat_limit integer,
  entitlement_source text default 'platform_override'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  active_count integer;
begin
  if auth.role() <> 'service_role' then
    raise exception using errcode = '42501', message = 'platform_authority_required';
  end if;
  if new_active_seat_limit < 1 or entitlement_source not in ('platform_override', 'billing') then
    raise exception using errcode = '22023', message = 'invalid_entitlement';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text, 0));
  select count(*) into active_count from public.organization_memberships
  where organization_id = target_organization_id and status = 'active';
  if new_active_seat_limit < active_count then
    raise exception using errcode = 'P0001', message = 'entitlement_below_active_members';
  end if;

  update public.organization_entitlements
  set active_seat_limit = new_active_seat_limit,
      source = entitlement_source,
      effective_at = now(),
      updated_at = now(),
      updated_by = auth.uid()
  where organization_id = target_organization_id;
  if not found then raise exception using errcode = 'P0002', message = 'organization_not_found'; end if;

  insert into public.audit_events (organization_id, actor_user_id, action, target_type, target_id, new_state)
  values (target_organization_id, auth.uid(), 'entitlement.seat_limit_changed', 'organization_entitlement',
          target_organization_id::text,
          jsonb_build_object('active_seat_limit', new_active_seat_limit, 'source', entitlement_source));
end;
$$;

create function app_private.storage_organization_id(object_name text)
returns uuid
language plpgsql
immutable
as $$
begin
  if split_part(object_name, '/', 1) <> 'organizations' then return null; end if;
  return split_part(object_name, '/', 2)::uuid;
exception when invalid_text_representation then return null;
end;
$$;

alter table public.user_profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_entitlements enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.organization_permission_grants enable row level security;
alter table public.audit_events enable row level security;

create policy profile_self_select on public.user_profiles for select
  using (user_id = auth.uid());
create policy profile_self_update on public.user_profiles for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy organization_member_select on public.organizations for select
  using (app_private.has_active_membership(id));
create policy entitlement_member_select on public.organization_entitlements for select
  using (app_private.has_active_membership(organization_id));
create policy membership_organization_select on public.organization_memberships for select
  using (user_id = auth.uid() or app_private.has_active_membership(organization_id));
create policy permission_owner_select on public.organization_permission_grants for select
  using (app_private.has_role(organization_id, array['owner']::public.membership_role[]));
create policy audit_authorized_select on public.audit_events for select
  using (app_private.has_permission(organization_id, 'audit.read'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'organization-documents',
  'organization-documents',
  false,
  20971520,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set public = false;

create policy organization_document_select on storage.objects for select to authenticated
using (
  bucket_id = 'organization-documents'
  and app_private.has_permission(app_private.storage_organization_id(name), 'storage.read')
);
create policy organization_document_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'organization-documents'
  and app_private.has_permission(app_private.storage_organization_id(name), 'storage.write')
);

revoke all on function public.create_organization(text, text) from public;
revoke all on function public.invite_member(uuid, uuid, text, public.membership_role) from public;
revoke all on function public.activate_member(uuid) from public;
revoke all on function public.deactivate_member(uuid) from public;
revoke all on function public.change_member_role(uuid, public.membership_role) from public;
revoke all on function public.set_organization_seat_entitlement(uuid, integer, text) from public, anon, authenticated;
grant execute on function public.create_organization(text, text) to authenticated;
grant execute on function public.invite_member(uuid, uuid, text, public.membership_role) to authenticated;
grant execute on function public.activate_member(uuid) to authenticated;
grant execute on function public.deactivate_member(uuid) to authenticated;
grant execute on function public.change_member_role(uuid, public.membership_role) to authenticated;
grant execute on function public.set_organization_seat_entitlement(uuid, integer, text) to authenticated;
grant execute on function public.set_organization_seat_entitlement(uuid, integer, text) to service_role;

revoke all on all functions in schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;
grant execute on function app_private.has_active_membership(uuid) to authenticated;
grant execute on function app_private.has_role(uuid, public.membership_role[]) to authenticated;
grant execute on function app_private.has_permission(uuid, text) to authenticated;
grant execute on function app_private.storage_organization_id(text) to authenticated;
grant usage on schema public to anon, authenticated;
grant select, update on public.user_profiles to authenticated;
grant select on public.organizations, public.organization_entitlements,
  public.organization_memberships, public.organization_permission_grants,
  public.audit_events to authenticated;
revoke insert, update, delete on public.organization_memberships from public, anon, authenticated;
revoke insert, update, delete on public.audit_events from public, anon, authenticated;

commit;
