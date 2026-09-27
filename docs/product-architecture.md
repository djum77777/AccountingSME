# Product Architecture

Status: Phase 0 architecture baseline
Audience: product, engineering, accounting, security, and operations
Authority: derived from `Part I — Product Definition.txt`; uncertain accounting and tax policy is explicitly deferred for professional review.

## 1. Product scope and principles

The product is a multi-tenant accounting and business-operations application for Indonesian SMEs/UMKM. It supports retail, online sellers, trading/distribution, and simple service businesses without assuming identical terminology, data fields, navigation, workflows, dashboards, or management reports.

Two experiences share one data and authorization model:

- **Business Mode** uses operational language: Sales, Purchases, Expenses, Products, Stock, Customers, Suppliers, Cash, Bank, and Reports.
- **Accounting Mode** exposes the Chart of Accounts, Journal Entries, General Ledger, Trial Balance, Opening Balances, Accounting Periods, Adjustments, and Period Closing.

The golden rule is: organizations control what they capture, see, and analyze; the application controls accounting mathematics, tenant isolation, audit integrity, and posted-record immutability. The ledger is double-entry: every posted financial event has at least two lines and total debits equal total credits.

## 2. System context and boundaries

The system is a Next.js application written in TypeScript and deployed on Vercel. PostgreSQL managed by Supabase is the structured-data source of truth. Supabase Auth, or a functionally equivalent trusted provider, owns credentials and identity verification. Private object storage holds invoice and receipt binaries. External OCR is an integration that may suggest data but cannot post accounting records.

```text
Browser/PWA
    |
    v
Next.js UI + server entry points (Vercel)
    |
    +-- application services / authorization / idempotency
    |       |
    |       +-- domain services: accounting, inventory, sales, purchases, tax
    |       +-- reporting and customization projections
    |
    +-- PostgreSQL/Supabase (authoritative structured state + RLS)
    +-- private object storage (documents)
    +-- trusted auth provider
    +-- OCR provider (untrusted extraction input)
```

### Application boundaries

- `app/`: route composition, React Server Components where suitable, and thin request handlers/server actions.
- `components/`: reusable presentation components; no posting, costing, or tax rules.
- `lib/auth/`: session resolution and authorization adapters.
- `lib/db/`: typed persistence, transaction boundaries, and organization-scoped repositories.
- `domain/accounting/`: journals, posting, reversals, opening balances, periods, and invariants.
- `domain/inventory/`: stock movements and weighted-average costing.
- `domain/sales/`, `domain/purchases/`, `domain/expenses/`, `domain/cash-bank/`: operational aggregates and accounting intents.
- `domain/tax/`: versioned rule selection and tax calculations.
- `services/ocr/`, `services/reporting/`, `services/import-export/`: orchestration and external adapters.
- `migrations/`: version-controlled PostgreSQL schema and RLS changes.
- `tests/`: unit, integration, database/RLS, contract, and end-to-end tests.

Dependencies point inward: UI and integrations call application/domain services; domain code does not import React, Next.js, Supabase SDKs, or provider-specific OCR code. All financial writes pass through server-side application services and database transactions.

## 3. Canonical tenancy and identity model

`organization` is the tenant and ownership boundary. Every tenant-owned row has a non-null `organization_id`; globally managed reference data is explicitly identified and read-only to tenants. A person authenticates as a `user` and participates through an `organization_membership`.

An organization starts with an entitlement of **3 active memberships**. Invited, suspended, and deactivated memberships do not count as active. Activating a membership requires owner approval and is enforced transactionally against the organization's current seat entitlement. A future monetization/platform-authority flow may increase that entitlement; owners cannot raise it themselves. Each person uses an individual identity; shared credentials are prohibited.

Canonical roles:

- `owner`: organization administration, membership and role management, permissions, accounting and tax settings, closing/reopening periods, exports, and critical customization. Every active organization must have at least one active owner.
- `admin_accountant`: accounting operations, reporting, adjustments, and other granted administrative work, but cannot transfer ownership or perform owner-only destructive/account-closure actions.
- `staff`: explicitly granted operational capabilities only.

Role is a baseline; sensitive actions also require named permissions and server-side policy checks. Row Level Security (RLS) is defense in depth for tenant isolation. See [security.md](security.md).

## 4. Canonical lifecycle vocabulary

These names are normative across the repository:

| Entity               | Statuses                                                           | Rule                                                                                            |
| -------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| Organization         | `active`, `suspended`, `closed`                                    | Closed data follows retention policy; it is not silently deleted.                               |
| Membership           | `invited`, `active`, `suspended`, `deactivated`                    | Only `active` counts toward the current seat entitlement; records are not physically deleted.   |
| Operational document | `draft`, `confirmed`, `voided`                                     | Confirmation creates or requests accounting effects; voiding a posted effect requires reversal. |
| Journal entry        | `draft`, `posted`, `reversed`                                      | Posted lines are immutable; `reversed` means a linked posted reversal exists.                   |
| Accounting period    | `open`, `closed`                                                   | Only an authorized owner may reopen; close/reopen is audited.                                   |
| OCR job              | `uploaded`, `processing`, `review_required`, `failed`, `completed` | `completed` means an editable draft was produced, never that it was posted.                     |
| Import job           | `uploaded`, `validating`, `review_required`, `committed`, `failed` | Commit is explicit and idempotent.                                                              |

Receivables and payables derive settlement state (`unpaid`, `partially_paid`, `paid`, `overpaid`) from allocations; it is not a freely editable field. Inventory movement status is `draft`, `posted`, or `reversed`, aligned with its journal effect.

## 5. Business capability map

- **Foundation:** organizations, memberships, RBAC, settings, currencies, numbering, audit, periods, and Chart of Accounts.
- **Accounting:** balanced journals, immutable posting, reversals, adjustments, opening balances, General Ledger, Trial Balance, and closing controls.
- **Sales and AR:** customers, invoices, credit/void correction flows, receipts, partial allocations, tax, revenue, inventory relief, and COGS.
- **Purchases and AP:** suppliers, bills, payment allocations, tax, inventory or expense recognition.
- **Expenses and cash/bank:** direct expenses, transfers, receipts, payments, and reconciliation-ready records.
- **Inventory:** products, locations if enabled, posted movements, on-hand quantities, and weighted-average cost.
- **Customization:** metadata definitions, labels, dimensions, forms, views, dashboards, and management-report definitions without modifying accounting rules.
- **Reporting:** immutable standard financial report semantics plus organization-configurable management views.
- **Documents/OCR:** private capture, extraction, normalization, matching, duplicate detection, editable draft, and explicit confirmation.
- **Tax:** effective-dated Indonesian tax rules and organization profiles, with human review and traceability.

## 6. Transaction and event strategy

An operational confirmation and its accounting consequences are committed atomically where practical. Application services accept an idempotency key for externally retryable commands. Each journal stores its source type and source identifier; each source has at most one active posted journal per posting purpose. Inventory movements and COGS are committed in the same transaction as the sale/purchase journal or fail together.

Domain events are recorded in an outbox table in the same database transaction and delivered asynchronously for non-critical work such as notifications, OCR processing, exports, and projection refreshes. The ledger never depends on a best-effort asynchronous handler to become balanced.

## 7. Data and storage ownership

- PostgreSQL owns organizations, business records, journals, inventory movements, tax snapshots, customization metadata, document metadata, audit events, and job states.
- Private object storage owns original and derived document files. Database rows contain opaque object keys, checksum, MIME type, size, ownership, and retention metadata.
- Auth provider owns password hashes, OAuth identities, verification, and recovery.
- Browser storage may contain harmless preferences only. It is not a financial source of truth and must not store auth tokens or sensitive accounting data.

## 8. OCR-to-draft boundary

The required workflow is: capture → private upload → OCR → normalization → matching and duplicate checks → editable draft → user review → explicit confirm/post → accounting engine. OCR output is untrusted input, retains confidence/provenance, and can never directly create a posted journal or posted inventory movement.

Google Document AI OCR/Form Parser is the initial benchmark candidate, not a permanent architectural dependency. An adapter permits provider replacement. Indonesian date, decimal, thousands separator, currency, supplier, product, and tax interpretations require deterministic normalization and review flags.

## 9. Quality attributes

- **Correctness:** decimal arithmetic, database constraints, balanced atomic posting, reproducible tax and cost snapshots.
- **Security:** deny-by-default authorization, organization scoping, RLS, private storage, least privilege, and append-only audit behavior.
- **Traceability:** every financial amount links from source document through journal lines, tax calculation, inventory movement, and actor/action history.
- **Configurability:** metadata extends capture and presentation while protected fields and calculations remain fixed.
- **Operability:** structured logs, request/correlation IDs, alerts, backup/restore drills, job retry visibility, and provider usage metering.
- **Internationalization:** Bahasa Indonesia and English from the first UI slice; locale is independent of stored canonical codes and amounts.

## 10. Architecture decisions

| ID      | Decision                                                                                                                            |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| ADR-001 | Use a modular monolith in Next.js/TypeScript for MVP; enforce domain boundaries in code rather than premature microservices.        |
| ADR-002 | PostgreSQL/Supabase is the structured-data source of truth; use database transactions, constraints, foreign keys, and RLS.          |
| ADR-003 | Store money in `NUMERIC`, use an application decimal library, and store ISO currency separately.                                    |
| ADR-004 | Treat posted journals and inventory movements as immutable; correct through linked reversals and replacement transactions.          |
| ADR-005 | Use private object storage with short-lived signed access, never public accounting-document URLs.                                   |
| ADR-006 | Represent customization as typed, versioned metadata and validated values, never tenant-authored executable code or schema changes. |
| ADR-007 | Keep standard financial reports semantically fixed; customization applies to management reports and presentation.                   |
| ADR-008 | Version and effective-date tax rules; snapshot applied rule inputs/results onto transactions and journal support records.           |
| ADR-009 | Deploy stateless Next.js workloads on Vercel; move long-running/retryable work to controlled background jobs.                       |

## 11. Deferred scope

FIFO inventory costing, full offline operation, payroll, manufacturing, consolidation, multi-entity accounting, automatic bank feeds, and claims of SAK EMKM or tax compliance are outside MVP unless separately approved. The schema and service boundaries should not prevent later addition, but MVP must not imply those capabilities.

## 12. Cross-document index

- Data model: [database-schema.md](database-schema.md)
- Posting and invariants: [accounting-engine.md](accounting-engine.md)
- Metadata boundaries: [customization-engine.md](customization-engine.md)
- Reports: [reporting-engine.md](reporting-engine.md)
- Access and privacy: [security.md](security.md)
- Bahasa Indonesia/English: [i18n.md](i18n.md)
- Tax: [tax-architecture.md](tax-architecture.md)
- Deployment and operations: [infrastructure.md](infrastructure.md)
- Verification: [testing-strategy.md](testing-strategy.md)
- Dependency-ordered delivery: [mvp-roadmap.md](mvp-roadmap.md)
