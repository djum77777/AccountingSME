# Phase 5 Implementation — Customer and Supplier Masters

## Delivered scope

Phase 5 adds organization-scoped party masters. One stable party identity can be a customer, a supplier, or both. Role rows carry role-specific payment terms and imports-ready external references. The master stores names, optional tax registration metadata, notes, contacts, addresses, lifecycle state, and Phase 2 `contact` custom-field values.

Purchases, sales, receipts, payments, AR, and AP are deliberately not implemented. In particular, there are no manually editable receivable or payable balances on a party record. Later phases must calculate balances from their transaction and allocation histories.

## Lifecycle and historical references

`parties.id` is the durable reference for future transaction foreign keys. Archiving records `archived_at` and `archived_by`; reactivation keeps the same ID. Parties, roles, contacts, and addresses cannot be deleted through application roles, and database delete guards retain master history. Removing a customer or supplier role archives the role row instead of deleting it.

## Duplicate controls and search

The directory search accepts name, email, phone, tax ID, or external reference and can filter by customer/supplier role or include archived records. Duplicate checks compare normalized exact name, tax ID, email, and phone values and return scored warning reasons. Warnings are advisory because legitimate related entities can share contact data; tax IDs and role-specific external references are unique inside an organization when present.

## Custom fields

Active Phase 2 custom-field definitions with `entity_type = 'contact'` appear on the party profile. Values retain the definition version and are written through a party-specific RPC that verifies organization, party, definition, permission, and value type before writing an audit event.

## Security and audit

All Phase 5 tables use RLS. Owners and Admin/Accountants can read and manage parties by default. Staff can read the directory for operational use but cannot mutate it; explicit permission grants remain authoritative. Application roles receive table reads plus narrow RPC execution and no direct DML. Create, update, archive/reactivate, contact, address, and custom-field changes emit append-only audit events.

## Future transaction contract

Phase 6 purchase/AP documents must reference an active supplier role by `party_id`. Phase 7 sales/AR documents must reference an active customer role by `party_id`. Historical documents must continue resolving archived parties by the same stable identifier and must snapshot the document-facing name, address, tax, and payment-term values required for immutable history.
