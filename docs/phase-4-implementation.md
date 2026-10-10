# Phase 4 Implementation — Catalog and Inventory Costing

## Delivered scope

Phase 4 implements organization-scoped product and service masters, categories, units, SKU/barcode data, stock locations, opening stock, stock in/out, adjustments, damage/loss, stock counts, transfers, low-stock queries, movement history, deterministic moving weighted-average cost, and inventory valuation. It deliberately does not implement parties, purchasing, sales, AR/AP, invoice numbering, OCR, or advanced reports.

## Quantity flow

`inventory_cost_states.quantity_on_hand` is a protected projection, not an editable balance. Each change starts as an authenticated RPC request with an organization, product, location, date, positive quantity, source, reason, and idempotency key. The database locks the product/location pool, validates chronology and availability, appends one or two immutable `inventory_movements`, then updates the projection in the same transaction. Opening stock requires empty history. Outbound movement cannot make quantity negative. A transfer appends equal transfer-out and transfer-in movements and conserves organization-wide quantity. A stock count records only the variance between counted and calculated quantity.

## Cost flow

Inbound stock contributes `quantity × submitted unit cost` to the pool. The database derives the new average as total pool value divided by total pool quantity, rounded to eight decimal places. Outbound stock uses the locked average cost immediately before the issue; it never accepts a caller-provided outbound cost. A final issue consumes the exact remaining value so no rounding residue remains. Transfers carry the source pool's cost into the destination pool and do not revalue the organization. Every movement stores quantity, value, and average-cost snapshots before and after, so historical cost basis remains reproducible.

The required example is covered in PostgreSQL tests: 10 units at Rp10,000 plus 10 units at Rp14,000 produces 20 units at Rp12,000 and Rp240,000. Removing 5 units leaves 15 units and Rp180,000.

## Accounting flow

Every financially relevant opening, receipt, issue, adjustment, damage/loss, or stock-count variance calls the Phase 3 `app_private.post_journal_internal` authority inside the same PostgreSQL transaction. Inbound movements debit the product's inventory asset and credit the selected offset account; outbound movements debit the selected offset account and credit inventory. The resulting journal ID is retained on the operation. If journal validation or posting fails—for example because the period is closed—the operation, movement, and cost-state update all roll back. Location transfers have no organization-wide financial effect and therefore create movements but no journal.

Offset-account selection in this foundation is intentionally manual. Later purchase and sales workflows must select accounts from approved transaction policy and call these authorities; they must not duplicate cost or journal logic.

## Security and integrity

- Owner and Admin/Accountant have `inventory.read` and `inventory.manage` by default; Staff has neither. Explicit permission grants remain authoritative.
- All tables and reporting views are protected by organization-aware RLS.
- Cross-organization references are rejected by composite foreign keys or RPC validation.
- App roles receive read access and narrow RPC execution only; direct derived-state DML is revoked and trigger guarded.
- Movement and operation history cannot be deleted; movements cannot be updated.
- Product/location cost pools and idempotency keys use transaction advisory locks, including deterministic lock order for transfers.
- Products and services share stable catalog identifiers, but services can never be inventory tracked.

## Verification evidence

- 126 pgTAP assertions across Phases 1–4 pass, including 46 Phase 4 inventory/RLS/accounting assertions.
- The costing example, rollback on accounting failure, historical snapshots, cross-tenant denial, staff denial, low stock, stock counts, transfers, idempotency, negative-stock denial, and backdating denial are covered.
- A separate two-client race test proves simultaneous receipts serialize to quantity 20, value Rp240,000, and average cost Rp12,000 with exactly two movements and two journals.
- TypeScript tests cover fixed-scale input normalization without binary floating-point arithmetic.

## Policy assumptions requiring professional review

1. Moving weighted-average cost is appropriate for the initial Indonesian SME target and eight-decimal unit cost/four-decimal value precision is acceptable.
2. Negative stock and backdated movements are prohibited rather than supported through controlled recalculation.
3. Damage/loss, count variance, opening stock, and manual in/out offset accounts may be selected by an authorized accountant during this foundation phase.
4. Location transfers have no journal effect and do not include freight, landed-cost reallocation, or in-transit ownership.
5. Positive stock-count variance uses the existing pool average when one exists; a unit cost is required only for an empty-cost pool.
6. The seeded Inventory account and detailed debit/credit mappings require qualified Indonesian accountant approval before production use.

## Recommended Phase 5 starting point

Build organization-scoped customer and supplier masters with retained deactivation history, contacts/addresses/tax identifiers, duplicate controls, RLS, imports-ready external references, and bilingual screens. Do not add purchase bills or sales invoices until those masters are tested; Phase 6 should then consume suppliers and this inventory receipt authority, and Phase 7 should consume customers plus the inventory issue authority.
