# MVP Roadmap

## 1. Delivery rules

This roadmap is dependency ordered. Each phase begins by reading these architecture documents, checking the repository, and creating a clean checkpoint. Each phase includes migrations, RLS, tests, observability, and documentation for its scope. No phase may route around the accounting engine or defer tenant-isolation tests.

Phase 0 produces documentation only; it does not implement the application.

## 2. Phase 0 — Architecture baseline (complete)

Deliver and review the eleven documents in `docs/`. Obtain product decisions and qualified Indonesian accountant/tax/legal review on the open assumptions. Convert accepted answers into versioned policy specifications and golden test examples. Establish architecture change review: material changes update all affected documents before implementation.

Exit: terminology, statuses, roles, ownership, accounting policies selected for the first slice, MVP tax scope, and compliance wording are approved.

## 3. Phase 1 — Repository and secure tenancy foundation

1. Scaffold Next.js + TypeScript modular monolith and quality tooling.
2. Configure local/test Supabase/PostgreSQL, migrations, typed environment validation, CI, and test harness.
3. Implement trusted auth integration, organization, profile, retained membership history, canonical RBAC/capabilities, default three-seat entitlement, owner-approved activation, protected future entitlement override boundary, and last-owner protection.
4. Add RLS to all foundation tables, private storage skeleton, append-only audit foundation, request correlation, and structured error/log conventions.
5. Provide a minimal bilingual shell and organization/locale selection.

Exit: automated cross-tenant/RBAC tests pass; organization A cannot read/write organization B by API, database, or storage path. No accounting screens are needed yet.

## 4. Phase 2 — SME onboarding and customization foundation (complete)

1. Provide the bilingual onboarding sequence: language, business type, business information, recommended template, and basic settings.
2. Seed General SME, Retail, Online Seller, Trading/Distributor, and Service templates; clone defaults into editable organization configuration.
3. Implement allowlisted module/navigation visibility and display-label aliases without changing stable identifiers.
4. Implement metadata-driven custom fields and dimensions, form-field configuration, and saved table views.
5. Protect ownership, roles, accounting status/mathematics, costing, RLS, and audit integrity; audit organization-wide configuration changes.
6. Prove cross-tenant isolation, archived-field history retention, and reset-without-business-data-deletion in PostgreSQL tests.

Exit: two organizations can use different templates and metadata with complete isolation; reset restores template-derived settings while preserving business-facing custom metadata and values.

## 5. Phase 3 — Ledger foundation (complete)

1. Chart of Accounts with reviewed Indonesian SME template and protected account rules.
2. Accounting periods and owner close/reopen audit controls.
3. Decimal/money primitives, transaction/idempotency conventions, journals/lines, posting function/service, reversals, and audit/outbox integration.
4. General Ledger and Trial Balance with reconciliation checks.
5. Opening-balance batch for initial simple accounts, then detailed AR/AP/inventory once those subledgers exist.

Exit achieved: accounting invariants, atomic rollback, immutability, reversal, period, tenant/RBAC, two-session concurrency, General Ledger, and Trial Balance tests pass against PostgreSQL. The seeded account policy remains explicitly subject to qualified Indonesian accountant review.

## 6. Phase 4 — Product/service masters and inventory costing (complete)

Implemented catalog categories/units/SKU/barcode, services, inventory-tracked products, locations, opening stock, stock in/out, adjustments, damage/loss, stock counts, transfers, low-stock query, immutable movement history, locked weighted-average cost, valuation, central-journal integration, RLS, and concurrency/reconciliation tests.

Exit achieved: the required 10@Rp10,000 + 10@Rp14,000 − 5 example produces 15 units valued at Rp180,000; accounting failures roll back inventory; historical cost snapshots and tenant isolation are proven.

## 7. Phase 5 — Customer and supplier masters (complete)

Implemented organization-scoped customer/supplier roles on stable party identities, retained archive/reactivation history, contacts, typed addresses, role-specific payment terms, optional tax metadata, notes, Phase 2 contact custom fields, advisory duplicate checks, directory search, bilingual workflows, RLS, audit events, and imports-ready external references. No purchase, sales, payment, AR, or AP transactions were introduced, and party records contain no editable balance fields.

Exit achieved: two tenants maintain isolated party masters; archive/reactivation preserves history and stable identifiers; duplicate, permission, audit, metadata, and cross-tenant tests pass.

## 8. Phase 6 — Purchases and AP

Implement purchase document numbering, purchase bills/receipts, inventory receipts through the Phase 4 authority, expenses, AP allocations/payments, supplier returns/corrections, and AP aging/control reconciliation.

Exit: purchase-to-stock/expense-to-payment scenarios reconcile inventory, AP, cash/bank, and GL, including retry, reversal, and closed-period behavior.

## 9. Phase 7 — Sales, AR, receipts, returns, and COGS

Implement sales document numbering, sales invoices, customer receipts and partial allocations, inventory issues through the Phase 4 authority, COGS, returns/corrections, the professionally approved tax-engine interface, and AR aging/control reconciliation.

Exit: cash/credit stocked and service sales reconcile AR, inventory, COGS, tax, cash/bank, and GL under retry, reversal, and closed-period scenarios.

## 10. Phase 8 — Management reporting and accounting integration

Integrate the Phase 2 metadata with accounting entities, snapshot dimensions on postings, and implement dashboards plus allowlisted management reports. Keep standard report semantics protected and extend saved views without accepting executable query fragments.

Exit: malicious/invalid metadata fails closed; customization cannot alter accounting, tenant, security, or audit invariants.

## 11. Phase 9 — Documents, OCR, imports, and exports

Implement private upload validation, document linking, OCR provider benchmark/adapter, Indonesian normalization, matching/duplicates, editable draft review, and explicit confirmation. Add staged imports with preview/idempotency and audited background exports with short-lived private downloads.

Exit: OCR/import output cannot post without authorized confirmation; failure/retry/duplicate/privacy tests pass.

## 12. Phase 10 — Production readiness and external beta

Complete staging, monitoring/alerts, quotas and OCR metering, backup/PITR and restore drill, incident/data-request runbooks, accessibility/performance review, security assessment, legal/privacy review, accountant/tax acceptance, SAK EMKM wording decision, support procedures, and production access controls.

Exit: operational owners accept RPO/RTO, restore and reconciliation evidence, security findings are resolved or explicitly accepted, and no unreviewed compliance claims remain.

## 13. Post-MVP candidates

FIFO costing, transaction-level multi-currency/FX, cash-flow statements, advanced tax filing integrations, payroll, manufacturing, automatic bank feeds/reconciliation, full offline drafts, consolidated/multi-entity reporting, and broader roles/users require new reviewed architecture decisions rather than silent expansion. Organization base currency already accepts any valid three-letter currency code; the deferred item is posting and settling transactions in multiple currencies.

## 14. Recommended Phase 5 first slice

Start with customer and supplier masters, retained deactivation history, duplicate detection, contacts/addresses/tax identifiers, RLS, and bilingual list/detail screens. Keep purchasing and sales documents in their dependency-ordered Phases 6 and 7 so they consume stable party identifiers and the tested Phase 4 costing authority.
