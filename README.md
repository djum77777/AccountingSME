# Buku Usaha — Phase 1 Foundation

Secure multi-tenant foundation for a configurable Indonesian SME accounting platform. Phase 1 deliberately contains no ledger, sales, purchasing, inventory, OCR, tax calculation, or financial-reporting features.

The permanent architecture is in [`docs/`](docs/), beginning with [`product-architecture.md`](docs/product-architecture.md).

## What Phase 1 includes

- Next.js 16, React 19, strict TypeScript, ESLint, Prettier, Vitest, and CI.
- Supabase Auth with email/password, Google OAuth, verified recovery flow, and server-refreshed sessions.
- Organizations, retained memberships, owner/admin-accountant/staff roles, extensible permissions, and append-only audit events.
- Three active seats by default. A platform-only entitlement operation can add seats; an owner still approves activation.
- Last-active-owner protection and prohibition on physical membership deletion.
- PostgreSQL RLS tenant isolation and private organization-scoped document storage policies.
- Bahasa Indonesia and English shell with configurable three-letter base currency (IDR is only the default).

## Prerequisites

- Node.js 24 LTS (see `.nvmrc`). Odd-numbered Node releases are intentionally not used in CI.
- Docker Desktop for the local Supabase database and database-security tests.
- Git.

## Local setup

```powershell
npm install
Copy-Item .env.example .env.local
npx supabase start
```

Copy the local Supabase URL and publishable/anon key printed by `supabase start` into `.env.local`, then run:

```powershell
npm run dev
```

Open `http://localhost:3000`.

## Required checks

```powershell
npm run format
npm run lint
npm run typecheck
npm run test
npm run test:db
npm run build
```

`npm run test:db` uses a real local PostgreSQL/Supabase instance. It proves RLS isolation, the default seat entitlement, platform-authorized seat increases, owner-approved activation, retained deactivation, last-owner protection, role authorization, and audit visibility.

## Environment variables

| Variable                               | Exposure     | Purpose                                                                                                                           |
| -------------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`             | Browser-safe | Supabase project URL.                                                                                                             |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Browser-safe | Publishable/anon key; security depends on RLS.                                                                                    |
| `NEXT_PUBLIC_APP_URL`                  | Browser-safe | Exact application origin for auth callbacks.                                                                                      |
| `SUPABASE_SERVICE_ROLE_KEY`            | Server-only  | Required only for owner-authorized member email invitations and future platform entitlement jobs. Never expose it to the browser. |

## Google OAuth setup

1. In Google Cloud Console, create an OAuth 2.0 Web application.
2. Add the Supabase callback shown under Supabase Authentication → Providers → Google as an authorized redirect URI. For hosted projects this is normally `https://<project-ref>.supabase.co/auth/v1/callback`.
3. Enable Google in Supabase Authentication and enter the Google client ID and secret.
4. Add the application callback (`http://localhost:3000/auth/callback` locally and the production equivalent) to Supabase Authentication → URL Configuration.
5. Set the deployed `NEXT_PUBLIC_APP_URL` to the exact HTTPS production origin.
6. Test a complete sign-in, logout, and account-link flow before declaring OAuth operational.

Do not put the Google client secret or Supabase service-role key in any `NEXT_PUBLIC_` variable.

## Non-engineer verification

1. Start Docker Desktop, then run `npx supabase start` and `npm run dev`.
2. Create an account and confirm the email if confirmations are enabled.
3. Create an organization; confirm it starts with currency IDR but accepts another three-letter currency such as USD.
4. Open Members. Invite and activate members until all three default seats are active.
5. Invite a fourth person. The invitation may exist, but activation must be blocked until the platform entitlement is increased.
6. Try to deactivate or demote the only active owner. The action must fail.
7. Add and activate another owner. Sign in as that owner and confirm they can approve the first owner's role change.
8. Sign in as Staff and confirm membership administration and another organization's URLs/data are inaccessible.
9. Switch between ID and EN and confirm navigation labels change.
10. Run all required checks above and save the results with the release record.

## External services and current limitation

Email delivery, Google OAuth, and hosted Supabase require project-specific credentials. The application and configuration paths are implemented, but those flows are not considered verified until configured and exercised against the target Supabase project.
