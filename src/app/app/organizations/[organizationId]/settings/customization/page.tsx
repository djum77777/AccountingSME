import Link from "next/link";
import {
  addCustomDimensionValue,
  archiveCustomField,
  createCustomDimension,
  createCustomField,
  createSavedView,
  resetOrganizationConfiguration,
  setDisplayLabelAlias,
  setModuleVisibility,
  upsertFormFieldConfiguration,
} from "@/app/actions/customization";
import { getCustomizationData } from "@/data/customization";
import {
  customFieldEntityTypes,
  customizableEntityKeys,
  customValueTypes,
  moduleKeys,
} from "@/lib/domain/customization";
import { getLocale, getTranslations } from "@/lib/i18n/server";

function HiddenOrganization({ id }: { id: string }) {
  return <input name="organizationId" type="hidden" value={id} />;
}

export default async function CustomizationPage({
  params,
}: {
  params: Promise<{ organizationId: string }>;
}) {
  const { organizationId } = await params;
  const [t, locale, data] = await Promise.all([
    getTranslations(),
    getLocale(),
    getCustomizationData(organizationId),
  ]);
  const label = (value: unknown) =>
    String((value as Record<string, unknown> | null)?.[locale] ?? "");

  return (
    <section>
      <div className="section-heading">
        <div>
          <p className="eyebrow">
            {data.configuration?.template_key ?? "Phase 2"}
          </p>
          <h1>{t.customization}</h1>
          <p>{data.organization?.display_name}</p>
        </div>
        <div className="button-row compact">
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/accounting`}
          >
            {t.accounting}
          </Link>
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/members`}
          >
            {t.members}
          </Link>
          <Link
            className="button secondary"
            href={`/app/onboarding/${organizationId}`}
          >
            {t.onboarding}
          </Link>
        </div>
      </div>
      <p className="notice">{t.configurationNotice}</p>
      {!data.canManage ? (
        <p className="form-message">
          Only an owner, or an admin explicitly granted customization.manage,
          can change configuration.
        </p>
      ) : null}

      <div className="settings-stack">
        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">01</p>
              <h2>{t.modules}</h2>
            </div>
            <p>Stable module keys; visibility only.</p>
          </div>
          <div className="toggle-grid">
            {moduleKeys.map((moduleKey) => {
              const configured = data.modules.find(
                (item) => item.module_key === moduleKey,
              );
              const visible = configured?.is_visible ?? false;
              return (
                <form
                  action={setModuleVisibility}
                  className="toggle-row"
                  key={moduleKey}
                >
                  <HiddenOrganization id={organizationId} />
                  <input name="moduleKey" type="hidden" value={moduleKey} />
                  <input
                    name="visible"
                    type="hidden"
                    value={visible ? "false" : "true"}
                  />
                  <span>
                    <strong>{moduleKey.replaceAll("_", " ")}</strong>
                    <small>{configured?.source ?? "not configured"}</small>
                  </span>
                  <button
                    className={`status-pill ${visible ? "active" : ""}`}
                    disabled={!data.canManage}
                    type="submit"
                  >
                    {visible ? t.visible : t.hidden}
                  </button>
                </form>
              );
            })}
          </div>
        </section>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">02</p>
              <h2>{t.displayLabels}</h2>
            </div>
            <p>Core identifiers never change.</p>
          </div>
          <form action={setDisplayLabelAlias} className="configuration-form">
            <HiddenOrganization id={organizationId} />
            <label>
              Entity
              <select name="entityKey">
                {customizableEntityKeys.map((key) => (
                  <option key={key}>{key}</option>
                ))}
              </select>
            </label>
            <label>
              {t.language}
              <select name="locale">
                <option value="id">Bahasa Indonesia</option>
                <option value="en">English</option>
              </select>
            </label>
            <label>
              Singular
              <input name="singular" required />
            </label>
            <label>
              Plural
              <input name="plural" required />
            </label>
            <button
              className="button primary"
              disabled={!data.canManage}
              type="submit"
            >
              {t.add}
            </button>
          </form>
          <div className="metadata-list">
            {data.aliases.map((item) => (
              <p key={item.id}>
                <strong>
                  {item.entity_key} · {item.locale}
                </strong>
                <span>
                  {item.singular_label} / {item.plural_label}
                </span>
              </p>
            ))}
          </div>
        </section>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">03</p>
              <h2>{t.customFields}</h2>
            </div>
            <p>Values live in metadata rows, never new physical columns.</p>
          </div>
          <form action={createCustomField} className="configuration-form">
            <HiddenOrganization id={organizationId} />
            <label>
              Stable key
              <input name="fieldKey" placeholder="customer_tier" required />
            </label>
            <label>
              Entity
              <select name="entityType">
                {customFieldEntityTypes.map((key) => (
                  <option key={key}>{key}</option>
                ))}
              </select>
            </label>
            <label>
              Value type
              <select name="valueType">
                {customValueTypes.map((key) => (
                  <option key={key}>{key}</option>
                ))}
              </select>
            </label>
            <label>
              Label (ID)
              <input name="labelId" required />
            </label>
            <label>
              Label (EN)
              <input name="labelEn" required />
            </label>
            <button
              className="button primary"
              disabled={!data.canManage}
              type="submit"
            >
              {t.add}
            </button>
          </form>
          <div className="metadata-list">
            {data.fields.map((item) => (
              <article key={item.id}>
                <p>
                  <strong>{label(item.label_i18n)}</strong>
                  <span>
                    {item.entity_type} · {item.value_type} · v{item.version} ·{" "}
                    {item.status}
                  </span>
                </p>
                {item.status !== "inactive" ? (
                  <form action={archiveCustomField}>
                    <HiddenOrganization id={organizationId} />
                    <input name="definitionId" type="hidden" value={item.id} />
                    <button
                      className="text-button danger"
                      disabled={!data.canManage}
                      type="submit"
                    >
                      {t.archive}
                    </button>
                  </form>
                ) : null}
              </article>
            ))}
          </div>
        </section>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">04</p>
              <h2>{t.customDimensions}</h2>
            </div>
            <p>
              Reusable analysis axes such as Branch, Marketplace, Project, or
              Client Type.
            </p>
          </div>
          <form action={createCustomDimension} className="configuration-form">
            <HiddenOrganization id={organizationId} />
            <label>
              Stable key
              <input name="dimensionKey" placeholder="branch" required />
            </label>
            <label>
              Label (ID)
              <input name="labelId" required />
            </label>
            <label>
              Label (EN)
              <input name="labelEn" required />
            </label>
            <button
              className="button primary"
              disabled={!data.canManage}
              type="submit"
            >
              {t.add}
            </button>
          </form>
          <div className="dimension-grid">
            {data.dimensions.map((dimension) => (
              <article className="sub-card" key={dimension.id}>
                <h3>{label(dimension.label_i18n)}</h3>
                <p className="fine-print">
                  {dimension.dimension_key} · {dimension.status}
                </p>
                <ul>
                  {data.dimensionValues
                    .filter((value) => value.dimension_id === dimension.id)
                    .map((value) => (
                      <li key={value.id}>
                        {label(value.label_i18n)}{" "}
                        <small>({value.value_code})</small>
                      </li>
                    ))}
                </ul>
                <form action={addCustomDimensionValue}>
                  <HiddenOrganization id={organizationId} />
                  <input
                    name="dimensionId"
                    type="hidden"
                    value={dimension.id}
                  />
                  <div className="configuration-form compact-form">
                    <label>
                      Code
                      <input name="valueCode" required />
                    </label>
                    <label>
                      ID
                      <input name="labelId" required />
                    </label>
                    <label>
                      EN
                      <input name="labelEn" required />
                    </label>
                    <button
                      className="button secondary"
                      disabled={!data.canManage}
                      type="submit"
                    >
                      {t.add}
                    </button>
                  </div>
                </form>
              </article>
            ))}
          </div>
        </section>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">05</p>
              <h2>{t.formConfiguration}</h2>
            </div>
            <p>
              Order, section, required/default, visibility, and role visibility.
            </p>
          </div>
          <form
            action={upsertFormFieldConfiguration}
            className="configuration-form"
          >
            <HiddenOrganization id={organizationId} />
            <label>
              Form
              <select name="formKey">
                {[
                  "contact",
                  "expense",
                  "sale",
                  "purchase",
                  "product",
                  "project",
                ].map((key) => (
                  <option key={key}>{key}</option>
                ))}
              </select>
            </label>
            <label>
              Field key
              <input
                name="fieldKey"
                placeholder="custom.customer_tier"
                required
              />
            </label>
            <label>
              Section
              <input defaultValue="main" name="sectionKey" required />
            </label>
            <label>
              Order
              <input defaultValue="10" min="0" name="sortOrder" type="number" />
            </label>
            <label>
              Default
              <input name="defaultValue" />
            </label>
            <label className="check-label">
              <input defaultChecked name="visible" type="checkbox" />
              Visible
            </label>
            <label className="check-label">
              <input name="required" type="checkbox" />
              Required
            </label>
            <label className="check-label">
              <input defaultChecked name="role_owner" type="checkbox" />
              Owner
            </label>
            <label className="check-label">
              <input
                defaultChecked
                name="role_admin_accountant"
                type="checkbox"
              />
              Admin/Accountant
            </label>
            <label className="check-label">
              <input defaultChecked name="role_staff" type="checkbox" />
              Staff
            </label>
            <button
              className="button primary"
              disabled={!data.canManage}
              type="submit"
            >
              Save
            </button>
          </form>
          <div className="metadata-list">
            {data.formFields.map((item) => (
              <p key={item.id}>
                <strong>{item.field_key}</strong>
                <span>
                  {item.section_key} · #{item.sort_order} ·{" "}
                  {item.is_visible ? "visible" : "hidden"} ·{" "}
                  {item.is_required ? "required" : "optional"} ·{" "}
                  {(item.role_visibility ?? []).join(", ")}
                </span>
              </p>
            ))}
          </div>
        </section>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">06</p>
              <h2>{t.savedViews}</h2>
            </div>
            <p>Allowlisted view metadata; no executable query fragments.</p>
          </div>
          <form action={createSavedView} className="configuration-form">
            <HiddenOrganization id={organizationId} />
            <label>
              Name
              <input name="name" required />
            </label>
            <label>
              Entity
              <select name="entityType">
                {customFieldEntityTypes.map((key) => (
                  <option key={key}>{key}</option>
                ))}
              </select>
            </label>
            <label>
              Columns (comma separated)
              <input
                name="columns"
                placeholder="name, status, customer_tier"
                required
              />
            </label>
            <label className="check-label">
              <input name="isShared" type="checkbox" />
              Shared with organization
            </label>
            <button className="button primary" type="submit">
              {t.add}
            </button>
          </form>
          <div className="metadata-list">
            {data.views.map((item) => (
              <p key={item.id}>
                <strong>{item.name}</strong>
                <span>
                  {item.entity_type} · {item.is_shared ? "shared" : "private"}
                </span>
              </p>
            ))}
          </div>
        </section>

        <section className="card settings-section danger-zone">
          <div>
            <h2>{t.resetDefaults}</h2>
            <p>
              Replaces only template-derived modules, aliases, and form layout.
              Custom fields, dimensions, values, members, and business records
              remain.
            </p>
          </div>
          <form action={resetOrganizationConfiguration}>
            <HiddenOrganization id={organizationId} />
            <button
              className="button secondary"
              disabled={!data.canManage}
              type="submit"
            >
              {t.resetDefaults}
            </button>
          </form>
        </section>
      </div>
    </section>
  );
}
