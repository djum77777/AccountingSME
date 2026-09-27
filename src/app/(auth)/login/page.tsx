import Link from "next/link";
import { AuthForm } from "@/components/auth-form";
import { getTranslations } from "@/lib/i18n/server";

export default async function LoginPage() {
  const t = await getTranslations();
  return (
    <main className="centered-page">
      <section className="card auth-card">
        <p className="eyebrow">Secure access</p>
        <h1>{t.login}</h1>
        <AuthForm
          labels={{
            email: t.email,
            password: t.password,
            submit: t.login,
            google: t.continueWithGoogle,
          }}
          mode="login"
        />
        <div className="auth-links">
          <Link href="/forgot-password">{t.forgotPassword}</Link>
          <Link href="/signup">{t.signup}</Link>
        </div>
      </section>
    </main>
  );
}
