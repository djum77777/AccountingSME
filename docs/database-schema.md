# Database Schema

> Implementation note: Phases 1–3 are materialized. Phase 3 adds `currencies`, `accounting_template_accounts`, `accounting_profiles`, `accounts`, `accounting_periods`, `journal_entries`, `journal_lines`, `opening_balance_batches`, `general_ledger`, and the protected posting/reporting functions in `202609270003_phase3_accounting_core.sql`.

## 1. Conventions

PostgreSQL managed by Supabase is the authoritative structured-data store. Names below are logical names; migrations may use snake_case tables and columns exactly as shown.

- Primary keys: UUID or sortable UUID-compatible identifiers generated server-side.
- Tenant ownership: every tenant-owned table has non-null `organization_id` and organization-inclusive foreign keys where possible.
- Time: `timestamptz` in UTC; business date is a separate `date`.
- Money: `numeric(20,4)` initially, plus ISO 4217 `currency_code`; never float. Quantity and unit cost may require greater precision (`numeric(24,8)`). Final precision requires accountant/domain review.
- Audit columns: `created_at`, `created_by`, and where mutable, `updated_at`, `updated_by`.
- Soft lifecycle is represented by explicit status, not generic deletion. Posted financial records are never deleted.
- Canonical statuses and roles are defined in [product-architecture.md](product-architecture.md).

## 2. Identity and tenancy

### `organizations`

`id`, `legal_name`, `display_name`, `status`, `base_currency_code`, `timezone`, `default_locale`, `tax_profile_id`, timestamps.

### `user_profiles`

Application profile keyed to trusted auth-provider user ID. Contains display name and non-secret preferences; no password material.

### `organization_memberships`

`id`, `organization_id`, `user_id`, `role` (`owner`, `admin_accountant`, `staff`), `status` (`invited`, `active`, `suspended`, `deactivated`), invitation and activation timestamps. Membership rows are retained rather than physically deleted.

Constraints/policies:

- unique active/invited identity per organization as appropriate;
- transactionally enforce active memberships against an organization entitlement that defaults to 3 seats;
- prevent removal/demotion of the last active owner;
- membership role alone does not replace permission checks.

`organization_entitlements` stores the platform-controlled active-seat limit. Tenant owners may read but cannot increase it. `membership_activation_requests` and `membership_role_change_requests` retain the requesting owner, approving higher-authority actor, decision, and audit context. Monetization is deferred, but the entitlement boundary prevents a later billing feature from weakening tenant controls.

### `role_permission_grants`

Optional organization-level refinement of named capabilities. Protected owner-only capabilities cannot be delegated through this table.

## 3. Foundation and configuration

- `organization_settings`: numbering, feature flags, locale defaults, and approved operational settings.
- `accounting_periods`: `start_date`, `end_date`, `status` (`open`, `closed`), close/reopen actor and timestamps; no overlapping periods per organization.
- `currencies`: global read-only ISO reference data.
- `exchange_rates`: organization or trusted-source rates, effective date, source, and precision. Multi-currency posting policy is deferred.
- `sequences`: organization-scoped document numbering with database-safe allocation.
- `customization_definitions`, `custom_field_values`, `saved_views`, `dashboard_definitions`, `management_report_definitions`: described in [customization-engine.md](customization-engine.md).

## 4. Parties and catalog

- `customers`: organization-scoped identity, contact, billing metadata, status.
- `suppliers`: organization-scoped identity, contact, payment metadata, status.
- `products`: SKU, product/service kind, sales/purchase defaults, inventory-tracked flag, unit of measure, status.
- `inventory_locations`: optional organization-scoped locations; one default location when location tracking is not exposed.
- `units_of_measure`: protected codes plus organization display labels.

Sensitive identifiers should be minimized and protected based on classification. Custom fields reference these records but cannot replace protected core identifiers.

## 5. Chart of Accounts and ledger

### `accounts`

`id`, `organization_id`, `code`, `name`, `category`, optional `parent_account_id`, `normal_balance`, `is_control_account`, `status`, and system-purpose metadata. Implemented categories are `asset`, `liability`, `equity`, `income`, and `expense`; further professional presentation categories remain a review question. An account is never deleted through the application; referenced identity fields are immutable and deactivation preserves history.

### `journal_entries`

`id`, `organization_id`, `entry_number`, `accounting_date`, `status` (`draft`, `posted`, `reversed`), `entry_kind` (standard, adjustment, opening, reversal, system), description, `source_type`, `source_id`, `reversal_of_entry_id`, posting actor/time, currency and idempotency metadata.

### `journal_lines`

`id`, `organization_id`, `journal_entry_id`, `line_number`, `account_id`, description, `debit`, `credit`, currency data, optional party/product references, and supported dimension assignments.

Database rules must ensure non-negative debit/credit, exactly one side is positive per line, and organization-safe foreign keys. Deferred constraint triggers or a trusted posting function must guarantee at least two lines and sum(debit) = sum(credit) before a journal becomes `posted`. Posted entries and lines reject update/delete except for the controlled, atomic original-header transition from `posted` to `reversed` when its linked reversal is posted; accounting content remains immutable. Reversal links are unique and organization-local.

### `opening_balance_batches`

Header and source details used to validate an opening position before producing one balanced `opening` journal. Inventory, AR, and AP subledger openings retain source detail and reconcile to control accounts.

## 6. Operational transactions

### Sales and AR

- `sales_invoices`: customer, issue/due dates, currency, status (`draft`, `confirmed`, `voided`), totals, tax snapshot, and source document references.
- `sales_invoice_lines`: product/service, quantity, unit price, discounts, tax selection/snapshot, revenue account, dimensions.
- `customer_receipts`: receipt details and status.
- `ar_allocations`: immutable allocation records between receipts/credits and invoices; reversals preserve original allocations.

Settlement (`unpaid`, `partially_paid`, `paid`, `overpaid`) is derived from confirmed amount less active allocations.

### Purchases and AP

- `purchase_bills`, `purchase_bill_lines`, `supplier_payments`, and `ap_allocations` mirror the sales principles.
- A purchase line explicitly classifies inventory, expense, asset, or other permitted destination; the accounting engine owns resulting journal mappings.

### Expenses and cash/bank

- `expenses`, `expense_lines`: payee, date, account classification, tax, payment state, and dimensions.
- `cash_bank_accounts`: link operational cash/bank records to one ledger account.
- `cash_bank_transactions`: receipts, payments, and transfers. A transfer is one business command producing balanced effects, not two unrelated edits.
- `payment_allocations`: shared abstraction only if it does not obscure AR/AP-specific constraints; otherwise retain explicit allocation tables.

Operational documents link to their posted journal by source reference. Unique organization-scoped constraints prevent duplicate active posting for the same purpose.

## 7. Inventory and costing

### `inventory_movements`

`id`, `organization_id`, `product_id`, `location_id`, `movement_date`, `movement_type`, quantity in/out, unit cost, total cost, `status` (`draft`, `posted`, `reversed`), `source_type`, `source_id`, and reversal link.

Movement types include opening, purchase_receipt, sale_issue, customer_return, supplier_return, adjustment_in, adjustment_out, and transfer legs. Negative-stock policy is an explicit organization setting only after accountant/product approval; the default remains undecided.

### `inventory_cost_layers` / `inventory_cost_state`

For weighted average, maintain an organization/product/location state containing quantity on hand, inventory value, and average unit cost, updated under row locking in the same transaction as a posted movement. Preserve each movement's calculated cost and before/after state so results can be reproduced. A future FIFO implementation may add cost layers behind the same costing interface.

## 8. Tax

- `tax_rule_sets`: globally curated or organization-specific version container.
- `tax_rules`: rule type, rate, calculation base, eligibility criteria, effective start/end dates, authority/source, review status, and immutable version.
- `organization_tax_profiles`: registrations, elections, applicability and dates; sensitive values protected.
- `transaction_tax_calculations`: applied rule version, inputs, rounding, taxable base, amount, overrides, reason, and reviewer.

Historical transactions always use stored snapshots and never change when a later rule version is introduced. See [tax-architecture.md](tax-architecture.md).

## 9. Documents, OCR, imports, exports, and audit

- `documents`: organization, private object key, checksum, original filename, detected/declared MIME, size, classification, uploader, retention state.
- `document_links`: typed links to invoices, bills, expenses, or other supported records.
- `ocr_jobs`: canonical status, provider, provider request reference, attempts, extraction version, confidence summary, errors, and timestamps.
- `ocr_extractions`: raw provider result location and normalized structured result; neither is a posting instruction.
- `import_jobs`, `import_rows`: mapping version, validation outcomes, duplicate keys, review decisions, commit status, and idempotency key.
- `export_jobs`: request scope, requester, status, expiry, object key, and audit link.
- `audit_events`: append-only event ID, organization, actor, action, target type/ID, timestamp, request/correlation ID, source IP/device metadata where lawful, and redacted before/after or structured change summary.
- `outbox_events`: transactionally recorded asynchronous messages with retry and delivery state.

## 10. RLS and ownership rules

RLS is enabled on every tenant-owned table. Policies require an active membership for `organization_id` and, where relevant, capability checks. Service credentials bypassing RLS are restricted to tightly scoped server jobs that independently assert organization context. Storage object keys begin with an opaque organization namespace and storage access policies mirror database ownership.

No client-supplied `organization_id` is trusted. Server code resolves permitted organization context from the authenticated membership, and inserts validate it against related rows.

## 11. Indexes and reconciliation constraints

Minimum indexes cover organization plus business date/status, foreign keys, document numbers, party/product lookup, journal source, and audit time. Unique constraints are organization-scoped. Reconciliation queries must efficiently prove:

- every posted journal balances;
- GL control accounts equal AR/AP/inventory subledgers at a cutoff;
- every posted source has the expected journal(s);
- inventory quantity/value tie to posted movements;
- no posted record falls in a closed period after its close timestamp without an audited reopen.

## 12. Migration policy

All schema, functions, RLS policies, and seed reference data are version-controlled migrations. Migrations are forward-tested on representative data, reviewed for locks/data loss, and applied through environment-specific deployment controls. Destructive schema changes require an export/backup, a compatibility plan, and explicit approval.

## 13. Phase 4 physical schema implemented

Migration `202610010004_phase4_inventory.sql` implements `product_categories`, `organization_units`, `inventory_locations`, `products`, `inventory_operations`, append-only `inventory_movements`, protected `inventory_cost_states`, and the `inventory_valuation` and `inventory_low_stock` security-invoker views. Inventory balances are projections of movement history; application roles cannot directly mutate them. Products and services share the catalog while database constraints prevent service inventory tracking.
