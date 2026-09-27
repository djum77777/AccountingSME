begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

insert into auth.users(id,email,aud,role) values
 ('41000000-0000-0000-0000-000000000001','ledger-owner-a@example.test','authenticated','authenticated'),
 ('41000000-0000-0000-0000-000000000002','ledger-admin-a@example.test','authenticated','authenticated'),
 ('41000000-0000-0000-0000-000000000003','ledger-staff-a@example.test','authenticated','authenticated'),
 ('42000000-0000-0000-0000-000000000001','ledger-owner-b@example.test','authenticated','authenticated');

create temporary table phase3_fixture(key text primary key,value uuid not null) on commit drop;
grant all on phase3_fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);

insert into phase3_fixture values('org_a',public.create_organization('Toko Maju Jaya','IDR'));
select lives_ok(format('select public.initialize_accounting(%L,%L,%L,%L)',
 (select value from phase3_fixture where key='org_a'),'retail','2026-01-01','2026-12-31'),
 'Owner initializes a template chart and first accounting period');
select is((select count(*)::integer from public.accounts where organization_id=(select value from phase3_fixture where key='org_a')),18,
 'Retail chart seeds the expected stable account set');
select is((select count(*)::integer from public.accounting_periods where organization_id=(select value from phase3_fixture where key='org_a')),1,
 'Initialization creates one open accounting period');
insert into phase3_fixture select 'subaccount_a',public.create_subaccount((select value from phase3_fixture where key='org_a'),
 (select id from public.accounts where organization_id=(select value from phase3_fixture where key='org_a') and code='5200'),
 '5210','Beban Internet','expense','debit');
select lives_ok(format('select public.rename_account(%L,%L)',(select value from phase3_fixture where key='subaccount_a'),'Beban Internet & Cloud'),
 'Owner can adjust an allowed account display label without changing stable identity');
select is((select name from public.accounts where id=(select value from phase3_fixture where key='subaccount_a')),'Beban Internet & Cloud',
 'Account label changes persist while code and category remain stable');
select lives_ok(format('select public.deactivate_account(%L)',(select value from phase3_fixture where key='subaccount_a')),
 'An unused custom subaccount can be deactivated rather than deleted');

select set_config('request.jwt.claim.sub','42000000-0000-0000-0000-000000000001',true);
insert into phase3_fixture values('org_b',public.create_organization('Service Ledger B','USD'));
select lives_ok(format('select public.initialize_accounting(%L,%L,%L,%L)',
 (select value from phase3_fixture where key='org_b'),'service','2026-01-01','2026-12-31'),
 'A second organization independently initializes a different template and currency');
select is((select count(*)::integer from public.accounts where organization_id=(select value from phase3_fixture where key='org_a')),0,
 'Organization B cannot read Organization A accounts through RLS');
insert into phase3_fixture
select 'cash_b',id from public.accounts where organization_id=(select value from phase3_fixture where key='org_b') and system_purpose='cash';

select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
insert into phase3_fixture
select 'cash_a',id from public.accounts where organization_id=(select value from phase3_fixture where key='org_a') and system_purpose='cash';
insert into phase3_fixture
select 'capital_a',id from public.accounts where organization_id=(select value from phase3_fixture where key='org_a') and system_purpose='owner_capital';
insert into phase3_fixture
select 'period_a',id from public.accounting_periods where organization_id=(select value from phase3_fixture where key='org_a');

insert into phase3_fixture
select 'opening_a',public.post_opening_balance(
 (select value from phase3_fixture where key='org_a'),'2026-01-01','Saldo awal Toko Maju Jaya',
 jsonb_build_array(
  jsonb_build_object('account_id',(select value from phase3_fixture where key='cash_a'),'debit','1000000.0000','credit','0'),
  jsonb_build_object('account_id',(select value from phase3_fixture where key='capital_a'),'debit','0','credit','1000000.0000')),
 'golden-opening-2026');
select ok((select status='posted' and total_debit=1000000 and total_credit=1000000 from public.journal_entries where id=(select value from phase3_fixture where key='opening_a')),
 'Balanced opening balance posts atomically with equal totals');
select is((select count(*)::integer from public.opening_balance_batches where journal_entry_id=(select value from phase3_fixture where key='opening_a')),1,
 'Opening balances retain their explicit batch provenance');
select is((select count(*)::integer from public.general_ledger where journal_entry_id=(select value from phase3_fixture where key='opening_a')),2,
 'General ledger is derived from both posted journal lines');
select is((select sum(total_debit)::numeric from public.get_trial_balance((select value from phase3_fixture where key='org_a'),null)),1000000::numeric,
 'Trial balance derives posted debit totals');
select is((select sum(total_credit)::numeric from public.get_trial_balance((select value from phase3_fixture where key='org_a'),null)),1000000::numeric,
 'Trial balance derives posted credit totals');

select throws_ok(format($sql$select public.post_journal(%L,'2026-02-01','Unbalanced','test',
 '[{"account_id":"%s","debit":"25","credit":"0"},{"account_id":"%s","debit":"0","credit":"20"}]'::jsonb,'unbalanced-attempt')$sql$,
 (select value from phase3_fixture where key='org_a'),(select value from phase3_fixture where key='cash_a'),(select value from phase3_fixture where key='capital_a')),
 '23514','journal_not_balanced','Unbalanced journals are rejected');
select is((select count(*)::integer from public.journal_entries where organization_id=(select value from phase3_fixture where key='org_a') and idempotency_key='unbalanced-attempt'),0,
 'A failed post rolls back its header and all partial lines');
select throws_ok(format($sql$select public.post_journal(%L,'2026-02-01','Cross tenant account','test',
 '[{"account_id":"%s","debit":"25","credit":"0"},{"account_id":"%s","debit":"0","credit":"25"}]'::jsonb,'cross-tenant-attempt')$sql$,
 (select value from phase3_fixture where key='org_a'),(select value from phase3_fixture where key='cash_b'),(select value from phase3_fixture where key='capital_a')),
 '23503','active_account_not_found','A journal cannot reference another organization account');
select is((select count(*)::integer from public.journal_entries where organization_id=(select value from phase3_fixture where key='org_a') and idempotency_key='cross-tenant-attempt'),0,
 'Cross-tenant validation failure leaves no partial journal');
select throws_ok(format($sql$select public.post_journal(%L,'2026-02-01','Too precise','test',
 '[{"account_id":"%s","debit":"1.00001","credit":"0"},{"account_id":"%s","debit":"0","credit":"1.00001"}]'::jsonb,'precision-attempt')$sql$,
 (select value from phase3_fixture where key='org_a'),(select value from phase3_fixture where key='cash_a'),(select value from phase3_fixture where key='capital_a')),
 '22023','amount_precision_exceeded','Amounts beyond the central four-decimal scale are rejected rather than silently rounded');

select is(public.post_opening_balance((select value from phase3_fixture where key='org_a'),'2026-01-01','Saldo awal Toko Maju Jaya',
 jsonb_build_array(jsonb_build_object('account_id',(select value from phase3_fixture where key='cash_a'),'debit','1000000.0000','credit','0'),
 jsonb_build_object('account_id',(select value from phase3_fixture where key='capital_a'),'debit','0','credit','1000000.0000')),'golden-opening-2026'),
 (select value from phase3_fixture where key='opening_a'),'An idempotent retry returns the original posted journal');
select is((select count(*)::integer from public.journal_entries where organization_id=(select value from phase3_fixture where key='org_a') and idempotency_key='golden-opening-2026'),1,
 'Idempotent retries never create duplicate journals');
select throws_ok(format($sql$select public.post_opening_balance(%L,'2026-01-01','Changed retry',
 '[{"account_id":"%s","debit":"1000000","credit":"0"},{"account_id":"%s","debit":"0","credit":"1000000"}]'::jsonb,'golden-opening-2026')$sql$,
 (select value from phase3_fixture where key='org_a'),(select value from phase3_fixture where key='cash_a'),(select value from phase3_fixture where key='capital_a')),
 '23505','idempotency_payload_mismatch','An opening-balance key cannot be reused with a changed payload');

select set_config('request.jwt.claim.sub','42000000-0000-0000-0000-000000000001',true);
select lives_ok(format($sql$select public.post_journal(%L,'2026-02-01','Same key, other tenant','test',
 '[{"account_id":"%s","debit":"10","credit":"0"},{"account_id":"%s","debit":"0","credit":"10"}]'::jsonb,'golden-opening-2026')$sql$,
 (select value from phase3_fixture where key='org_b'),
 (select id from public.accounts where organization_id=(select value from phase3_fixture where key='org_b') and system_purpose='cash'),
 (select id from public.accounts where organization_id=(select value from phase3_fixture where key='org_b') and system_purpose='owner_capital')),
 'The same idempotency key is isolated and valid in another organization');

select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
select throws_ok(format('select public.create_accounting_period(%L,%L,%L,%L)',(select value from phase3_fixture where key='org_a'),'Overlap','2026-06-01','2027-05-31'),
 '23514','accounting_period_overlap','Overlapping periods are rejected');

insert into phase3_fixture select 'admin_a',public.invite_member((select value from phase3_fixture where key='org_a'),
 '41000000-0000-0000-0000-000000000002','ledger-admin-a@example.test','admin_accountant');
select public.activate_member((select value from phase3_fixture where key='admin_a'));
insert into phase3_fixture select 'staff_a',public.invite_member((select value from phase3_fixture where key='org_a'),
 '41000000-0000-0000-0000-000000000003','ledger-staff-a@example.test','staff');
select public.activate_member((select value from phase3_fixture where key='staff_a'));

select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000003',true);
select throws_ok(format($sql$select public.post_journal(%L,'2026-02-01','Staff attempt','test',
 '[{"account_id":"%s","debit":"10","credit":"0"},{"account_id":"%s","debit":"0","credit":"10"}]'::jsonb,'staff-attempt')$sql$,
 (select value from phase3_fixture where key='org_a'),(select value from phase3_fixture where key='cash_a'),(select value from phase3_fixture where key='capital_a')),
 '42501','permission_denied','Staff cannot use the protected posting path without an explicit grant');
select throws_ok(format('select public.close_accounting_period(%L,%L)',(select value from phase3_fixture where key='period_a'),'Staff close'),
 '42501','owner_required','Only an owner can close a period');

select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
select lives_ok(format($sql$select public.post_journal(%L,'2026-02-01','Admin journal','test',
 '[{"account_id":"%s","debit":"10","credit":"0"},{"account_id":"%s","debit":"0","credit":"10"}]'::jsonb,'admin-post-2026')$sql$,
 (select value from phase3_fixture where key='org_a'),(select value from phase3_fixture where key='cash_a'),(select value from phase3_fixture where key='capital_a')),
 'Admin/Accountant can post through the protected posting service');

select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
select lives_ok(format('select public.close_accounting_period(%L,%L)',(select value from phase3_fixture where key='period_a'),'Year review'),
 'Owner can close an accounting period with an audit reason');
select throws_ok(format($sql$select public.post_journal(%L,'2026-02-02','Closed period','test',
 '[{"account_id":"%s","debit":"10","credit":"0"},{"account_id":"%s","debit":"0","credit":"10"}]'::jsonb,'closed-period-attempt')$sql$,
 (select value from phase3_fixture where key='org_a'),(select value from phase3_fixture where key='cash_a'),(select value from phase3_fixture where key='capital_a')),
 '23514','open_accounting_period_required','Closed periods reject posting');
select lives_ok(format('select public.reopen_accounting_period(%L,%L)',(select value from phase3_fixture where key='period_a'),'Correction approved by owner'),
 'Owner can reopen a period with a required reason and audit event');

insert into phase3_fixture select 'reversal_a',public.reverse_journal((select value from phase3_fixture where key='opening_a'),'2026-01-31','Reverse golden opening','golden-reversal-2026');
select ok((select kind='reversal' and status='posted' and reversal_of_id=(select value from phase3_fixture where key='opening_a')
 from public.journal_entries where id=(select value from phase3_fixture where key='reversal_a')),
 'Reversal is a separate posted journal linked to its source');
select is((select status::text from public.journal_entries where id=(select value from phase3_fixture where key='opening_a')),'reversed',
 'The source journal records its reversed lifecycle state');
select throws_ok(format('select public.reverse_journal(%L,%L,%L,%L)',(select value from phase3_fixture where key='opening_a'),'2026-01-31','Changed reversal reason','golden-reversal-2026'),
 '23505','idempotency_payload_mismatch','A reversal key cannot be reused with changed reversal input');
select is((select sum(debit_balance+credit_balance)::numeric from public.get_trial_balance((select value from phase3_fixture where key='org_a'),'2026-01-31')),0::numeric,
 'The golden opening and reversal net to zero at the January cutoff');
select throws_ok(format('update public.journal_entries set description=%L where id=%L','Tamper',(select value from phase3_fixture where key='reversal_a')),
 '42501','permission denied for table journal_entries','Authenticated callers cannot mutate posted headers directly');
select throws_ok(format('update public.journal_lines set debit=9 where journal_entry_id=%L',(select value from phase3_fixture where key='reversal_a')),
 '42501','permission denied for table journal_lines','Authenticated callers cannot mutate posted lines directly');
select ok((select count(*)>=4 from public.audit_events where organization_id=(select value from phase3_fixture where key='org_a')
 and action in ('accounting.initialized','journal.posted','opening_balance.posted','journal.reversed','accounting_period.closed','accounting_period.reopened')),
 'Accounting lifecycle operations emit immutable organization audit events');
select is((select sum(total_debit-total_credit)::numeric from public.get_trial_balance((select value from phase3_fixture where key='org_a'),null)),0::numeric,
 'The complete trial balance satisfies the debit-equals-credit invariant');

select * from finish();
rollback;
