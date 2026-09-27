# Security Architecture

> Phase 2 implementation status: every customization table uses organization-scoped RLS; definition and reset mutations use owner-authorized security-definer functions; protected accounting/security keys are denylisted and module/entity keys are allowlisted. Authentication provider setup is documented in `authentication-setup.md`.

## 1. Security objectives

The primary objectives are tenant isolation, correct authorization, confidentiality of financial documents, integrity/traceability of accounting records, resilient authentication, and recoverability. Security controls are layered across the UI, server, database/RLS, storage, provider configuration, and operations.

## 2. Authentication

Use Supabase Auth or an equivalent trusted provider supporting email/password and Google OAuth. The provider owns password hashing, verification, OAuth, password reset by verified email link or OTP, session rotation, and abuse controls. Security questions and shared credentials are prohibited.

Prefer secure, HttpOnly, Secure, SameSite cookies for web sessions where the chosen integration supports them. Do not place sensitive tokens in localStorage. Require reauthentication for high-impact actions such as ownership transfer, sensitive exports, credential/security changes, and account closure.

## 3. Authorization and tenant isolation

Authorization is deny-by-default and evaluated server-side using authenticated user, active membership, organization, role, named capability, resource ownership, and entity state. UI visibility is not authorization.

Every tenant-owned query is organization-scoped and reinforced with PostgreSQL RLS. Related rows use organization-safe foreign keys. Client-provided tenant IDs are treated as untrusted. Background jobs carry signed/internal organization context and use least-privilege credentials.

The three canonical roles and default 3-active-seat entitlement are defined in [product-architecture.md](product-architecture.md). The database transactionally enforces the current entitlement and last-owner protection. Increasing the entitlement is reserved for a platform-authorized service flow; an organization owner still approves membership activation.

## 4. RBAC baseline

Phase 3 implements `accounting.read` and `accounting.post` for Owner and Admin/Accountant, and `accounting.initialize` for Owner. Staff receives none of these by default. Period close/reopen performs an explicit owner-role check and is not delegable through the generic permission table.

| Capability                                  | Owner |  Admin/Accountant |                                     Staff |
| ------------------------------------------- | ----: | ----------------: | ----------------------------------------: |
| Manage organization/ownership/users         |   Yes |                No |                                        No |
| Configure protected accounting/tax settings |   Yes | By explicit grant |                                        No |
| Close/reopen periods                        |   Yes |     No by default |                                        No |
| Post/reverse accounting entries             |   Yes |               Yes | Only narrowly granted operational posting |
| View standard financial reports             |   Yes |               Yes |                         By explicit grant |
| Export organization-wide financial data     |   Yes | By explicit grant |                             No by default |
| Operate sales/purchases/expenses/stock      |   Yes |               Yes |                         By explicit grant |
| Critical customization/publication          |   Yes | By explicit grant |                                        No |

Final capability details require product and accountant review, especially separation of duties for small three-user organizations.

## 5. Application and API controls

- Validate input with shared server schemas, size limits, canonicalization, and allowlists.
- Use parameterized queries and safe output encoding; prohibit tenant-authored HTML/script/SQL.
- Protect state-changing browser requests against CSRF as appropriate to the session architecture.
- Apply per-IP, per-user, per-organization, and sensitive-action rate limits.
- Use idempotency keys for retryable financial commands and webhook signature verification.
- Set security headers including CSP, frame restrictions, content-type controls, and an appropriate referrer policy.
- Avoid secrets and sensitive financial payloads in URLs, logs, analytics, or client errors.

## 6. File and OCR security

Documents live in private storage. Access uses short-lived, narrowly scoped signed URLs or authenticated server streaming. Uploads enforce allowlisted MIME/type validation based on content, size/page limits, sanitized filenames, malware scanning where available, checksum/deduplication, and safe image/PDF processing. Active content is not rendered inline unsafely.

OCR providers receive only necessary documents under reviewed data-processing terms. Extraction is untrusted input and cannot post. Provider callbacks are authenticated and replay-protected. Raw files/results follow documented retention and deletion policy.

## 7. Audit integrity

Audit events cover authentication/security changes, membership and permission changes, posting/reversal, period close/reopen, settings, tax overrides, customization publication, imports/exports, document access where appropriate, and operational admin access. Application users cannot update or delete audit events. Logs redact secrets and minimize personal data.

For stronger tamper evidence, periodically seal audit batches with hashes/export to restricted storage. Privileged maintenance is separately logged and reviewed.

## 8. Secrets and environments

Secrets live in environment-scoped secret management, never Git or browser bundles. Separate development, staging, and production projects/credentials/data. Use least-privilege database roles, rotate service/OAuth/OCR keys, restrict production console access, and require MFA for operational administrators and source/deployment providers.

## 9. Privacy and Indonesian legal review

Build for data minimization, declared purposes/lawful processing, correction and export workflows, retention, account closure, processor inventory, incident logging, and transparent privacy notices. Data residency/transfer, consent or other lawful basis, retention, breach duties, data-subject rights, Indonesian PDP requirements, and PSE obligations require qualified Indonesian legal advice before commercial launch.

## 10. Incident and vulnerability management

Maintain dependency and secret scanning, patch SLAs by severity, security test coverage, responsible disclosure contact, and an incident runbook covering containment, credential rotation, evidence preservation, tenant impact analysis, notification decision, recovery, and postmortem. Alerts should cover cross-tenant denial events, unusual exports, authentication abuse, privilege changes, storage access anomalies, and audit pipeline failure.

## 11. Security verification gates

Release gates include automated RLS cross-tenant tests, authorization matrix tests, dependency/secret scans, upload abuse tests, session/CSRF/XSS checks, webhook replay tests, backup restore tests, and manual review of high-risk changes. Before beta, obtain an independent security review focused on tenant isolation and financial-record integrity.
