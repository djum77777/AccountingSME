# Testing Strategy

> Current evidence (Phase 3): 80 pgTAP assertions pass across tenancy, customization, and accounting; a separate two-client race test proves concurrent idempotency; 13 TypeScript unit tests pass; lint, type-check, formatting, and the Next.js production build pass. See `phase-3-implementation.md`.

## 1. Quality model

Tests prioritize financial correctness, tenant isolation, authorization, immutability, reproducibility, and recovery ahead of superficial coverage percentages. Every implementation phase includes tests for its behavior and negative/security cases.

## 2. Test layers

- **Unit:** decimal calculations, journal construction, weighted-average costing, tax rule selection/calculation, allocation math, status machines, normalization, and metadata validation.
- **Property/invariant:** generated journals always balance; reversals net to zero; allocations conserve value; cost state equals movement history; locale formatting never changes stored amounts.
- **Integration:** application services with real PostgreSQL transactions, constraints, RLS, storage adapters, auth claims, outbox, and idempotent retries.
- **Database/RLS:** cross-organization reads/writes fail for every tenant table and role; constraints reject malformed/unbalanced/mutable posted data.
- **Contract:** OCR/auth/storage/provider adapters and webhook signatures with recorded/synthetic fixtures; no real sensitive documents in tests.
- **End-to-end:** critical owner/accountant/staff workflows in Indonesian and English, including mobile document capture to editable draft and explicit posting.
- **Security/operational:** dependency/secret scans, upload abuse, rate limits, session protections, backup restore, migration rehearsal, observability, and incident drills.

## 3. Mandatory accounting invariants

Automated tests must prove:

1. Posted debit total equals credit total and every entry has at least two valid lines.
2. Posted journals/lines cannot be updated or deleted through application or ordinary database roles.
3. Reversal is equal/opposite, uniquely linked, auditable, and dated in an open period.
4. Closed periods reject posting and accounting-effect changes until an authorized audited reopen.
5. Opening batches balance and AR/AP/inventory detail equals control totals.
6. AR/AP original amounts remain intact; allocations and reversals derive correct open balance/status.
7. Inventory movement history reproduces quantity, value, average cost, and COGS under approved rounding.
8. Operational confirmation, journal, inventory, audit, and outbox effects commit atomically or roll back together.
9. Idempotent retries do not duplicate documents, payments, journals, movements, or jobs.
10. Trial Balance balances; Balance Sheet equation holds; AR/AP/inventory reconcile to control accounts.
11. Tax calculations reproduce from stored rule/profile versions and snapshots.
12. No customization can alter protected accounting values, rules, ownership, permissions, or history.

## 4. Tenancy and RBAC matrix

Create at least Organizations A and B with owner, admin/accountant, and staff identities. For every API/service/table/storage path test own-tenant allowed cases, other-tenant denial, absent/suspended membership denial, URL/body tenant tampering, role/capability denial, service-job context validation, and signed-object expiry. Test the transactional seat entitlement (default 3), platform-authorized entitlement increase, owner-approved activation, retained deactivation history, and last-owner protection under concurrency.

## 5. Scenario suites

- Cash and credit sales, stocked/service lines, tax, COGS, partial/multiple receipts, returns, void/reversal.
- Inventory purchase and expense bill, partial/multiple supplier payments, returns and corrections.
- Cash/bank receipts, payments, transfers, fees, and duplicate retries.
- Opening balances with cash, inventory, AR, AP, loans, assets, and equity.
- Period close prechecks, denial, close, attempted mutation, reopen reason, and audit.
- OCR success, low confidence, ambiguous Indonesian formats, duplicate document, provider timeout/retry, malicious file, and confirmation.
- Imports with mapping/validation/preview, partial error handling, duplicate idempotency, explicit commit, and rollback.
- Standard report and export reconciliation across dates, timezones, locales, reversals, and custom dimensions.

## 6. Numerical and temporal edge cases

Use boundary/property fixtures for zero, very small/large values, fractional quantities, rounding residuals, tax-inclusive/exclusive calculations, discounts, leap dates, timezone midnight, period boundaries, concurrent movements, backdating policy, and negative stock policy. Avoid binary floating point in test expectations as well as production.

## 7. Test data and professional golden files

Factories create synthetic, deterministic, organization-scoped data. Never copy production documents or personal data into non-production. Qualified Indonesian accounting/tax professionals approve a versioned suite of golden transactions, expected journals, costing results, tax results, and financial statements. Rule updates must preserve historical fixtures and add new effective-date cases.

## 8. Release gates

No release proceeds with failing invariant, RLS, migration, or reconciliation tests. Required gates include type/build checks, unit/property tests, real-database integration/RLS tests, critical E2E smoke, vulnerability/secret scans, migration rehearsal, and backup/restore evidence on the agreed cadence. Flaky accounting/security tests are release failures, not retries to ignore.

## 9. Production verification

Post-deploy smoke tests use a dedicated non-customer tenant. Scheduled read-only reconciliation detects imbalance, missing source postings, subledger differences, inventory differences, stuck jobs, and audit gaps. Alerts reveal identifiers and safe diagnostics without exposing customer financial data.

## 10. Traceability

Each requirement and accountant-approved policy links to test cases. Test reports record application version, migration version, tax-rule catalog version, environment, and fixtures. Defects involving financial history include impact analysis and a reviewed correction/migration plan rather than silent data edits.
