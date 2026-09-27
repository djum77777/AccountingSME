begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

insert into auth.users (id, email, aud, role) values
  ('31000000-0000-0000-0000-000000000001', 'phase2-owner-a@example.test', 'authenticated', 'authenticated'),
  ('31000000-0000-0000-0000-000000000002', 'phase2-staff-a@example.test', 'authenticated', 'authenticated'),
  ('32000000-0000-0000-0000-000000000001', 'phase2-owner-b@example.test', 'authenticated', 'authenticated');

create temporary table phase2_fixture (key text primary key, value uuid not null) on commit drop;
grant all on phase2_fixture to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '31000000-0000-0000-0000-000000000001', true);
insert into phase2_fixture values ('org_a', public.create_organization('Retail A', 'IDR'));
select lives_ok(format(
  'select public.complete_organization_onboarding(%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L)',
  (select value from phase2_fixture where key='org_a'),'id','retail','Retail A','Jakarta','021','NPWP-A','retail','IDR','Asia/Jakarta','DD/MM/YYYY'
), 'Organization A completes the Retail onboarding template');

select set_config('request.jwt.claim.sub', '32000000-0000-0000-0000-000000000001', true);
insert into phase2_fixture values ('org_b', public.create_organization('Service B', 'USD'));
select lives_ok(format(
  'select public.complete_organization_onboarding(%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L)',
  (select value from phase2_fixture where key='org_b'),'en','service','Service B','Bali','','','service','USD','Asia/Makassar','YYYY-MM-DD'
), 'Organization B completes the Service onboarding template');

select is((select template_key from public.organization_configurations where organization_id=(select value from phase2_fixture where key='org_b')),
  'service', 'Organization B retains its independently selected template');
select ok((select exists(select 1 from public.organization_modules where organization_id=(select value from phase2_fixture where key='org_b') and module_key='projects')),
  'Service template enables Projects');
select is((select count(*)::integer from public.organization_modules where organization_id=(select value from phase2_fixture where key='org_b') and module_key='inventory'),
  0, 'Service template does not inherit Retail inventory');

select set_config('request.jwt.claim.sub', '31000000-0000-0000-0000-000000000001', true);
select is((select count(*)::integer from public.organization_configurations where organization_id=(select value from phase2_fixture where key='org_b')),
  0, 'Organization A cannot read Organization B configuration');
select is((select count(*)::integer from public.organization_modules where organization_id=(select value from phase2_fixture where key='org_b')),
  0, 'Organization A cannot read Organization B modules');
select ok((select exists(select 1 from public.organization_modules where organization_id=(select value from phase2_fixture where key='org_a') and module_key='inventory')),
  'Retail template enables Inventory for Organization A');

insert into phase2_fixture select 'branch', public.create_custom_dimension((select value from phase2_fixture where key='org_a'),'branch','Cabang','Branch');
insert into phase2_fixture select 'marketplace', public.create_custom_dimension((select value from phase2_fixture where key='org_a'),'marketplace','Marketplace','Marketplace');
select lives_ok(format('select public.add_custom_dimension_value(%L,%L,%L,%L)',(select value from phase2_fixture where key='branch'),'JKT','Jakarta','Jakarta'),
  'Organization A can add a Branch value');
select is((select count(*)::integer from public.custom_dimension_definitions where organization_id=(select value from phase2_fixture where key='org_a')),
  2, 'Organization A has Branch and Marketplace dimensions');

insert into phase2_fixture select 'field_a', public.create_custom_field((select value from phase2_fixture where key='org_a'),'customer_tier','contact','text','Tingkat Pelanggan','Customer Tier');
insert into phase2_fixture values ('entity_a','33000000-0000-0000-0000-000000000001');
select lives_ok(format('select public.set_custom_field_value(%L,%L,%L::jsonb)',(select value from phase2_fixture where key='field_a'),(select value from phase2_fixture where key='entity_a'),'"Gold"'),
  'An active custom field stores a metadata-driven value');
select lives_ok(format('select public.set_custom_field_status(%L,%L)',(select value from phase2_fixture where key='field_a'),'inactive'),
  'Custom field can be archived without deletion');
select is((select count(*)::integer from public.custom_field_values where definition_id=(select value from phase2_fixture where key='field_a')),
  1, 'Archiving a custom field preserves historical values');
select throws_ok(format('select public.set_custom_field_value(%L,%L,%L::jsonb)',(select value from phase2_fixture where key='field_a'),'33000000-0000-0000-0000-000000000002','"Silver"'),
  '23514','custom_field_not_active','An archived custom field rejects new values');

select throws_ok(format('select public.upsert_form_field_configuration(%L,%L,%L,%L,10,false,true,null,array[''owner'']::public.membership_role[])',
  (select value from phase2_fixture where key='org_a'),'sale','posting_status','main'),
  '42501','protected_field','Form configuration cannot redefine a protected posting field');

select lives_ok(format('select public.set_display_label_alias(%L,%L,%L,%L,%L)',(select value from phase2_fixture where key='org_a'),'customer','en','Shopper','Shoppers'),
  'Organization A can safely alias a display label');
select lives_ok(format('select public.reset_organization_configuration(%L)',(select value from phase2_fixture where key='org_a')),
  'Organization A can reset template-derived configuration');
select is((select singular_label from public.display_label_aliases where organization_id=(select value from phase2_fixture where key='org_a') and entity_key='customer' and locale='en'),
  'Customer', 'Reset restores the Retail template label');
select is((select count(*)::integer from public.custom_field_values where definition_id=(select value from phase2_fixture where key='field_a')),
  1, 'Reset preserves custom-field business history');
select is((select count(*)::integer from public.custom_dimension_definitions where organization_id=(select value from phase2_fixture where key='org_a')),
  2, 'Reset preserves organization-defined dimensions');

insert into phase2_fixture select 'staff_a', public.invite_member((select value from phase2_fixture where key='org_a'),'31000000-0000-0000-0000-000000000002','phase2-staff-a@example.test','staff');
select public.activate_member((select value from phase2_fixture where key='staff_a'));
select set_config('request.jwt.claim.sub', '31000000-0000-0000-0000-000000000002', true);
select throws_ok(format('select public.reset_organization_configuration(%L)',(select value from phase2_fixture where key='org_a')),
  '42501','permission_denied','Staff cannot reset protected organization configuration');
select throws_ok(format('select public.set_module_visibility(%L,%L,true)',(select value from phase2_fixture where key='org_a'),'journal_math'),
  '42501','permission_denied','Staff cannot use customization to alter protected accounting behavior');

select set_config('request.jwt.claim.sub', '32000000-0000-0000-0000-000000000001', true);
insert into phase2_fixture select 'project', public.create_custom_dimension((select value from phase2_fixture where key='org_b'),'project','Proyek','Project');
insert into phase2_fixture select 'client_type', public.create_custom_dimension((select value from phase2_fixture where key='org_b'),'client_type','Jenis Klien','Client Type');
select is((select count(*)::integer from public.custom_dimension_definitions where organization_id=(select value from phase2_fixture where key='org_b')),
  2,'Organization B independently has Project and Client Type dimensions');

select * from finish();
rollback;
