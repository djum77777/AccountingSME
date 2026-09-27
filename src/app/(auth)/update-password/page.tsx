import { AuthForm } from "@/components/auth-form";
import { getTranslations } from "@/lib/i18n/server";

export default async function UpdatePasswordPage() {
  const t = await getTranslations();
  return (
    <main className="centered-page">
      <section className="card auth-card">
        <h1>{t.resetPassword}</h1>
        <AuthForm
          labels={{
            email: t.email,
            password: t.password,
            submit: t.resetPassword,
          }}
          mode="update"
        />
      </section>
    </main>
  );
}
