# Email and Google Authentication Setup

This guide covers local manual testing and the production Supabase configuration. Authentication proves identity; organization membership, roles, RLS, and the three-active-user entitlement still decide access.

## Local environment

1. Start Docker Desktop and wait until the engine is running.
2. Run `npx supabase start` from the repository root.
3. Run `npx supabase status -o env`. Copy `API_URL` to `NEXT_PUBLIC_SUPABASE_URL` and `PUBLISHABLE_KEY` to `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in `.env.local`. Set `NEXT_PUBLIC_APP_URL=http://localhost:3000`.
4. Run `npm run dev`, then open `http://localhost:3000`.
5. Open local Mailpit at `http://127.0.0.1:54324`. Local confirmation, invitation, and password-reset messages appear here; they are not sent to the public internet.

Do not put the service-role key or a Google client secret in any `NEXT_PUBLIC_*` variable.

## Manually test email authentication

1. Open `/signup`, register a new test address and a password of at least 10 characters.
2. Confirm that the UI asks the user to check email and does not create an authenticated app session before confirmation.
3. In Mailpit, open the confirmation message and follow its link. Confirm that the callback returns to `/app`.
4. Log out, then use `/login` with the same credentials.
5. Open `/forgot-password`, submit the address, open the reset message in Mailpit, follow the link, set a new password at `/update-password`, and sign in with it.
6. Create an organization and confirm the owner membership is created, onboarding opens, and another tenant cannot read it.

For hosted Supabase, configure Authentication > URL Configuration with the production Site URL and explicit redirect URLs for `https://<your-domain>/auth/callback`. Keep localhost redirects only in development or preview projects.

## Configure Google OAuth

### Google Cloud Console

1. Create or select a Google Cloud project.
2. Configure Google Auth Platform / OAuth consent. During development choose External and add the Google accounts that will test the app.
3. Create an OAuth client of type **Web application**.
4. For local Supabase, add `http://localhost:3000` as an authorized JavaScript origin and `http://127.0.0.1:54321/auth/v1/callback` as an authorized redirect URI.
5. For hosted Supabase, also add the exact callback shown by Supabase, normally `https://<project-ref>.supabase.co/auth/v1/callback`. Do not substitute the Next.js callback here; Google first returns to Supabase, and Supabase then returns to `/auth/callback`.

### Supabase provider

For the hosted project, open Authentication > Providers > Google, enable it, and paste the Google client ID and client secret. In Authentication > URL Configuration, allow the application callback URLs used by local, preview, and production environments.

For local CLI testing, add this block to `supabase/config.toml` only after the two environment variables are available to the shell that starts Supabase:

```toml
[auth.external.google]
enabled = true
client_id = "env(SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID)"
secret = "env(SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET)"
redirect_uri = ""
skip_nonce_check = false
```

Set `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` and `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET` in the local shell or a private developer secret store, then run `npx supabase stop` followed by `npx supabase start`. Never commit either value.

## Manually test Google authentication

1. Open `/login` and select **Continue with Google**.
2. Sign in with an OAuth consent-screen test user.
3. Confirm the browser returns through `/auth/callback` to `/app` and that a `user_profiles` row was created by the trusted database trigger.
4. Log out, repeat Google sign-in, and confirm the same user is reused rather than duplicated.
5. Try a Google account not on the consent-screen test-user list; during testing it should be rejected by Google.
6. Verify that Google sign-in alone grants no organization access until a valid active membership exists.

## Production checklist

- Use separate Supabase and Google OAuth projects for development and production.
- Verify exact HTTPS origins and callback URLs; avoid wildcard production redirects.
- Keep email confirmation enabled and configure a verified SMTP sender/domain.
- Review Supabase Auth rate limits, CAPTCHA/bot controls, and breached-password protection.
- Rotate a leaked OAuth secret immediately and review authentication/audit logs.
- Test login, logout, email confirmation, password reset, invite acceptance, session expiry, and revoked membership before launch.
