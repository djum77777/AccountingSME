# Customization Engine

> Phase 2 implementation status: onboarding, five seeded business templates, cloned organization configuration, module visibility, safe label aliases, metadata-driven custom fields/dimensions, form-field configuration, saved views, audited reset, and bilingual configuration UI are implemented. Reset intentionally preserves custom definitions/values and business data.

## 1. Goal and non-goals

The customization engine lets each organization adapt capture and presentation without forking code or weakening accounting controls. It is metadata-driven: definitions are typed, validated, versioned, organization-scoped data interpreted by trusted application code.

It does not allow tenant-authored executable code, SQL, formulas with unrestricted evaluation, physical database schema changes, edits to posted journal lines, changes to inventory costing, bypass of periods/RBAC/RLS, or mutation of audit history.

## 2. Supported customization

- Operational custom fields on approved entity types.
- Organization-specific display labels and terminology.
- Custom dimensions such as Branch, Project, Department, Salesperson, Marketplace, Region, Store, Channel, or Campaign.
- Form layout/visibility for optional operational fields.
- Table columns, filters, sorting, and saved views.
- Dashboard layout and permitted widgets.
- Navigation visibility, which never grants permission.
- Custom management reports built from approved semantic fields/measures.

Standard financial statement semantics remain protected. Account display labels and report presentation may vary, but underlying account types, ledger values, and accounting equations do not.

## 3. Metadata model

`customization_definitions` contains `organization_id`, stable key, entity type, kind, value type, localized label, validation constraints, applicability, visibility rules, sensitivity classification, status, and version. Keys are immutable after use; definitions may be deactivated rather than deleted.

Supported value types begin with text, long text, integer, decimal, boolean, date, datetime, single select, multi-select, and approved entity reference. Each type has strict length/range/option validation. File values use the document service, not embedded blobs.

`custom_field_values` stores organization, definition/version, entity type/ID, and a typed value representation. Persistence must support validation and indexing without relying on opaque JSON for every query. JSONB may hold layout metadata, but core searchable values use typed columns or purpose-built indexes.

Dimensions have definitions and members. Transactions store validated dimension assignments. Posted journal lines snapshot applicable dimension assignments so historical reporting does not change when an operational record is later relabeled.

## 4. Definition lifecycle

Definitions use `draft`, `active`, and `inactive` lifecycle states, distinct from operational-document statuses. Activation validates unique keys, labels, target support, and constraints. Changes that alter interpretation create a new version; historical values retain their original definition version. Narrowing constraints cannot invalidate existing data silently.

Only `owner` may change critical customization by default. `admin_accountant` may manage reporting and non-critical definitions when explicitly granted. `staff` may enter values where their operational permissions allow but cannot define metadata.

Every definition activation/deactivation, sensitive label change, option change, and report/dashboard publication is audited.

## 5. Protected versus customizable fields

Protected fields include organization ownership, identifiers, lifecycle status, accounting dates, currency and core monetary totals, account types, journal debit/credit, tax calculation snapshots, inventory quantities/cost results, period state, source links, permissions, and audit fields.

Custom fields supplement rather than override protected fields. A custom field named “Total” or “Tax” cannot shadow the canonical amount or influence posting unless a future reviewed extension explicitly maps it through a constrained domain contract.

## 6. Rendering and validation

The server publishes an allowlisted form/view schema derived from active metadata and permissions. The client renders components from that schema. On submission, the server reloads the authoritative definition, rejects unknown/unauthorized fields, normalizes locale-sensitive input, and validates values. Client validation is convenience only.

Labels are localized for Indonesian and English with organization fallback behavior described in [i18n.md](i18n.md). Stable keys, not translated labels, drive storage, imports, APIs, and tests.

## 7. Saved views, dashboards, and management reports

Saved filters use a parsed, allowlisted query model—never raw SQL. Definitions name approved dimensions, measures, operators, grouping, sorting, date basis, and visibility. Query compilation always injects organization and permission scope.

Private definitions belong to their creator; shared definitions belong to the organization and require publish permission. Versioning preserves reproducibility for exported management reports.

## 8. Limits and performance

MVP establishes conservative limits for active fields per entity, dimensions per line, select options, dashboard widgets, and report complexity after load testing. The UI communicates limits. Definitions used in filtering/reporting receive appropriate organization-scoped indexes; high-cardinality or sensitive fields require review.

## 9. Security and privacy

Each definition declares data classification and export/search eligibility. Sensitive custom values inherit entity authorization, RLS, audit, retention, and export controls. Custom HTML, script, unsafe URL rendering, and arbitrary template execution are prohibited. Values are escaped by output context.

## 10. Compatibility

Metadata APIs have schema versions. Application releases migrate or continue to interpret older versions. Unknown definition types fail closed. Imports reference stable keys and validate active versions. Exports include labels and stable keys where useful so data remains intelligible and re-importable.
