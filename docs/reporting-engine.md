# Reporting Engine

## 1. Reporting classes

The engine separates protected standard reports from customizable management reports.

**Standard reports** have fixed accounting semantics: General Ledger, Trial Balance, Profit & Loss, Balance Sheet/Statement of Financial Position, AR aging, AP aging, inventory movement/valuation, and audit-oriented transaction detail. Organizations may choose dates, permitted filters, comparative columns, display labels, and presentation, but cannot redefine accounting equations or omit ledger data in a way presented as a standard statement.

**Management reports** may select approved measures, dimensions, filters, groupings, charts, and layouts. They must be labeled as management/custom reports and must not imply statutory or SAK EMKM compliance.

## 2. Source-of-truth rules

- Standard financial statements derive only from economically posted journal lines: entries whose header is `posted` or `reversed`. A `reversed` original remains in the ledger and its separate posted reversal offsets it.
- Draft entries are excluded. Reversed-by-offset history remains available in detail, and balances include both original and reversal postings.
- AR/AP reports derive from confirmed documents and active allocation history and reconcile to ledger control accounts.
- Inventory reports derive from posted inventory movements/cost state and reconcile to the inventory control account.
- Tax reports use stored transaction tax snapshots and rule versions.
- Custom fields/dimensions enrich segmentation but never replace ledger amounts.

## 3. Report contracts

Every report request includes organization, authenticated actor, report type/version, as-of or period dates, timezone, locale, currency/presentation settings, filters, and permission scope. Output includes generation timestamp, data cutoff, basis, filters, report-definition version, and warnings.

The same canonical query/service produces on-screen, CSV/XLSX, and PDF data to prevent export drift. Formatting adapters do not recalculate financial values.

## 4. Standard report semantics

- **General Ledger:** ordered posted journal lines by account and date with source and running balance.
- **Trial Balance:** debit/credit movements and ending balances; total debits and credits must agree.
- **Profit & Loss:** revenue, COGS, expenses, other income/expense for a period according to approved account mapping.
- **Statement of Financial Position:** assets, liabilities, and equity at a date; must satisfy Assets = Liabilities + Equity.
- **AR/AP aging:** original amount, allocations, open balance, due date, and aging buckets; bucket definitions and date basis are explicit.
- **Inventory valuation:** quantity, average unit cost, and value at cutoff, tied to movement history and GL.

SAK EMKM-oriented layouts and notes are supported only after qualified professional review. Until then, reports are accurately named financial/management reports without an automatic-compliance claim.

## 5. Custom management reports

Definitions use an allowlisted semantic catalog: dimensions, measures, joins, filters, and aggregations with ownership and sensitivity metadata. A compiler turns the definition into parameterized, organization-scoped queries. Raw SQL and arbitrary formulas are forbidden.

Publishing a shared report requires permission and creates a version. Historical exports record that version. Standard report names/badges are reserved and cannot be imitated by a custom report.

## 6. Reconciliation and warnings

The engine exposes machine-checkable reconciliations:

- Trial Balance debit equals credit.
- Balance Sheet equation holds.
- AR control balance equals AR subledger at cutoff.
- AP control balance equals AP subledger at cutoff.
- Inventory control balance equals inventory valuation, subject to documented timing/policy.
- Source documents expected to post have active journal references.

Reports show warnings for unresolved mapping, missing periods, out-of-balance subledgers, stale projections, unreviewed tax overrides, or incomplete closing checks. Warnings cannot be hidden in official exports.

## 7. Performance architecture

Begin with indexed PostgreSQL queries and transactionally correct views. Add materialized projections only after measurement. Every projection has a freshness marker and reproducible rebuild path; the ledger remains authoritative. Large exports run as background jobs, write encrypted/private artifacts, use short expiry, and are audited.

## 8. Authorization and privacy

Report authorization applies before query execution and at export/download. Staff see only explicitly granted reports/data domains. Custom dimensions marked sensitive require matching permission. All queries are organization-scoped and protected by RLS defense in depth. Export scope, actor, filters, and artifact access are audited.

## 9. Time, locale, and rounding

Dates use the organization timezone for business cutoffs. Stored codes and numeric results are locale-neutral; labels, dates, and numbers render in Indonesian or English. Report totals use the same central rounding policy as posting, never sums of display-rounded strings.

## 10. Professional-review decisions

Confirm statement presentation, account grouping, comparative requirements, notes, cash-flow scope, aging basis/buckets, rounding, treatment of prior-period adjustments, year-end close, and what is required for SAK EMKM-oriented output. These remain documented assumptions until approved.
