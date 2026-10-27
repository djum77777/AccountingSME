import Link from "next/link";
import { PartyCreateForm } from "@/components/party-create-form";
import { getPartyDirectory } from "@/data/parties";
import { getLocale, getTranslations } from "@/lib/i18n/server";

export default async function PartiesPage({
  params,
  searchParams,
}: {
  params: Promise<{ organizationId: string }>;
  searchParams: Promise<{
    q?: string;
    role?: string;
    archived?: string;
  }>;
}) {
  const [{ organizationId }, filters, t, locale] = await Promise.all([
    params,
    searchParams,
    getTranslations(),
    getLocale(),
  ]);
  const data = await getPartyDirectory(organizationId, {
    query: filters.q,
    role: filters.role,
    includeArchived: filters.archived === "true",
  });
  const alias = (entity: "customer" | "supplier", fallback: string) =>
    data.aliases.find(
      (item) => item.entity_key === entity && item.locale === locale,
    )?.singular_label ?? fallback;
  const customerLabel = alias("customer", t.customer);
  const supplierLabel = alias("supplier", t.supplier);

  return (
    <section>
      <div className="section-heading">
        <div>
          <p className="eyebrow">Phase 5 · Stable party identities</p>
          <h1>{t.parties}</h1>
          <p>{data.organization.display_name}</p>
        </div>
        <div className="button-row compact">
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/purchases`}
          >
            {t.purchases}
          </Link>
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/inventory`}
          >
            {t.inventory}
          </Link>
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/settings/customization`}
          >
            {t.customization}
          </Link>
        </div>
      </div>
      <p className="notice">{t.partyNotice}</p>

      <div className="settings-stack">
        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">01</p>
              <h2>{t.partyDirectory}</h2>
            </div>
            <p>{t.partySearchHint}</p>
          </div>
          <form className="party-search-form" method="get">
            <label>
              {t.search}
              <input
                defaultValue={filters.q}
                name="q"
                placeholder="Name, email, phone, tax ID, reference"
              />
            </label>
            <label>
              {t.role}
              <select defaultValue={filters.role ?? ""} name="role">
                <option value="">{t.all}</option>
                <option value="customer">{customerLabel}</option>
                <option value="supplier">{supplierLabel}</option>
              </select>
            </label>
            <label className="check-label">
              <input
                defaultChecked={filters.archived === "true"}
                name="archived"
                type="checkbox"
                value="true"
              />
              {t.includeArchived}
            </label>
            <button className="button secondary" type="submit">
              {t.search}
            </button>
          </form>
          <div className="accounting-table">
            <div className="party-directory-row table-header">
              <span>{t.party}</span>
              <span>{t.role}</span>
              <span>{t.contactDetails}</span>
              <span>{t.taxIdentifier}</span>
              <span>{t.status}</span>
            </div>
            {data.parties.map((party) => (
              <Link
                className="party-directory-row party-directory-link"
                href={`/app/organizations/${organizationId}/parties/${party.id}`}
                key={party.id}
              >
                <span>
                  <strong>{party.display_name}</strong>
                  <small>{party.legal_name}</small>
                </span>
                <span>
                  {(party.roles ?? [])
                    .map((role: string) =>
                      role === "customer" ? customerLabel : supplierLabel,
                    )
                    .join(" · ")}
                </span>
                <span>
                  {party.primary_email ?? "—"}
                  <small>{party.primary_phone ?? ""}</small>
                </span>
                <span>{party.tax_identifier ?? "—"}</span>
                <span className={`status-pill ${party.status}`}>
                  {party.status}
                </span>
              </Link>
            ))}
          </div>
          {!data.parties.length ? (
            <p className="empty-state">{t.noParties}</p>
          ) : null}
        </section>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">02</p>
              <h2>{t.createParty}</h2>
            </div>
            <p>{t.duplicateGuidance}</p>
          </div>
          <PartyCreateForm
            canManage={data.canManage}
            labels={{
              customer: customerLabel,
              supplier: supplierLabel,
              duplicateCheck: t.checkDuplicates,
              duplicateNone: t.noDuplicates,
              duplicateWarning: t.duplicateWarning,
              create: t.createParty,
            }}
            organizationId={organizationId}
          />
        </section>
      </div>
    </section>
  );
}
