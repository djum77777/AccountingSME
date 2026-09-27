begin;

create type public.account_category as enum ('asset','liability','equity','income','expense');
create type public.normal_balance as enum ('debit','credit');
create type public.account_status as enum ('active','inactive');
create type public.accounting_period_status as enum ('open','closed');
create type public.journal_status as enum ('draft','posted','reversed');
create type public.journal_kind as enum ('manual','opening','reversal','system');

create table public.currencies (
  code text primary key check (code ~ '^[A-Z]{3}$'),
  name text not null,
  minor_unit smallint not null check (minor_unit between 0 and 4),
  is_active boolean not null default true
);

insert into public.currencies(code,name,minor_unit) values
('IDR','Indonesian Rupiah',0),('USD','US Dollar',2),('EUR','Euro',2),
('SGD','Singapore Dollar',2),('MYR','Malaysian Ringgit',2),('AUD','Australian Dollar',2),
('JPY','Japanese Yen',0),('CNY','Chinese Yuan',2),('GBP','Pound Sterling',2)
on conflict do nothing;
insert into public.currencies(code,name,minor_unit)
select distinct base_currency_code, base_currency_code || ' (organization currency)', 2
from public.organizations on conflict do nothing;

create table public.accounting_template_accounts (
  template_key text not null references public.business_templates(template_key),
  code text not null,
  name_id text not null,
  name_en text not null,
  category public.account_category not null,
  normal_balance public.normal_balance not null,
  parent_code text,
  system_purpose text,
  is_control_account boolean not null default false,
  is_active_by_default boolean not null default true,
  sort_order integer not null,
  primary key(template_key,code),
  unique(template_key,system_purpose)
);

create table public.accounting_profiles (
  organization_id uuid primary key references public.organizations(id),
  template_key text not null references public.business_templates(template_key),
  template_version integer not null default 1,
  amount_scale smallint not null default 4 check(amount_scale=4),
  initialized_at timestamptz not null default now(),
  initialized_by uuid not null references auth.users(id)
);

create table public.accounts (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code text not null check(code ~ '^[A-Z0-9][A-Z0-9.-]{0,19}$'),
  name text not null check(char_length(btrim(name)) between 1 and 120),
  category public.account_category not null,
  normal_balance public.normal_balance not null,
  parent_account_id uuid,
  system_purpose text,
  is_control_account boolean not null default false,
  status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(organization_id,code), unique(organization_id,system_purpose),
  foreign key(organization_id,parent_account_id) references public.accounts(organization_id,id)
);

create table public.accounting_periods (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  name text not null check(char_length(btrim(name)) between 1 and 80),
  starts_on date not null,
  ends_on date not null,
  status public.accounting_period_status not null default 'open',
  closed_at timestamptz, closed_by uuid references auth.users(id), close_reason text,
  reopened_at timestamptz, reopened_by uuid references auth.users(id), reopen_reason text,
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(organization_id,name), check(starts_on<=ends_on)
);

create table public.journal_entries (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  period_id uuid not null,
  entry_number bigint generated always as identity,
  accounting_date date not null,
  description text not null check(char_length(btrim(description)) between 1 and 500),
  kind public.journal_kind not null,
  status public.journal_status not null default 'draft',
  currency_code text not null references public.currencies(code),
  source_reference text,
  idempotency_key text not null check(char_length(idempotency_key) between 8 and 200),
  request_fingerprint text not null,
  reversal_of_id uuid,
  reversal_entry_id uuid,
  total_debit numeric(20,4) not null default 0,
  total_credit numeric(20,4) not null default 0,
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  posted_at timestamptz, posted_by uuid references auth.users(id),
  reversed_at timestamptz, reversed_by uuid references auth.users(id),
  unique(organization_id,id), unique(organization_id,idempotency_key),
  foreign key(organization_id,period_id) references public.accounting_periods(organization_id,id),
  foreign key(organization_id,reversal_of_id) references public.journal_entries(organization_id,id),
  foreign key(organization_id,reversal_entry_id) references public.journal_entries(organization_id,id),
  check(total_debit>=0 and total_credit>=0)
);

create table public.journal_lines (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  journal_entry_id uuid not null,
  line_number integer not null check(line_number>0),
  account_id uuid not null,
  description text,
  debit numeric(20,4) not null default 0,
  credit numeric(20,4) not null default 0,
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(journal_entry_id,line_number),
  foreign key(organization_id,journal_entry_id) references public.journal_entries(organization_id,id),
  foreign key(organization_id,account_id) references public.accounts(organization_id,id),
  check((debit>0 and credit=0) or (credit>0 and debit=0))
);

create table public.opening_balance_batches (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  journal_entry_id uuid not null,
  idempotency_key text not null,
  description text not null,
  posted_at timestamptz not null default now(), posted_by uuid not null references auth.users(id),
  unique(organization_id,id), unique(organization_id,idempotency_key),
  foreign key(organization_id,journal_entry_id) references public.journal_entries(organization_id,id)
);

create index accounts_org_status_idx on public.accounts(organization_id,status,code);
create index periods_org_dates_idx on public.accounting_periods(organization_id,starts_on,ends_on);
create index journals_org_date_idx on public.journal_entries(organization_id,accounting_date,entry_number);
create index lines_journal_idx on public.journal_lines(organization_id,journal_entry_id,line_number);
create index lines_account_idx on public.journal_lines(organization_id,account_id);

-- Same stable account codes across templates; templates choose which operational accounts are initially active.
insert into public.accounting_template_accounts
(template_key,code,name_id,name_en,category,normal_balance,parent_code,system_purpose,is_control_account,is_active_by_default,sort_order)
select template_key, account.code, account.name_id, account.name_en,
       account.category::public.account_category, account.normal_balance::public.normal_balance,
       account.parent_code, account.system_purpose, account.is_control,
       not(coalesce(account.system_purpose in ('inventory','cost_of_goods_sold'),false) and template_key in ('general_sme','service')),
       account.sort_order
from (values ('general_sme'),('retail'),('online_seller'),('trading_distributor'),('service')) templates(template_key)
cross join (values
 ('1000','Aset','Assets','asset','debit',null,null,false,100),
 ('1100','Kas','Cash','asset','debit','1000','cash',true,110),
 ('1110','Bank','Bank','asset','debit','1000','bank',true,120),
 ('1200','Piutang Usaha','Accounts Receivable','asset','debit','1000','accounts_receivable',true,130),
 ('1300','Persediaan','Inventory','asset','debit','1000','inventory',true,140),
 ('2000','Liabilitas','Liabilities','liability','credit',null,null,false,200),
 ('2100','Utang Usaha','Accounts Payable','liability','credit','2000','accounts_payable',true,210),
 ('2200','Utang Pajak','Taxes Payable','liability','credit','2000','taxes_payable',true,220),
 ('3000','Ekuitas','Equity','equity','credit',null,null,false,300),
 ('3100','Modal Pemilik','Owner Capital','equity','credit','3000','owner_capital',true,310),
 ('3200','Laba Ditahan','Retained Earnings','equity','credit','3000','retained_earnings',true,320),
 ('4000','Pendapatan','Income','income','credit',null,null,false,400),
 ('4100','Pendapatan Penjualan','Sales Revenue','income','credit','4000','sales_revenue',false,410),
 ('4200','Pendapatan Jasa','Service Revenue','income','credit','4000','service_revenue',false,420),
 ('5000','Beban','Expenses','expense','debit',null,null,false,500),
 ('5100','Harga Pokok Penjualan','Cost of Goods Sold','expense','debit','5000','cost_of_goods_sold',true,510),
 ('5200','Beban Operasional','Operating Expenses','expense','debit','5000','operating_expense',false,520),
 ('5300','Beban Pajak','Tax Expense','expense','debit','5000','tax_expense',false,530)
) account(code,name_id,name_en,category,normal_balance,parent_code,system_purpose,is_control,sort_order);

create function app_private.require_accounting_permission(target_organization_id uuid,target_permission text)
returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not app_private.has_permission(target_organization_id,target_permission) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
end; $$;

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
    return target_permission=any(array['members.read','audit.read','storage.read','storage.write','accounting.read','accounting.post']);
  end if;
  return target_permission=any(array['storage.read','storage.write']);
end; $$;

create function app_private.guard_period_overlap()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.organization_id::text || ':period',0));
  if exists(select 1 from public.accounting_periods p where p.organization_id=new.organization_id and p.id<>new.id
    and daterange(p.starts_on,p.ends_on,'[]') && daterange(new.starts_on,new.ends_on,'[]')) then
    raise exception using errcode='23514',message='accounting_period_overlap';
  end if;
  return new;
end; $$;
create trigger accounting_period_no_overlap before insert or update of starts_on,ends_on on public.accounting_periods
for each row execute function app_private.guard_period_overlap();

create function app_private.guard_account_history()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if tg_op='DELETE' then raise exception using errcode='P0001',message='account_deletion_forbidden'; end if;
  if exists(select 1 from public.journal_lines where account_id=old.id) and
    (new.code<>old.code or new.category<>old.category or new.normal_balance<>old.normal_balance or
     new.parent_account_id is distinct from old.parent_account_id or new.system_purpose is distinct from old.system_purpose or
     new.is_control_account<>old.is_control_account or new.organization_id<>old.organization_id) then
    raise exception using errcode='P0001',message='referenced_account_identity_immutable';
  end if;
  return new;
end; $$;
create trigger account_history_guard before update or delete on public.accounts for each row execute function app_private.guard_account_history();

create function app_private.guard_period_mutation()
returns trigger language plpgsql as $$
begin
  if tg_op='DELETE' then raise exception using errcode='P0001',message='accounting_period_deletion_forbidden'; end if;
  if current_setting('app.accounting_write',true)<>'allowed' then raise exception using errcode='42501',message='protected_accounting_mutation'; end if;
  return new;
end; $$;
create trigger accounting_period_mutation_guard before update or delete on public.accounting_periods for each row execute function app_private.guard_period_mutation();

create function app_private.guard_journal_mutation()
returns trigger language plpgsql as $$
begin
  if current_setting('app.accounting_write',true)<>'allowed' then raise exception using errcode='42501',message='protected_accounting_mutation'; end if;
  if tg_op='DELETE' then raise exception using errcode='P0001',message='journal_deletion_forbidden'; end if;
  if old.status='posted' and not(new.status='reversed' and new.reversal_entry_id is not null) then
    raise exception using errcode='P0001',message='posted_journal_immutable';
  end if;
  if old.status='reversed' then raise exception using errcode='P0001',message='reversed_journal_immutable'; end if;
  return new;
end; $$;
create trigger journal_mutation_guard before update or delete on public.journal_entries for each row execute function app_private.guard_journal_mutation();

create function app_private.guard_journal_line_mutation()
returns trigger language plpgsql as $$
begin
  if current_setting('app.accounting_write',true)<>'allowed' then raise exception using errcode='42501',message='protected_accounting_mutation'; end if;
  if tg_op in ('UPDATE','DELETE') and exists(select 1 from public.journal_entries j where j.id=old.journal_entry_id and j.status in ('posted','reversed')) then
    raise exception using errcode='P0001',message='posted_journal_lines_immutable';
  end if;
  return coalesce(new,old);
end; $$;
create trigger journal_line_mutation_guard before insert or update or delete on public.journal_lines for each row execute function app_private.guard_journal_line_mutation();

create function public.initialize_accounting(target_organization_id uuid,selected_template_key text,first_period_start date,first_period_end date)
returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); item record; parent_id uuid;
begin
  perform app_private.require_accounting_permission(target_organization_id,'accounting.initialize');
  if first_period_start>first_period_end then raise exception using errcode='22023',message='invalid_period_dates'; end if;
  if not exists(select 1 from public.business_templates where template_key=selected_template_key and is_active) then
    raise exception using errcode='22023',message='invalid_accounting_template';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text || ':initialize',0));
  if exists(select 1 from public.accounting_profiles where organization_id=target_organization_id) then return; end if;
  insert into public.accounting_profiles values(target_organization_id,selected_template_key,1,4,now(),actor);
  for item in select * from public.accounting_template_accounts where template_key=selected_template_key order by sort_order loop
    parent_id:=null;
    if item.parent_code is not null then select id into parent_id from public.accounts where organization_id=target_organization_id and code=item.parent_code; end if;
    insert into public.accounts(organization_id,code,name,category,normal_balance,parent_account_id,system_purpose,is_control_account,status,created_by,updated_by)
    values(target_organization_id,item.code,item.name_id,item.category,item.normal_balance,parent_id,item.system_purpose,item.is_control_account,
      case when item.is_active_by_default then 'active'::public.account_status else 'inactive'::public.account_status end,actor,actor);
  end loop;
  insert into public.accounting_periods(organization_id,name,starts_on,ends_on,created_by)
  values(target_organization_id,to_char(first_period_start,'YYYY-MM-DD')||' – '||to_char(first_period_end,'YYYY-MM-DD'),first_period_start,first_period_end,actor);
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'accounting.initialized','accounting_profile',target_organization_id::text,
    jsonb_build_object('template_key',selected_template_key,'period_start',first_period_start,'period_end',first_period_end,'policy_status','requires_accountant_review'));
end; $$;

create function app_private.post_journal_internal(actor uuid,target_organization_id uuid,target_accounting_date date,target_description text,
  target_source_reference text,target_lines jsonb,target_idempotency_key text,target_kind public.journal_kind,target_reversal_of uuid default null)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare org public.organizations%rowtype; period_id uuid; created_id uuid; existing record; item jsonb; account_record public.accounts%rowtype;
  debit_value numeric; credit_value numeric; debit_total numeric(20,4):=0; credit_total numeric(20,4):=0; line_no integer:=0; fingerprint text;
begin
  if actor is null then raise exception using errcode='42501',message='authentication_required'; end if;
  if target_lines is null or jsonb_typeof(target_lines)<>'array' or jsonb_array_length(target_lines)<2 then
    raise exception using errcode='22023',message='journal_requires_two_lines';
  end if;
  if char_length(target_idempotency_key) not between 8 and 200 then raise exception using errcode='22023',message='invalid_idempotency_key'; end if;
  fingerprint:=encode(extensions.digest(concat_ws('|',target_accounting_date,target_description,coalesce(target_source_reference,''),target_kind,target_reversal_of,target_lines::text),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text || ':journal:' || target_idempotency_key,0));
  select id,request_fingerprint into existing from public.journal_entries where organization_id=target_organization_id and idempotency_key=target_idempotency_key;
  if found then
    if existing.request_fingerprint<>fingerprint then raise exception using errcode='23505',message='idempotency_payload_mismatch'; end if;
    return existing.id;
  end if;
  select * into org from public.organizations where id=target_organization_id and status='active';
  if not found then raise exception using errcode='P0002',message='organization_not_found'; end if;
  if not exists(select 1 from public.currencies where code=org.base_currency_code and is_active) then raise exception using errcode='23514',message='unsupported_base_currency'; end if;
  select id into period_id from public.accounting_periods where organization_id=target_organization_id and status='open'
    and target_accounting_date between starts_on and ends_on for update;
  if period_id is null then raise exception using errcode='23514',message='open_accounting_period_required'; end if;
  perform set_config('app.accounting_write','allowed',true);
  insert into public.journal_entries(organization_id,period_id,accounting_date,description,kind,currency_code,source_reference,
    idempotency_key,request_fingerprint,reversal_of_id,created_by)
  values(target_organization_id,period_id,target_accounting_date,btrim(target_description),target_kind,org.base_currency_code,
    nullif(btrim(target_source_reference),''),target_idempotency_key,fingerprint,target_reversal_of,actor) returning id into created_id;
  for item in select value from jsonb_array_elements(target_lines) loop
    line_no:=line_no+1;
    begin
      debit_value:=coalesce(nullif(item->>'debit','')::numeric,0); credit_value:=coalesce(nullif(item->>'credit','')::numeric,0);
    exception when invalid_text_representation then raise exception using errcode='22023',message='invalid_decimal_amount'; end;
    if debit_value<>round(debit_value,4) or credit_value<>round(credit_value,4) then raise exception using errcode='22023',message='amount_precision_exceeded'; end if;
    if not((debit_value>0 and credit_value=0) or (credit_value>0 and debit_value=0)) then raise exception using errcode='23514',message='invalid_debit_credit_line'; end if;
    begin select * into account_record from public.accounts where id=(item->>'account_id')::uuid and organization_id=target_organization_id and status='active';
    exception when invalid_text_representation then raise exception using errcode='22023',message='invalid_account_id'; end;
    if not found then raise exception using errcode='23503',message='active_account_not_found'; end if;
    insert into public.journal_lines(organization_id,journal_entry_id,line_number,account_id,description,debit,credit,created_by)
    values(target_organization_id,created_id,line_no,account_record.id,nullif(btrim(item->>'description'),''),debit_value,credit_value,actor);
    debit_total:=debit_total+debit_value; credit_total:=credit_total+credit_value;
  end loop;
  if debit_total<=0 or debit_total<>credit_total then raise exception using errcode='23514',message='journal_not_balanced'; end if;
  update public.journal_entries set status='posted',total_debit=debit_total,total_credit=credit_total,posted_at=now(),posted_by=actor where id=created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'journal.posted','journal_entry',created_id::text,
    jsonb_build_object('kind',target_kind,'accounting_date',target_accounting_date,'total',debit_total,'idempotency_key',target_idempotency_key));
  return created_id;
end; $$;

create function public.post_journal(target_organization_id uuid,target_accounting_date date,target_description text,
  target_source_reference text,target_lines jsonb,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform app_private.require_accounting_permission(target_organization_id,'accounting.post');
  return app_private.post_journal_internal(auth.uid(),target_organization_id,target_accounting_date,target_description,target_source_reference,
    target_lines,target_idempotency_key,'manual',null);
end; $$;

create function public.post_opening_balance(target_organization_id uuid,target_accounting_date date,target_description text,
  target_lines jsonb,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); journal_id uuid;
begin
  perform app_private.require_accounting_permission(target_organization_id,'accounting.post');
  journal_id:=app_private.post_journal_internal(actor,target_organization_id,target_accounting_date,target_description,'opening-balance',target_lines,target_idempotency_key,'opening',null);
  insert into public.opening_balance_batches(organization_id,journal_entry_id,idempotency_key,description,posted_by)
  values(target_organization_id,journal_id,target_idempotency_key,target_description,actor) on conflict(organization_id,idempotency_key) do nothing;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'opening_balance.posted','opening_balance_batch',journal_id::text,jsonb_build_object('journal_entry_id',journal_id));
  return journal_id;
end; $$;

create function public.reverse_journal(target_journal_entry_id uuid,target_accounting_date date,target_reason text,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); original public.journal_entries%rowtype; reversal_id uuid; reversal_lines jsonb; existing public.journal_entries%rowtype;
begin
  select * into original from public.journal_entries where id=target_journal_entry_id for update;
  if not found then raise exception using errcode='P0002',message='journal_not_found'; end if;
  perform app_private.require_accounting_permission(original.organization_id,'accounting.post');
  select * into existing from public.journal_entries where organization_id=original.organization_id and idempotency_key=target_idempotency_key;
  if found then
    if existing.reversal_of_id=original.id and existing.accounting_date=target_accounting_date
      and existing.description='Reversal: '||target_reason and existing.source_reference=original.id::text then return existing.id; end if;
    raise exception using errcode='23505',message='idempotency_payload_mismatch';
  end if;
  if original.status<>'posted' then raise exception using errcode='23514',message='only_posted_journal_can_be_reversed'; end if;
  select jsonb_agg(jsonb_build_object('account_id',account_id,'description','Reversal: '||coalesce(description,''),'debit',credit::text,'credit',debit::text) order by line_number)
  into reversal_lines from public.journal_lines where journal_entry_id=original.id;
  reversal_id:=app_private.post_journal_internal(actor,original.organization_id,target_accounting_date,'Reversal: '||target_reason,
    original.id::text,reversal_lines,target_idempotency_key,'reversal',original.id);
  perform set_config('app.accounting_write','allowed',true);
  update public.journal_entries set status='reversed',reversed_at=now(),reversed_by=actor,reversal_entry_id=reversal_id where id=original.id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,old_state,new_state)
  values(original.organization_id,actor,'journal.reversed','journal_entry',original.id::text,jsonb_build_object('status','posted'),
    jsonb_build_object('status','reversed','reversal_entry_id',reversal_id,'reason',target_reason));
  return reversal_id;
end; $$;

create function public.close_accounting_period(target_period_id uuid,target_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); target public.accounting_periods%rowtype;
begin
  select * into target from public.accounting_periods where id=target_period_id for update;
  if not found then raise exception using errcode='P0002',message='accounting_period_not_found'; end if;
  if not app_private.has_role(target.organization_id,array['owner']::public.membership_role[]) then raise exception using errcode='42501',message='owner_required'; end if;
  if target.status='closed' then return; end if;
  perform set_config('app.accounting_write','allowed',true);
  update public.accounting_periods set status='closed',closed_at=now(),closed_by=actor,close_reason=nullif(btrim(target_reason),'') where id=target.id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target.organization_id,actor,'accounting_period.closed','accounting_period',target.id::text,jsonb_build_object('reason',target_reason));
end; $$;

create function public.reopen_accounting_period(target_period_id uuid,target_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); target public.accounting_periods%rowtype;
begin
  select * into target from public.accounting_periods where id=target_period_id for update;
  if not found then raise exception using errcode='P0002',message='accounting_period_not_found'; end if;
  if not app_private.has_role(target.organization_id,array['owner']::public.membership_role[]) then raise exception using errcode='42501',message='owner_required'; end if;
  if target.status='open' then return; end if;
  if char_length(btrim(target_reason))<3 then raise exception using errcode='22023',message='reopen_reason_required'; end if;
  perform set_config('app.accounting_write','allowed',true);
  update public.accounting_periods set status='open',reopened_at=now(),reopened_by=actor,reopen_reason=btrim(target_reason) where id=target.id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target.organization_id,actor,'accounting_period.reopened','accounting_period',target.id::text,jsonb_build_object('reason',target_reason));
end; $$;

create function public.create_accounting_period(target_organization_id uuid,target_name text,target_start date,target_end date)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  if not app_private.has_role(target_organization_id,array['owner']::public.membership_role[]) then raise exception using errcode='42501',message='owner_required'; end if;
  insert into public.accounting_periods(organization_id,name,starts_on,ends_on,created_by)
  values(target_organization_id,btrim(target_name),target_start,target_end,actor) returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'accounting_period.created','accounting_period',created_id::text,jsonb_build_object('starts_on',target_start,'ends_on',target_end));
  return created_id;
end; $$;

create function public.deactivate_account(target_account_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); target public.accounts%rowtype;
begin
  select * into target from public.accounts where id=target_account_id for update;
  if not found then raise exception using errcode='P0002',message='account_not_found'; end if;
  perform app_private.require_accounting_permission(target.organization_id,'accounting.initialize');
  if target.is_control_account then raise exception using errcode='23514',message='control_account_cannot_be_deactivated'; end if;
  update public.accounts set status='inactive',updated_at=now(),updated_by=actor where id=target.id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target.organization_id,actor,'account.deactivated','account',target.id::text,jsonb_build_object('code',target.code));
end; $$;

create function public.create_subaccount(target_organization_id uuid,target_parent_account_id uuid,target_code text,target_name text,
  target_category public.account_category,target_normal_balance public.normal_balance)
returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid:=auth.uid(); parent public.accounts%rowtype; created_id uuid;
begin
  perform app_private.require_accounting_permission(target_organization_id,'accounting.initialize');
  select * into parent from public.accounts where id=target_parent_account_id and organization_id=target_organization_id and status='active';
  if not found then raise exception using errcode='23503',message='active_parent_account_not_found'; end if;
  if parent.category<>target_category then raise exception using errcode='23514',message='subaccount_category_mismatch'; end if;
  insert into public.accounts(organization_id,code,name,category,normal_balance,parent_account_id,created_by,updated_by)
  values(target_organization_id,upper(btrim(target_code)),btrim(target_name),target_category,target_normal_balance,parent.id,actor,actor)
  returning id into created_id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,new_state)
  values(target_organization_id,actor,'account.created','account',created_id::text,
    jsonb_build_object('code',upper(btrim(target_code)),'name',btrim(target_name),'parent_account_id',parent.id));
  return created_id;
end; $$;

create function public.rename_account(target_account_id uuid,target_name text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid:=auth.uid(); target public.accounts%rowtype;
begin
  select * into target from public.accounts where id=target_account_id for update;
  if not found then raise exception using errcode='P0002',message='account_not_found'; end if;
  perform app_private.require_accounting_permission(target.organization_id,'accounting.initialize');
  if char_length(btrim(target_name)) not between 1 and 120 then raise exception using errcode='22023',message='invalid_account_name'; end if;
  update public.accounts set name=btrim(target_name),updated_at=now(),updated_by=actor where id=target.id;
  insert into public.audit_events(organization_id,actor_user_id,action,target_type,target_id,old_state,new_state)
  values(target.organization_id,actor,'account.renamed','account',target.id::text,jsonb_build_object('name',target.name),jsonb_build_object('name',btrim(target_name)));
end; $$;

create view public.general_ledger with (security_invoker=true) as
select j.organization_id,j.id journal_entry_id,j.entry_number,j.accounting_date,j.kind,j.status,j.description journal_description,
 l.line_number,l.account_id,a.code account_code,a.name account_name,l.description line_description,l.debit,l.credit,j.currency_code
from public.journal_entries j join public.journal_lines l on l.organization_id=j.organization_id and l.journal_entry_id=j.id
join public.accounts a on a.organization_id=l.organization_id and a.id=l.account_id
where j.status in ('posted','reversed');

create function public.get_trial_balance(target_organization_id uuid,target_through_date date default null)
returns table(account_id uuid,account_code text,account_name text,category public.account_category,total_debit numeric,total_credit numeric,debit_balance numeric,credit_balance numeric)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  perform app_private.require_accounting_permission(target_organization_id,'accounting.read');
  return query select a.id,a.code,a.name,a.category,coalesce(sum(l.debit),0),coalesce(sum(l.credit),0),
    greatest(coalesce(sum(l.debit-l.credit),0),0),greatest(coalesce(sum(l.credit-l.debit),0),0)
  from public.accounts a left join (public.journal_lines l join public.journal_entries j
    on j.organization_id=l.organization_id and j.id=l.journal_entry_id and j.status in ('posted','reversed')
    and (target_through_date is null or j.accounting_date<=target_through_date))
    on l.organization_id=a.organization_id and l.account_id=a.id
  where a.organization_id=target_organization_id group by a.id,a.code,a.name,a.category order by a.code;
end; $$;

alter table public.currencies enable row level security;
alter table public.accounting_template_accounts enable row level security;
alter table public.accounting_profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.accounting_periods enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.opening_balance_batches enable row level security;
create policy currencies_authenticated_read on public.currencies for select to authenticated using(is_active);
create policy coa_templates_authenticated_read on public.accounting_template_accounts for select to authenticated using(true);
create policy accounting_profiles_read on public.accounting_profiles for select to authenticated using(app_private.has_permission(organization_id,'accounting.read'));
create policy accounts_read on public.accounts for select to authenticated using(app_private.has_permission(organization_id,'accounting.read'));
create policy periods_read on public.accounting_periods for select to authenticated using(app_private.has_permission(organization_id,'accounting.read'));
create policy journals_read on public.journal_entries for select to authenticated using(app_private.has_permission(organization_id,'accounting.read'));
create policy journal_lines_read on public.journal_lines for select to authenticated using(app_private.has_permission(organization_id,'accounting.read'));
create policy opening_balances_read on public.opening_balance_batches for select to authenticated using(app_private.has_permission(organization_id,'accounting.read'));

grant select on public.currencies,public.accounting_template_accounts,public.accounting_profiles,public.accounts,public.accounting_periods,
 public.journal_entries,public.journal_lines,public.opening_balance_batches,public.general_ledger to authenticated;
revoke insert,update,delete on public.accounting_profiles,public.accounts,public.accounting_periods,public.journal_entries,public.journal_lines,public.opening_balance_batches from public,anon,authenticated;
revoke all on function app_private.require_accounting_permission(uuid,text) from public,anon,authenticated;
revoke all on function app_private.post_journal_internal(uuid,uuid,date,text,text,jsonb,text,public.journal_kind,uuid) from public,anon,authenticated;
revoke all on function app_private.guard_period_overlap() from public,anon,authenticated;
revoke all on function app_private.guard_account_history() from public,anon,authenticated;
revoke all on function app_private.guard_period_mutation() from public,anon,authenticated;
revoke all on function app_private.guard_journal_mutation() from public,anon,authenticated;
revoke all on function app_private.guard_journal_line_mutation() from public,anon,authenticated;
grant execute on function public.initialize_accounting(uuid,text,date,date) to authenticated;
grant execute on function public.post_journal(uuid,date,text,text,jsonb,text) to authenticated;
grant execute on function public.post_opening_balance(uuid,date,text,jsonb,text) to authenticated;
grant execute on function public.reverse_journal(uuid,date,text,text) to authenticated;
grant execute on function public.close_accounting_period(uuid,text) to authenticated;
grant execute on function public.reopen_accounting_period(uuid,text) to authenticated;
grant execute on function public.create_accounting_period(uuid,text,date,date) to authenticated;
grant execute on function public.deactivate_account(uuid) to authenticated;
grant execute on function public.create_subaccount(uuid,uuid,text,text,public.account_category,public.normal_balance) to authenticated;
grant execute on function public.rename_account(uuid,text) to authenticated;
grant execute on function public.get_trial_balance(uuid,date) to authenticated;

commit;
