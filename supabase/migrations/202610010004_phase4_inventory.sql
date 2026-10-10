begin;

create type public.catalog_item_kind as enum ('product','service');
create type public.catalog_status as enum ('active','inactive');
create type public.inventory_operation_kind as enum ('opening','stock_in','stock_out','adjustment','damage_loss','stock_count','transfer');
create type public.inventory_movement_kind as enum ('opening','stock_in','stock_out','adjustment_in','adjustment_out','damage_loss','stock_count_in','stock_count_out','transfer_in','transfer_out');

create table public.product_categories (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,19}$'),
  name text not null check(char_length(btrim(name)) between 1 and 120),
  status public.catalog_status not null default 'active',
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(organization_id,code)
);

create table public.organization_units (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,19}$'),
  name text not null check(char_length(btrim(name)) between 1 and 80),
  symbol text not null check(char_length(btrim(symbol)) between 1 and 16),
  quantity_scale smallint not null default 4 check(quantity_scale between 0 and 8),
  status public.catalog_status not null default 'active',
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(organization_id,code)
);

create table public.inventory_locations (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,19}$'),
  name text not null check(char_length(btrim(name)) between 1 and 120),
  is_default boolean not null default false,
  status public.catalog_status not null default 'active',
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(organization_id,code)
);
create unique index inventory_locations_one_default on public.inventory_locations(organization_id) where is_default;

create table public.products (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  item_kind public.catalog_item_kind not null,
  name text not null check(char_length(btrim(name)) between 1 and 160),
  sku text not null check(char_length(btrim(sku)) between 1 and 60),
  barcode text,
  category_id uuid,
  unit_id uuid not null,
  inventory_tracked boolean not null default false,
  inventory_account_id uuid,
  low_stock_threshold numeric(24,8) not null default 0 check(low_stock_threshold>=0),
  status public.catalog_status not null default 'active',
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(), updated_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(organization_id,sku),
  foreign key(organization_id,category_id) references public.product_categories(organization_id,id),
  foreign key(organization_id,unit_id) references public.organization_units(organization_id,id),
  foreign key(organization_id,inventory_account_id) references public.accounts(organization_id,id),
  check(barcode is null or char_length(btrim(barcode)) between 1 and 80),
  check((item_kind='service' and not inventory_tracked and inventory_account_id is null and low_stock_threshold=0)
    or (item_kind='product' and ((inventory_tracked and inventory_account_id is not null) or (not inventory_tracked and inventory_account_id is null))))
);
create unique index products_barcode_unique on public.products(organization_id,barcode) where barcode is not null;

create table public.inventory_operations (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  operation_kind public.inventory_operation_kind not null,
  movement_date date not null,
  source_type text not null check(source_type ~ '^[a-z][a-z0-9_]*$'),
  source_reference text,
  reason text not null check(char_length(btrim(reason)) between 3 and 500),
  idempotency_key text not null check(char_length(idempotency_key) between 8 and 200),
  request_fingerprint text not null,
  journal_entry_id uuid,
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(organization_id,idempotency_key),
  foreign key(organization_id,journal_entry_id) references public.journal_entries(organization_id,id)
);

create table public.inventory_cost_states (
  organization_id uuid not null references public.organizations(id),
  product_id uuid not null,
  location_id uuid not null,
  quantity_on_hand numeric(24,8) not null default 0 check(quantity_on_hand>=0),
  inventory_value numeric(24,4) not null default 0 check(inventory_value>=0),
  average_unit_cost numeric(24,8) not null default 0 check(average_unit_cost>=0),
  last_movement_date date,
  last_movement_id uuid,
  version bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(organization_id,product_id,location_id),
  foreign key(organization_id,product_id) references public.products(organization_id,id),
  foreign key(organization_id,location_id) references public.inventory_locations(organization_id,id),
  check((quantity_on_hand=0 and inventory_value=0 and average_unit_cost=0) or quantity_on_hand>0)
);

create table public.inventory_movements (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  operation_id uuid not null,
  product_id uuid not null,
  location_id uuid not null,
  movement_kind public.inventory_movement_kind not null,
  movement_date date not null,
  quantity_delta numeric(24,8) not null check(quantity_delta<>0),
  applied_unit_cost numeric(24,8) not null check(applied_unit_cost>0),
  value_delta numeric(24,4) not null check(value_delta<>0),
  quantity_before numeric(24,8) not null,
  quantity_after numeric(24,8) not null check(quantity_after>=0),
  value_before numeric(24,4) not null,
  value_after numeric(24,4) not null check(value_after>=0),
  average_cost_before numeric(24,8) not null,
  average_cost_after numeric(24,8) not null,
  reason text not null,
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  unique(organization_id,id),
  foreign key(organization_id,operation_id) references public.inventory_operations(organization_id,id),
  foreign key(organization_id,product_id) references public.products(organization_id,id),
  foreign key(organization_id,location_id) references public.inventory_locations(organization_id,id),
  check((quantity_delta>0 and value_delta>0) or (quantity_delta<0 and value_delta<0))
);
alter table public.inventory_cost_states add constraint inventory_cost_state_last_movement_fk
  foreign key(organization_id,last_movement_id) references public.inventory_movements(organization_id,id);

create index products_org_status_idx on public.products(organization_id,status,item_kind);
create index inventory_operations_org_date_idx on public.inventory_operations(organization_id,movement_date desc);
create index inventory_movements_pool_idx on public.inventory_movements(organization_id,product_id,location_id,movement_date,id);

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
    return target_permission=any(array['members.read','audit.read','storage.read','storage.write','accounting.read','accounting.post','inventory.read','inventory.manage']);
  end if;
  return target_permission=any(array['storage.read','storage.write']);
end; $$;

create function app_private.require_inventory_permission(target_organization_id uuid,target_permission text)
returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not app_private.has_permission(target_organization_id,target_permission) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
end; $$;

create function app_private.guard_inventory_master_history()
returns trigger language plpgsql as $$
begin
  if tg_op='DELETE' then raise exception using errcode='P0001',message='inventory_master_deletion_forbidden'; end if;
  return new;
end; $$;
create trigger product_category_history_guard before delete on public.product_categories for each row execute function app_private.guard_inventory_master_history();
create trigger organization_unit_history_guard before delete on public.organization_units for each row execute function app_private.guard_inventory_master_history();
create trigger inventory_location_history_guard before delete on public.inventory_locations for each row execute function app_private.guard_inventory_master_history();
create trigger product_history_guard before delete on public.products for each row execute function app_private.guard_inventory_master_history();

create function app_private.guard_inventory_derived_rows()
returns trigger language plpgsql as $$
begin
  if current_setting('app.inventory_write',true)<>'allowed' then raise exception using errcode='42501',message='protected_inventory_mutation'; end if;
  if tg_op='DELETE' then raise exception using errcode='P0001',message='inventory_history_deletion_forbidden'; end if;
  if tg_table_name='inventory_movements' and tg_op='UPDATE' then raise exception using errcode='P0001',message='inventory_movement_immutable'; end if;
  if tg_table_name='inventory_operations' then
    if tg_op='UPDATE' and not(old.journal_entry_id is null and new.journal_entry_id is not null) then
      raise exception using errcode='P0001',message='inventory_operation_immutable';
    end if;
  end if;
  return coalesce(new,old);
end; $$;
create trigger inventory_operation_guard before update or delete on public.inventory_operations for each row execute function app_private.guard_inventory_derived_rows();
create trigger inventory_movement_guard before update or delete on public.inventory_movements for each row execute function app_private.guard_inventory_derived_rows();
create trigger inventory_cost_state_guard before insert or update or delete on public.inventory_cost_states for each row execute function app_private.guard_inventory_derived_rows();

create function public.initialize_inventory(target_organization_id uuid)
returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid();
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  if not exists(select 1 from public.accounting_profiles where organization_id=target_organization_id) then
    raise exception using errcode='23514',message='accounting_initialization_required';
  end if;
  insert into public.organization_units(organization_id,code,name,symbol,quantity_scale,created_by,updated_by) values
    (target_organization_id,'PCS','Piece','pcs',0,actor,actor),
    (target_organization_id,'HOUR','Hour','hr',2,actor,actor)
  on conflict(organization_id,code) do nothing;
  insert into public.inventory_locations(organization_id,code,name,is_default,created_by,updated_by)
  values(target_organization_id,'MAIN','Main Location',true,actor,actor)
  on conflict(organization_id,code) do nothing;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'inventory.initialized','organization',target_organization_id::text,jsonb_build_object('default_location','MAIN'));
end; $$;

create function public.create_product_category(target_organization_id uuid,target_code text,target_name text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  insert into public.product_categories(organization_id,code,name,created_by,updated_by)
  values(target_organization_id,upper(btrim(target_code)),btrim(target_name),actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'inventory.category_created','product_category',created_id::text,jsonb_build_object('code',upper(btrim(target_code))));
  return created_id;
end; $$;

create function public.create_inventory_unit(target_organization_id uuid,target_code text,target_name text,target_symbol text,target_quantity_scale smallint)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  insert into public.organization_units(organization_id,code,name,symbol,quantity_scale,created_by,updated_by)
  values(target_organization_id,upper(btrim(target_code)),btrim(target_name),btrim(target_symbol),target_quantity_scale,actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'inventory.unit_created','organization_unit',created_id::text,jsonb_build_object('code',upper(btrim(target_code))));
  return created_id;
end; $$;

create function public.create_inventory_location(target_organization_id uuid,target_code text,target_name text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  insert into public.inventory_locations(organization_id,code,name,created_by,updated_by)
  values(target_organization_id,upper(btrim(target_code)),btrim(target_name),actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'inventory.location_created','inventory_location',created_id::text,jsonb_build_object('code',upper(btrim(target_code))));
  return created_id;
end; $$;

create function public.create_catalog_item(target_organization_id uuid,target_item_kind public.catalog_item_kind,target_name text,target_sku text,
  target_barcode text,target_category_id uuid,target_unit_id uuid,target_inventory_tracked boolean,target_inventory_account_id uuid,target_low_stock_threshold numeric)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid; inventory_account public.accounts%rowtype;
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  if not exists(select 1 from public.organization_units where organization_id=target_organization_id and id=target_unit_id and status='active') then
    raise exception using errcode='23503',message='active_unit_not_found';
  end if;
  if target_category_id is not null and not exists(select 1 from public.product_categories where organization_id=target_organization_id and id=target_category_id and status='active') then
    raise exception using errcode='23503',message='active_category_not_found';
  end if;
  if target_item_kind='service' and target_inventory_tracked then raise exception using errcode='23514',message='service_cannot_track_inventory'; end if;
  if target_inventory_tracked then
    select * into inventory_account from public.accounts where organization_id=target_organization_id and id=target_inventory_account_id and status='active';
    if not found or inventory_account.category<>'asset' then raise exception using errcode='23503',message='active_inventory_asset_account_required'; end if;
  end if;
  insert into public.products(organization_id,item_kind,name,sku,barcode,category_id,unit_id,inventory_tracked,inventory_account_id,low_stock_threshold,created_by,updated_by)
  values(target_organization_id,target_item_kind,btrim(target_name),upper(btrim(target_sku)),nullif(btrim(target_barcode),''),target_category_id,target_unit_id,
    target_inventory_tracked,case when target_inventory_tracked then target_inventory_account_id else null end,
    case when target_inventory_tracked then target_low_stock_threshold else 0 end,actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'catalog.item_created','product',created_id::text,
    jsonb_build_object('kind',target_item_kind,'sku',upper(btrim(target_sku)),'inventory_tracked',target_inventory_tracked));
  return created_id;
end; $$;

create function public.set_catalog_item_status(target_organization_id uuid,target_product_id uuid,target_status public.catalog_status)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); prior_status public.catalog_status;
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  select status into prior_status from public.products where organization_id=target_organization_id and id=target_product_id for update;
  if not found then raise exception using errcode='23503',message='catalog_item_not_found'; end if;
  if prior_status=target_status then return; end if;
  update public.products set status=target_status,updated_at=now(),updated_by=actor
   where organization_id=target_organization_id and id=target_product_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,old_state,new_state)
  values(target_organization_id,actor,'catalog.item_status_changed','product',target_product_id::text,
    jsonb_build_object('status',prior_status),jsonb_build_object('status',target_status));
end; $$;

create function app_private.post_inventory_movement_internal(actor uuid,target_organization_id uuid,target_product_id uuid,target_location_id uuid,
  target_movement_date date,target_movement_kind public.inventory_movement_kind,target_quantity numeric,target_unit_cost numeric,
  target_offset_account_id uuid,target_reason text,target_source_type text,target_source_reference text,target_idempotency_key text,
  target_operation_kind public.inventory_operation_kind)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare product public.products%rowtype; location public.inventory_locations%rowtype; offset_account public.accounts%rowtype;
  state public.inventory_cost_states%rowtype; existing public.inventory_operations%rowtype; operation_id uuid; movement_id uuid; journal_id uuid;
  fingerprint text; inbound boolean; quantity_delta numeric(24,8); applied_cost numeric(24,8); value_amount numeric(24,4);
  quantity_after numeric(24,8); value_after numeric(24,4); average_after numeric(24,8); lines jsonb;
begin
  if actor is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if target_quantity<=0 or target_quantity<>round(target_quantity,8) then raise exception using errcode='22023',message='invalid_inventory_quantity'; end if;
  if char_length(btrim(target_reason))<3 then raise exception using errcode='22023',message='inventory_reason_required'; end if;
  fingerprint:=encode(extensions.digest(concat_ws('|',target_product_id,target_location_id,target_movement_date,target_movement_kind,
    target_quantity,target_unit_cost,target_offset_account_id,target_reason,target_source_type,target_source_reference),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':inventory-operation:'||target_idempotency_key,0));
  select * into existing from public.inventory_operations where organization_id=target_organization_id and idempotency_key=target_idempotency_key;
  if found then
    if existing.request_fingerprint<>fingerprint then raise exception using errcode='23505',message='idempotency_payload_mismatch'; end if;
    return existing.id;
  end if;
  select * into product from public.products where organization_id=target_organization_id and id=target_product_id and status='active' and inventory_tracked;
  if not found then raise exception using errcode='23503',message='active_inventory_product_not_found'; end if;
  select * into location from public.inventory_locations where organization_id=target_organization_id and id=target_location_id and status='active';
  if not found then raise exception using errcode='23503',message='active_inventory_location_not_found'; end if;
  select * into offset_account from public.accounts where organization_id=target_organization_id and id=target_offset_account_id and status='active';
  if not found or offset_account.id=product.inventory_account_id then raise exception using errcode='23503',message='valid_offset_account_required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':'||target_product_id::text||':'||target_location_id::text,0));
  perform set_config('app.inventory_write','allowed',true);
  insert into public.inventory_cost_states(organization_id,product_id,location_id) values(target_organization_id,target_product_id,target_location_id)
  on conflict do nothing;
  select * into state from public.inventory_cost_states where organization_id=target_organization_id and product_id=target_product_id and location_id=target_location_id for update;
  if state.last_movement_date is not null and target_movement_date<state.last_movement_date then raise exception using errcode='23514',message='backdated_inventory_movement_forbidden'; end if;
  inbound:=target_movement_kind in ('opening','stock_in','adjustment_in','stock_count_in');
  if target_movement_kind='opening' and (state.quantity_on_hand<>0 or state.version<>0) then raise exception using errcode='23514',message='opening_stock_requires_empty_history'; end if;
  if inbound then
    applied_cost:=case when target_movement_kind='stock_count_in' and state.average_unit_cost>0 then state.average_unit_cost else target_unit_cost end;
    if applied_cost is null or applied_cost<=0 or applied_cost<>round(applied_cost,8) then raise exception using errcode='22023',message='positive_unit_cost_required'; end if;
    quantity_delta:=target_quantity; value_amount:=round(target_quantity*applied_cost,4);
    quantity_after:=state.quantity_on_hand+target_quantity; value_after:=state.inventory_value+value_amount;
    average_after:=round(value_after/quantity_after,8);
  else
    if state.quantity_on_hand<target_quantity then raise exception using errcode='23514',message='negative_inventory_forbidden'; end if;
    if state.average_unit_cost<=0 then raise exception using errcode='23514',message='inventory_cost_unavailable'; end if;
    quantity_delta:=-target_quantity;
    if state.quantity_on_hand=target_quantity then value_amount:=state.inventory_value; applied_cost:=round(state.inventory_value/target_quantity,8);
    else applied_cost:=state.average_unit_cost; value_amount:=round(target_quantity*applied_cost,4); end if;
    quantity_after:=state.quantity_on_hand-target_quantity; value_after:=state.inventory_value-value_amount;
    if quantity_after=0 then value_after:=0; average_after:=0; else average_after:=round(value_after/quantity_after,8); end if;
  end if;
  if value_amount<=0 then raise exception using errcode='23514',message='positive_inventory_value_required'; end if;
  insert into public.inventory_operations(organization_id,operation_kind,movement_date,source_type,source_reference,reason,idempotency_key,request_fingerprint,created_by)
  values(target_organization_id,target_operation_kind,target_movement_date,target_source_type,nullif(btrim(target_source_reference),''),btrim(target_reason),
    target_idempotency_key,fingerprint,actor) returning id into operation_id;
  lines:=case when inbound then jsonb_build_array(
    jsonb_build_object('account_id',product.inventory_account_id,'debit',value_amount::text,'credit','0','description',target_reason),
    jsonb_build_object('account_id',offset_account.id,'debit','0','credit',value_amount::text,'description',target_reason))
  else jsonb_build_array(
    jsonb_build_object('account_id',offset_account.id,'debit',value_amount::text,'credit','0','description',target_reason),
    jsonb_build_object('account_id',product.inventory_account_id,'debit','0','credit',value_amount::text,'description',target_reason)) end;
  journal_id:=app_private.post_journal_internal(actor,target_organization_id,target_movement_date,'Inventory: '||target_reason,
    operation_id::text,lines,'inventory:'||target_idempotency_key,'system',null);
  update public.inventory_operations set journal_entry_id=journal_id where id=operation_id;
  insert into public.inventory_movements(organization_id,operation_id,product_id,location_id,movement_kind,movement_date,quantity_delta,
    applied_unit_cost,value_delta,quantity_before,quantity_after,value_before,value_after,average_cost_before,average_cost_after,reason,created_by)
  values(target_organization_id,operation_id,target_product_id,target_location_id,target_movement_kind,target_movement_date,quantity_delta,applied_cost,
    case when inbound then value_amount else -value_amount end,state.quantity_on_hand,quantity_after,state.inventory_value,value_after,
    state.average_unit_cost,average_after,btrim(target_reason),actor) returning id into movement_id;
  update public.inventory_cost_states set quantity_on_hand=quantity_after,inventory_value=value_after,average_unit_cost=average_after,
    last_movement_date=target_movement_date,last_movement_id=movement_id,version=version+1,updated_at=now()
  where organization_id=target_organization_id and product_id=target_product_id and location_id=target_location_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'inventory.movement_posted','inventory_operation',operation_id::text,
    jsonb_build_object('movement_kind',target_movement_kind,'quantity_delta',quantity_delta,'value_delta',case when inbound then value_amount else -value_amount end,
      'journal_entry_id',journal_id,'average_cost_after',average_after));
  return operation_id;
end; $$;

create function public.post_inventory_movement(target_organization_id uuid,target_product_id uuid,target_location_id uuid,target_movement_date date,
  target_movement_kind public.inventory_movement_kind,target_quantity numeric,target_unit_cost numeric,target_offset_account_id uuid,
  target_reason text,target_source_reference text,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare operation_kind public.inventory_operation_kind;
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  if target_movement_kind not in ('opening','stock_in','stock_out','adjustment_in','adjustment_out','damage_loss') then
    raise exception using errcode='22023',message='unsupported_manual_movement_kind';
  end if;
  operation_kind:=case target_movement_kind when 'opening' then 'opening' when 'stock_in' then 'stock_in' when 'stock_out' then 'stock_out'
    when 'damage_loss' then 'damage_loss' else 'adjustment' end;
  return app_private.post_inventory_movement_internal(auth.uid(),target_organization_id,target_product_id,target_location_id,target_movement_date,
    target_movement_kind,target_quantity,target_unit_cost,target_offset_account_id,target_reason,'manual_inventory',target_source_reference,
    target_idempotency_key,operation_kind);
end; $$;

create function public.post_inventory_stock_count(target_organization_id uuid,target_product_id uuid,target_location_id uuid,target_movement_date date,
  target_counted_quantity numeric,target_unit_cost_if_empty numeric,target_offset_account_id uuid,target_reason text,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare current_quantity numeric; difference numeric; movement_kind public.inventory_movement_kind;
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  if target_counted_quantity<0 or target_counted_quantity<>round(target_counted_quantity,8) then raise exception using errcode='22023',message='invalid_counted_quantity'; end if;
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':'||target_product_id::text||':'||target_location_id::text,0));
  select coalesce(quantity_on_hand,0) into current_quantity from public.inventory_cost_states
    where organization_id=target_organization_id and product_id=target_product_id and location_id=target_location_id;
  current_quantity:=coalesce(current_quantity,0); difference:=target_counted_quantity-current_quantity;
  if difference=0 then raise exception using errcode='P0001',message='stock_count_no_adjustment_required'; end if;
  movement_kind:=case when difference>0 then 'stock_count_in'::public.inventory_movement_kind else 'stock_count_out'::public.inventory_movement_kind end;
  return app_private.post_inventory_movement_internal(auth.uid(),target_organization_id,target_product_id,target_location_id,target_movement_date,
    movement_kind,abs(difference),target_unit_cost_if_empty,target_offset_account_id,target_reason,'stock_count',null,target_idempotency_key,'stock_count');
end; $$;

create function public.post_inventory_transfer(target_organization_id uuid,target_product_id uuid,target_from_location_id uuid,target_to_location_id uuid,
  target_movement_date date,target_quantity numeric,target_reason text,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); product public.products%rowtype; source_state public.inventory_cost_states%rowtype; destination_state public.inventory_cost_states%rowtype;
  existing public.inventory_operations%rowtype; operation_id uuid; out_id uuid; in_id uuid; fingerprint text; transferred_value numeric(24,4);
  applied_cost numeric(24,8); source_qty_after numeric(24,8); source_value_after numeric(24,4); source_avg_after numeric(24,8);
  destination_qty_after numeric(24,8); destination_value_after numeric(24,4); destination_avg_after numeric(24,8);
begin
  perform app_private.require_inventory_permission(target_organization_id,'inventory.manage');
  if target_from_location_id=target_to_location_id then raise exception using errcode='22023',message='transfer_locations_must_differ'; end if;
  if target_quantity<=0 or target_quantity<>round(target_quantity,8) then raise exception using errcode='22023',message='invalid_inventory_quantity'; end if;
  fingerprint:=encode(extensions.digest(concat_ws('|',target_product_id,target_from_location_id,target_to_location_id,target_movement_date,target_quantity,target_reason),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':inventory-operation:'||target_idempotency_key,0));
  select * into existing from public.inventory_operations where organization_id=target_organization_id and idempotency_key=target_idempotency_key;
  if found then if existing.request_fingerprint<>fingerprint then raise exception using errcode='23505',message='idempotency_payload_mismatch'; end if; return existing.id; end if;
  select * into product from public.products where organization_id=target_organization_id and id=target_product_id and status='active' and inventory_tracked;
  if not found then raise exception using errcode='23503',message='active_inventory_product_not_found'; end if;
  if (select count(*) from public.inventory_locations where organization_id=target_organization_id and id in (target_from_location_id,target_to_location_id) and status='active')<>2 then
    raise exception using errcode='23503',message='active_inventory_location_not_found';
  end if;
  if not exists(select 1 from public.accounting_periods where organization_id=target_organization_id and status='open'
    and target_movement_date between starts_on and ends_on) then
    raise exception using errcode='23514',message='open_accounting_period_required';
  end if;
  perform pg_advisory_xact_lock(least(hashtextextended(target_organization_id::text||':'||target_product_id::text||':'||target_from_location_id::text,0),
    hashtextextended(target_organization_id::text||':'||target_product_id::text||':'||target_to_location_id::text,0)));
  perform pg_advisory_xact_lock(greatest(hashtextextended(target_organization_id::text||':'||target_product_id::text||':'||target_from_location_id::text,0),
    hashtextextended(target_organization_id::text||':'||target_product_id::text||':'||target_to_location_id::text,0)));
  perform set_config('app.inventory_write','allowed',true);
  insert into public.inventory_cost_states(organization_id,product_id,location_id) values
    (target_organization_id,target_product_id,target_from_location_id),(target_organization_id,target_product_id,target_to_location_id) on conflict do nothing;
  select * into source_state from public.inventory_cost_states where organization_id=target_organization_id and product_id=target_product_id and location_id=target_from_location_id for update;
  select * into destination_state from public.inventory_cost_states where organization_id=target_organization_id and product_id=target_product_id and location_id=target_to_location_id for update;
  if target_movement_date<coalesce(source_state.last_movement_date,target_movement_date) or target_movement_date<coalesce(destination_state.last_movement_date,target_movement_date) then
    raise exception using errcode='23514',message='backdated_inventory_movement_forbidden'; end if;
  if source_state.quantity_on_hand<target_quantity then raise exception using errcode='23514',message='negative_inventory_forbidden'; end if;
  if source_state.quantity_on_hand=target_quantity then transferred_value:=source_state.inventory_value; applied_cost:=round(transferred_value/target_quantity,8);
  else applied_cost:=source_state.average_unit_cost; transferred_value:=round(target_quantity*applied_cost,4); end if;
  source_qty_after:=source_state.quantity_on_hand-target_quantity; source_value_after:=source_state.inventory_value-transferred_value;
  if source_qty_after=0 then source_value_after:=0; source_avg_after:=0; else source_avg_after:=round(source_value_after/source_qty_after,8); end if;
  destination_qty_after:=destination_state.quantity_on_hand+target_quantity; destination_value_after:=destination_state.inventory_value+transferred_value;
  destination_avg_after:=round(destination_value_after/destination_qty_after,8);
  insert into public.inventory_operations(organization_id,operation_kind,movement_date,source_type,reason,idempotency_key,request_fingerprint,created_by)
  values(target_organization_id,'transfer',target_movement_date,'inventory_transfer',btrim(target_reason),target_idempotency_key,fingerprint,actor) returning id into operation_id;
  insert into public.inventory_movements(organization_id,operation_id,product_id,location_id,movement_kind,movement_date,quantity_delta,applied_unit_cost,value_delta,
    quantity_before,quantity_after,value_before,value_after,average_cost_before,average_cost_after,reason,created_by)
  values(target_organization_id,operation_id,target_product_id,target_from_location_id,'transfer_out',target_movement_date,-target_quantity,applied_cost,-transferred_value,
    source_state.quantity_on_hand,source_qty_after,source_state.inventory_value,source_value_after,source_state.average_unit_cost,source_avg_after,btrim(target_reason),actor)
  returning id into out_id;
  insert into public.inventory_movements(organization_id,operation_id,product_id,location_id,movement_kind,movement_date,quantity_delta,applied_unit_cost,value_delta,
    quantity_before,quantity_after,value_before,value_after,average_cost_before,average_cost_after,reason,created_by)
  values(target_organization_id,operation_id,target_product_id,target_to_location_id,'transfer_in',target_movement_date,target_quantity,applied_cost,transferred_value,
    destination_state.quantity_on_hand,destination_qty_after,destination_state.inventory_value,destination_value_after,destination_state.average_unit_cost,destination_avg_after,btrim(target_reason),actor)
  returning id into in_id;
  update public.inventory_cost_states set quantity_on_hand=source_qty_after,inventory_value=source_value_after,average_unit_cost=source_avg_after,
    last_movement_date=target_movement_date,last_movement_id=out_id,version=version+1,updated_at=now()
    where organization_id=target_organization_id and product_id=target_product_id and location_id=target_from_location_id;
  update public.inventory_cost_states set quantity_on_hand=destination_qty_after,inventory_value=destination_value_after,average_unit_cost=destination_avg_after,
    last_movement_date=target_movement_date,last_movement_id=in_id,version=version+1,updated_at=now()
    where organization_id=target_organization_id and product_id=target_product_id and location_id=target_to_location_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'inventory.transfer_posted','inventory_operation',operation_id::text,
    jsonb_build_object('quantity',target_quantity,'value',transferred_value,'from_location_id',target_from_location_id,'to_location_id',target_to_location_id));
  return operation_id;
end; $$;

create view public.inventory_valuation with (security_invoker=true) as
select s.organization_id,s.product_id,p.sku,p.name product_name,s.location_id,l.code location_code,l.name location_name,
 s.quantity_on_hand,s.average_unit_cost,s.inventory_value,s.last_movement_date
from public.inventory_cost_states s join public.products p on p.organization_id=s.organization_id and p.id=s.product_id
join public.inventory_locations l on l.organization_id=s.organization_id and l.id=s.location_id;

create view public.inventory_low_stock with (security_invoker=true) as
select p.organization_id,p.id product_id,p.sku,p.name product_name,s.location_id,l.code location_code,l.name location_name,
 coalesce(s.quantity_on_hand,0::numeric) quantity_on_hand,p.low_stock_threshold
from public.products p cross join public.inventory_locations l
left join public.inventory_cost_states s on s.organization_id=p.organization_id and s.product_id=p.id and s.location_id=l.id
where p.organization_id=l.organization_id and p.status='active' and p.inventory_tracked and l.status='active'
 and coalesce(s.quantity_on_hand,0)<=p.low_stock_threshold;

alter table public.product_categories enable row level security;
alter table public.organization_units enable row level security;
alter table public.inventory_locations enable row level security;
alter table public.products enable row level security;
alter table public.inventory_operations enable row level security;
alter table public.inventory_cost_states enable row level security;
alter table public.inventory_movements enable row level security;
create policy product_categories_read on public.product_categories for select to authenticated using(app_private.has_permission(organization_id,'inventory.read'));
create policy organization_units_read on public.organization_units for select to authenticated using(app_private.has_permission(organization_id,'inventory.read'));
create policy inventory_locations_read on public.inventory_locations for select to authenticated using(app_private.has_permission(organization_id,'inventory.read'));
create policy products_read on public.products for select to authenticated using(app_private.has_permission(organization_id,'inventory.read'));
create policy inventory_operations_read on public.inventory_operations for select to authenticated using(app_private.has_permission(organization_id,'inventory.read'));
create policy inventory_cost_states_read on public.inventory_cost_states for select to authenticated using(app_private.has_permission(organization_id,'inventory.read'));
create policy inventory_movements_read on public.inventory_movements for select to authenticated using(app_private.has_permission(organization_id,'inventory.read'));

grant select on public.product_categories,public.organization_units,public.inventory_locations,public.products,public.inventory_operations,
 public.inventory_cost_states,public.inventory_movements,public.inventory_valuation,public.inventory_low_stock to authenticated;
revoke insert,update,delete on public.product_categories,public.organization_units,public.inventory_locations,public.products,public.inventory_operations,
 public.inventory_cost_states,public.inventory_movements from public,anon,authenticated;
revoke all on function app_private.require_inventory_permission(uuid,text) from public,anon,authenticated;
revoke all on function app_private.guard_inventory_master_history() from public,anon,authenticated;
revoke all on function app_private.guard_inventory_derived_rows() from public,anon,authenticated;
revoke all on function app_private.post_inventory_movement_internal(uuid,uuid,uuid,uuid,date,public.inventory_movement_kind,numeric,numeric,uuid,text,text,text,text,public.inventory_operation_kind) from public,anon,authenticated;
grant execute on function public.initialize_inventory(uuid) to authenticated;
grant execute on function public.create_product_category(uuid,text,text) to authenticated;
grant execute on function public.create_inventory_unit(uuid,text,text,text,smallint) to authenticated;
grant execute on function public.create_inventory_location(uuid,text,text) to authenticated;
grant execute on function public.create_catalog_item(uuid,public.catalog_item_kind,text,text,text,uuid,uuid,boolean,uuid,numeric) to authenticated;
grant execute on function public.set_catalog_item_status(uuid,uuid,public.catalog_status) to authenticated;
grant execute on function public.post_inventory_movement(uuid,uuid,uuid,date,public.inventory_movement_kind,numeric,numeric,uuid,text,text,text) to authenticated;
grant execute on function public.post_inventory_stock_count(uuid,uuid,uuid,date,numeric,numeric,uuid,text,text) to authenticated;
grant execute on function public.post_inventory_transfer(uuid,uuid,uuid,uuid,date,numeric,text,text) to authenticated;

commit;
