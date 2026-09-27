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

## 6. Phase 4 — Parties, catalog, sales, and AR

Implement customers, products/services, document numbering, sales invoices, receipts, partial allocations, source-to-journal posting, tax-engine interface (only professionally approved initial rules), and basic P&L/financial-position effects. Defer stocked-product confirmation until inventory integration is available or restrict the phase to services/non-stock items.

Exit: cash/credit service-sale scenarios reconcile through AR and GL, including reversal and closed-period behavior.

## 7. Phase 5 — Inventory and stocked sales

Implement locations/default location, inventory movements, locked weighted-average cost state, opening inventory detail, purchases needed to receive stock, sale issues, COGS, returns/corrections, and inventory valuation/control reconciliation. Finalize policies for negative stock, backdating, returns, landed cost, and rounding before coding their behavior.

Exit: concurrency and property tests reproduce quantity/value/COGS and reconcile inventory to GL.

## 8. Phase 6 — Purchases, AP, expenses, and cash/bank

Complete suppliers, purchase bills, AP allocations/payments, expense flows, cash/bank accounts, transfers, fees, corrections, and subledger reporting. Expand opening balances for detailed AR/AP and add aging reports.

Exit: end-to-end operating cycle (purchase → stock/expense → sale → receipt/payment) reconciles across subledgers, inventory, cash/bank, and GL.

## 9. Phase 7 — Management reporting and accounting integration

Integrate the Phase 2 metadata with accounting entities, snapshot dimensions on postings, and implement dashboards plus allowlisted management reports. Keep standard report semantics protected and extend saved views without accepting executable query fragments.

Exit: malicious/invalid metadata fails closed; customization cannot alter accounting, tenant, security, or audit invariants.

## 10. Phase 8 — Documents, OCR, imports, and exports

Implement private upload validation, document linking, OCR provider benchmark/adapter, Indonesian normalization, matching/duplicates, editable draft review, and explicit confirmation. Add staged imports with preview/idempotency and audited background exports with short-lived private downloads.

Exit: OCR/import output cannot post without authorized confirmation; failure/retry/duplicate/privacy tests pass.

## 11. Phase 9 — Production readiness and external beta

Complete staging, monitoring/alerts, quotas and OCR metering, backup/PITR and restore drill, incident/data-request runbooks, accessibility/performance review, security assessment, legal/privacy review, accountant/tax acceptance, SAK EMKM wording decision, support procedures, and production access controls.

Exit: operational owners accept RPO/RTO, restore and reconciliation evidence, security findings are resolved or explicitly accepted, and no unreviewed compliance claims remain.

## 12. Post-MVP candidates

FIFO costing, transaction-level multi-currency/FX, cash-flow statements, advanced tax filing integrations, payroll, manufacturing, automatic bank feeds/reconciliation, full offline drafts, consolidated/multi-entity reporting, and broader roles/users require new reviewed architecture decisions rather than silent expansion. Organization base currency already accepts any valid three-letter currency code; the deferred item is posting and settling transactions in multiple currencies.

## 13. Recommended Phase 4 first slice

Start with customers, products/services, document numbering, service/non-stock sales invoices, customer receipts, and AR allocation history. Route confirmation, receipt, reversal, and retry through the Phase 3 posting authority and reconcile AR to its control account. Defer stocked-product confirmation until the inventory movement and weighted-average costing authority is implemented.
