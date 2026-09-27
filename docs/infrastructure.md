# Infrastructure and Operations

## 1. Deployment model

Deploy the Next.js/TypeScript modular monolith on Vercel. Use Supabase for managed PostgreSQL, trusted authentication, and private object storage initially. External OCR is accessed through a provider adapter; Google Document AI OCR/Form Parser is the first benchmark candidate.

Vercel workloads are stateless. Financial consistency lives in PostgreSQL transactions. Long-running OCR, imports, exports, notifications, and projection rebuilds use controlled background workers/jobs with durable state, bounded retries, idempotency, and dead-letter/operator visibility; they do not hold a request open or perform partial ledger posting.

## 2. Environments

Maintain separate local/development and production environments. Add an isolated staging environment before external beta. Each has distinct database, auth tenant, storage, OAuth credentials, OCR credentials, URLs, and secrets. Development/test data never shares production resources.

Preview deployments use non-production services or short-lived isolated resources and must not receive production secrets or customer data. Database migrations are promoted through environments with the same artifacts and approval gates.

## 3. Configuration and secrets

Validate environment variables at startup. Separate public client configuration from server-only secrets. Store secrets in environment-scoped Vercel/Supabase/provider secret management; never in Git, logs, generated exports, or browser bundles. Document owners, rotation cadence, and emergency revocation for database, auth, OAuth, OCR, email, and storage credentials.

## 4. Database operations

- Version-controlled migrations for schema, functions, RLS, indexes, and seed references.
- Connection pooling suitable for Vercel concurrency and database limits.
- Statement timeouts, transaction timeouts, and measured indexes.
- Least-privilege runtime, migration, read-only support, and background-job roles.
- Migration preflight for locks, backfills, compatibility, and rollback/forward-fix strategy.
- No ad hoc production changes outside audited emergency procedure.

## 5. Storage and document lifecycle

Use private buckets separated by environment and logical classification. Object keys are opaque and organization-namespaced. Upload through authenticated/signed workflows, verify checksum/type/size, and retain database metadata. Download access is short-lived and audited where appropriate.

Retention and deletion are policy-driven, considering accounting/tax/legal holds. Account closure begins a controlled export/retention/deletion workflow rather than immediate recursive deletion. Orphan detection reconciles objects and database rows.

## 6. Background processing and OCR

Jobs persist organization, command ID, status, attempts, provider reference, next retry, error classification, and correlation ID. Workers claim jobs safely and make every side effect idempotent. Retries use exponential backoff and bounded attempts; permanent failures become visible for review.

Meter OCR pages/jobs and cost per organization. Enforce file/page quotas and abuse limits. Benchmark providers on Indonesian invoices/receipts for extraction accuracy, latency, cost, privacy terms, regional processing, supported formats, and operational reliability before selection.

## 7. Observability

Structured logs include timestamp, environment, service/version, request/correlation ID, organization pseudonymous ID, actor pseudonymous ID, route/job, outcome, latency, and safe error code. Never log tokens, document content, tax identifiers, or unnecessary financial payloads.

Metrics and alerts cover request/job failures, latency, database saturation, connection usage, migration failures, auth anomalies, RLS denials, upload/OCR failures, posting invariant failures, outbox backlog, export volume, storage errors, backup status, and reconciliation failures. Distributed tracing links requests to database/job/provider operations without exposing sensitive content.

## 8. Backups, restore, and continuity

Enable managed PostgreSQL backups and point-in-time recovery appropriate to the plan. Define target RPO/RTO before beta. Protect backup access separately and include storage/document recovery or a documented reconstruction strategy. Regularly test restore into an isolated environment and run ledger/subledger/inventory reconciliation after restore.

Maintain incident runbooks for database loss/corruption, leaked credentials, auth outage, storage outage, OCR outage, failed migration, and erroneous tax rule publication. OCR unavailability must not compromise existing accounting data; manual draft entry remains possible.

## 9. Delivery pipeline

CI gates formatting/type checks, unit/integration tests, migration/RLS tests, build, dependency/secret scanning, and artifact provenance. Production deployment requires passing gates and reviewed migrations. Deploy application code compatibly before destructive schema cleanup. Use feature flags only for behavior rollout, never to bypass invariants/security.

## 10. Scalability and cost

Start lean on managed tiers, then scale from measurements. Watch database connections/storage, report query cost, document volume, OCR pages, egress, background concurrency, and Vercel execution. Quotas prevent one organization from exhausting shared capacity. Re-check provider pricing and service limits before launch; architecture documents must not encode stale prices.

## 11. Operational ownership before beta

Assign owners for deployments, migrations, tax catalog publication, backups/restores, incidents, access review, vulnerability response, and customer data requests. Create dashboards, alert routing, escalation contacts, maintenance communications, and a production-access review cadence.
