begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email,aud,role) values
 ('71000000-0000-0000-0000-000000000001','purchase-owner-a@example.test','authenticated','authenticated'),
 ('71000000-0000-0000-0000-000000000002','purchase-admin-a@example.test','authenticated','authenticated'),
 ('71000000-0000-0000-0000-000000000003','purchase-staff-a@example.test','authenticated','authenticated'),
 ('72000000-0000-0000-0000-000000000001','purchase-owner-b@example.test','authenticated','authenticated');

create temporary table phase6_fixture(key text primary key,value uuid not null) on commit drop;
grant all on phase6_fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);

insert into phase6_fixture values('org_a',public.create_organization('Purchases A','IDR'));
select public.initialize_accounting((select value from phase6_fixture where key='org_a'),'retail','2026-01-01','2026-12-31');
select public.initialize_inventory((select value from phase6_fixture where key='org_a'));
insert into phase6_fixture select 'unit_a',id from public.organization_units where organization_id=(select value from phase6_fixture where key='org_a') and code='PCS';
insert into phase6_fixture select 'hour_a',id from public.organization_units where organization_id=(select value from phase6_fixture where key='org_a') and code='HOUR';
insert into phase6_fixture select 'location_a',id from public.inventory_locations where organization_id=(select value from phase6_fixture where key='org_a') and code='MAIN';
insert into phase6_fixture select 'inventory_a',id from public.accounts where organization_id=(select value from phase6_fixture where key='org_a') and system_purpose='inventory';
insert into phase6_fixture select 'ap_a',id from public.accounts where organization_id=(select value from phase6_fixture where key='org_a') and system_purpose='accounts_payable';
insert into phase6_fixture select 'cash_a',id from public.accounts where organization_id=(select value from phase6_fixture where key='org_a') and system_purpose='cash';
insert into phase6_fixture select 'bank_a',id from public.accounts where organization_id=(select value from phase6_fixture where key='org_a') and system_purpose='bank';
insert into phase6_fixture select 'expense_a',id from public.accounts where organization_id=(select value from phase6_fixture where key='org_a') and system_purpose='operating_expense';
insert into phase6_fixture select 'period_a',id from public.accounting_periods where organization_id=(select value from phase6_fixture where key='org_a');
insert into phase6_fixture select 'supplier_a',public.create_party((select value from phase6_fixture where key='org_a'),
 'PT Supplier A','Supplier A',false,true,0,30,null,'SUP-A',null,null,null,'not_set',null);
insert into phase6_fixture select 'product_a',public.create_catalog_item((select value from phase6_fixture where key='org_a'),'product',
 'Purchase Product','PUR-PROD',null,null,(select value from phase6_fixture where key='unit_a'),true,(select value from phase6_fixture where key='inventory_a'),0);
insert into phase6_fixture select 'service_a',public.create_catalog_item((select value from phase6_fixture where key='org_a'),'service',
 'Purchase Service','PUR-SVC',null,null,(select value from phase6_fixture where key='hour_a'),false,null,0);

-- Cash product purchase.
insert into phase6_fixture select 'cash_purchase',public.create_purchase_draft((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'CASH-001','2026-02-01','2026-02-01','cash',
 (select value from phase6_fixture where key='location_a'),(select value from phase6_fixture where key='cash_a'),0,0,'Cash purchase');
insert into phase6_fixture select 'cash_line',public.add_purchase_line((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='cash_purchase'),(select value from phase6_fixture where key='product_a'),2,10000,0,0,null,'Cash stock');
select lives_ok(format('select public.confirm_purchase(%L,%L,%L)',(select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='cash_purchase'),'confirm-cash-purchase-001'),'Cash product purchase confirms');
select is((select status::text from public.purchase_documents where id=(select value from phase6_fixture where key='cash_purchase')),'paid',
 'Cash purchase is paid without an AP open item');
select is((select count(*)::integer from public.purchase_open_items where purchase_id=(select value from phase6_fixture where key='cash_purchase')),0,
 'Cash purchase creates no Accounts Payable item');
select is((select quantity_on_hand from public.inventory_cost_states where organization_id=(select value from phase6_fixture where key='org_a')
 and product_id=(select value from phase6_fixture where key='product_a') and location_id=(select value from phase6_fixture where key='location_a')),2::numeric,
 'Cash product purchase increases stock through the inventory authority');
select is((select credit_balance from public.get_trial_balance((select value from phase6_fixture where key='org_a'),null)
 where account_id=(select value from phase6_fixture where key='cash_a')),20000::numeric,'Cash purchase credits cash by Rp20,000');

-- Golden credit purchase: 10 x Rp50,000.
insert into phase6_fixture select 'golden_purchase',public.create_purchase_draft((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'INV-GOLDEN','2026-02-02','2026-03-04','credit',
 (select value from phase6_fixture where key='location_a'),null,0,0,'Golden scenario');
insert into phase6_fixture select 'golden_line',public.add_purchase_line((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='golden_purchase'),(select value from phase6_fixture where key='product_a'),10,50000,0,0,null,'Golden stocked units');
select public.confirm_purchase((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='golden_purchase'),'confirm-golden-purchase-001');
select is((select total_amount from public.purchase_documents where id=(select value from phase6_fixture where key='golden_purchase')),500000::numeric,
 'Golden purchase total is Rp500,000');
select is((select outstanding_amount from public.purchase_open_items where purchase_id=(select value from phase6_fixture where key='golden_purchase')),500000::numeric,
 'Golden credit purchase creates Rp500,000 AP');
select is((select quantity_on_hand from public.inventory_cost_states where organization_id=(select value from phase6_fixture where key='org_a')
 and product_id=(select value from phase6_fixture where key='product_a') and location_id=(select value from phase6_fixture where key='location_a')),12::numeric,
 'Golden purchase adds ten stocked units');
select is((select debit_balance from public.get_trial_balance((select value from phase6_fixture where key='org_a'),null)
 where account_id=(select value from phase6_fixture where key='inventory_a')),520000::numeric,
 'Inventory control includes Rp20,000 cash plus Rp500,000 credit purchases');
select is((select credit_balance from public.get_trial_balance((select value from phase6_fixture where key='org_a'),null)
 where account_id=(select value from phase6_fixture where key='ap_a')),500000::numeric,'AP control increases Rp500,000');

-- Confirmation retry is idempotent.
select is(public.confirm_purchase((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='golden_purchase'),
 'confirm-golden-purchase-001'),(select value from phase6_fixture where key='golden_purchase'),'Duplicate confirmation returns the original purchase');
select is((select count(*)::integer from public.inventory_operations where organization_id=(select value from phase6_fixture where key='org_a')
 and source_type='purchase' and source_reference=(select document_number from public.purchase_documents where id=(select value from phase6_fixture where key='golden_purchase'))),1,
 'Duplicate confirmation creates no extra inventory movement');

-- Service-only credit purchase.
insert into phase6_fixture select 'service_purchase',public.create_purchase_draft((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'SVC-001','2026-02-03','2026-03-05','credit',null,null,0,0,'Service bill');
insert into phase6_fixture select 'service_line',public.add_purchase_line((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='service_purchase'),(select value from phase6_fixture where key='service_a'),1,100000,0,0,
 (select value from phase6_fixture where key='expense_a'),'Consulting');
select public.confirm_purchase((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='service_purchase'),'confirm-service-purchase-001');
select is((select count(*)::integer from public.purchase_posting_links where purchase_id=(select value from phase6_fixture where key='service_purchase')
 and inventory_operation_id is not null),0,'Service-only purchase creates no inventory movement');
select is((select debit_balance from public.get_trial_balance((select value from phase6_fixture where key='org_a'),null)
 where account_id=(select value from phase6_fixture where key='expense_a')),100000::numeric,'Service purchase debits operating expense');

-- Golden partial and full payment.
insert into phase6_fixture select 'payment_200',public.post_supplier_payment((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'2026-02-10',(select value from phase6_fixture where key='bank_a'),'Golden partial',
 jsonb_build_array(jsonb_build_object('purchase_id',(select value from phase6_fixture where key='golden_purchase'),'amount','200000')),'supplier-payment-golden-200');
select is((select outstanding_amount from public.purchase_open_items where purchase_id=(select value from phase6_fixture where key='golden_purchase')),300000::numeric,
 'Rp200,000 payment leaves Rp300,000 AP');
select is((select status::text from public.purchase_documents where id=(select value from phase6_fixture where key='golden_purchase')),'partially_paid',
 'Partially paid invoice has derived partial status');
select is((select allocated_amount from public.supplier_payment_allocations where payment_id=(select value from phase6_fixture where key='payment_200')),200000::numeric,
 'Partial payment allocation is retained');
select is((select credit_balance from public.get_trial_balance((select value from phase6_fixture where key='org_a'),null)
 where account_id=(select value from phase6_fixture where key='bank_a')),200000::numeric,'Partial payment credits bank Rp200,000');
insert into phase6_fixture select 'payment_300',public.post_supplier_payment((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'2026-02-11',(select value from phase6_fixture where key='bank_a'),'Golden final',
 jsonb_build_array(jsonb_build_object('purchase_id',(select value from phase6_fixture where key='golden_purchase'),'amount','300000')),'supplier-payment-golden-300');
select is((select outstanding_amount from public.purchase_open_items where purchase_id=(select value from phase6_fixture where key='golden_purchase')),0::numeric,
 'Final Rp300,000 payment settles golden AP to zero');
select is((select status::text from public.purchase_documents where id=(select value from phase6_fixture where key='golden_purchase')),'paid',
 'Fully allocated golden invoice is paid');

-- One payment across invoices.
insert into phase6_fixture select 'small_service_purchase',public.create_purchase_draft((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'SVC-002','2026-02-04','2026-03-06','credit',null,null,0,0,'Second service bill');
select public.add_purchase_line((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='small_service_purchase'),
 (select value from phase6_fixture where key='service_a'),1,50000,0,0,(select value from phase6_fixture where key='expense_a'),'Second consulting');
select public.confirm_purchase((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='small_service_purchase'),'confirm-service-purchase-002');
insert into phase6_fixture select 'multi_payment',public.post_supplier_payment((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'2026-02-12',(select value from phase6_fixture where key='bank_a'),'Multi allocation',
 jsonb_build_array(jsonb_build_object('purchase_id',(select value from phase6_fixture where key='service_purchase'),'amount','100000'),
 jsonb_build_object('purchase_id',(select value from phase6_fixture where key='small_service_purchase'),'amount','50000')),'supplier-payment-multi-001');
select is((select count(*)::integer from public.supplier_payment_allocations where payment_id=(select value from phase6_fixture where key='multi_payment')),2,
 'One supplier payment allocates across two invoices');
select is((select amount from public.supplier_payments where id=(select value from phase6_fixture where key='multi_payment')),150000::numeric,
 'Multi-invoice payment amount equals its allocations');

-- Credit product purchase and supplier return.
insert into phase6_fixture select 'return_purchase',public.create_purchase_draft((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'RET-001','2026-02-05','2026-03-07','credit',
 (select value from phase6_fixture where key='location_a'),null,0,0,'Return source');
insert into phase6_fixture select 'return_line',public.add_purchase_line((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='return_purchase'),(select value from phase6_fixture where key='product_a'),2,50000,0,0,null,'Returnable stock');
select public.confirm_purchase((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='return_purchase'),'confirm-return-source-001');
insert into phase6_fixture select 'credit_a',public.post_purchase_credit((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='return_purchase'),'2026-02-13','Return one unit',
 jsonb_build_array(jsonb_build_object('purchase_line_id',(select value from phase6_fixture where key='return_line'),'quantity','1','credit_amount','50000')),
 'purchase-credit-return-001');
select is((select credited_amount from public.purchase_open_items where purchase_id=(select value from phase6_fixture where key='return_purchase')),50000::numeric,
 'Supplier credit reduces the originating open invoice by Rp50,000');
select is((select count(*)::integer from public.purchase_credit_lines where credit_id=(select value from phase6_fixture where key='credit_a')
 and inventory_operation_id is not null),1,'Product return uses the inventory outbound authority');
select is((select quantity_delta from public.inventory_movements where operation_id=(select inventory_operation_id from public.purchase_credit_lines
 where credit_id=(select value from phase6_fixture where key='credit_a'))),(-1)::numeric,'Purchase return records an outbound inventory movement');

-- Discounts and additional costs are allocated into posted line cost.
insert into phase6_fixture select 'adjusted_purchase',public.create_purchase_draft((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'ADJ-001','2026-02-14','2026-03-16','credit',
 (select value from phase6_fixture where key='location_a'),null,5,10,'Adjusted purchase');
insert into phase6_fixture select 'adjusted_line',public.add_purchase_line((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='adjusted_purchase'),(select value from phase6_fixture where key='product_a'),2,100,10,5,null,'Adjusted stock');
select public.confirm_purchase((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='adjusted_purchase'),'confirm-adjusted-purchase-001');
select is((select posted_amount from public.purchase_lines where id=(select value from phase6_fixture where key='adjusted_line')),200::numeric,
 'Line and document discounts/additional costs produce a deterministic posted amount');

-- AP aging and reconciliation.
select ok((select exists(select 1 from public.get_ap_aging((select value from phase6_fixture where key='org_a'),'2026-04-30')
 where purchase_id=(select value from phase6_fixture where key='return_purchase') and outstanding_amount=50000 and aging_bucket='31_60')),
 'AP aging reports outstanding supplier invoices in the correct bucket');
select is((select sum(outstanding_amount) from public.purchase_open_items),
 (select credit_balance-debit_balance from public.get_trial_balance((select value from phase6_fixture where key='org_a'),null)
   where account_id=(select value from phase6_fixture where key='ap_a')),
 'Derived AP open items reconcile to the AP control account');

-- Cash purchase refund uses the original cash/bank account and never AP.
insert into phase6_fixture select 'cash_service_purchase',public.create_purchase_draft((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'CASH-SVC-001','2026-02-14','2026-02-14','cash',null,
 (select value from phase6_fixture where key='cash_a'),0,0,'Cash service return');
insert into phase6_fixture select 'cash_service_line',public.add_purchase_line((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='cash_service_purchase'),(select value from phase6_fixture where key='service_a'),1,10000,0,0,
 (select value from phase6_fixture where key='expense_a'),'Refundable cash service');
select public.confirm_purchase((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='cash_service_purchase'),
 'confirm-cash-service-001');
insert into phase6_fixture select 'cash_service_credit',public.post_purchase_credit((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='cash_service_purchase'),'2026-02-14','Cash service refund',
 jsonb_build_array(jsonb_build_object('purchase_line_id',(select value from phase6_fixture where key='cash_service_line'),'quantity','1','credit_amount','10000')),
 'credit-cash-service-001');
select is((select status::text from public.purchase_documents where id=(select value from phase6_fixture where key='cash_service_purchase')),'credited',
 'A fully refunded cash purchase becomes credited');
select is((select debit from public.journal_lines where journal_entry_id=(select journal_entry_id from public.purchase_credit_lines
 where credit_id=(select value from phase6_fixture where key='cash_service_credit')) and account_id=(select value from phase6_fixture where key='cash_a')),
 10000::numeric,'Cash purchase refund debits the original cash account');
select is((select inventory_operation_id from public.purchase_credit_lines where credit_id=(select value from phase6_fixture where key='cash_service_credit')),
 null::uuid,'A cash service refund creates no inventory movement');

-- Atomic rollback after an earlier product line succeeds inside confirmation.
insert into phase6_fixture select 'rollback_expense',public.create_subaccount((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='expense_a'),'5299','Rollback Expense','expense','debit');
insert into phase6_fixture select 'rollback_purchase',public.create_purchase_draft((select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='supplier_a'),'ROLLBACK-001','2026-02-15','2026-03-17','credit',
 (select value from phase6_fixture where key='location_a'),null,0,0,'Rollback test');
select public.add_purchase_line((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='rollback_purchase'),
 (select value from phase6_fixture where key='product_a'),1,1000,0,0,null,'First product line');
select public.add_purchase_line((select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='rollback_purchase'),
 (select value from phase6_fixture where key='service_a'),1,1000,0,0,(select value from phase6_fixture where key='rollback_expense'),'Failing service line');
select public.deactivate_account((select value from phase6_fixture where key='rollback_expense'));
select throws_ok(format('select public.confirm_purchase(%L,%L,%L)',(select value from phase6_fixture where key='org_a'),
 (select value from phase6_fixture where key='rollback_purchase'),'confirm-rollback-purchase-001'),
 '23503','active_account_not_found','A mid-confirmation accounting failure rejects the whole purchase');
select is((select status::text from public.purchase_documents where id=(select value from phase6_fixture where key='rollback_purchase')),'draft',
 'Failed confirmation leaves the purchase draft');
select is((select count(*)::integer from public.inventory_operations where source_reference=(select document_number from public.purchase_documents
 where id=(select value from phase6_fixture where key='rollback_purchase'))),0,'Failed confirmation rolls back earlier inventory effects');

-- Closed period rejection.
select public.close_accounting_period((select value from phase6_fixture where key='period_a'),'Phase 6 closed period test');
select throws_ok(format('select public.post_supplier_payment(%L,%L,%L,%L,%L,%L::jsonb,%L)',
 (select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='supplier_a'),'2026-02-20',
 (select value from phase6_fixture where key='bank_a'),'Closed payment',
 jsonb_build_array(jsonb_build_object('purchase_id',(select value from phase6_fixture where key='return_purchase'),'amount','1000'))::text,
 'supplier-payment-closed-001'),'23514','open_accounting_period_required','Closed period rejects supplier payment posting');
select is((select count(*)::integer from public.supplier_payments where idempotency_key='supplier-payment-closed-001'),0,
 'Closed-period payment leaves no partial payment record');
select public.reopen_accounting_period((select value from phase6_fixture where key='period_a'),'Continue Phase 6 tests');

-- Tenant and permission boundaries.
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000001',true);
insert into phase6_fixture values('org_b',public.create_organization('Purchases B','IDR'));
select public.initialize_accounting((select value from phase6_fixture where key='org_b'),'retail','2026-01-01','2026-12-31');
select public.initialize_inventory((select value from phase6_fixture where key='org_b'));
insert into phase6_fixture select 'supplier_b',public.create_party((select value from phase6_fixture where key='org_b'),'Supplier B','Supplier B',false,true,0,0,null,null,null,null,null,'not_set',null);
select is((select count(*)::integer from public.purchase_documents where organization_id=(select value from phase6_fixture where key='org_a')),0,
 'Organization B cannot read Organization A purchases');
select throws_ok(format('select public.create_purchase_draft(%L,%L,null,%L,%L,%L,null,null,0,0,null)',
 (select value from phase6_fixture where key='org_b'),(select value from phase6_fixture where key='supplier_a'),'2026-02-01','2026-02-01','credit'),
 '23503','active_supplier_required','Cross-organization supplier reference is rejected');

select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);
insert into phase6_fixture select 'admin_a',public.invite_member((select value from phase6_fixture where key='org_a'),
 '71000000-0000-0000-0000-000000000002','purchase-admin-a@example.test','admin_accountant');
select public.activate_member((select value from phase6_fixture where key='admin_a'));
insert into phase6_fixture select 'staff_a',public.invite_member((select value from phase6_fixture where key='org_a'),
 '71000000-0000-0000-0000-000000000003','purchase-staff-a@example.test','staff');
select public.activate_member((select value from phase6_fixture where key='staff_a'));
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000003',true);
select is((select count(*)::integer from public.purchase_documents where organization_id=(select value from phase6_fixture where key='org_a')),0,
 'Staff has no purchase read permission by default');
select throws_ok(format('select public.create_purchase_draft(%L,%L,null,%L,%L,%L,null,null,0,0,null)',
 (select value from phase6_fixture where key='org_a'),(select value from phase6_fixture where key='supplier_a'),'2026-02-01','2026-02-01','credit'),
 '42501','permission_denied','Staff cannot create purchases by default');
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000002',true);
select ok((select count(*)>0 from public.purchase_documents where organization_id=(select value from phase6_fixture where key='org_a')),
 'Admin/Accountant can read purchases');
select ok((select count(*)>0 from public.audit_events where organization_id=(select value from phase6_fixture where key='org_a') and action='purchase.confirmed'),
 'Purchase confirmations emit audit events');

select * from finish();
rollback;
