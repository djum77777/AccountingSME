begin;

create type public.party_status as enum ('active','archived');
create type public.party_role_kind as enum ('customer','supplier');
create type public.party_tax_status as enum ('not_set','non_taxable','taxable');
create type public.party_address_kind as enum ('billing','shipping','office','other');

create function app_private.normalize_party_text(value text)
returns text language sql immutable parallel safe set search_path=pg_catalog as $$
  select nullif(regexp_replace(lower(btrim(coalesce(value,''))), '[^a-z0-9]+', '', 'g'), '')
$$;

create table public.parties (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  legal_name text not null check(char_length(btrim(legal_name)) between 1 and 160),
  display_name text not null check(char_length(btrim(display_name)) between 1 and 160),
  tax_identifier text,
  tax_registration_name text,
  tax_registration_address text,
  tax_status public.party_tax_status not null default 'not_set',
  notes text check(notes is null or char_length(notes)<=4000),
  status public.party_status not null default 'active',
  archived_at timestamptz,
  archived_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique(organization_id,id),
  check(tax_identifier is null or char_length(btrim(tax_identifier)) between 1 and 80),
  check(tax_registration_name is null or char_length(btrim(tax_registration_name)) between 1 and 160),
  check(tax_registration_address is null or char_length(btrim(tax_registration_address))<=1000),
  check((status='active' and archived_at is null and archived_by is null) or
        (status='archived' and archived_at is not null and archived_by is not null))
);

create table public.party_roles (
  organization_id uuid not null references public.organizations(id),
  party_id uuid not null,
  role_kind public.party_role_kind not null,
  payment_term_days integer not null default 0 check(payment_term_days between 0 and 3650),
  external_reference text,
  status public.party_status not null default 'active',
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  primary key(organization_id,party_id,role_kind),
  foreign key(organization_id,party_id) references public.parties(organization_id,id),
  check(external_reference is null or char_length(btrim(external_reference)) between 1 and 100)
);

create table public.party_contacts (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  party_id uuid not null,
  contact_name text not null check(char_length(btrim(contact_name)) between 1 and 160),
  job_title text check(job_title is null or char_length(btrim(job_title))<=120),
  email text check(email is null or char_length(btrim(email))<=254),
  phone text check(phone is null or char_length(btrim(phone))<=60),
  is_primary boolean not null default false,
  status public.party_status not null default 'active',
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique(organization_id,id),
  foreign key(organization_id,party_id) references public.parties(organization_id,id),
  check(email is not null or phone is not null)
);

create table public.party_addresses (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  party_id uuid not null,
  address_kind public.party_address_kind not null,
  label text not null check(char_length(btrim(label)) between 1 and 80),
  address_line_1 text not null check(char_length(btrim(address_line_1)) between 1 and 240),
  address_line_2 text check(address_line_2 is null or char_length(btrim(address_line_2))<=240),
  city text check(city is null or char_length(btrim(city))<=120),
  province text check(province is null or char_length(btrim(province))<=120),
  postal_code text check(postal_code is null or char_length(btrim(postal_code))<=24),
  country_code text not null default 'ID' check(country_code ~ '^[A-Z]{2}$'),
  is_primary boolean not null default false,
  status public.party_status not null default 'active',
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique(organization_id,id),
  foreign key(organization_id,party_id) references public.parties(organization_id,id)
);

create unique index party_roles_external_reference_unique
  on public.party_roles(organization_id,role_kind,lower(external_reference)) where external_reference is not null;
create unique index parties_tax_identifier_unique
  on public.parties(organization_id,app_private.normalize_party_text(tax_identifier)) where tax_identifier is not null;
create unique index party_contacts_one_primary
  on public.party_contacts(organization_id,party_id) where is_primary and status='active';
create unique index party_addresses_one_primary_per_kind
  on public.party_addresses(organization_id,party_id,address_kind) where is_primary and status='active';
create index parties_directory_idx on public.parties(organization_id,status,display_name);
create index parties_normalized_name_idx on public.parties(organization_id,app_private.normalize_party_text(display_name));
create index party_contacts_party_idx on public.party_contacts(organization_id,party_id,status);
create index party_addresses_party_idx on public.party_addresses(organization_id,party_id,status);

create or replace function app_private.has_permission(target_organization_id uuid,target_permission text)
returns boolean language plpgsql stable security definer set search_path=public,pg_temp as $$
declare current_membership public.organization_memberships%rowtype; explicit_grant boolean;
begin
  select * into current_membership from public.organization_memberships
   where organization_id=target_organization_id and user_id=auth.uid() and status='active';
  if not found then return false; end if;
  select allowed into explicit_grant from public.organization_permission_grants
   where organization_id=target_organization_id and membership_id=current_membership.id and permission_key=target_permission;
  if explicit_grant is not null then return explicit_grant; end if;
  if current_membership.role='owner' then return true; end if;
  if current_membership.role='admin_accountant' then
    return target_permission=any(array['members.read','audit.read','storage.read','storage.write','accounting.read','accounting.post','inventory.read','inventory.manage','parties.read','parties.manage']);
  end if;
  return target_permission=any(array['storage.read','storage.write','parties.read']);
end; $$;

create function app_private.require_party_permission(target_organization_id uuid,target_permission text)
returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not app_private.has_permission(target_organization_id,target_permission) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
end; $$;

create function app_private.guard_party_history()
returns trigger language plpgsql as $$
begin
  if tg_op='DELETE' then raise exception using errcode='P0001',message='party_history_deletion_forbidden'; end if;
  return new;
end; $$;
create trigger party_history_guard before delete on public.parties for each row execute function app_private.guard_party_history();
create trigger party_role_history_guard before delete on public.party_roles for each row execute function app_private.guard_party_history();
create trigger party_contact_history_guard before delete on public.party_contacts for each row execute function app_private.guard_party_history();
create trigger party_address_history_guard before delete on public.party_addresses for each row execute function app_private.guard_party_history();

create function app_private.sync_party_roles(actor uuid,target_organization_id uuid,target_party_id uuid,
  target_is_customer boolean,target_is_supplier boolean,target_customer_terms integer,target_supplier_terms integer,
  target_customer_reference text,target_supplier_reference text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not target_is_customer and not target_is_supplier then
    raise exception using errcode='23514',message='party_role_required';
  end if;
  if target_is_customer then
    insert into public.party_roles(organization_id,party_id,role_kind,payment_term_days,external_reference,status,created_by,updated_by)
    values(target_organization_id,target_party_id,'customer',target_customer_terms,nullif(btrim(target_customer_reference),''),'active',actor,actor)
    on conflict(organization_id,party_id,role_kind) do update set payment_term_days=excluded.payment_term_days,
      external_reference=excluded.external_reference,status='active',updated_at=now(),updated_by=actor;
  else
    update public.party_roles set status='archived',updated_at=now(),updated_by=actor
     where organization_id=target_organization_id and party_id=target_party_id and role_kind='customer' and status<>'archived';
  end if;
  if target_is_supplier then
    insert into public.party_roles(organization_id,party_id,role_kind,payment_term_days,external_reference,status,created_by,updated_by)
    values(target_organization_id,target_party_id,'supplier',target_supplier_terms,nullif(btrim(target_supplier_reference),''),'active',actor,actor)
    on conflict(organization_id,party_id,role_kind) do update set payment_term_days=excluded.payment_term_days,
      external_reference=excluded.external_reference,status='active',updated_at=now(),updated_by=actor;
  else
    update public.party_roles set status='archived',updated_at=now(),updated_by=actor
     where organization_id=target_organization_id and party_id=target_party_id and role_kind='supplier' and status<>'archived';
  end if;
end; $$;

create function public.create_party(target_organization_id uuid,target_legal_name text,target_display_name text,
  target_is_customer boolean,target_is_supplier boolean,target_customer_terms integer,target_supplier_terms integer,
  target_customer_reference text,target_supplier_reference text,target_tax_identifier text,target_tax_registration_name text,
  target_tax_registration_address text,target_tax_status public.party_tax_status,target_notes text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  perform app_private.require_party_permission(target_organization_id,'parties.manage');
  insert into public.parties(organization_id,legal_name,display_name,tax_identifier,tax_registration_name,
    tax_registration_address,tax_status,notes,created_by,updated_by)
  values(target_organization_id,btrim(target_legal_name),btrim(target_display_name),nullif(btrim(target_tax_identifier),''),
    nullif(btrim(target_tax_registration_name),''),nullif(btrim(target_tax_registration_address),''),target_tax_status,
    nullif(btrim(target_notes),''),actor,actor) returning id into created_id;
  perform app_private.sync_party_roles(actor,target_organization_id,created_id,target_is_customer,target_is_supplier,
    target_customer_terms,target_supplier_terms,target_customer_reference,target_supplier_reference);
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'party.created','party',created_id::text,
    jsonb_build_object('customer',target_is_customer,'supplier',target_is_supplier,'status','active'));
  return created_id;
end; $$;

create function public.update_party(target_organization_id uuid,target_party_id uuid,target_legal_name text,target_display_name text,
  target_is_customer boolean,target_is_supplier boolean,target_customer_terms integer,target_supplier_terms integer,
  target_customer_reference text,target_supplier_reference text,target_tax_identifier text,target_tax_registration_name text,
  target_tax_registration_address text,target_tax_status public.party_tax_status,target_notes text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); prior_roles text[];
begin
  perform app_private.require_party_permission(target_organization_id,'parties.manage');
  if not exists(select 1 from public.parties where organization_id=target_organization_id and id=target_party_id) then
    raise exception using errcode='23503',message='party_not_found';
  end if;
  select coalesce(array_agg(role_kind::text order by role_kind::text),'{}') into prior_roles from public.party_roles
   where organization_id=target_organization_id and party_id=target_party_id and status='active';
  update public.parties set legal_name=btrim(target_legal_name),display_name=btrim(target_display_name),
    tax_identifier=nullif(btrim(target_tax_identifier),''),tax_registration_name=nullif(btrim(target_tax_registration_name),''),
    tax_registration_address=nullif(btrim(target_tax_registration_address),''),tax_status=target_tax_status,
    notes=nullif(btrim(target_notes),''),updated_at=now(),updated_by=actor
   where organization_id=target_organization_id and id=target_party_id;
  perform app_private.sync_party_roles(actor,target_organization_id,target_party_id,target_is_customer,target_is_supplier,
    target_customer_terms,target_supplier_terms,target_customer_reference,target_supplier_reference);
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,old_state,new_state)
  values(target_organization_id,actor,'party.updated','party',target_party_id::text,
    jsonb_build_object('roles',prior_roles),jsonb_build_object('customer',target_is_customer,'supplier',target_is_supplier));
end; $$;

create function public.set_party_status(target_organization_id uuid,target_party_id uuid,target_status public.party_status)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); prior_status public.party_status;
begin
  perform app_private.require_party_permission(target_organization_id,'parties.manage');
  select status into prior_status from public.parties where organization_id=target_organization_id and id=target_party_id for update;
  if not found then raise exception using errcode='23503',message='party_not_found'; end if;
  if prior_status=target_status then return; end if;
  update public.parties set status=target_status,archived_at=case when target_status='archived' then now() else null end,
    archived_by=case when target_status='archived' then actor else null end,updated_at=now(),updated_by=actor
   where organization_id=target_organization_id and id=target_party_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,old_state,new_state)
  values(target_organization_id,actor,'party.status_changed','party',target_party_id::text,
    jsonb_build_object('status',prior_status),jsonb_build_object('status',target_status));
end; $$;

create function public.add_party_contact(target_organization_id uuid,target_party_id uuid,target_contact_name text,
  target_job_title text,target_email text,target_phone text,target_is_primary boolean)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  perform app_private.require_party_permission(target_organization_id,'parties.manage');
  if not exists(select 1 from public.parties where organization_id=target_organization_id and id=target_party_id) then
    raise exception using errcode='23503',message='party_not_found';
  end if;
  if target_is_primary then update public.party_contacts set is_primary=false,updated_at=now(),updated_by=actor
    where organization_id=target_organization_id and party_id=target_party_id and is_primary; end if;
  insert into public.party_contacts(organization_id,party_id,contact_name,job_title,email,phone,is_primary,created_by,updated_by)
  values(target_organization_id,target_party_id,btrim(target_contact_name),nullif(btrim(target_job_title),''),
    nullif(lower(btrim(target_email)),''),nullif(btrim(target_phone),''),target_is_primary,actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'party.contact_added','party_contact',created_id::text,
    jsonb_build_object('party_id',target_party_id,'is_primary',target_is_primary));
  return created_id;
end; $$;

create function public.add_party_address(target_organization_id uuid,target_party_id uuid,target_address_kind public.party_address_kind,
  target_label text,target_address_line_1 text,target_address_line_2 text,target_city text,target_province text,
  target_postal_code text,target_country_code text,target_is_primary boolean)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  perform app_private.require_party_permission(target_organization_id,'parties.manage');
  if not exists(select 1 from public.parties where organization_id=target_organization_id and id=target_party_id) then
    raise exception using errcode='23503',message='party_not_found';
  end if;
  if target_is_primary then update public.party_addresses set is_primary=false,updated_at=now(),updated_by=actor
    where organization_id=target_organization_id and party_id=target_party_id and address_kind=target_address_kind and is_primary; end if;
  insert into public.party_addresses(organization_id,party_id,address_kind,label,address_line_1,address_line_2,city,province,
    postal_code,country_code,is_primary,created_by,updated_by)
  values(target_organization_id,target_party_id,target_address_kind,btrim(target_label),btrim(target_address_line_1),
    nullif(btrim(target_address_line_2),''),nullif(btrim(target_city),''),nullif(btrim(target_province),''),
    nullif(btrim(target_postal_code),''),upper(btrim(target_country_code)),target_is_primary,actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'party.address_added','party_address',created_id::text,
    jsonb_build_object('party_id',target_party_id,'kind',target_address_kind,'is_primary',target_is_primary));
  return created_id;
end; $$;

create function public.set_party_custom_field_value(target_organization_id uuid,target_party_id uuid,target_definition_id uuid,target_value jsonb)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); definition public.custom_field_definitions%rowtype; value_id uuid;
begin
  perform app_private.require_party_permission(target_organization_id,'parties.manage');
  if not exists(select 1 from public.parties where organization_id=target_organization_id and id=target_party_id) then
    raise exception using errcode='23503',message='party_not_found';
  end if;
  select * into definition from public.custom_field_definitions where organization_id=target_organization_id
    and id=target_definition_id and entity_type='contact' and status='active';
  if not found then raise exception using errcode='23503',message='active_party_custom_field_not_found'; end if;
  insert into public.custom_field_values(organization_id,definition_id,definition_version,entity_type,entity_id,value,created_by,updated_by)
  values(target_organization_id,definition.id,definition.version,'contact',target_party_id,target_value,actor,actor)
  on conflict(definition_id,entity_id) do update set value=excluded.value,definition_version=excluded.definition_version,
    updated_at=now(),updated_by=actor returning id into value_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'party.custom_field_changed','party',target_party_id::text,
    jsonb_build_object('definition_id',target_definition_id,'definition_version',definition.version));
  return value_id;
end; $$;

create function public.search_party_duplicates(target_organization_id uuid,target_name text,target_email text,target_phone text,
  target_tax_identifier text,target_exclude_party_id uuid default null)
returns table(party_id uuid,display_name text,status public.party_status,reasons text[],match_score integer)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  perform app_private.require_party_permission(target_organization_id,'parties.read');
  return query
  select p.id,p.display_name,p.status,
    array_remove(array[
      case when app_private.normalize_party_text(target_name) is not null and
        (app_private.normalize_party_text(p.display_name)=app_private.normalize_party_text(target_name) or
         app_private.normalize_party_text(p.legal_name)=app_private.normalize_party_text(target_name)) then 'name' end,
      case when app_private.normalize_party_text(target_tax_identifier) is not null and
        app_private.normalize_party_text(p.tax_identifier)=app_private.normalize_party_text(target_tax_identifier) then 'tax_identifier' end,
      case when app_private.normalize_party_text(target_email) is not null and exists(select 1 from public.party_contacts pc
        where pc.organization_id=p.organization_id and pc.party_id=p.id and pc.status='active' and
        app_private.normalize_party_text(pc.email)=app_private.normalize_party_text(target_email)) then 'email' end,
      case when app_private.normalize_party_text(target_phone) is not null and exists(select 1 from public.party_contacts pc
        where pc.organization_id=p.organization_id and pc.party_id=p.id and pc.status='active' and
        app_private.normalize_party_text(pc.phone)=app_private.normalize_party_text(target_phone)) then 'phone' end
    ],null)::text[] as reasons,
    ((app_private.normalize_party_text(target_name) is not null and
      (app_private.normalize_party_text(p.display_name)=app_private.normalize_party_text(target_name) or
       app_private.normalize_party_text(p.legal_name)=app_private.normalize_party_text(target_name)))::integer * 25 +
     (app_private.normalize_party_text(target_tax_identifier) is not null and
      app_private.normalize_party_text(p.tax_identifier)=app_private.normalize_party_text(target_tax_identifier))::integer * 50 +
     (app_private.normalize_party_text(target_email) is not null and exists(select 1 from public.party_contacts pc
      where pc.organization_id=p.organization_id and pc.party_id=p.id and pc.status='active' and
      app_private.normalize_party_text(pc.email)=app_private.normalize_party_text(target_email)))::integer * 40 +
     (app_private.normalize_party_text(target_phone) is not null and exists(select 1 from public.party_contacts pc
      where pc.organization_id=p.organization_id and pc.party_id=p.id and pc.status='active' and
      app_private.normalize_party_text(pc.phone)=app_private.normalize_party_text(target_phone)))::integer * 35)::integer
  from public.parties p
  where p.organization_id=target_organization_id and (target_exclude_party_id is null or p.id<>target_exclude_party_id)
    and (app_private.normalize_party_text(target_name) is not null or app_private.normalize_party_text(target_email) is not null
      or app_private.normalize_party_text(target_phone) is not null or app_private.normalize_party_text(target_tax_identifier) is not null)
    and ((app_private.normalize_party_text(target_name) is not null and
          (app_private.normalize_party_text(p.display_name)=app_private.normalize_party_text(target_name) or
           app_private.normalize_party_text(p.legal_name)=app_private.normalize_party_text(target_name)))
      or (app_private.normalize_party_text(target_tax_identifier) is not null and
          app_private.normalize_party_text(p.tax_identifier)=app_private.normalize_party_text(target_tax_identifier))
      or (app_private.normalize_party_text(target_email) is not null and exists(select 1 from public.party_contacts pc
          where pc.organization_id=p.organization_id and pc.party_id=p.id and pc.status='active' and
          app_private.normalize_party_text(pc.email)=app_private.normalize_party_text(target_email)))
      or (app_private.normalize_party_text(target_phone) is not null and exists(select 1 from public.party_contacts pc
          where pc.organization_id=p.organization_id and pc.party_id=p.id and pc.status='active' and
          app_private.normalize_party_text(pc.phone)=app_private.normalize_party_text(target_phone))))
  order by match_score desc,p.display_name;
end; $$;

create function public.search_parties(target_organization_id uuid,target_query text default null,
  target_role public.party_role_kind default null,target_include_archived boolean default false)
returns table(id uuid,legal_name text,display_name text,status public.party_status,tax_identifier text,
  roles text[],primary_email text,primary_phone text,updated_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare normalized_query text:=app_private.normalize_party_text(target_query);
begin
  perform app_private.require_party_permission(target_organization_id,'parties.read');
  return query
  select p.id,p.legal_name,p.display_name,p.status,p.tax_identifier,
    coalesce((select array_agg(pr.role_kind::text order by pr.role_kind::text) from public.party_roles pr
      where pr.organization_id=p.organization_id and pr.party_id=p.id and pr.status='active'),'{}'::text[]),
    primary_contact.email,primary_contact.phone,p.updated_at
  from public.parties p
  left join lateral (select pc.email,pc.phone from public.party_contacts pc where pc.organization_id=p.organization_id
    and pc.party_id=p.id and pc.status='active' order by pc.is_primary desc,pc.created_at limit 1) primary_contact on true
  where p.organization_id=target_organization_id and (target_include_archived or p.status='active')
    and (target_role is null or exists(select 1 from public.party_roles pr where pr.organization_id=p.organization_id
      and pr.party_id=p.id and pr.role_kind=target_role and pr.status='active'))
    and (normalized_query is null or app_private.normalize_party_text(p.display_name) like '%'||normalized_query||'%'
      or app_private.normalize_party_text(p.legal_name) like '%'||normalized_query||'%'
      or app_private.normalize_party_text(p.tax_identifier) like '%'||normalized_query||'%'
      or exists(select 1 from public.party_contacts pc where pc.organization_id=p.organization_id and pc.party_id=p.id
        and pc.status='active' and (app_private.normalize_party_text(pc.email) like '%'||normalized_query||'%'
          or app_private.normalize_party_text(pc.phone) like '%'||normalized_query||'%'))
      or exists(select 1 from public.party_roles pr where pr.organization_id=p.organization_id and pr.party_id=p.id
        and app_private.normalize_party_text(pr.external_reference) like '%'||normalized_query||'%'))
  order by p.status,p.display_name;
end; $$;

alter table public.parties enable row level security;
alter table public.party_roles enable row level security;
alter table public.party_contacts enable row level security;
alter table public.party_addresses enable row level security;
create policy parties_read on public.parties for select to authenticated using(app_private.has_permission(organization_id,'parties.read'));
create policy party_roles_read on public.party_roles for select to authenticated using(app_private.has_permission(organization_id,'parties.read'));
create policy party_contacts_read on public.party_contacts for select to authenticated using(app_private.has_permission(organization_id,'parties.read'));
create policy party_addresses_read on public.party_addresses for select to authenticated using(app_private.has_permission(organization_id,'parties.read'));

revoke all on public.parties,public.party_roles,public.party_contacts,public.party_addresses from public,anon;
grant select on public.parties,public.party_roles,public.party_contacts,public.party_addresses to authenticated;
revoke insert,update,delete on public.parties,public.party_roles,public.party_contacts,public.party_addresses from authenticated;
revoke all on function app_private.require_party_permission(uuid,text),app_private.sync_party_roles(uuid,uuid,uuid,boolean,boolean,integer,integer,text,text),app_private.guard_party_history() from public,anon,authenticated;
grant execute on function public.create_party(uuid,text,text,boolean,boolean,integer,integer,text,text,text,text,text,public.party_tax_status,text) to authenticated;
grant execute on function public.update_party(uuid,uuid,text,text,boolean,boolean,integer,integer,text,text,text,text,text,public.party_tax_status,text) to authenticated;
grant execute on function public.set_party_status(uuid,uuid,public.party_status) to authenticated;
grant execute on function public.add_party_contact(uuid,uuid,text,text,text,text,boolean) to authenticated;
grant execute on function public.add_party_address(uuid,uuid,public.party_address_kind,text,text,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.set_party_custom_field_value(uuid,uuid,uuid,jsonb) to authenticated;
grant execute on function public.search_party_duplicates(uuid,text,text,text,text,uuid) to authenticated;
grant execute on function public.search_parties(uuid,text,public.party_role_kind,boolean) to authenticated;

commit;
