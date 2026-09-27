# Phase 2 Implementation

## Delivered scope

Phase 2 adds a bilingual, tenant-protected setup and configuration layer. It does not implement accounting transactions, products, inventory, purchasing, sales, OCR, or report building.

The onboarding sequence is language, business type, business information, recommended template, then basic settings. Available templates are General SME, Retail, Online Seller, Trading/Distributor, and Service.

## Template versus organization configuration

`business_templates` contains global, versioned, read-only defaults. Completing onboarding copies the selected defaults into organization-owned rows for module visibility, label aliases, and form availability. Later organization edits do not modify the global template. A reset re-copies only the selected template's configuration defaults; it does not delete custom fields, dimensions, their values, memberships, audit events, or business records.

## Metadata storage

- `custom_field_definitions` stores stable keys, target entity, type, bilingual labels, validation metadata, lifecycle status, and version.
- `custom_field_values` stores an entity reference, definition/version reference, and validated JSON value. Disabling a definition changes its status and preserves every historical value.
- `custom_dimension_definitions` stores stable analysis-axis definitions such as Branch or Project.
- `custom_dimension_values` stores organization-owned members such as Jakarta or Project A.
- `form_configurations` and `form_configuration_fields` store section, order, required/default, visibility, and role-visibility metadata.
- `saved_views` stores allowlisted columns and structured view metadata, never SQL or executable expressions.

## Security boundary

All Phase 2 tables have RLS. Active organization membership is required to read tenant rows. Owner authorization (`customization.manage`) is required for organization-wide changes; an Admin/Accountant can receive a future explicit permission grant without changing the role model. Staff can use active definitions to store values but cannot change definitions or reset configuration.

Stable ownership, tenant, role, posting, journal, debit/credit, ledger, costing, RLS, and audit identifiers are outside the customization allowlist. The database functions reject protected form keys and unknown module/entity keys. Every organization-wide customization command writes an audit event.

## Verification

The pgTAP scenario creates two organizations with different templates and isolated configurations. Organization A uses Retail with Branch and Marketplace dimensions; Organization B uses Service with Project and Client Type dimensions. The suite proves RLS isolation, preserved values after field archival, preserved custom metadata after reset, and staff denial. Phase 1's last-owner, seat-limit, and tenant tests run in the same suite.
