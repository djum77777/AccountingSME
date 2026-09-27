# Phase 3 Implementation — Accounting Core / Ledger Foundation

## Status

Phase 3 is implemented and verified locally. It intentionally stops at the accounting core: no sales, purchases, inventory movements/costing, OCR, tax automation, custom report builder, dashboards, or bank feeds were added.

## Request-to-ledger path

`authenticated application request → Next.js Server Action → public protected RPC → app_private posting transaction → journal_entries + journal_lines → general_ledger view → get_trial_balance()`

The browser never writes accounting tables. Server Actions validate identifiers, dates, descriptions, and exact decimal strings, then call one of the allowlisted RPCs. PostgreSQL rechecks membership, capability, organization ownership, active account state, open period, precision, debit/credit shape, balance, and idempotency inside one transaction.

## Implemented database foundation

- ISO-style currency reference catalog and organization base-currency validation at posting time.
- Five Chart of Accounts templates keyed to the Phase 2 business templates. Inventory and COGS accounts start inactive for General SME and Service; all stable codes remain available for later controlled activation.
- Owner-controlled subaccount creation, display-label changes, and deactivation. Stable codes/categories and referenced history remain protected; application deletion is unavailable.
- Organization accounting profile, accounts, non-overlapping accounting periods, journal headers/lines, and opening-balance batches.
- Journal lifecycle: internal `draft` while the atomic transaction is assembled, then `posted`; a posted source becomes `reversed` only when its separate equal-and-opposite reversal has posted.
- One central internal posting function, exposed through protected manual-journal and opening-balance RPCs.
- Organization-scoped idempotency keys, request fingerprints, a transaction advisory lock, and a unique constraint. Equal retries return the first journal; changed payloads using the same key fail.
- Posted General Ledger view and parameterized Trial Balance function. Both include economically posted source entries even after their lifecycle marker becomes `reversed`, along with the offsetting reversal.
- Append-only audit events for initialization, posting, opening balances, reversals, and period close/reopen.
- RLS and organization-inclusive foreign keys for every tenant-owned accounting relation.

## Decimal and rounding boundary

Journal values use PostgreSQL `numeric(20,4)`. The TypeScript boundary parses decimal text into scaled `bigint`; exponent notation and more than four decimals are rejected. No binary floating-point arithmetic is used for posting. PostgreSQL repeats the four-decimal check before insertion, rather than silently accepting application rounding.

Currency minor units are reference metadata only in Phase 3. The ledger persists four decimals for every base currency. Document, tax, price, quantity, foreign-exchange, and display-rounding policies are deliberately not invented here and require professional approval before their modules are implemented.

## Authorization

- Owner: read, initialize, post, reverse, close, and reopen.
- Admin/Accountant: read, post, and reverse by default.
- Staff: no accounting read/post capability by default; a future operational workflow may grant narrowly scoped capability after product review.
- Period close/reopen is hard owner-only and cannot be delegated through a general permission grant.

Direct `insert`, `update`, and `delete` are revoked from application roles. Trigger guards also reject protected mutation. Accounts are deactivated rather than deleted; referenced account identity fields become immutable.

## Application surface

The bilingual organization accounting route supports initialization, Chart of Accounts inspection, owner period controls, opening balances, manual journals, reversals, journal history, General Ledger, and Trial Balance. It is a thin administration/testing surface over the database authority, not an operational sales or purchasing workflow.

## Verification evidence

- Phase 1 and Phase 2 regression suite: 43 pgTAP assertions passed.
- Phase 3 accounting suite: 37 pgTAP assertions passed.
- Total database suite: 80/80 passed.
- A separate two-client integration race sends the same request simultaneously; both receive the same journal ID, exactly one header exists, and exactly two complete lines commit.
- TypeScript unit suite: 13/13 passed, including decimal parsing/precision and RBAC cases.
- Formatting, ESLint, TypeScript, and Next.js production build passed.

The Phase 3 suite covers template/tenant isolation, balance and line rules, atomic rollback after a partially assembled request fails, cross-tenant account rejection, precision rejection, opening balances, idempotent retry, same key in different organizations, period overlap, owner-only close/reopen, closed-period denial, role checks, immutable posted records, reversals, audit events, General Ledger derivation, and Trial Balance equality.

## Golden scenario

The automated golden scenario creates **Toko Maju Jaya** and posts:

| Account       | Debit        | Credit       |
| ------------- | ------------ | ------------ |
| Cash          | 1,000,000.00 | 0.00         |
| Owner Capital | 0.00         | 1,000,000.00 |

It then posts a linked reversal with debit and credit exchanged. The source remains immutable and marked `reversed`, the reversal remains `posted`, both appear in the General Ledger, and their Trial Balance effect nets to zero.

## Guarantees in plain language

- An unbalanced journal cannot be posted.
- A failed journal leaves neither a partial header nor partial lines.
- A posted journal cannot be edited or deleted by application users.
- Corrections preserve history through a linked reversal.
- Closed periods cannot receive postings.
- Retrying the same request does not duplicate money.
- Simultaneous duplicate requests commit once.
- One organization cannot read or post to another organization's accounts.
- Trial Balance reads only committed ledger history and always retains debit/credit evidence.

## Accountant-review questions before production use

1. Approve or replace the seeded Indonesian SME account names, codes, hierarchy, categories, normal balances, and protected control accounts for each business template.
2. Confirm whether account category should distinguish revenue, COGS, operating expense, other income/expense, and tax beyond the implemented five top-level categories.
3. Confirm IDR and non-IDR storage, document, tax, unit-price, quantity, journal, and display precision; approve rounding order and residual-account treatment.
4. Confirm opening-balance equity offset and required detailed AR, AP, fixed-asset, tax, and inventory migration evidence.
5. Confirm whether reversal date must be the original date, current open period, or a policy-selected date when the source period is closed.
6. Confirm owner-only period close/reopen, required approvals, close checklist, lock date behavior, and audit wording.
7. Define year-end closing, current earnings, retained earnings, and comparative-period behavior.
8. Confirm whether manual posting to control accounts is allowed or must be limited once AR/AP/inventory subledgers exist.
9. Confirm when an inactive account may be reactivated and whether any system/control account may ever be deactivated.
10. Confirm foreign-currency scope, rate sources, realized/unrealized exchange differences, and whether Phase 3 base-currency-only posting is acceptable for initial release.

## Next recommended phase

Begin Phase 4 with parties, products/services, document numbering, service/non-stock sales invoices, customer receipts, and AR allocations. Each confirmation must call the existing posting RPC/service boundary rather than writing journals directly. Do not enable stocked sales until the inventory movement and costing authority exists.
