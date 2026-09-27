# Phase 1 Implementation Record

## Scope

Phase 1 implements the repository, authentication, organization, membership, entitlement, RBAC, tenant-isolation, private-storage, audit, i18n, testing, and CI foundations. It does not implement accounting or business-operation modules.

## Policy clarifications incorporated

- Memberships are deactivated, never physically deleted through the application.
- Organizations receive three active seats by default.
- Invitations do not consume seats.
- Activating a member requires an owner and an available entitled seat.
- Only a platform-authorized service operation can increase the entitlement; monetization is not implemented.
- A member cannot approve their own role change. Another active owner must approve it.
- Base currency is a configurable ISO-style three-letter code; IDR is the default, not a restriction.

## Migration

`supabase/migrations/202609250001_phase1_foundation.sql` creates profiles, organizations, entitlements, retained memberships, permission grants, and audit events. It installs concurrency-safe seat and last-owner guards, trusted RPCs, RLS policies, a private document bucket, and organization-path storage policies.

## Verification status

Unit tests, type checking, lint, formatting, and production build can run without external credentials. Real database/RLS/storage policy tests require Docker and the Supabase local stack. Hosted authentication requires manually configured Supabase and Google credentials.

The Phase 1 completion gate must not be reported as fully passed until the database security suite and real authentication flows have run successfully.
