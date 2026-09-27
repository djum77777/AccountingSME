import Link from "next/link";
import { AuthForm } from "@/components/auth-form";
import { getTranslations } from "@/lib/i18n/server";

export default async function SignupPage() {
  const t = await getTranslations();
  return (
    <main className="centered-page">
      <section className="card auth-card">
        <p className="eyebrow">Individual account</p>
        <h1>{t.signup}</h1>
        <AuthForm
          labels={{
            email: t.email,
            password: t.password,
            submit: t.signup,
            google: t.continueWithGoogle,
          }}
          mode="signup"
        />
        <div className="auth-links">
          <Link href="/login">{t.login}</Link>
        </div>
      </section>
    </main>
  );
}
