# Phase 6 Implementation — Purchases and Accounts Payable

## Delivered scope

Phase 6 adds organization-scoped purchase drafts and numbered purchase documents, stocked-product and service lines, cash and credit purchases, line/document discounts, additional costs, supplier payments and allocations, supplier credits/returns, derived AP open items, AP aging, source references, audit events, and bilingual purchase/AP screens.

Supplier identity is always a Phase 5 `party_id` with an active supplier role. Product receipt and return quantities/costs are posted only through the Phase 4 inventory authority. Every financial effect is posted only through the Phase 3 journal authority and inherits its open-period checks. The module does not introduce editable AP balances.

## Posting, atomicity, and history

`confirm_purchase` locks the draft and completes the document, inventory operations, journals, posting links, and audit event in one PostgreSQL transaction. Any failure rolls the complete confirmation back. Posted purchase snapshots retain supplier name, tax identifier, address, and payment terms even if the master changes later.

Cash purchases credit the selected cash/bank asset account and never enter AP open items. Credit purchases credit the system AP account. Service-only purchases debit their selected expense account and do not create an inventory operation. Product purchases delegate weighted-average valuation and inventory account posting to Phase 4.

## AP, payments, and credits

`purchase_open_items` derives outstanding AP as original posted amount less posted allocations and supplier credits. A payment can allocate across one or more invoices for the same supplier. Allocation rows are immutable and payments reduce AP only through the posted payment journal. AP aging is calculated as of a supplied date from the same histories and reconciles to the AP control account in tests.

Supplier credits retain line-level references. Service credits reverse expense and AP, or refund the original cash/bank account for a cash purchase. Product returns use Phase 4 outbound costing against AP or the original cash/bank account; any difference between supplier credit value and current weighted-average inventory value is posted as a purchase-return variance pending professional policy review.

## Idempotency, concurrency, and security

Confirmations, payments, inventory effects, and credits use scoped idempotency keys and immutable request fingerprints. Draft rows and settlement advisory locks prevent duplicate confirmation, over-allocation, and competing payment/credit inconsistencies. A two-client race test proves duplicate confirmation creates one stock movement and simultaneous full-payment requests allow exactly one settlement.

All Phase 6 tables use RLS. Application roles receive read access and narrow RPC execution without direct DML. Owners and Admin/Accountants receive purchase management/payment permissions; cross-organization supplier, account, product, location, purchase, and line references are rejected. Draft creation, confirmation, payment, and credit events are recorded in the append-only audit log.

## Golden scenario

A credit purchase of 10 stocked units at Rp50,000 posts Rp500,000 to Inventory and Rp500,000 to Accounts Payable. A Rp200,000 payment debits AP and credits Cash/Bank, leaving Rp300,000 open. A second Rp300,000 payment leaves AP at Rp0. The purchase, one inventory operation, linked journal evidence, and both immutable payment allocations reconcile in the database scenario suite.

## Deferred policy and scope

Professional review is required for the chosen product-return variance account and for future Indonesian purchase-tax rules. This phase intentionally does not implement sales invoices, AR, customer receipts, sales returns/COGS, OCR, or any Phase 7+ workflow.
