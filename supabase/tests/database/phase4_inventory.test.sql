begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email,aud,role) values
 ('51000000-0000-0000-0000-000000000001','inventory-owner-a@example.test','authenticated','authenticated'),
 ('51000000-0000-0000-0000-000000000002','inventory-admin-a@example.test','authenticated','authenticated'),
 ('51000000-0000-0000-0000-000000000003','inventory-staff-a@example.test','authenticated','authenticated'),
 ('52000000-0000-0000-0000-000000000001','inventory-owner-b@example.test','authenticated','authenticated');

create temporary table phase4_fixture(key text primary key,value uuid not null) on commit drop;
grant all on phase4_fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true);

insert into phase4_fixture values('org_a',public.create_organization('Inventory A','IDR'));
select public.initialize_accounting((select value from phase4_fixture where key='org_a'),'retail','2026-01-01','2026-12-31');
select lives_ok(format('select public.initialize_inventory(%L)',(select value from phase4_fixture where key='org_a')),
 'Owner initializes inventory after the accounting foundation');
select is((select count(*)::integer from public.organization_units where organization_id=(select value from phase4_fixture where key='org_a')),2,
 'Inventory initialization creates Piece and Hour units');
select is((select count(*)::integer from public.inventory_locations where organization_id=(select value from phase4_fixture where key='org_a') and is_default),1,
 'Inventory initialization creates exactly one default location');

insert into phase4_fixture select 'unit_a',id from public.organization_units where organization_id=(select value from phase4_fixture where key='org_a') and code='PCS';
insert into phase4_fixture select 'main_a',id from public.inventory_locations where organization_id=(select value from phase4_fixture where key='org_a') and code='MAIN';
insert into phase4_fixture select 'secondary_a',public.create_inventory_location((select value from phase4_fixture where key='org_a'),'SECOND','Secondary Warehouse');
insert into phase4_fixture select 'category_a',public.create_product_category((select value from phase4_fixture where key='org_a'),'GOODS','Goods');
insert into phase4_fixture select 'inventory_account_a',id from public.accounts where organization_id=(select value from phase4_fixture where key='org_a') and system_purpose='inventory';
insert into phase4_fixture select 'capital_a',id from public.accounts where organization_id=(select value from phase4_fixture where key='org_a') and system_purpose='owner_capital';
insert into phase4_fixture select 'expense_a',id from public.accounts where organization_id=(select value from phase4_fixture where key='org_a') and system_purpose='operating_expense';
insert into phase4_fixture select 'period_a',id from public.accounting_periods where organization_id=(select value from phase4_fixture where key='org_a');

insert into phase4_fixture select 'product_a',public.create_catalog_item((select value from phase4_fixture where key='org_a'),'product','Test Product','SKU-001','8990001',
 (select value from phase4_fixture where key='category_a'),(select value from phase4_fixture where key='unit_a'),true,
 (select value from phase4_fixture where key='inventory_account_a'),16);
insert into phase4_fixture select 'service_a',public.create_catalog_item((select value from phase4_fixture where key='org_a'),'service','Consulting Hour','SVC-001',null,
 null,(select id from public.organization_units where organization_id=(select value from phase4_fixture where key='org_a') and code='HOUR'),false,null,0);
select ok((select not inventory_tracked from public.products where id=(select value from phase4_fixture where key='service_a')),
 'Service master exists without inventory tracking');
select lives_ok(format('select public.set_catalog_item_status(%L,%L,%L)',(select value from phase4_fixture where key='org_a'),
 (select value from phase4_fixture where key='service_a'),'inactive'),'Catalog items are deactivated instead of deleted');
select ok((select status='inactive' from public.products where id=(select value from phase4_fixture where key='service_a')),
 'Deactivated service master remains in retained history');
select public.set_catalog_item_status((select value from phase4_fixture where key='org_a'),(select value from phase4_fixture where key='service_a'),'active');
select throws_ok(format('select public.create_catalog_item(%L,%L,%L,%L,null,null,%L,true,%L,0)',
 (select value from phase4_fixture where key='org_a'),'service','Invalid stocked service','SVC-BAD',(select value from phase4_fixture where key='unit_a'),
 (select value from phase4_fixture where key='inventory_account_a')),
 '23514','service_cannot_track_inventory','A service cannot be configured as inventory tracked');

insert into phase4_fixture select 'opening_op',public.post_inventory_movement((select value from phase4_fixture where key='org_a'),
 (select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),'2026-01-01','opening',10,10000,
 (select value from phase4_fixture where key='capital_a'),'Opening stock','opening-import','inventory-opening-a');
select is((select quantity_on_hand from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),10::numeric,
 'Opening stock creates 10 units');
select is((select inventory_value from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),100000::numeric,
 'Opening stock creates Rp100,000 value');

insert into phase4_fixture select 'receipt_op',public.post_inventory_movement((select value from phase4_fixture where key='org_a'),
 (select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),'2026-01-02','stock_in',10,14000,
 (select value from phase4_fixture where key='capital_a'),'Second stock receipt','manual-stock-in','inventory-receipt-a');
select is((select average_unit_cost from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),12000::numeric,
 '10 at Rp10,000 plus 10 at Rp14,000 produces Rp12,000 weighted average');
select is((select inventory_value from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),240000::numeric,
 'Two receipts retain Rp240,000 total inventory value');

insert into phase4_fixture select 'out_op',public.post_inventory_movement((select value from phase4_fixture where key='org_a'),
 (select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),'2026-01-03','stock_out',5,null,
 (select value from phase4_fixture where key='expense_a'),'Manual stock out','manual-stock-out','inventory-out-a');
select is((select quantity_on_hand from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),15::numeric,
 'Removing five leaves 15 units');
select is((select inventory_value from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),180000::numeric,
 'Removing five at weighted average leaves Rp180,000 value');
select is((select average_unit_cost from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),12000::numeric,
 'Outbound movement preserves the Rp12,000 historical cost basis');
select is((select count(*)::integer from public.inventory_movements where product_id=(select value from phase4_fixture where key='product_a')),3,
 'Every quantity and value change has an immutable movement');
select is((select applied_unit_cost from public.inventory_movements where operation_id=(select value from phase4_fixture where key='opening_op')),10000::numeric,
 'Opening movement retains its original Rp10,000 cost snapshot');
select is((select applied_unit_cost from public.inventory_movements where operation_id=(select value from phase4_fixture where key='receipt_op')),14000::numeric,
 'Second receipt retains its original Rp14,000 cost snapshot');
select is((select applied_unit_cost from public.inventory_movements where operation_id=(select value from phase4_fixture where key='out_op')),12000::numeric,
 'Outbound movement stores the weighted average applied at issue time');
select is((select count(*)::integer from public.journal_entries where id in (select journal_entry_id from public.inventory_operations where organization_id=(select value from phase4_fixture where key='org_a'))),3,
 'Each financially relevant movement calls the central journal engine exactly once');
select is((select debit_balance from public.get_trial_balance((select value from phase4_fixture where key='org_a'),null) where account_id=(select value from phase4_fixture where key='inventory_account_a')),180000::numeric,
 'Inventory control account reconciles to movement valuation');
select ok((select exists(select 1 from public.inventory_low_stock where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and quantity_on_hand=15)),
 'Low-stock query flags the product at its configured threshold');

select is(public.post_inventory_movement((select value from phase4_fixture where key='org_a'),(select value from phase4_fixture where key='product_a'),
 (select value from phase4_fixture where key='main_a'),'2026-01-03','stock_out',5,null,(select value from phase4_fixture where key='expense_a'),
 'Manual stock out','manual-stock-out','inventory-out-a'),(select value from phase4_fixture where key='out_op'),
 'Idempotent inventory retry returns the original operation');
select is((select count(*)::integer from public.inventory_operations where organization_id=(select value from phase4_fixture where key='org_a') and idempotency_key='inventory-out-a'),1,
 'Inventory retry does not duplicate movements or journals');
select throws_ok(format('select public.post_inventory_movement(%L,%L,%L,%L,%L,4,null,%L,%L,%L,%L)',
 (select value from phase4_fixture where key='org_a'),(select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),
 '2026-01-03','stock_out',(select value from phase4_fixture where key='expense_a'),'Changed retry','manual-stock-out','inventory-out-a'),
 '23505','idempotency_payload_mismatch','Changed payload cannot reuse an inventory idempotency key');
select throws_ok(format('select public.post_inventory_movement(%L,%L,%L,%L,%L,99,null,%L,%L,%L,%L)',
 (select value from phase4_fixture where key='org_a'),(select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),
 '2026-01-04','stock_out',(select value from phase4_fixture where key='expense_a'),'Too much stock','manual-stock-out','inventory-negative-a'),
 '23514','negative_inventory_forbidden','Negative inventory is rejected');
select throws_ok(format('select public.post_inventory_movement(%L,%L,%L,%L,%L,1,null,%L,%L,%L,%L)',
 (select value from phase4_fixture where key='org_a'),(select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),
 '2025-12-31','stock_out',(select value from phase4_fixture where key='expense_a'),'Backdated issue','manual-stock-out','inventory-backdate-a'),
 '23514','backdated_inventory_movement_forbidden','Backdated movement is rejected to preserve deterministic history');
select is((select quantity_on_hand from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),15::numeric,
 'Rejected movements do not alter calculated stock');

insert into phase4_fixture select 'transfer_op',public.post_inventory_transfer((select value from phase4_fixture where key='org_a'),
 (select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),(select value from phase4_fixture where key='secondary_a'),
 '2026-01-04',5,'Move to secondary','inventory-transfer-a');
select is((select quantity_on_hand from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='main_a')),10::numeric,
 'Transfer reduces source location quantity');
select is((select quantity_on_hand from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='secondary_a')),5::numeric,
 'Transfer increases destination location quantity');
select is((select sum(inventory_value) from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a')),180000::numeric,
 'Location transfer conserves total inventory value without a duplicate ledger post');
select is((select count(*)::integer from public.inventory_movements where operation_id=(select value from phase4_fixture where key='transfer_op')),2,
 'Transfer history contains linked out and in movements');

insert into phase4_fixture select 'count_op',public.post_inventory_stock_count((select value from phase4_fixture where key='org_a'),
 (select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='secondary_a'),'2026-01-05',4,null,
 (select value from phase4_fixture where key='expense_a'),'Count variance','inventory-count-a');
select is((select quantity_on_hand from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a') and location_id=(select value from phase4_fixture where key='secondary_a')),4::numeric,
 'Stock count creates an explicit variance movement to the counted quantity');
select is((select sum(inventory_value) from public.inventory_valuation where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a')),168000::numeric,
 'Inventory valuation reflects the financially posted stock-count loss');

select lives_ok(format('select public.close_accounting_period(%L,%L)',(select value from phase4_fixture where key='period_a'),'Phase 4 rollback test'),
 'Owner closes the period for rollback verification');
select throws_ok(format('select public.post_inventory_movement(%L,%L,%L,%L,%L,1,12000,%L,%L,%L,%L)',
 (select value from phase4_fixture where key='org_a'),(select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),
 '2026-01-06','stock_in',(select value from phase4_fixture where key='capital_a'),'Closed period receipt','manual-stock-in','inventory-closed-a'),
 '23514','open_accounting_period_required','Accounting failure rolls back the entire inventory operation');
select is((select count(*)::integer from public.inventory_operations where organization_id=(select value from phase4_fixture where key='org_a') and idempotency_key='inventory-closed-a'),0,
 'Failed accounting leaves no partial inventory operation');
select is((select sum(inventory_value) from public.inventory_cost_states where organization_id=(select value from phase4_fixture where key='org_a') and product_id=(select value from phase4_fixture where key='product_a')),168000::numeric,
 'Failed accounting preserves the prior inventory cost state');
select public.reopen_accounting_period((select value from phase4_fixture where key='period_a'),'Continue Phase 4 tests');

select set_config('request.jwt.claim.sub','52000000-0000-0000-0000-000000000001',true);
insert into phase4_fixture values('org_b',public.create_organization('Inventory B','IDR'));
select public.initialize_accounting((select value from phase4_fixture where key='org_b'),'service','2026-01-01','2026-12-31');
select public.initialize_inventory((select value from phase4_fixture where key='org_b'));
insert into phase4_fixture select 'account_b',id from public.accounts where organization_id=(select value from phase4_fixture where key='org_b') and system_purpose='inventory';
select is((select count(*)::integer from public.products where organization_id=(select value from phase4_fixture where key='org_a')),0,
 'Organization B cannot read Organization A product masters');
select is((select count(*)::integer from public.inventory_movements where organization_id=(select value from phase4_fixture where key='org_a')),0,
 'Organization B cannot read Organization A movement history');

select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true);
select throws_ok(format('select public.post_inventory_movement(%L,%L,%L,%L,%L,1,12000,%L,%L,%L,%L)',
 (select value from phase4_fixture where key='org_a'),(select value from phase4_fixture where key='product_a'),(select value from phase4_fixture where key='main_a'),
 '2026-01-06','stock_in',(select value from phase4_fixture where key='account_b'),'Cross tenant offset','manual-stock-in','inventory-cross-tenant-a'),
 '23503','valid_offset_account_required','Inventory accounting cannot reference another tenant account');

insert into phase4_fixture select 'admin_a',public.invite_member((select value from phase4_fixture where key='org_a'),'51000000-0000-0000-0000-000000000002','inventory-admin-a@example.test','admin_accountant');
select public.activate_member((select value from phase4_fixture where key='admin_a'));
insert into phase4_fixture select 'staff_a',public.invite_member((select value from phase4_fixture where key='org_a'),'51000000-0000-0000-0000-000000000003','inventory-staff-a@example.test','staff');
select public.activate_member((select value from phase4_fixture where key='staff_a'));
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000003',true);
select is((select count(*)::integer from public.products where organization_id=(select value from phase4_fixture where key='org_a')),0,
 'Staff has no inventory read capability by default');
select throws_ok(format('select public.create_inventory_location(%L,%L,%L)',(select value from phase4_fixture where key='org_a'),'STAFF','Staff Location'),
 '42501','permission_denied','Staff cannot mutate inventory masters by default');
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000002',true);
select ok((select count(*)>0 from public.inventory_movements where organization_id=(select value from phase4_fixture where key='org_a')),
 'Admin/Accountant can read organization inventory history');
select lives_ok(format('select public.create_inventory_location(%L,%L,%L)',(select value from phase4_fixture where key='org_a'),'ADMIN','Admin Location'),
 'Admin/Accountant can manage inventory by default');
select throws_ok(format('update public.inventory_cost_states set quantity_on_hand=999 where organization_id=%L and product_id=%L',
 (select value from phase4_fixture where key='org_a'),(select value from phase4_fixture where key='product_a')),
 '42501','permission denied for table inventory_cost_states','Application roles cannot directly overwrite calculated stock');
select throws_ok(format('update public.inventory_movements set applied_unit_cost=1 where product_id=%L',(select value from phase4_fixture where key='product_a')),
 '42501','permission denied for table inventory_movements','Application roles cannot rewrite historical cost basis');

select * from finish();
rollback;
