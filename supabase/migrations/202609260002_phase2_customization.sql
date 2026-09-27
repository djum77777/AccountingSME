begin;

create type public.configuration_status as enum ('draft', 'active', 'inactive');
create type public.onboarding_status as enum ('not_started', 'in_progress', 'completed');
create type public.custom_value_type as enum (
  'text', 'long_text', 'integer', 'decimal', 'boolean', 'date', 'datetime', 'single_select', 'multi_select'
);

create table public.business_templates (
  template_key text primary key check (template_key ~ '^[a-z][a-z0-9_]*$'),
  version integer not null default 1 check (version > 0),
  name_i18n jsonb not null,
  description_i18n jsonb not null,
  recommended_business_types text[] not null default '{}',
  defaults jsonb not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (name_i18n ?& array['id', 'en']),
  check (description_i18n ?& array['id', 'en']),
  check (jsonb_typeof(defaults) = 'object')
);

create table public.organization_configurations (
  organization_id uuid primary key references public.organizations(id),
  template_key text not null references public.business_templates(template_key),
  template_version integer not null,
  business_type text not null check (business_type ~ '^[a-z][a-z0-9_]*$'),
  onboarding_status public.onboarding_status not null default 'in_progress',
  onboarding_step smallint not null default 1 check (onboarding_step between 1 and 5),
  business_name text not null check (char_length(btrim(business_name)) between 1 and 120),
  business_address text,
  phone text,
  tax_identifier text,
  locale text not null default 'id' check (locale in ('id', 'en')),
  timezone text not null default 'Asia/Jakarta',
  date_format text not null default 'DD/MM/YYYY' check (date_format in ('DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD')),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id)
);

create table public.organization_modules (
  organization_id uuid not null references public.organizations(id),
  module_key text not null check (module_key = any(array[
    'dashboard', 'contacts', 'expenses', 'cash_bank', 'sales', 'purchases',
    'inventory', 'projects', 'marketplaces', 'branches', 'reports', 'tax', 'settings'
  ])),
  is_visible boolean not null default true,
  sort_order integer not null default 0 check (sort_order >= 0),
  source text not null default 'organization' check (source in ('template', 'organization')),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  primary key (organization_id, module_key)
);

create table public.display_label_aliases (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  entity_key text not null check (entity_key = any(array[
    'customer', 'supplier', 'product', 'service', 'project', 'branch', 'marketplace', 'invoice', 'bill'
  ])),
  locale text not null check (locale in ('id', 'en')),
  singular_label text not null check (char_length(btrim(singular_label)) between 1 and 60),
  plural_label text not null check (char_length(btrim(plural_label)) between 1 and 60),
  is_active boolean not null default true,
  source text not null default 'organization' check (source in ('template', 'organization')),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique (organization_id, entity_key, locale)
);

create table public.custom_field_definitions (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  field_key text not null check (field_key ~ '^[a-z][a-z0-9_]*$'),
  entity_type text not null check (entity_type = any(array[
    'contact', 'expense', 'cash_transaction', 'sale', 'purchase', 'product', 'project'
  ])),
  value_type public.custom_value_type not null,
  label_i18n jsonb not null,
  help_text_i18n jsonb not null default '{"id":"","en":""}'::jsonb,
  options jsonb not null default '[]'::jsonb,
  validation_rules jsonb not null default '{}'::jsonb,
  default_value jsonb,
  is_required boolean not null default false,
  status public.configuration_status not null default 'draft',
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique (organization_id, field_key),
  check (label_i18n ?& array['id', 'en']),
  check (jsonb_typeof(options) = 'array'),
  check (jsonb_typeof(validation_rules) = 'object')
);

create table public.custom_field_values (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  definition_id uuid not null references public.custom_field_definitions(id),
  definition_version integer not null check (definition_version > 0),
  entity_type text not null,
  entity_id uuid not null,
  value jsonb not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique (definition_id, entity_id)
);

create table public.custom_dimension_definitions (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  dimension_key text not null check (dimension_key ~ '^[a-z][a-z0-9_]*$'),
  label_i18n jsonb not null,
  status public.configuration_status not null default 'draft',
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique (organization_id, dimension_key),
  check (label_i18n ?& array['id', 'en'])
);

create table public.custom_dimension_values (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  dimension_id uuid not null references public.custom_dimension_definitions(id),
  value_code text not null check (value_code ~ '^[A-Za-z0-9][A-Za-z0-9_-]*$'),
  label_i18n jsonb not null,
  status public.configuration_status not null default 'active',
  sort_order integer not null default 0 check (sort_order >= 0),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique (dimension_id, value_code),
  check (label_i18n ?& array['id', 'en'])
);

create table public.form_configurations (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  form_key text not null check (form_key = any(array['contact', 'expense', 'sale', 'purchase', 'product', 'project'])),
  version integer not null default 1 check (version > 0),
  source text not null default 'organization' check (source in ('template', 'organization')),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique (organization_id, form_key)
);

create table public.form_configuration_fields (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  form_configuration_id uuid not null references public.form_configurations(id) on delete cascade,
  field_key text not null check (field_key ~ '^[a-z][a-z0-9_.]*$'),
  section_key text not null default 'main' check (section_key ~ '^[a-z][a-z0-9_]*$'),
  sort_order integer not null default 0 check (sort_order >= 0),
  is_required boolean not null default false,
  is_visible boolean not null default true,
  default_value jsonb,
  role_visibility public.membership_role[] not null default array['owner','admin_accountant','staff']::public.membership_role[],
  source text not null default 'organization' check (source in ('template', 'organization')),
  unique (form_configuration_id, field_key)
);

create table public.saved_views (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  owner_user_id uuid not null references auth.users(id),
  entity_type text not null check (entity_type = any(array[
    'contact', 'expense', 'cash_transaction', 'sale', 'purchase', 'product', 'project'
  ])),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  columns_config jsonb not null default '[]'::jsonb,
  filter_config jsonb not null default '[]'::jsonb,
  sort_config jsonb not null default '[]'::jsonb,
  is_shared boolean not null default false,
  status public.configuration_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, owner_user_id, entity_type, name),
  check (jsonb_typeof(columns_config) = 'array'),
  check (jsonb_typeof(filter_config) = 'array'),
  check (jsonb_typeof(sort_config) = 'array')
);

create index custom_field_definitions_org_entity_idx on public.custom_field_definitions (organization_id, entity_type, status);
create index custom_field_values_org_entity_idx on public.custom_field_values (organization_id, entity_type, entity_id);
create index custom_dimension_definitions_org_idx on public.custom_dimension_definitions (organization_id, status);
create index saved_views_org_entity_idx on public.saved_views (organization_id, entity_type, status);

insert into public.business_templates (template_key, name_i18n, description_i18n, recommended_business_types, defaults) values
('general_sme', '{"id":"UMKM Umum","en":"General SME"}', '{"id":"Fondasi fleksibel untuk sebagian besar usaha.","en":"A flexible foundation for most businesses."}', array['general','other'],
 '{"modules":["dashboard","contacts","expenses","cash_bank","sales","purchases","reports","settings"],"aliases":{},"forms":["contact","expense","sale","purchase"]}'),
('retail', '{"id":"Ritel","en":"Retail"}', '{"id":"Untuk toko dengan stok dan beberapa lokasi.","en":"For stores with stock and multiple locations."}', array['retail'],
 '{"modules":["dashboard","contacts","expenses","cash_bank","sales","purchases","inventory","branches","reports","tax","settings"],"aliases":{"customer":{"id":["Pelanggan","Pelanggan"],"en":["Customer","Customers"]}},"forms":["contact","expense","sale","purchase","product"]}'),
('online_seller', '{"id":"Penjual Online","en":"Online Seller"}', '{"id":"Untuk penjualan melalui marketplace.","en":"For marketplace-based selling."}', array['online_seller'],
 '{"modules":["dashboard","contacts","expenses","cash_bank","sales","purchases","inventory","marketplaces","reports","tax","settings"],"aliases":{"customer":{"id":["Pembeli","Pembeli"],"en":["Buyer","Buyers"]}},"forms":["contact","expense","sale","purchase","product"]}'),
('trading_distributor', '{"id":"Perdagangan/Distributor","en":"Trading/Distributor"}', '{"id":"Untuk pembelian, stok, dan distribusi.","en":"For purchasing, inventory, and distribution."}', array['trading','distributor'],
 '{"modules":["dashboard","contacts","expenses","cash_bank","sales","purchases","inventory","branches","reports","tax","settings"],"aliases":{"customer":{"id":["Pelanggan","Pelanggan"],"en":["Customer","Customers"]}},"forms":["contact","expense","sale","purchase","product"]}'),
('service', '{"id":"Jasa","en":"Service"}', '{"id":"Untuk usaha berbasis jasa dan proyek.","en":"For service and project businesses."}', array['service','consulting'],
 '{"modules":["dashboard","contacts","expenses","cash_bank","sales","projects","reports","tax","settings"],"aliases":{"customer":{"id":["Klien","Klien"],"en":["Client","Clients"]}},"forms":["contact","expense","sale","project"]}');

create function app_private.require_customization_manager(target_organization_id uuid)
returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not app_private.has_permission(target_organization_id, 'customization.manage') then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
end;
$$;

create function app_private.validate_custom_field_value()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare definition public.custom_field_definitions%rowtype;
begin
  select * into definition from public.custom_field_definitions where id = new.definition_id;
  if not found or definition.organization_id <> new.organization_id or definition.entity_type <> new.entity_type then
    raise exception using errcode = '23514', message = 'custom_field_definition_mismatch';
  end if;
  if definition.status <> 'active' then raise exception using errcode = '23514', message = 'custom_field_not_active'; end if;
  if definition.value_type in ('text','long_text','date','datetime','single_select') and jsonb_typeof(new.value) <> 'string' then
    raise exception using errcode = '22023', message = 'custom_field_value_type_mismatch';
  elsif definition.value_type in ('integer','decimal') and jsonb_typeof(new.value) <> 'number' then
    raise exception using errcode = '22023', message = 'custom_field_value_type_mismatch';
  elsif definition.value_type = 'boolean' and jsonb_typeof(new.value) <> 'boolean' then
    raise exception using errcode = '22023', message = 'custom_field_value_type_mismatch';
  elsif definition.value_type = 'multi_select' and jsonb_typeof(new.value) <> 'array' then
    raise exception using errcode = '22023', message = 'custom_field_value_type_mismatch';
  end if;
  new.definition_version := definition.version;
  return new;
end;
$$;
create trigger custom_field_value_valid before insert or update on public.custom_field_values
for each row execute function app_private.validate_custom_field_value();

create function app_private.protect_definition_identity()
returns trigger language plpgsql as $$
begin
  if old.organization_id <> new.organization_id then raise exception using errcode = 'P0001', message = 'organization_immutable'; end if;
  if tg_table_name = 'custom_field_definitions'
     and to_jsonb(old)->>'field_key' <> to_jsonb(new)->>'field_key' then
    raise exception using errcode = 'P0001', message = 'definition_key_immutable';
  elsif tg_table_name = 'custom_dimension_definitions'
     and to_jsonb(old)->>'dimension_key' <> to_jsonb(new)->>'dimension_key' then
    raise exception using errcode = 'P0001', message = 'definition_key_immutable';
  end if;
  return new;
end;
$$;
create trigger custom_field_identity_immutable before update on public.custom_field_definitions
for each row execute function app_private.protect_definition_identity();
create trigger custom_dimension_identity_immutable before update on public.custom_dimension_definitions
for each row execute function app_private.protect_definition_identity();

create function public.complete_organization_onboarding(
  target_organization_id uuid, selected_locale text, selected_business_type text,
  selected_business_name text, selected_business_address text, selected_phone text,
  selected_tax_identifier text, selected_template_key text, selected_currency_code text,
  selected_timezone text, selected_date_format text
) returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare actor uuid := auth.uid(); template public.business_templates%rowtype; item text; alias_item record; form_item text; position integer := 0;
begin
  perform app_private.require_customization_manager(target_organization_id);
  if selected_locale not in ('id','en') or selected_business_type !~ '^[a-z][a-z0-9_]*$' then raise exception using errcode='22023', message='invalid_onboarding_selection'; end if;
  if char_length(btrim(selected_business_name)) not between 1 and 120 then raise exception using errcode='22023', message='invalid_business_name'; end if;
  selected_currency_code := upper(btrim(selected_currency_code));
  if selected_currency_code !~ '^[A-Z]{3}$' then raise exception using errcode='22023', message='invalid_currency_code'; end if;
  select * into template from public.business_templates where template_key = selected_template_key and is_active;
  if not found then raise exception using errcode='22023', message='template_not_found'; end if;

  insert into public.organization_configurations (organization_id, template_key, template_version, business_type, onboarding_status, onboarding_step,
    business_name, business_address, phone, tax_identifier, locale, timezone, date_format, completed_at, created_by, updated_by)
  values (target_organization_id, template.template_key, template.version, selected_business_type, 'completed', 5,
    btrim(selected_business_name), nullif(btrim(selected_business_address),''), nullif(btrim(selected_phone),''), nullif(btrim(selected_tax_identifier),''),
    selected_locale, selected_timezone, selected_date_format, now(), actor, actor)
  on conflict (organization_id) do update set template_key=excluded.template_key, template_version=excluded.template_version,
    business_type=excluded.business_type, onboarding_status='completed', onboarding_step=5, business_name=excluded.business_name,
    business_address=excluded.business_address, phone=excluded.phone, tax_identifier=excluded.tax_identifier, locale=excluded.locale,
    timezone=excluded.timezone, date_format=excluded.date_format, completed_at=now(), updated_at=now(), updated_by=actor;
  update public.organizations set legal_name=btrim(selected_business_name), display_name=btrim(selected_business_name),
    base_currency_code=selected_currency_code, default_locale=selected_locale, updated_at=now(), updated_by=actor where id=target_organization_id;

  delete from public.organization_modules where organization_id=target_organization_id and source='template';
  for item in select jsonb_array_elements_text(template.defaults->'modules') loop
    position := position + 10;
    insert into public.organization_modules values (target_organization_id,item,true,position,'template',now(),actor)
    on conflict (organization_id,module_key) do update set is_visible=true,sort_order=excluded.sort_order,source='template',updated_at=now(),updated_by=actor;
  end loop;
  for alias_item in select key, value from jsonb_each(coalesce(template.defaults->'aliases','{}'::jsonb)) loop
    insert into public.display_label_aliases (organization_id,entity_key,locale,singular_label,plural_label,source,updated_by)
    values (target_organization_id,alias_item.key,'id',alias_item.value->'id'->>0,alias_item.value->'id'->>1,'template',actor)
    on conflict (organization_id,entity_key,locale) do update set singular_label=excluded.singular_label,plural_label=excluded.plural_label,is_active=true,source='template',updated_at=now(),updated_by=actor;
    insert into public.display_label_aliases (organization_id,entity_key,locale,singular_label,plural_label,source,updated_by)
    values (target_organization_id,alias_item.key,'en',alias_item.value->'en'->>0,alias_item.value->'en'->>1,'template',actor)
    on conflict (organization_id,entity_key,locale) do update set singular_label=excluded.singular_label,plural_label=excluded.plural_label,is_active=true,source='template',updated_at=now(),updated_by=actor;
  end loop;
  for form_item in select jsonb_array_elements_text(template.defaults->'forms') loop
    insert into public.form_configurations (organization_id,form_key,source,updated_by) values (target_organization_id,form_item,'template',actor)
    on conflict (organization_id,form_key) do update set source='template',version=public.form_configurations.version+1,updated_at=now(),updated_by=actor;
  end loop;
  insert into public.audit_events (organization_id,actor_user_id,action,target_type,target_id,new_state)
  values (target_organization_id,actor,'customization.onboarding_completed','organization_configuration',target_organization_id::text,
    jsonb_build_object('template_key',template.template_key,'business_type',selected_business_type));
end;
$$;

create function public.set_module_visibility(target_organization_id uuid, target_module_key text, visible boolean)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid();
begin
  perform app_private.require_customization_manager(target_organization_id);
  if target_module_key not in ('dashboard','contacts','expenses','cash_bank','sales','purchases','inventory','projects','marketplaces','branches','reports','tax','settings') then raise exception using errcode='22023',message='invalid_module'; end if;
  insert into public.organization_modules (organization_id,module_key,is_visible,sort_order,source,updated_by)
  values(target_organization_id,target_module_key,visible,999,'organization',actor)
  on conflict(organization_id,module_key) do update set is_visible=excluded.is_visible,source='organization',updated_at=now(),updated_by=actor;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'customization.module_visibility_changed','organization_module',target_module_key,jsonb_build_object('is_visible',visible));
end; $$;

create function public.set_display_label_alias(target_organization_id uuid, target_entity_key text, target_locale text, singular text, plural text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid();
begin
  perform app_private.require_customization_manager(target_organization_id);
  if target_entity_key not in ('customer','supplier','product','service','project','branch','marketplace','invoice','bill') or target_locale not in ('id','en') then raise exception using errcode='22023',message='invalid_label_alias'; end if;
  insert into public.display_label_aliases(organization_id,entity_key,locale,singular_label,plural_label,source,updated_by)
  values(target_organization_id,target_entity_key,target_locale,btrim(singular),btrim(plural),'organization',actor)
  on conflict(organization_id,entity_key,locale) do update set singular_label=excluded.singular_label,plural_label=excluded.plural_label,is_active=true,source='organization',updated_at=now(),updated_by=actor;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'customization.label_alias_changed','display_label_alias',target_entity_key||':'||target_locale,jsonb_build_object('singular',singular,'plural',plural));
end; $$;

create function public.create_custom_field(target_organization_id uuid, target_field_key text, target_entity_type text,
  target_value_type public.custom_value_type, label_id text, label_en text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  perform app_private.require_customization_manager(target_organization_id);
  insert into public.custom_field_definitions(organization_id,field_key,entity_type,value_type,label_i18n,status,created_by,updated_by)
  values(target_organization_id,lower(btrim(target_field_key)),target_entity_type,target_value_type,jsonb_build_object('id',btrim(label_id),'en',btrim(label_en)),'active',actor,actor)
  returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'customization.custom_field_created','custom_field_definition',created_id::text,jsonb_build_object('field_key',target_field_key));
  return created_id;
end; $$;

create function public.set_custom_field_status(target_definition_id uuid, target_status public.configuration_status)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); definition public.custom_field_definitions%rowtype;
begin
  select * into definition from public.custom_field_definitions where id=target_definition_id;
  if not found then raise exception using errcode='P0002',message='custom_field_not_found'; end if;
  perform app_private.require_customization_manager(definition.organization_id);
  update public.custom_field_definitions set status=target_status,version=version+1,updated_at=now(),updated_by=actor where id=target_definition_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,old_state,new_state)
  values(definition.organization_id,actor,'customization.custom_field_status_changed','custom_field_definition',target_definition_id::text,jsonb_build_object('status',definition.status),jsonb_build_object('status',target_status));
end; $$;

create function public.set_custom_field_value(target_definition_id uuid, target_entity_id uuid, target_value jsonb)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); definition public.custom_field_definitions%rowtype; value_id uuid;
begin
  select * into definition from public.custom_field_definitions where id=target_definition_id;
  if not found or not app_private.has_active_membership(definition.organization_id) then raise exception using errcode='42501',message='permission_denied'; end if;
  insert into public.custom_field_values(organization_id,definition_id,definition_version,entity_type,entity_id,value,created_by,updated_by)
  values(definition.organization_id,definition.id,definition.version,definition.entity_type,target_entity_id,target_value,actor,actor)
  on conflict(definition_id,entity_id) do update set value=excluded.value,definition_version=excluded.definition_version,updated_at=now(),updated_by=actor
  returning id into value_id;
  return value_id;
end; $$;

create function public.create_custom_dimension(target_organization_id uuid, target_dimension_key text, label_id text, label_en text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  perform app_private.require_customization_manager(target_organization_id);
  insert into public.custom_dimension_definitions(organization_id,dimension_key,label_i18n,status,created_by,updated_by)
  values(target_organization_id,lower(btrim(target_dimension_key)),jsonb_build_object('id',btrim(label_id),'en',btrim(label_en)),'active',actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'customization.dimension_created','custom_dimension_definition',created_id::text,jsonb_build_object('dimension_key',target_dimension_key));
  return created_id;
end; $$;

create function public.add_custom_dimension_value(target_dimension_id uuid, target_value_code text, label_id text, label_en text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); definition public.custom_dimension_definitions%rowtype; created_id uuid;
begin
  select * into definition from public.custom_dimension_definitions where id=target_dimension_id;
  if not found then raise exception using errcode='P0002',message='dimension_not_found'; end if;
  perform app_private.require_customization_manager(definition.organization_id);
  insert into public.custom_dimension_values(organization_id,dimension_id,value_code,label_i18n,created_by,updated_by)
  values(definition.organization_id,definition.id,btrim(target_value_code),jsonb_build_object('id',btrim(label_id),'en',btrim(label_en)),actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(definition.organization_id,actor,'customization.dimension_value_created','custom_dimension_value',created_id::text,jsonb_build_object('value_code',target_value_code));
  return created_id;
end; $$;

create function public.create_saved_view(target_organization_id uuid,target_entity_type text,target_name text,target_columns jsonb,target_is_shared boolean)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  if not app_private.has_active_membership(target_organization_id) then raise exception using errcode='42501',message='permission_denied'; end if;
  insert into public.saved_views(organization_id,owner_user_id,entity_type,name,columns_config,is_shared)
  values(target_organization_id,actor,target_entity_type,btrim(target_name),target_columns,target_is_shared) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'customization.saved_view_created','saved_view',created_id::text,
    jsonb_build_object('entity_type',target_entity_type,'name',target_name,'is_shared',target_is_shared));
  return created_id;
end; $$;

create function public.can_manage_customization(target_organization_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select app_private.has_permission(target_organization_id, 'customization.manage');
$$;

create function public.upsert_form_field_configuration(
  target_organization_id uuid, target_form_key text, target_field_key text, target_section_key text,
  target_sort_order integer, target_required boolean, target_visible boolean,
  target_default_value jsonb, target_role_visibility public.membership_role[]
) returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); form_id uuid; field_id uuid;
begin
  perform app_private.require_customization_manager(target_organization_id);
  if target_form_key not in ('contact','expense','sale','purchase','product','project') then raise exception using errcode='22023',message='invalid_form'; end if;
  if target_field_key in ('organization_id','owner_user_id','membership_role','posting_status','journal_balance','debit','credit','ledger_account_id','inventory_costing_method','weighted_average_cost','row_level_security','audit_event') then
    raise exception using errcode='42501',message='protected_field';
  end if;
  insert into public.form_configurations(organization_id,form_key,source,updated_by)
  values(target_organization_id,target_form_key,'organization',actor)
  on conflict(organization_id,form_key) do update set version=public.form_configurations.version+1,source='organization',updated_at=now(),updated_by=actor
  returning id into form_id;
  insert into public.form_configuration_fields(organization_id,form_configuration_id,field_key,section_key,sort_order,is_required,is_visible,default_value,role_visibility,source)
  values(target_organization_id,form_id,target_field_key,target_section_key,target_sort_order,target_required,target_visible,target_default_value,target_role_visibility,'organization')
  on conflict(form_configuration_id,field_key) do update set section_key=excluded.section_key,sort_order=excluded.sort_order,
    is_required=excluded.is_required,is_visible=excluded.is_visible,default_value=excluded.default_value,role_visibility=excluded.role_visibility,source='organization'
  returning id into field_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'customization.form_field_configured','form_configuration_field',field_id::text,
    jsonb_build_object('form_key',target_form_key,'field_key',target_field_key,'section_key',target_section_key,'sort_order',target_sort_order,
      'required',target_required,'visible',target_visible,'role_visibility',target_role_visibility));
  return field_id;
end; $$;

create function public.reset_organization_configuration(target_organization_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); config public.organization_configurations%rowtype; template public.business_templates%rowtype; item text; alias_item record; position integer:=0;
begin
  perform app_private.require_customization_manager(target_organization_id);
  select * into config from public.organization_configurations where organization_id=target_organization_id;
  if not found then raise exception using errcode='P0002',message='organization_configuration_not_found'; end if;
  select * into template from public.business_templates where template_key=config.template_key;
  delete from public.organization_modules where organization_id=target_organization_id;
  delete from public.display_label_aliases where organization_id=target_organization_id;
  delete from public.form_configurations where organization_id=target_organization_id;
  for item in select jsonb_array_elements_text(template.defaults->'modules') loop
    position:=position+10;
    insert into public.organization_modules values(target_organization_id,item,true,position,'template',now(),actor);
  end loop;
  for alias_item in select key,value from jsonb_each(coalesce(template.defaults->'aliases','{}'::jsonb)) loop
    insert into public.display_label_aliases(organization_id,entity_key,locale,singular_label,plural_label,source,updated_by) values
      (target_organization_id,alias_item.key,'id',alias_item.value->'id'->>0,alias_item.value->'id'->>1,'template',actor),
      (target_organization_id,alias_item.key,'en',alias_item.value->'en'->>0,alias_item.value->'en'->>1,'template',actor);
  end loop;
  for item in select jsonb_array_elements_text(template.defaults->'forms') loop
    insert into public.form_configurations(organization_id,form_key,source,updated_by) values(target_organization_id,item,'template',actor);
  end loop;
  update public.organization_configurations set template_version=template.version,updated_at=now(),updated_by=actor where organization_id=target_organization_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'customization.configuration_reset','organization_configuration',target_organization_id::text,jsonb_build_object('template_key',template.template_key));
end; $$;

alter table public.business_templates enable row level security;
alter table public.organization_configurations enable row level security;
alter table public.organization_modules enable row level security;
alter table public.display_label_aliases enable row level security;
alter table public.custom_field_definitions enable row level security;
alter table public.custom_field_values enable row level security;
alter table public.custom_dimension_definitions enable row level security;
alter table public.custom_dimension_values enable row level security;
alter table public.form_configurations enable row level security;
alter table public.form_configuration_fields enable row level security;
alter table public.saved_views enable row level security;

create policy template_authenticated_read on public.business_templates for select to authenticated using (is_active);
create policy organization_configuration_member_read on public.organization_configurations for select to authenticated using(app_private.has_active_membership(organization_id));
create policy organization_modules_member_read on public.organization_modules for select to authenticated using(app_private.has_active_membership(organization_id));
create policy label_aliases_member_read on public.display_label_aliases for select to authenticated using(app_private.has_active_membership(organization_id));
create policy custom_fields_member_read on public.custom_field_definitions for select to authenticated using(app_private.has_active_membership(organization_id));
create policy custom_field_values_member_read on public.custom_field_values for select to authenticated using(app_private.has_active_membership(organization_id));
create policy dimensions_member_read on public.custom_dimension_definitions for select to authenticated using(app_private.has_active_membership(organization_id));
create policy dimension_values_member_read on public.custom_dimension_values for select to authenticated using(app_private.has_active_membership(organization_id));
create policy form_configurations_member_read on public.form_configurations for select to authenticated using(app_private.has_active_membership(organization_id));
create policy form_fields_member_read on public.form_configuration_fields for select to authenticated using(app_private.has_active_membership(organization_id));
create policy saved_views_read on public.saved_views for select to authenticated using(app_private.has_active_membership(organization_id) and (is_shared or owner_user_id=auth.uid()));

grant select on public.business_templates,public.organization_configurations,public.organization_modules,public.display_label_aliases,
 public.custom_field_definitions,public.custom_field_values,public.custom_dimension_definitions,public.custom_dimension_values,
 public.form_configurations,public.form_configuration_fields,public.saved_views to authenticated;

revoke all on function app_private.require_customization_manager(uuid) from public,anon,authenticated;
revoke all on function app_private.validate_custom_field_value() from public,anon,authenticated;
revoke all on function app_private.protect_definition_identity() from public,anon,authenticated;
grant execute on function public.complete_organization_onboarding(uuid,text,text,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.set_module_visibility(uuid,text,boolean) to authenticated;
grant execute on function public.set_display_label_alias(uuid,text,text,text,text) to authenticated;
grant execute on function public.create_custom_field(uuid,text,text,public.custom_value_type,text,text) to authenticated;
grant execute on function public.set_custom_field_status(uuid,public.configuration_status) to authenticated;
grant execute on function public.set_custom_field_value(uuid,uuid,jsonb) to authenticated;
grant execute on function public.create_custom_dimension(uuid,text,text,text) to authenticated;
grant execute on function public.add_custom_dimension_value(uuid,text,text,text) to authenticated;
grant execute on function public.create_saved_view(uuid,text,text,jsonb,boolean) to authenticated;
grant execute on function public.can_manage_customization(uuid) to authenticated;
grant execute on function public.upsert_form_field_configuration(uuid,text,text,text,integer,boolean,boolean,jsonb,public.membership_role[]) to authenticated;
grant execute on function public.reset_organization_configuration(uuid) to authenticated;

commit;
