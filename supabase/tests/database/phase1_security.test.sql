begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users (id, email, aud, role) values
  ('10000000-0000-0000-0000-000000000001', 'owner-a@example.test', 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000002', 'staff-a@example.test', 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000003', 'admin-a@example.test', 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000004', 'fourth-a@example.test', 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000005', 'owner-c@example.test', 'authenticated', 'authenticated'),
  ('20000000-0000-0000-0000-000000000001', 'owner-b@example.test', 'authenticated', 'authenticated'),
  ('20000000-0000-0000-0000-000000000002', 'staff-b@example.test', 'authenticated', 'authenticated');

create temporary table phase1_fixture (
  key text primary key,
  value uuid not null
) on commit drop;
grant all on phase1_fixture to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
insert into phase1_fixture values ('org_a', public.create_organization('Organization A', 'IDR'));

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
insert into phase1_fixture values ('org_b', public.create_organization('Organization B', 'USD'));

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*)::integer from public.organizations where id = (select value from phase1_fixture where key = 'org_a')),
  1,
  'Owner A can read Organization A'
);
select is(
  (select count(*)::integer from public.organizations where id = (select value from phase1_fixture where key = 'org_b')),
  0,
  'Owner A cannot read Organization B through RLS'
);
select is(
  (select active_seat_limit from public.organization_entitlements where organization_id = (select value from phase1_fixture where key = 'org_a')),
  3,
  'New organizations receive three active seats'
);

insert into phase1_fixture
select 'staff_a_membership', public.invite_member(
  (select value from phase1_fixture where key = 'org_a'),
  '10000000-0000-0000-0000-000000000002', 'staff-a@example.test', 'staff'
);
select lives_ok(
  format('select public.activate_member(%L)', (select value from phase1_fixture where key = 'staff_a_membership')),
  'Owner can approve Staff A activation'
);
insert into phase1_fixture
select 'admin_a_membership', public.invite_member(
  (select value from phase1_fixture where key = 'org_a'),
  '10000000-0000-0000-0000-000000000003', 'admin-a@example.test', 'admin_accountant'
);
select lives_ok(
  format('select public.activate_member(%L)', (select value from phase1_fixture where key = 'admin_a_membership')),
  'Owner can approve Admin A activation'
);
insert into phase1_fixture
select 'fourth_a_membership', public.invite_member(
  (select value from phase1_fixture where key = 'org_a'),
  '10000000-0000-0000-0000-000000000004', 'fourth-a@example.test', 'staff'
);
select throws_ok(
  format('select public.activate_member(%L)', (select value from phase1_fixture where key = 'fourth_a_membership')),
  'P0001', 'active_seat_limit_reached',
  'Fourth activation is blocked while entitlement is three'
);
select throws_ok(
  format('select public.set_organization_seat_entitlement(%L, 4, %L)', (select value from phase1_fixture where key = 'org_a'), 'platform_override'),
  '42501', 'platform_authority_required',
  'Owner cannot increase the platform seat entitlement'
);

reset role;
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select lives_ok(
  format('select public.set_organization_seat_entitlement(%L, 4, %L)', (select value from phase1_fixture where key = 'org_a'), 'platform_override'),
  'Platform authority can grant a fourth entitled seat'
);
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select lives_ok(
  format('select public.activate_member(%L)', (select value from phase1_fixture where key = 'fourth_a_membership')),
  'Owner can activate the fourth member after entitlement approval'
);

select throws_ok(
  format('select public.deactivate_member(%L)', (
    select id from public.organization_memberships
    where organization_id = (select value from phase1_fixture where key = 'org_a')
      and user_id = '10000000-0000-0000-0000-000000000001'
  )),
  'P0001', 'last_active_owner_required',
  'The final active owner cannot be deactivated'
);
select throws_ok(
  format('select public.change_member_role(%L, %L)', (
    select id from public.organization_memberships
    where organization_id = (select value from phase1_fixture where key = 'org_a')
      and user_id = '10000000-0000-0000-0000-000000000001'
  ), 'staff'),
  'P0001', 'self_role_change_requires_another_owner',
  'An owner cannot approve their own role change'
);

select lives_ok(
  format('select public.deactivate_member(%L)', (select value from phase1_fixture where key = 'admin_a_membership')),
  'Deactivation retains the membership while freeing a seat'
);
insert into phase1_fixture
select 'owner_c_membership', public.invite_member(
  (select value from phase1_fixture where key = 'org_a'),
  '10000000-0000-0000-0000-000000000005', 'owner-c@example.test', 'owner'
);
select lives_ok(
  format('select public.activate_member(%L)', (select value from phase1_fixture where key = 'owner_c_membership')),
  'A second owner can be activated'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
select lives_ok(
  format('select public.change_member_role(%L, %L)', (
    select id from public.organization_memberships
    where organization_id = (select value from phase1_fixture where key = 'org_a')
      and user_id = '10000000-0000-0000-0000-000000000001'
  ), 'admin_accountant'),
  'Another owner can approve the original owner role change'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*)::integer from public.organizations where id = (select value from phase1_fixture where key = 'org_b')),
  0,
  'Staff A cannot query Organization B'
);
select throws_ok(
  format('select public.change_member_role(%L, %L)', (select value from phase1_fixture where key = 'fourth_a_membership'), 'admin_accountant'),
  '42501', 'permission_denied',
  'Staff cannot change organization roles'
);
select throws_ok(
  format('delete from public.organization_memberships where id = %L', (select value from phase1_fixture where key = 'staff_a_membership')),
  '42501', null,
  'Authenticated users cannot physically delete membership records'
);
select is(
  (select count(*)::integer from public.audit_events where organization_id = (select value from phase1_fixture where key = 'org_a')),
  0,
  'Staff cannot read the organization audit trail'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
select ok(
  (select count(*) > 0 from public.audit_events where organization_id = (select value from phase1_fixture where key = 'org_a')),
  'Owner can read retained audit history'
);
select throws_ok(
  format('update public.audit_events set action = %L where organization_id = %L', 'tampered', (select value from phase1_fixture where key = 'org_a')),
  '42501', null,
  'Authenticated owners cannot update audit events'
);

select * from finish();
rollback;
