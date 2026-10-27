begin;

create type public.purchase_document_status as enum ('draft','posted','partially_paid','paid','credited','voided');
create type public.purchase_payment_mode as enum ('cash','credit');
create type public.purchase_line_kind as enum ('product','service');
create type public.purchase_number_kind as enum ('purchase','payment','credit');

create table public.purchase_number_counters (
  organization_id uuid not null references public.organizations(id),
  number_kind public.purchase_number_kind not null,
  number_year integer not null check(number_year between 2000 and 9999),
  last_number bigint not null default 0 check(last_number>=0),
  updated_at timestamptz not null default now(),
  primary key(organization_id,number_kind,number_year)
);

create table public.purchase_documents (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  document_number text not null,
  supplier_party_id uuid not null,
  supplier_invoice_number text,
  supplier_name_snapshot text,
  supplier_tax_identifier_snapshot text,
  supplier_address_snapshot text,
  payment_term_days_snapshot integer not null default 0 check(payment_term_days_snapshot between 0 and 3650),
  invoice_date date not null,
  due_date date not null,
  payment_mode public.purchase_payment_mode not null,
  inventory_location_id uuid,
  cash_account_id uuid,
  document_discount_amount numeric(24,4) not null default 0 check(document_discount_amount>=0),
  additional_cost_amount numeric(24,4) not null default 0 check(additional_cost_amount>=0),
  subtotal_amount numeric(24,4) not null default 0 check(subtotal_amount>=0),
  total_amount numeric(24,4) not null default 0 check(total_amount>=0),
  notes text check(notes is null or char_length(notes)<=4000),
  status public.purchase_document_status not null default 'draft',
  confirmation_idempotency_key text,
  posted_at timestamptz,
  posted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique(organization_id,id),
  unique(organization_id,document_number),
  unique(organization_id,confirmation_idempotency_key),
  foreign key(organization_id,supplier_party_id) references public.parties(organization_id,id),
  foreign key(organization_id,inventory_location_id) references public.inventory_locations(organization_id,id),
  foreign key(organization_id,cash_account_id) references public.accounts(organization_id,id),
  check(due_date>=invoice_date),
  check((payment_mode='cash' and cash_account_id is not null) or payment_mode='credit'),
  check((status='draft' and posted_at is null and posted_by is null) or
        (status<>'draft' and posted_at is not null and posted_by is not null))
);
create unique index purchase_supplier_invoice_unique on public.purchase_documents(
  organization_id,supplier_party_id,app_private.normalize_party_text(supplier_invoice_number)
) where supplier_invoice_number is not null and status<>'voided';
create index purchase_documents_org_date_idx on public.purchase_documents(organization_id,invoice_date desc,status);
create index purchase_documents_supplier_idx on public.purchase_documents(organization_id,supplier_party_id,status,due_date);

create table public.purchase_lines (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  purchase_id uuid not null,
  line_number integer not null check(line_number>0),
  line_kind public.purchase_line_kind not null,
  catalog_item_id uuid not null,
  description_snapshot text not null check(char_length(btrim(description_snapshot)) between 1 and 500),
  quantity numeric(24,8) not null check(quantity>0),
  unit_price numeric(24,8) not null check(unit_price>=0),
  line_discount_amount numeric(24,4) not null default 0 check(line_discount_amount>=0),
  line_additional_cost_amount numeric(24,4) not null default 0 check(line_additional_cost_amount>=0),
  base_amount numeric(24,4) not null check(base_amount>=0),
  posted_amount numeric(24,4),
  expense_account_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  unique(organization_id,id),
  unique(organization_id,purchase_id,line_number),
  foreign key(organization_id,purchase_id) references public.purchase_documents(organization_id,id),
  foreign key(organization_id,catalog_item_id) references public.products(organization_id,id),
  foreign key(organization_id,expense_account_id) references public.accounts(organization_id,id),
  check(line_discount_amount<=round(quantity*unit_price,4)),
  check((line_kind='product' and expense_account_id is null) or (line_kind='service' and expense_account_id is not null))
);
create index purchase_lines_purchase_idx on public.purchase_lines(organization_id,purchase_id,line_number);

create table public.purchase_posting_links (
  organization_id uuid not null references public.organizations(id),
  purchase_id uuid not null,
  purchase_line_id uuid not null,
  inventory_operation_id uuid,
  journal_entry_id uuid not null,
  created_at timestamptz not null default now(),
  primary key(organization_id,purchase_line_id),
  foreign key(organization_id,purchase_id) references public.purchase_documents(organization_id,id),
  foreign key(organization_id,purchase_line_id) references public.purchase_lines(organization_id,id),
  foreign key(organization_id,inventory_operation_id) references public.inventory_operations(organization_id,id),
  foreign key(organization_id,journal_entry_id) references public.journal_entries(organization_id,id)
);

create table public.supplier_payments (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  payment_number text not null,
  supplier_party_id uuid not null,
  payment_date date not null,
  amount numeric(24,4) not null check(amount>0),
  cash_account_id uuid not null,
  source_reference text,
  idempotency_key text not null check(char_length(idempotency_key) between 8 and 200),
  request_fingerprint text not null,
  journal_entry_id uuid not null,
  posted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  unique(organization_id,id),
  unique(organization_id,payment_number),
  unique(organization_id,idempotency_key),
  foreign key(organization_id,supplier_party_id) references public.parties(organization_id,id),
  foreign key(organization_id,cash_account_id) references public.accounts(organization_id,id),
  foreign key(organization_id,journal_entry_id) references public.journal_entries(organization_id,id)
);

create table public.supplier_payment_allocations (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  payment_id uuid not null,
  purchase_id uuid not null,
  allocated_amount numeric(24,4) not null check(allocated_amount>0),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  unique(organization_id,id),
  unique(organization_id,payment_id,purchase_id),
  foreign key(organization_id,payment_id) references public.supplier_payments(organization_id,id),
  foreign key(organization_id,purchase_id) references public.purchase_documents(organization_id,id)
);
create index supplier_allocations_purchase_idx on public.supplier_payment_allocations(organization_id,purchase_id);

create table public.purchase_credits (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  credit_number text not null,
  purchase_id uuid not null,
  credit_date date not null,
  reason text not null check(char_length(btrim(reason)) between 3 and 500),
  total_amount numeric(24,4) not null check(total_amount>0),
  idempotency_key text not null check(char_length(idempotency_key) between 8 and 200),
  request_fingerprint text not null,
  posted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  unique(organization_id,id),
  unique(organization_id,credit_number),
  unique(organization_id,idempotency_key),
  foreign key(organization_id,purchase_id) references public.purchase_documents(organization_id,id)
);

create table public.purchase_credit_lines (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  credit_id uuid not null,
  purchase_line_id uuid not null,
  quantity numeric(24,8) not null check(quantity>0),
  credit_amount numeric(24,4) not null check(credit_amount>0),
  inventory_operation_id uuid,
  journal_entry_id uuid,
  inventory_value numeric(24,4),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  unique(organization_id,id),
  unique(organization_id,credit_id,purchase_line_id),
  foreign key(organization_id,credit_id) references public.purchase_credits(organization_id,id),
  foreign key(organization_id,purchase_line_id) references public.purchase_lines(organization_id,id),
  foreign key(organization_id,inventory_operation_id) references public.inventory_operations(organization_id,id),
  foreign key(organization_id,journal_entry_id) references public.journal_entries(organization_id,id)
);
create index purchase_credit_lines_purchase_line_idx on public.purchase_credit_lines(organization_id,purchase_line_id);

create view public.purchase_open_items with (security_invoker=true) as
select p.organization_id,p.id as purchase_id,p.document_number,p.supplier_party_id,p.supplier_name_snapshot,p.invoice_date,p.due_date,
 p.total_amount,
 coalesce((select sum(a.allocated_amount) from public.supplier_payment_allocations a where a.organization_id=p.organization_id and a.purchase_id=p.id),0)::numeric(24,4) as paid_amount,
 coalesce((select sum(c.total_amount) from public.purchase_credits c where c.organization_id=p.organization_id and c.purchase_id=p.id),0)::numeric(24,4) as credited_amount,
 (p.total_amount
  -coalesce((select sum(a.allocated_amount) from public.supplier_payment_allocations a where a.organization_id=p.organization_id and a.purchase_id=p.id),0)
  -coalesce((select sum(c.total_amount) from public.purchase_credits c where c.organization_id=p.organization_id and c.purchase_id=p.id),0))::numeric(24,4) as outstanding_amount,
 p.status
from public.purchase_documents p where p.payment_mode='credit' and p.status not in ('draft','voided');

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
    return target_permission=any(array['members.read','audit.read','storage.read','storage.write','accounting.read','accounting.post','inventory.read','inventory.manage','parties.read','parties.manage','purchases.read','purchases.manage','purchases.pay']);
  end if;
  return target_permission=any(array['storage.read','storage.write','parties.read']);
end; $$;

create function app_private.require_purchase_permission(target_organization_id uuid,target_permission text)
returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not app_private.has_permission(target_organization_id,target_permission) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
end; $$;

create function app_private.next_purchase_number(target_organization_id uuid,target_kind public.purchase_number_kind,target_date date)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare next_value bigint; prefix text; target_year integer:=extract(year from target_date)::integer;
begin
  insert into public.purchase_number_counters(organization_id,number_kind,number_year,last_number)
  values(target_organization_id,target_kind,target_year,1)
  on conflict(organization_id,number_kind,number_year) do update set last_number=purchase_number_counters.last_number+1,updated_at=now()
  returning last_number into next_value;
  prefix:=case target_kind when 'purchase' then 'PUR' when 'payment' then 'PAY' else 'PCR' end;
  return prefix||'-'||target_year::text||'-'||lpad(next_value::text,6,'0');
end; $$;

create function app_private.purchase_outstanding(target_organization_id uuid,target_purchase_id uuid,target_as_of date default null)
returns numeric language sql stable security definer set search_path=public,pg_temp as $$
  select (p.total_amount
    -coalesce((select sum(a.allocated_amount) from public.supplier_payment_allocations a join public.supplier_payments sp
      on sp.organization_id=a.organization_id and sp.id=a.payment_id where a.organization_id=p.organization_id and a.purchase_id=p.id
      and (target_as_of is null or sp.payment_date<=target_as_of)),0)
    -coalesce((select sum(c.total_amount) from public.purchase_credits c where c.organization_id=p.organization_id and c.purchase_id=p.id
      and (target_as_of is null or c.credit_date<=target_as_of)),0))::numeric(24,4)
  from public.purchase_documents p where p.organization_id=target_organization_id and p.id=target_purchase_id
$$;

create function app_private.refresh_purchase_status(target_organization_id uuid,target_purchase_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare remaining numeric; original numeric; credited numeric; paid numeric; mode public.purchase_payment_mode;
begin
  select total_amount,payment_mode into original,mode from public.purchase_documents where organization_id=target_organization_id and id=target_purchase_id;
  remaining:=app_private.purchase_outstanding(target_organization_id,target_purchase_id,null);
  select coalesce(sum(total_amount),0) into credited from public.purchase_credits where organization_id=target_organization_id and purchase_id=target_purchase_id;
  select coalesce(sum(a.allocated_amount),0) into paid from public.supplier_payment_allocations a where a.organization_id=target_organization_id and a.purchase_id=target_purchase_id;
  update public.purchase_documents set status=case
    when remaining=0 and credited=original and paid=0 then 'credited'::public.purchase_document_status
    when mode='cash' then 'paid'::public.purchase_document_status
    when remaining=0 then 'paid'::public.purchase_document_status
    when remaining<original then 'partially_paid'::public.purchase_document_status
    else 'posted'::public.purchase_document_status end,updated_at=now()
  where organization_id=target_organization_id and id=target_purchase_id and status not in ('draft','voided');
end; $$;

create function app_private.guard_purchase_history()
returns trigger language plpgsql as $$
begin
  if tg_op='DELETE' then raise exception using errcode='P0001',message='purchase_history_deletion_forbidden'; end if;
  return new;
end; $$;
create trigger purchase_document_history_guard before delete on public.purchase_documents for each row execute function app_private.guard_purchase_history();
create trigger purchase_line_history_guard before delete on public.purchase_lines for each row execute function app_private.guard_purchase_history();
create trigger supplier_payment_history_guard before update or delete on public.supplier_payments for each row execute function app_private.guard_purchase_history();
create trigger supplier_allocation_history_guard before update or delete on public.supplier_payment_allocations for each row execute function app_private.guard_purchase_history();
create trigger purchase_credit_history_guard before update or delete on public.purchase_credits for each row execute function app_private.guard_purchase_history();
create trigger purchase_credit_line_history_guard before update or delete on public.purchase_credit_lines for each row execute function app_private.guard_purchase_history();

create function public.create_purchase_draft(target_organization_id uuid,target_supplier_party_id uuid,target_supplier_invoice_number text,
  target_invoice_date date,target_due_date date,target_payment_mode public.purchase_payment_mode,target_inventory_location_id uuid,
  target_cash_account_id uuid,target_document_discount_amount numeric,target_additional_cost_amount numeric,target_notes text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid; number text; supplier public.parties%rowtype; terms integer; address_snapshot text; account public.accounts%rowtype;
begin
  perform app_private.require_purchase_permission(target_organization_id,'purchases.manage');
  select p.* into supplier from public.parties p join public.party_roles r on r.organization_id=p.organization_id and r.party_id=p.id
   where p.organization_id=target_organization_id and p.id=target_supplier_party_id and p.status='active' and r.role_kind='supplier' and r.status='active';
  if not found then raise exception using errcode='23503',message='active_supplier_required'; end if;
  select payment_term_days into terms from public.party_roles where organization_id=target_organization_id and party_id=target_supplier_party_id and role_kind='supplier' and status='active';
  select concat_ws(', ',address_line_1,address_line_2,city,province,postal_code,country_code) into address_snapshot
   from public.party_addresses where organization_id=target_organization_id and party_id=target_supplier_party_id and status='active'
   order by is_primary desc,created_at limit 1;
  if target_due_date<target_invoice_date then raise exception using errcode='22023',message='invalid_purchase_due_date'; end if;
  if target_document_discount_amount<0 or target_additional_cost_amount<0 then raise exception using errcode='22023',message='invalid_purchase_adjustment'; end if;
  if target_payment_mode='cash' then
    select * into account from public.accounts where organization_id=target_organization_id and id=target_cash_account_id and status='active'
      and system_purpose in ('cash','bank');
    if not found then raise exception using errcode='23503',message='active_cash_bank_account_required'; end if;
  end if;
  if target_inventory_location_id is not null and not exists(select 1 from public.inventory_locations where organization_id=target_organization_id and id=target_inventory_location_id and status='active') then
    raise exception using errcode='23503',message='active_inventory_location_required';
  end if;
  number:=app_private.next_purchase_number(target_organization_id,'purchase',target_invoice_date);
  insert into public.purchase_documents(organization_id,document_number,supplier_party_id,supplier_invoice_number,supplier_name_snapshot,
    supplier_tax_identifier_snapshot,supplier_address_snapshot,payment_term_days_snapshot,invoice_date,due_date,payment_mode,
    inventory_location_id,cash_account_id,document_discount_amount,additional_cost_amount,notes,created_by,updated_by)
  values(target_organization_id,number,target_supplier_party_id,nullif(btrim(target_supplier_invoice_number),''),supplier.display_name,
    supplier.tax_identifier,address_snapshot,terms,target_invoice_date,target_due_date,target_payment_mode,target_inventory_location_id,
    case when target_payment_mode='cash' then target_cash_account_id else null end,target_document_discount_amount,target_additional_cost_amount,
    nullif(btrim(target_notes),''),actor,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'purchase.draft_created','purchase',created_id::text,jsonb_build_object('document_number',number,'payment_mode',target_payment_mode));
  return created_id;
end; $$;

create function public.add_purchase_line(target_organization_id uuid,target_purchase_id uuid,target_catalog_item_id uuid,
  target_quantity numeric,target_unit_price numeric,target_line_discount_amount numeric,target_line_additional_cost_amount numeric,
  target_expense_account_id uuid,target_description text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); purchase public.purchase_documents%rowtype; item public.products%rowtype; expense public.accounts%rowtype;
  created_id uuid; next_line integer; base numeric(24,4); kind public.purchase_line_kind;
begin
  perform app_private.require_purchase_permission(target_organization_id,'purchases.manage');
  select * into purchase from public.purchase_documents where organization_id=target_organization_id and id=target_purchase_id for update;
  if not found or purchase.status<>'draft' then raise exception using errcode='23514',message='editable_purchase_draft_required'; end if;
  select * into item from public.products where organization_id=target_organization_id and id=target_catalog_item_id and status='active';
  if not found then raise exception using errcode='23503',message='active_catalog_item_required'; end if;
  kind:=item.item_kind::text::public.purchase_line_kind;
  if kind='product' and not item.inventory_tracked then raise exception using errcode='23514',message='purchase_product_must_track_inventory'; end if;
  if kind='service' then
    select * into expense from public.accounts where organization_id=target_organization_id and id=target_expense_account_id and status='active' and category='expense';
    if not found then raise exception using errcode='23503',message='active_service_expense_account_required'; end if;
  end if;
  if target_quantity<=0 or target_quantity<>round(target_quantity,8) or target_unit_price<0 or target_unit_price<>round(target_unit_price,8) then
    raise exception using errcode='22023',message='invalid_purchase_line_amount'; end if;
  base:=round(target_quantity*target_unit_price,4)-target_line_discount_amount+target_line_additional_cost_amount;
  if target_line_discount_amount<0 or target_line_additional_cost_amount<0 or base<=0 then raise exception using errcode='22023',message='invalid_purchase_line_adjustment'; end if;
  select coalesce(max(line_number),0)+1 into next_line from public.purchase_lines where organization_id=target_organization_id and purchase_id=target_purchase_id;
  insert into public.purchase_lines(organization_id,purchase_id,line_number,line_kind,catalog_item_id,description_snapshot,quantity,unit_price,
    line_discount_amount,line_additional_cost_amount,base_amount,expense_account_id,created_by)
  values(target_organization_id,target_purchase_id,next_line,kind,target_catalog_item_id,coalesce(nullif(btrim(target_description),''),item.name),
    target_quantity,target_unit_price,target_line_discount_amount,target_line_additional_cost_amount,base,
    case when kind='service' then target_expense_account_id else null end,actor) returning id into created_id;
  return created_id;
end; $$;

create function public.confirm_purchase(target_organization_id uuid,target_purchase_id uuid,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); purchase public.purchase_documents%rowtype; line public.purchase_lines%rowtype; ap_account uuid; offset_account uuid;
  line_count integer; subtotal numeric(24,4); total numeric(24,4); allocated numeric(24,4):=0; line_amount numeric(24,4); line_index integer:=0;
  operation_id uuid; journal_id uuid; inventory_journal uuid; unit_cost numeric(24,8); journal_lines jsonb;
begin
  perform app_private.require_purchase_permission(target_organization_id,'purchases.manage');
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':purchase-confirm:'||target_idempotency_key,0));
  select * into purchase from public.purchase_documents where organization_id=target_organization_id and id=target_purchase_id for update;
  if not found then raise exception using errcode='23503',message='purchase_not_found'; end if;
  if purchase.status<>'draft' then
    if purchase.confirmation_idempotency_key=target_idempotency_key then return purchase.id; end if;
    raise exception using errcode='23514',message='purchase_already_confirmed';
  end if;
  if exists(select 1 from public.purchase_documents where organization_id=target_organization_id and confirmation_idempotency_key=target_idempotency_key and id<>target_purchase_id) then
    raise exception using errcode='23505',message='purchase_idempotency_key_reused'; end if;
  if not exists(select 1 from public.parties p join public.party_roles r on r.organization_id=p.organization_id and r.party_id=p.id
    where p.organization_id=target_organization_id and p.id=purchase.supplier_party_id and p.status='active' and r.role_kind='supplier' and r.status='active') then
    raise exception using errcode='23503',message='active_supplier_required'; end if;
  select count(*),coalesce(sum(base_amount),0) into line_count,subtotal from public.purchase_lines where organization_id=target_organization_id and purchase_id=target_purchase_id;
  if line_count=0 or subtotal<=0 or purchase.document_discount_amount>subtotal then raise exception using errcode='23514',message='valid_purchase_lines_required'; end if;
  total:=subtotal-purchase.document_discount_amount+purchase.additional_cost_amount;
  if total<=0 then raise exception using errcode='23514',message='positive_purchase_total_required'; end if;
  if exists(select 1 from public.purchase_lines where organization_id=target_organization_id and purchase_id=target_purchase_id and line_kind='product')
    and purchase.inventory_location_id is null then raise exception using errcode='23503',message='inventory_location_required'; end if;
  select id into ap_account from public.accounts where organization_id=target_organization_id and system_purpose='accounts_payable' and status='active';
  if ap_account is null then raise exception using errcode='23503',message='active_accounts_payable_account_required'; end if;
  offset_account:=case when purchase.payment_mode='cash' then purchase.cash_account_id else ap_account end;
  for line in select * from public.purchase_lines where organization_id=target_organization_id and purchase_id=target_purchase_id order by line_number,id loop
    line_index:=line_index+1;
    line_amount:=case when line_index=line_count then total-allocated else round(line.base_amount*total/subtotal,4) end;
    allocated:=allocated+line_amount;
    update public.purchase_lines set posted_amount=line_amount where id=line.id;
    if line.line_kind='product' then
      unit_cost:=round(line_amount/line.quantity,8);
      operation_id:=app_private.post_inventory_movement_internal(actor,target_organization_id,line.catalog_item_id,purchase.inventory_location_id,
        purchase.invoice_date,'stock_in',line.quantity,unit_cost,offset_account,'Purchase '||purchase.document_number,'purchase',purchase.document_number,
        'purchase:'||purchase.id::text||':line:'||line.id::text,'stock_in');
      select journal_entry_id into inventory_journal from public.inventory_operations where organization_id=target_organization_id and id=operation_id;
      insert into public.purchase_posting_links(organization_id,purchase_id,purchase_line_id,inventory_operation_id,journal_entry_id)
      values(target_organization_id,purchase.id,line.id,operation_id,inventory_journal);
    else
      journal_lines:=jsonb_build_array(
        jsonb_build_object('account_id',line.expense_account_id,'debit',line_amount::text,'credit','0','description',line.description_snapshot),
        jsonb_build_object('account_id',offset_account,'debit','0','credit',line_amount::text,'description',line.description_snapshot));
      journal_id:=app_private.post_journal_internal(actor,target_organization_id,purchase.invoice_date,'Purchase: '||purchase.document_number,
        purchase.id::text,journal_lines,'purchase:'||purchase.id::text||':service:'||line.id::text,'system',null);
      insert into public.purchase_posting_links(organization_id,purchase_id,purchase_line_id,journal_entry_id)
      values(target_organization_id,purchase.id,line.id,journal_id);
    end if;
  end loop;
  update public.purchase_documents set subtotal_amount=subtotal,total_amount=total,status=case when payment_mode='cash' then 'paid'::public.purchase_document_status else 'posted'::public.purchase_document_status end,
    confirmation_idempotency_key=target_idempotency_key,posted_at=now(),posted_by=actor,updated_at=now(),updated_by=actor
   where organization_id=target_organization_id and id=target_purchase_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'purchase.confirmed','purchase',target_purchase_id::text,
    jsonb_build_object('document_number',purchase.document_number,'total_amount',total,'payment_mode',purchase.payment_mode));
  return target_purchase_id;
end; $$;

create function public.post_supplier_payment(target_organization_id uuid,target_supplier_party_id uuid,target_payment_date date,
  target_cash_account_id uuid,target_source_reference text,target_allocations jsonb,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); existing public.supplier_payments%rowtype; allocation jsonb; invoice public.purchase_documents%rowtype;
  payment_id uuid; journal_id uuid; ap_account uuid; total numeric(24,4); amount numeric(24,4); outstanding numeric(24,4);
  number text; fingerprint text; lines jsonb;
begin
  perform app_private.require_purchase_permission(target_organization_id,'purchases.pay');
  if jsonb_typeof(target_allocations)<>'array' or jsonb_array_length(target_allocations)=0 then raise exception using errcode='22023',message='payment_allocations_required'; end if;
  fingerprint:=encode(extensions.digest(concat_ws('|',target_supplier_party_id,target_payment_date,target_cash_account_id,target_source_reference,target_allocations::text),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':supplier-payment:'||target_idempotency_key,0));
  select * into existing from public.supplier_payments where organization_id=target_organization_id and idempotency_key=target_idempotency_key;
  if found then
    if existing.request_fingerprint<>fingerprint then raise exception using errcode='23505',message='idempotency_payload_mismatch'; end if;
    return existing.id;
  end if;
  if not exists(select 1 from public.parties p join public.party_roles r on r.organization_id=p.organization_id and r.party_id=p.id
    where p.organization_id=target_organization_id and p.id=target_supplier_party_id and p.status='active' and r.role_kind='supplier' and r.status='active') then
    raise exception using errcode='23503',message='active_supplier_required'; end if;
  if not exists(select 1 from public.accounts where organization_id=target_organization_id and id=target_cash_account_id and status='active'
    and system_purpose in ('cash','bank')) then
    raise exception using errcode='23503',message='active_cash_bank_account_required'; end if;
  select id into ap_account from public.accounts where organization_id=target_organization_id and system_purpose='accounts_payable' and status='active';
  total:=0;
  for allocation in select value from jsonb_array_elements(target_allocations) loop
    amount:=(allocation->>'amount')::numeric;
    if amount<=0 or amount<>round(amount,4) then raise exception using errcode='22023',message='invalid_payment_allocation'; end if;
    perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':purchase-settlement:'||(allocation->>'purchase_id'),0));
    select * into invoice from public.purchase_documents where organization_id=target_organization_id and id=(allocation->>'purchase_id')::uuid for update;
    if not found or invoice.supplier_party_id<>target_supplier_party_id or invoice.payment_mode<>'credit' or invoice.status in ('draft','voided','paid','credited') then
      raise exception using errcode='23503',message='open_supplier_invoice_required'; end if;
    outstanding:=app_private.purchase_outstanding(target_organization_id,invoice.id,null);
    if amount>outstanding then raise exception using errcode='23514',message='payment_allocation_exceeds_outstanding'; end if;
    total:=total+amount;
  end loop;
  if (select count(*) from (select value->>'purchase_id' id from jsonb_array_elements(target_allocations) group by value->>'purchase_id') x)<>jsonb_array_length(target_allocations) then
    raise exception using errcode='23505',message='duplicate_payment_invoice_allocation'; end if;
  number:=app_private.next_purchase_number(target_organization_id,'payment',target_payment_date);
  lines:=jsonb_build_array(jsonb_build_object('account_id',ap_account,'debit',total::text,'credit','0','description','Supplier payment '||number),
    jsonb_build_object('account_id',target_cash_account_id,'debit','0','credit',total::text,'description','Supplier payment '||number));
  journal_id:=app_private.post_journal_internal(actor,target_organization_id,target_payment_date,'Supplier payment: '||number,
    number,lines,'supplier-payment:'||target_idempotency_key,'system',null);
  insert into public.supplier_payments(organization_id,payment_number,supplier_party_id,payment_date,amount,cash_account_id,source_reference,
    idempotency_key,request_fingerprint,journal_entry_id,created_by)
  values(target_organization_id,number,target_supplier_party_id,target_payment_date,total,target_cash_account_id,nullif(btrim(target_source_reference),''),
    target_idempotency_key,fingerprint,journal_id,actor) returning id into payment_id;
  for allocation in select value from jsonb_array_elements(target_allocations) loop
    insert into public.supplier_payment_allocations(organization_id,payment_id,purchase_id,allocated_amount,created_by)
    values(target_organization_id,payment_id,(allocation->>'purchase_id')::uuid,(allocation->>'amount')::numeric,actor);
    perform app_private.refresh_purchase_status(target_organization_id,(allocation->>'purchase_id')::uuid);
  end loop;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'purchase.payment_posted','supplier_payment',payment_id::text,
    jsonb_build_object('payment_number',number,'amount',total,'allocation_count',jsonb_array_length(target_allocations)));
  return payment_id;
end; $$;

create function public.post_purchase_credit(target_organization_id uuid,target_purchase_id uuid,target_credit_date date,target_reason text,
  target_lines jsonb,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); purchase public.purchase_documents%rowtype; original_line public.purchase_lines%rowtype; item jsonb;
  existing public.purchase_credits%rowtype; credit_id uuid; number text; fingerprint text; ap_account uuid; variance_account uuid;
  quantity numeric(24,8); credit_amount numeric(24,4); total numeric(24,4):=0; prior_quantity numeric(24,8);
  returned_operation_id uuid; inventory_journal uuid; inventory_value numeric(24,4); difference numeric(24,4); journal_id uuid; lines jsonb;
begin
  perform app_private.require_purchase_permission(target_organization_id,'purchases.manage');
  if jsonb_typeof(target_lines)<>'array' or jsonb_array_length(target_lines)=0 then raise exception using errcode='22023',message='credit_lines_required'; end if;
  fingerprint:=encode(extensions.digest(concat_ws('|',target_purchase_id,target_credit_date,target_reason,target_lines::text),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':purchase-credit:'||target_idempotency_key,0));
  select * into existing from public.purchase_credits where organization_id=target_organization_id and idempotency_key=target_idempotency_key;
  if found then
    if existing.request_fingerprint<>fingerprint then raise exception using errcode='23505',message='idempotency_payload_mismatch'; end if;
    return existing.id;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text||':purchase-settlement:'||target_purchase_id::text,0));
  select * into purchase from public.purchase_documents where organization_id=target_organization_id and id=target_purchase_id for update;
  if not found or purchase.status in ('draft','voided','credited') or (purchase.payment_mode='credit' and purchase.status='paid') then
    raise exception using errcode='23514',message='returnable_purchase_required'; end if;
  if purchase.payment_mode='cash' then
    ap_account:=purchase.cash_account_id;
  else
    select id into ap_account from public.accounts where organization_id=target_organization_id and system_purpose='accounts_payable' and status='active';
  end if;
  select id into variance_account from public.accounts where organization_id=target_organization_id and system_purpose='operating_expense' and status='active';
  if ap_account is null or variance_account is null then raise exception using errcode='23503',message='purchase_return_accounts_required'; end if;
  for item in select value from jsonb_array_elements(target_lines) loop
    select * into original_line from public.purchase_lines where organization_id=target_organization_id and id=(item->>'purchase_line_id')::uuid and purchase_id=target_purchase_id;
    if not found then raise exception using errcode='23503',message='purchase_credit_line_reference_required'; end if;
    quantity:=(item->>'quantity')::numeric; credit_amount:=(item->>'credit_amount')::numeric;
    if quantity<=0 or quantity<>round(quantity,8) or credit_amount<=0 or credit_amount<>round(credit_amount,4) then
      raise exception using errcode='22023',message='invalid_purchase_credit_line'; end if;
    select coalesce(sum(cl.quantity),0) into prior_quantity from public.purchase_credit_lines cl join public.purchase_credits c
      on c.organization_id=cl.organization_id and c.id=cl.credit_id where cl.organization_id=target_organization_id and cl.purchase_line_id=original_line.id;
    if prior_quantity+quantity>original_line.quantity then raise exception using errcode='23514',message='purchase_return_quantity_exceeded'; end if;
    total:=total+credit_amount;
  end loop;
  if total>app_private.purchase_outstanding(target_organization_id,target_purchase_id,null) then
    raise exception using errcode='23514',message='purchase_credit_exceeds_outstanding'; end if;
  number:=app_private.next_purchase_number(target_organization_id,'credit',target_credit_date);
  insert into public.purchase_credits(organization_id,credit_number,purchase_id,credit_date,reason,total_amount,idempotency_key,request_fingerprint,created_by)
  values(target_organization_id,number,target_purchase_id,target_credit_date,btrim(target_reason),total,target_idempotency_key,fingerprint,actor) returning id into credit_id;
  for item in select value from jsonb_array_elements(target_lines) loop
    select * into original_line from public.purchase_lines where organization_id=target_organization_id and id=(item->>'purchase_line_id')::uuid;
    quantity:=(item->>'quantity')::numeric; credit_amount:=(item->>'credit_amount')::numeric;
    returned_operation_id:=null; journal_id:=null; inventory_value:=null;
    if original_line.line_kind='product' then
      returned_operation_id:=app_private.post_inventory_movement_internal(actor,target_organization_id,original_line.catalog_item_id,purchase.inventory_location_id,
        target_credit_date,'stock_out',quantity,null,ap_account,'Supplier credit '||number,'purchase_credit',number,
        'purchase-credit:'||credit_id::text||':line:'||original_line.id::text,'stock_out');
      select journal_entry_id into inventory_journal from public.inventory_operations where organization_id=target_organization_id and id=returned_operation_id;
      select abs(im.value_delta) into inventory_value from public.inventory_movements im
       where im.organization_id=target_organization_id and im.operation_id=returned_operation_id;
      difference:=credit_amount-inventory_value;
      if difference<>0 then
        lines:=case when difference>0 then jsonb_build_array(
          jsonb_build_object('account_id',ap_account,'debit',difference::text,'credit','0','description','Purchase return variance '||number),
          jsonb_build_object('account_id',variance_account,'debit','0','credit',difference::text,'description','Purchase return variance '||number))
        else jsonb_build_array(
          jsonb_build_object('account_id',variance_account,'debit',abs(difference)::text,'credit','0','description','Purchase return variance '||number),
          jsonb_build_object('account_id',ap_account,'debit','0','credit',abs(difference)::text,'description','Purchase return variance '||number)) end;
        journal_id:=app_private.post_journal_internal(actor,target_organization_id,target_credit_date,'Purchase return variance: '||number,
          credit_id::text,lines,'purchase-credit-variance:'||credit_id::text||':'||original_line.id::text,'system',null);
      else journal_id:=inventory_journal; end if;
    else
      lines:=jsonb_build_array(jsonb_build_object('account_id',ap_account,'debit',credit_amount::text,'credit','0','description','Supplier credit '||number),
        jsonb_build_object('account_id',original_line.expense_account_id,'debit','0','credit',credit_amount::text,'description','Supplier credit '||number));
      journal_id:=app_private.post_journal_internal(actor,target_organization_id,target_credit_date,'Supplier credit: '||number,
        credit_id::text,lines,'purchase-credit:'||credit_id::text||':'||original_line.id::text,'system',null);
    end if;
    insert into public.purchase_credit_lines(organization_id,credit_id,purchase_line_id,quantity,credit_amount,inventory_operation_id,journal_entry_id,inventory_value,created_by)
    values(target_organization_id,credit_id,original_line.id,quantity,credit_amount,returned_operation_id,journal_id,inventory_value,actor);
  end loop;
  perform app_private.refresh_purchase_status(target_organization_id,target_purchase_id);
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'purchase.credit_posted','purchase_credit',credit_id::text,
    jsonb_build_object('credit_number',number,'purchase_id',target_purchase_id,'amount',total));
  return credit_id;
end; $$;

create function public.get_ap_aging(target_organization_id uuid,target_as_of_date date)
returns table(purchase_id uuid,document_number text,supplier_party_id uuid,supplier_name text,invoice_date date,due_date date,
  original_amount numeric,paid_amount numeric,credited_amount numeric,outstanding_amount numeric,days_overdue integer,aging_bucket text)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  perform app_private.require_purchase_permission(target_organization_id,'purchases.read');
  return query select p.id,p.document_number,p.supplier_party_id,p.supplier_name_snapshot,p.invoice_date,p.due_date,p.total_amount,
    coalesce((select sum(a.allocated_amount) from public.supplier_payment_allocations a join public.supplier_payments sp
      on sp.organization_id=a.organization_id and sp.id=a.payment_id where a.organization_id=p.organization_id and a.purchase_id=p.id and sp.payment_date<=target_as_of_date),0)::numeric,
    coalesce((select sum(c.total_amount) from public.purchase_credits c where c.organization_id=p.organization_id and c.purchase_id=p.id and c.credit_date<=target_as_of_date),0)::numeric,
    app_private.purchase_outstanding(p.organization_id,p.id,target_as_of_date),
    greatest(target_as_of_date-p.due_date,0),
    case when target_as_of_date<=p.due_date then 'current' when target_as_of_date-p.due_date<=30 then '1_30'
      when target_as_of_date-p.due_date<=60 then '31_60' when target_as_of_date-p.due_date<=90 then '61_90' else 'over_90' end
  from public.purchase_documents p where p.organization_id=target_organization_id and p.payment_mode='credit'
    and p.status not in ('draft','voided') and p.invoice_date<=target_as_of_date
    and app_private.purchase_outstanding(p.organization_id,p.id,target_as_of_date)>0 order by p.due_date,p.document_number;
end; $$;

alter table public.purchase_number_counters enable row level security;
alter table public.purchase_documents enable row level security;
alter table public.purchase_lines enable row level security;
alter table public.purchase_posting_links enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.supplier_payment_allocations enable row level security;
alter table public.purchase_credits enable row level security;
alter table public.purchase_credit_lines enable row level security;
create policy purchase_counters_read on public.purchase_number_counters for select to authenticated using(app_private.has_permission(organization_id,'purchases.read'));
create policy purchase_documents_read on public.purchase_documents for select to authenticated using(app_private.has_permission(organization_id,'purchases.read'));
create policy purchase_lines_read on public.purchase_lines for select to authenticated using(app_private.has_permission(organization_id,'purchases.read'));
create policy purchase_posting_links_read on public.purchase_posting_links for select to authenticated using(app_private.has_permission(organization_id,'purchases.read'));
create policy supplier_payments_read on public.supplier_payments for select to authenticated using(app_private.has_permission(organization_id,'purchases.read'));
create policy supplier_allocations_read on public.supplier_payment_allocations for select to authenticated using(app_private.has_permission(organization_id,'purchases.read'));
create policy purchase_credits_read on public.purchase_credits for select to authenticated using(app_private.has_permission(organization_id,'purchases.read'));
create policy purchase_credit_lines_read on public.purchase_credit_lines for select to authenticated using(app_private.has_permission(organization_id,'purchases.read'));

revoke all on public.purchase_number_counters,public.purchase_documents,public.purchase_lines,public.purchase_posting_links,
 public.supplier_payments,public.supplier_payment_allocations,public.purchase_credits,public.purchase_credit_lines from public,anon;
grant select on public.purchase_number_counters,public.purchase_documents,public.purchase_lines,public.purchase_posting_links,
 public.supplier_payments,public.supplier_payment_allocations,public.purchase_credits,public.purchase_credit_lines,public.purchase_open_items to authenticated;
revoke insert,update,delete on public.purchase_number_counters,public.purchase_documents,public.purchase_lines,public.purchase_posting_links,
 public.supplier_payments,public.supplier_payment_allocations,public.purchase_credits,public.purchase_credit_lines from authenticated;
revoke all on function app_private.require_purchase_permission(uuid,text),app_private.next_purchase_number(uuid,public.purchase_number_kind,date),
 app_private.purchase_outstanding(uuid,uuid,date),app_private.refresh_purchase_status(uuid,uuid),app_private.guard_purchase_history() from public,anon,authenticated;
grant execute on function public.create_purchase_draft(uuid,uuid,text,date,date,public.purchase_payment_mode,uuid,uuid,numeric,numeric,text) to authenticated;
grant execute on function public.add_purchase_line(uuid,uuid,uuid,numeric,numeric,numeric,numeric,uuid,text) to authenticated;
grant execute on function public.confirm_purchase(uuid,uuid,text) to authenticated;
grant execute on function public.post_supplier_payment(uuid,uuid,date,uuid,text,jsonb,text) to authenticated;
grant execute on function public.post_purchase_credit(uuid,uuid,date,text,jsonb,text) to authenticated;
grant execute on function public.get_ap_aging(uuid,date) to authenticated;

commit;
