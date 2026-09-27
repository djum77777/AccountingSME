# Accounting Engine

> Implementation status: the Phase 3 ledger foundation is implemented in `202609270003_phase3_accounting_core.sql`. The authoritative path is application Server Action → protected public RPC → private PostgreSQL posting transaction → journal header/lines → General Ledger → Trial Balance. Sales, purchases, inventory, tax, and subledger posting patterns below remain architecture for later phases.

## 1. Purpose and boundary

The accounting engine is the sole authority for translating confirmed business events into double-entry ledger postings. UI components, imports, OCR, integrations, and customization metadata submit validated commands; they never write posted journal lines directly.

The engine is a protected PostgreSQL transaction boundary called by server-side TypeScript. PostgreSQL is authoritative for posting arithmetic and constraints; TypeScript accepts fixed-scale decimal strings and performs no binary floating-point financial arithmetic.

## 2. Core invariants

For every posted journal entry:

1. It belongs to exactly one organization and all referenced rows belong to that organization.
2. It contains at least two lines.
3. Every line has either a positive debit or positive credit, never both or neither.
4. Total debits equal total credits at the posting currency precision.
5. Its accounting date lies in an `open` period at posting time.
6. Its source and idempotency key cannot create a duplicate active posting.
7. Posted accounting content is immutable. The only original-header mutation is the controlled `posted` → `reversed` transition made atomically when its linked reversal posts.
8. A correction uses a linked, equal-and-opposite posted reversal plus a corrected source/posting when required.
9. Control-account totals reconcile to their subledgers.
10. Amounts, tax rule versions, costing outcomes, actor, and source are traceable.

## 3. Journal lifecycle

- `draft`: editable by an authorized user; not included in the GL or standard financial statements.
- `posted`: validated and atomically committed; included in the GL and immutable.
- `reversed`: original remains economically posted and in history, but a unique linked posted reversal offsets it. The status is a controlled lifecycle marker indicating that link exists; it does not permit edits to accounting content.

Posting is a command with organization context, permission, accounting date, source reference, and idempotency key. Validation occurs before and inside the transaction. Database protections are the final guard against unbalanced or mutable posted data.

## 4. Posting pipeline

1. Resolve authenticated membership and capability.
2. Load organization settings, open period, relevant accounts, tax snapshot, and source aggregate under appropriate locks.
3. Validate source status, completeness, currency, accounts, and duplicate/idempotency conditions.
4. Calculate business totals using decimal arithmetic and documented rounding.
5. For inventory-affecting events, calculate and lock weighted-average cost state.
6. Build a journal proposal and validate invariants.
7. Atomically persist confirmed source state, posted journal/lines, allocations, inventory movements/cost state, audit event, and outbox events.
8. Return stable identifiers; retries return the prior result rather than duplicate it.

## 5. Posting patterns

Exact account mappings are organization configuration constrained by account type and protected control-account rules.

- Cash sale: debit cash/bank, credit revenue and applicable tax liabilities; for stocked goods also debit COGS and credit inventory at calculated cost.
- Credit sale: debit AR instead of cash/bank; receipt later debits cash/bank and credits AR through an allocation.
- Inventory purchase on credit: debit inventory and eligible tax asset, credit AP. Payment debits AP and credits cash/bank.
- Direct expense: debit expense and eligible tax asset, credit cash/bank or AP.
- Cash/bank transfer: debit destination cash/bank and credit source cash/bank, with fees posted separately when present.
- Customer/supplier returns: use explicit return/credit workflows and linked reversals/adjustments; never edit the original posted transaction.

Revenue recognition timing, tax presentation, discounts, freight/landed cost, and return specifics require professional review before mappings are finalized.

## 6. Reversals and corrections

A reversal copies the original lines with debit and credit exchanged, retains the original accounting dimensions and currency data, and links both entries. Its date must be in an open period. If the original period is closed, policy must determine whether to reverse in the current open period or reopen; the system must not decide silently.

The original record, reversal reason, actor, approval where required, and corrected replacement all remain visible. Reversing an operational event also reverses its allocations and inventory movements in a coordinated transaction.

## 7. Opening balances

Opening balances are prepared in a batch and posted only when the entire opening position balances. Detailed AR, AP, and inventory opening records must reconcile to their respective control-account lines. The offset may be opening equity or other professionally approved accounts; the product will not assume the policy.

Opening inventory records quantity and value so weighted-average cost begins reproducibly. Validation reports show missing parties, products, due dates, account mappings, and imbalance before posting. After posting, corrections use reversal and replacement.

## 8. Accounting periods

Periods do not overlap. Posting, reversal, allocation changes with accounting effect, and inventory movement posting require an open period. Closing runs pre-close checks: balanced ledger, source-to-journal completeness, subledger reconciliation, inventory valuation, unresolved drafts/exceptions, and tax/report warnings.

Only an `owner` with the close/reopen capability may close or reopen under the initial model. Reopen requires a reason and audit event. Whether `admin_accountant` may be granted this action is an explicit accountant/product review question, not an implicit implementation choice.

Year-end closing entries and retained earnings treatment are deferred pending professional review.

## 9. Inventory and weighted-average costing

For each organization/product/location cost pool:

- Inbound quantity at cost increases quantity and inventory value.
- New average cost = (prior value + inbound value) / (prior quantity + inbound quantity), subject to the approved rounding policy.
- Outbound sale uses the current average unit cost immediately before the issue; it reduces quantity and value and posts COGS/inventory.
- Returns reference the originating movement where possible; the accountant-approved return valuation policy must be explicit.
- Each posted movement stores calculated unit/total cost and before/after state.

Concurrent movements lock cost state and process in deterministic order. Backdated movements, negative stock, landed costs, and corrections can require downstream revaluation; MVP policy must be chosen and tested before release. FIFO remains a future costing strategy behind an interface, not an MVP option.

## 10. AR and AP allocations

Invoices/bills preserve original confirmed totals. Payments and credits create allocations, allowing partial and multiple payments. Open balance and settlement state are derived from active allocation history. Allocation cannot exceed the available payment/credit or permitted document balance unless an approved overpayment/advance policy applies. Corrections reverse allocations rather than erasing them.

## 11. Currency and rounding

The organization has a base currency, initially expected to be IDR for the target market but not hard-coded. Each transaction stores currency. Multi-currency recognition, exchange differences, and rate sources are deferred until approved. The system must define and centrally implement currency scale, line/tax/document rounding sequence, residual handling, and display rounding before production.

## 12. Protected controls

Customization cannot change balancing, normal posting mappings outside constrained configuration, period enforcement, posted immutability, costing formulas, tax rule evaluation code, control-account semantics, or audit emission. Direct database access in production is operationally restricted and audited.

## 13. Accountant-review assumptions and questions

The following are architecture assumptions, not claims of Indonesian accounting/tax compliance:

- Weighted-average cost is the MVP default; confirm acceptability and whether averaging is perpetual and per location.
- Confirm treatment of negative stock, backdating, returns, freight/landed cost, discounts, and inventory write-downs.
- Confirm recommended Indonesian SME Chart of Accounts templates and protected control accounts.
- Confirm opening-balance offset and detailed AR/AP/inventory migration treatment.
- Confirm revenue/expense recognition timing for each supported document flow.
- Confirm cash-basis versus accrual presentation expectations and whether both are needed.
- Confirm period reopening authority, approval, reversal dating, year-end close, and retained earnings behavior.
- Confirm IDR precision and rounding for prices, quantities, discounts, tax, COGS, and journal totals.
- Confirm foreign-currency scope and exchange-gain/loss policy if enabled.
- Confirm SAK EMKM statement structure, notes, comparative periods, and required disclosures before any compliance claim.
