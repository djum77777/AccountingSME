import { createOrganization } from "@/app/actions/organizations";
import { getTranslations } from "@/lib/i18n/server";

export default async function SetupPage() {
  const t = await getTranslations();
  return (
    <main className="centered-page">
      <section className="card setup-card">
        <p className="eyebrow">Tenant setup</p>
        <h1>{t.createOrganization}</h1>
        <form action={createOrganization}>
          <label>
            {t.organizationName}
            <input maxLength={120} name="name" required />
          </label>
          <label>
            {t.baseCurrency}
            <input
              defaultValue="IDR"
              maxLength={3}
              minLength={3}
              name="currency"
              pattern="[A-Za-z]{3}"
              required
            />
          </label>
          <button className="button primary full" type="submit">
            {t.createOrganization}
          </button>
        </form>
      </section>
    </main>
  );
}
