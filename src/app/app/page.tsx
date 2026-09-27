import Link from "next/link";
import { listOrganizations } from "@/data/organizations";
import { getTranslations } from "@/lib/i18n/server";

export default async function AppHomePage() {
  const [t, organizations] = await Promise.all([
    getTranslations(),
    listOrganizations(),
  ]);

  return (
    <section>
      <div className="section-heading">
        <div>
          <p className="eyebrow">Secure tenancy</p>
          <h1>{t.organizations}</h1>
        </div>
        <Link className="button primary" href="/setup">
          {t.createOrganization}
        </Link>
      </div>
      <p className="notice">{t.phaseNotice}</p>
      {organizations.length ? (
        <div className="organization-grid">
          {organizations.map((organization) => (
            <Link
              className="card organization-card"
              href={`/app/organizations/${organization.id}/accounting`}
              key={organization.id}
            >
              <span className="currency-chip">
                {organization.baseCurrencyCode}
              </span>
              <h2>{organization.displayName}</h2>
              <p>{t.accounting} →</p>
            </Link>
          ))}
        </div>
      ) : (
        <div className="card empty-state">
          <p>{t.noOrganization}</p>
        </div>
      )}
    </section>
  );
}
