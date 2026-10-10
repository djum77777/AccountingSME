begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email,aud,role) values
 ('61000000-0000-0000-0000-000000000001','party-owner-a@example.test','authenticated','authenticated'),
 ('61000000-0000-0000-0000-000000000002','party-admin-a@example.test','authenticated','authenticated'),
 ('61000000-0000-0000-0000-000000000003','party-staff-a@example.test','authenticated','authenticated'),
 ('62000000-0000-0000-0000-000000000001','party-owner-b@example.test','authenticated','authenticated');

create temporary table phase5_fixture(key text primary key,value uuid not null) on commit drop;
grant all on phase5_fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);

insert into phase5_fixture values('org_a',public.create_organization('Party A','IDR'));
insert into phase5_fixture select 'party_a',public.create_party(
  (select value from phase5_fixture where key='org_a'),'PT Nusantara Retail','Nusantara Retail',true,true,30,14,
  'CUST-001','SUP-001','12.345.678.9-012.000','PT Nusantara Retail','Jl. Pajak 1','taxable','Priority relationship');

select is((select count(*)::integer from public.parties where organization_id=(select value from phase5_fixture where key='org_a')),1,
  'Owner creates one organization-scoped party');
select is((select count(*)::integer from public.party_roles where party_id=(select value from phase5_fixture where key='party_a') and status='active'),2,
  'One stable party identity can have customer and supplier roles');
select is((select payment_term_days from public.party_roles where party_id=(select value from phase5_fixture where key='party_a') and role_kind='customer'),30,
  'Customer payment terms are stored on the customer role');
select is((select payment_term_days from public.party_roles where party_id=(select value from phase5_fixture where key='party_a') and role_kind='supplier'),14,
  'Supplier payment terms are stored independently');
select is((select count(*)::integer from information_schema.columns where table_schema='public' and table_name='parties'
  and column_name in ('balance','receivable_balance','payable_balance','ar_balance','ap_balance')),0,
  'Party masters have no manually editable AR or AP balance columns');

insert into phase5_fixture select 'contact_a',public.add_party_contact((select value from phase5_fixture where key='org_a'),
  (select value from phase5_fixture where key='party_a'),'Ayu Finance','Finance Manager','ayu@example.test','+62 812-0000',true);
insert into phase5_fixture select 'address_a',public.add_party_address((select value from phase5_fixture where key='org_a'),
  (select value from phase5_fixture where key='party_a'),'billing','Head Office','Jl. Merdeka 10',null,'Denpasar','Bali','80111','ID',true);
select ok((select is_primary from public.party_contacts where id=(select value from phase5_fixture where key='contact_a')),
  'Primary contact details are retained');
select is((select city from public.party_addresses where id=(select value from phase5_fixture where key='address_a')),'Denpasar',
  'Typed party addresses are retained');

select is((select count(*)::integer from public.search_parties((select value from phase5_fixture where key='org_a'),'ayu',null,false)
  where id=(select value from phase5_fixture where key='party_a')),1,
  'Directory search matches contact email');
select is((select count(*)::integer from public.search_parties((select value from phase5_fixture where key='org_a'),'SUP001','supplier',false)
  where id=(select value from phase5_fixture where key='party_a')),1,
  'Directory search matches normalized external references and role filter');
select ok((select reasons @> array['name']::text[] from public.search_party_duplicates((select value from phase5_fixture where key='org_a'),
  'Nusantara Retail',null,null,null,null) where party_id=(select value from phase5_fixture where key='party_a')),
  'Duplicate warning reports an exact normalized name match');
select ok((select reasons @> array['email','phone','tax_identifier']::text[] from public.search_party_duplicates(
  (select value from phase5_fixture where key='org_a'),null,'AYU@example.test','628120000','123456789012000',null)
  where party_id=(select value from phase5_fixture where key='party_a')),
  'Duplicate warning reports normalized tax, email, and phone reasons');

insert into phase5_fixture select 'field_a',public.create_custom_field((select value from phase5_fixture where key='org_a'),
  'customer_tier','contact','text','Tingkat pelanggan','Customer tier');
select lives_ok(format('select public.set_party_custom_field_value(%L,%L,%L,%L::jsonb)',
  (select value from phase5_fixture where key='org_a'),(select value from phase5_fixture where key='party_a'),
  (select value from phase5_fixture where key='field_a'),'"gold"'),
  'Phase 2 contact custom fields attach to a party through the guarded Phase 5 RPC');
select is((select value #>> '{}' from public.custom_field_values where definition_id=(select value from phase5_fixture where key='field_a')
  and entity_id=(select value from phase5_fixture where key='party_a')),'gold',
  'Party custom-field value is stored with the stable party ID');

select lives_ok(format('select public.update_party(%L,%L,%L,%L,true,false,45,0,%L,null,%L,%L,%L,%L,%L)',
  (select value from phase5_fixture where key='org_a'),(select value from phase5_fixture where key='party_a'),
  'PT Nusantara Retail','Nusantara', 'CUST-001','12.345.678.9-012.000','PT Nusantara Retail','Jl. Pajak 1','taxable','Updated note'),
  'Owner updates the profile and role settings');
select is((select status::text from public.party_roles where party_id=(select value from phase5_fixture where key='party_a') and role_kind='supplier'),'archived',
  'Removing a supplier role archives its history rather than deleting it');
select is((select payment_term_days from public.party_roles where party_id=(select value from phase5_fixture where key='party_a') and role_kind='customer'),45,
  'Updating customer terms changes the role profile');

select public.set_party_status((select value from phase5_fixture where key='org_a'),(select value from phase5_fixture where key='party_a'),'archived');
select ok((select status='archived' and archived_at is not null and archived_by is not null from public.parties
  where id=(select value from phase5_fixture where key='party_a')),
  'Archiving records actor and time while retaining the party');
select is((select count(*)::integer from public.search_parties((select value from phase5_fixture where key='org_a'),null,null,false)),0,
  'Archived parties are hidden by default');
select is((select id from public.search_parties((select value from phase5_fixture where key='org_a'),null,null,true)),
  (select value from phase5_fixture where key='party_a'),'Archived directory results retain the same stable ID');
select public.set_party_status((select value from phase5_fixture where key='org_a'),(select value from phase5_fixture where key='party_a'),'active');
select ok((select status='active' and archived_at is null from public.parties where id=(select value from phase5_fixture where key='party_a')),
  'Reactivation preserves identity and clears archive metadata');
select throws_ok(format('delete from public.parties where id=%L',(select value from phase5_fixture where key='party_a')),
  '42501','permission denied for table parties','Application users cannot delete a party master');
select ok((select count(*)>=6 from public.audit_events where organization_id=(select value from phase5_fixture where key='org_a')
  and action like 'party.%'),'Party master changes emit append-only audit events');

select set_config('request.jwt.claim.sub','62000000-0000-0000-0000-000000000001',true);
insert into phase5_fixture values('org_b',public.create_organization('Party B','IDR'));
select is((select count(*)::integer from public.parties where organization_id=(select value from phase5_fixture where key='org_a')),0,
  'Organization B cannot read Organization A parties through RLS');
select is((select count(*)::integer from public.party_contacts where organization_id=(select value from phase5_fixture where key='org_a')),0,
  'Organization B cannot read Organization A contacts through RLS');
select throws_ok(format('select public.add_party_contact(%L,%L,%L,null,%L,null,false)',
  (select value from phase5_fixture where key='org_b'),(select value from phase5_fixture where key='party_a'),'Cross tenant','cross@example.test'),
  '23503','party_not_found','Cross-tenant child references are rejected by the guarded RPC');

select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
insert into phase5_fixture select 'admin_a',public.invite_member((select value from phase5_fixture where key='org_a'),
  '61000000-0000-0000-0000-000000000002','party-admin-a@example.test','admin_accountant');
select public.activate_member((select value from phase5_fixture where key='admin_a'));
insert into phase5_fixture select 'staff_a',public.invite_member((select value from phase5_fixture where key='org_a'),
  '61000000-0000-0000-0000-000000000003','party-staff-a@example.test','staff');
select public.activate_member((select value from phase5_fixture where key='staff_a'));

select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000003',true);
select is((select count(*)::integer from public.parties where organization_id=(select value from phase5_fixture where key='org_a')),1,
  'Staff can read the operational party directory by default');
select throws_ok(format('select public.create_party(%L,%L,%L,true,false,0,0,null,null,null,null,null,%L,null)',
  (select value from phase5_fixture where key='org_a'),'Staff Party','Staff Party','not_set'),
  '42501','permission_denied','Staff cannot manage party masters by default');

select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000002',true);
select lives_ok(format('select public.add_party_contact(%L,%L,%L,null,%L,null,false)',
  (select value from phase5_fixture where key='org_a'),(select value from phase5_fixture where key='party_a'),'Admin Contact','admin-contact@example.test'),
  'Admin/Accountant can manage party masters by default');

select * from finish();
rollback;
