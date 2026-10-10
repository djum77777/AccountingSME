import Link from "next/link";
import {
  addPartyAddress,
  addPartyContact,
  setPartyCustomField,
  setPartyStatus,
  updateParty,
} from "@/app/actions/parties";
import { getPartyDetail } from "@/data/parties";
import { partyAddressKinds } from "@/lib/domain/parties";
import { getLocale, getTranslations } from "@/lib/i18n/server";

function HiddenIds({
  organizationId,
  partyId,
}: {
  organizationId: string;
  partyId: string;
}) {
  return (
    <>
      <input name="organizationId" type="hidden" value={organizationId} />
      <input name="partyId" type="hidden" value={partyId} />
    </>
  );
}

function displayValue(value: unknown) {
  if (Array.isArray(value)) return value.join(", ");
  if (typeof value === "boolean") return value ? "true" : "false";
  return value === null || value === undefined ? "" : String(value);
}

export default async function PartyDetailPage({
  params,
}: {
  params: Promise<{ organizationId: string; partyId: string }>;
}) {
  const [{ organizationId, partyId }, t, locale] = await Promise.all([
    params,
    getTranslations(),
    getLocale(),
  ]);
  const data = await getPartyDetail(organizationId, partyId);
  const party = data.party;
  const customerRole = data.roles.find(
    (role) => role.role_kind === "customer" && role.status === "active",
  );
  const supplierRole = data.roles.find(
    (role) => role.role_kind === "supplier" && role.status === "active",
  );
  const label = (value: unknown) =>
    String((value as Record<string, unknown> | null)?.[locale] ?? "");

  return (
    <section>
      <div className="section-heading">
        <div>
          <p className="eyebrow">
            {party.status} · {party.id}
          </p>
          <h1>{party.display_name}</h1>
          <p>{data.organization.display_name}</p>
        </div>
        <div className="button-row compact">
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/parties`}
          >
            ← {t.partyDirectory}
          </Link>
          <form action={setPartyStatus}>
            <HiddenIds organizationId={organizationId} partyId={partyId} />
            <input
              name="status"
              type="hidden"
              value={party.status === "active" ? "archived" : "active"}
            />
            <button
              className="button secondary"
              disabled={!data.canManage}
              type="submit"
            >
              {party.status === "active" ? t.archive : t.reactivate}
            </button>
          </form>
        </div>
      </div>
      <p className="notice">{t.noBalancesNotice}</p>

      <div className="settings-stack">
        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">01</p>
              <h2>{t.partyProfile}</h2>
            </div>
            <p>{t.stableReferenceNotice}</p>
          </div>
          <form action={updateParty} className="party-profile-form">
            <HiddenIds organizationId={organizationId} partyId={partyId} />
            <div className="configuration-form">
              <label>
                Legal name / Nama resmi
                <input
                  defaultValue={party.legal_name}
                  name="legalName"
                  required
                />
              </label>
              <label>
                Display name / Nama tampilan
                <input
                  defaultValue={party.display_name}
                  name="displayName"
                  required
                />
              </label>
              <label>
                Tax ID / NPWP
                <input
                  defaultValue={party.tax_identifier ?? ""}
                  name="taxIdentifier"
                />
              </label>
              <label>
                Tax status / Status pajak
                <select defaultValue={party.tax_status} name="taxStatus">
                  <option value="not_set">Not set / Belum diisi</option>
                  <option value="non_taxable">Non-taxable / Non-PKP</option>
                  <option value="taxable">Taxable / PKP</option>
                </select>
              </label>
              <label>
                Tax registration name / Nama pajak
                <input
                  defaultValue={party.tax_registration_name ?? ""}
                  name="taxRegistrationName"
                />
              </label>
              <label>
                Tax registration address / Alamat pajak
                <textarea
                  defaultValue={party.tax_registration_address ?? ""}
                  name="taxRegistrationAddress"
                  rows={2}
                />
              </label>
            </div>
            <div className="role-term-grid">
              <section className="sub-card">
                <label className="check-label">
                  <input
                    defaultChecked={Boolean(customerRole)}
                    name="isCustomer"
                    type="checkbox"
                  />
                  {t.customer}
                </label>
                <label>
                  {t.paymentTermDays}
                  <input
                    defaultValue={customerRole?.payment_term_days ?? 0}
                    max="3650"
                    min="0"
                    name="customerPaymentTermDays"
                    type="number"
                  />
                </label>
                <label>
                  {t.externalReference}
                  <input
                    defaultValue={customerRole?.external_reference ?? ""}
                    name="customerExternalReference"
                  />
                </label>
              </section>
              <section className="sub-card">
                <label className="check-label">
                  <input
                    defaultChecked={Boolean(supplierRole)}
                    name="isSupplier"
                    type="checkbox"
                  />
                  {t.supplier}
                </label>
                <label>
                  {t.paymentTermDays}
                  <input
                    defaultValue={supplierRole?.payment_term_days ?? 0}
                    max="3650"
                    min="0"
                    name="supplierPaymentTermDays"
                    type="number"
                  />
                </label>
                <label>
                  {t.externalReference}
                  <input
                    defaultValue={supplierRole?.external_reference ?? ""}
                    name="supplierExternalReference"
                  />
                </label>
              </section>
            </div>
            <label>
              {t.notes}
              <textarea
                defaultValue={party.notes ?? ""}
                name="notes"
                rows={4}
              />
            </label>
            <button
              className="button primary"
              disabled={!data.canManage}
              type="submit"
            >
              {t.save}
            </button>
          </form>
        </section>

        <div className="party-detail-grid">
          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">02</p>
                <h2>{t.contactDetails}</h2>
              </div>
            </div>
            <div className="metadata-list">
              {data.contacts.map((contact) => (
                <article key={contact.id}>
                  <p>
                    <strong>{contact.contact_name}</strong>
                    <span>
                      {contact.job_title ?? ""}{" "}
                      {contact.is_primary ? "· primary" : ""}
                    </span>
                  </p>
                  <span>
                    {contact.email ?? "—"} · {contact.phone ?? "—"}
                  </span>
                </article>
              ))}
            </div>
            <form action={addPartyContact} className="party-stacked-form">
              <HiddenIds organizationId={organizationId} partyId={partyId} />
              <label>
                Name / Nama
                <input name="contactName" required />
              </label>
              <label>
                Job title / Jabatan
                <input name="jobTitle" />
              </label>
              <label>
                Email
                <input name="email" type="email" />
              </label>
              <label>
                Phone / Telepon
                <input name="phone" />
              </label>
              <label className="check-label">
                <input name="isPrimary" type="checkbox" /> Primary / Utama
              </label>
              <button
                className="button secondary"
                disabled={!data.canManage}
                type="submit"
              >
                {t.addContact}
              </button>
            </form>
          </section>

          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">03</p>
                <h2>{t.addresses}</h2>
              </div>
            </div>
            <div className="metadata-list">
              {data.addresses.map((address) => (
                <article key={address.id}>
                  <p>
                    <strong>{address.label}</strong>
                    <span>
                      {address.address_kind}{" "}
                      {address.is_primary ? "· primary" : ""}
                    </span>
                  </p>
                  <span>
                    {[
                      address.address_line_1,
                      address.address_line_2,
                      address.city,
                      address.province,
                      address.postal_code,
                      address.country_code,
                    ]
                      .filter(Boolean)
                      .join(", ")}
                  </span>
                </article>
              ))}
            </div>
            <form action={addPartyAddress} className="party-stacked-form">
              <HiddenIds organizationId={organizationId} partyId={partyId} />
              <label>
                Kind / Jenis
                <select name="addressKind">
                  {partyAddressKinds.map((kind) => (
                    <option key={kind}>{kind}</option>
                  ))}
                </select>
              </label>
              <label>
                Label
                <input name="label" placeholder="Head office" required />
              </label>
              <label>
                Address line 1 / Alamat baris 1
                <input name="addressLine1" required />
              </label>
              <label>
                Address line 2 / Alamat baris 2
                <input name="addressLine2" />
              </label>
              <label>
                City / Kota
                <input name="city" />
              </label>
              <label>
                Province / Provinsi
                <input name="province" />
              </label>
              <label>
                Postal code / Kode pos
                <input name="postalCode" />
              </label>
              <label>
                Country
                <input defaultValue="ID" maxLength={2} name="countryCode" />
              </label>
              <label className="check-label">
                <input name="isPrimary" type="checkbox" /> Primary / Utama
              </label>
              <button
                className="button secondary"
                disabled={!data.canManage}
                type="submit"
              >
                {t.addAddress}
              </button>
            </form>
          </section>
        </div>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">04</p>
              <h2>{t.customFields}</h2>
            </div>
            <p>{t.customFieldPartyHint}</p>
          </div>
          {data.fieldDefinitions.length ? (
            <div className="custom-field-grid">
              {data.fieldDefinitions.map((definition) => {
                const saved = data.fieldValues.find(
                  (value) => value.definition_id === definition.id,
                );
                return (
                  <form
                    action={setPartyCustomField}
                    className="sub-card party-stacked-form"
                    key={definition.id}
                  >
                    <HiddenIds
                      organizationId={organizationId}
                      partyId={partyId}
                    />
                    <input
                      name="definitionId"
                      type="hidden"
                      value={definition.id}
                    />
                    <input
                      name="valueType"
                      type="hidden"
                      value={definition.value_type}
                    />
                    <label>
                      {label(definition.label_i18n) || definition.field_key}
                      {definition.value_type === "boolean" ? (
                        <select
                          defaultValue={displayValue(saved?.value) || "false"}
                          name="value"
                        >
                          <option value="false">No / Tidak</option>
                          <option value="true">Yes / Ya</option>
                        </select>
                      ) : (
                        <input
                          defaultValue={displayValue(saved?.value)}
                          name="value"
                          required={definition.is_required}
                          type={
                            definition.value_type === "date"
                              ? "date"
                              : definition.value_type === "datetime"
                                ? "datetime-local"
                                : definition.value_type === "integer" ||
                                    definition.value_type === "decimal"
                                  ? "number"
                                  : "text"
                          }
                        />
                      )}
                    </label>
                    <button
                      className="button secondary"
                      disabled={!data.canManage}
                      type="submit"
                    >
                      {t.save}
                    </button>
                  </form>
                );
              })}
            </div>
          ) : (
            <p>{t.noPartyCustomFields}</p>
          )}
        </section>
      </div>
    </section>
  );
}
