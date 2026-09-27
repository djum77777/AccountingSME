"use client";

import { useMemo, useState } from "react";
import { completeOnboarding } from "@/app/actions/customization";

type TemplateOption = {
  key: string;
  names: Record<string, string>;
  descriptions: Record<string, string>;
  recommendedBusinessTypes: string[];
};

export function OnboardingForm({
  organizationId,
  initialName,
  initialCurrency,
  initialLocale,
  templates,
  labels,
}: {
  organizationId: string;
  initialName: string;
  initialCurrency: string;
  initialLocale: string;
  templates: TemplateOption[];
  labels: Record<string, string>;
}) {
  const [step, setStep] = useState(1);
  const [locale, setLocale] = useState(initialLocale === "en" ? "en" : "id");
  const [businessType, setBusinessType] = useState("general");
  const recommended = useMemo(
    () =>
      templates.find((item) =>
        item.recommendedBusinessTypes.includes(businessType),
      )?.key ?? "general_sme",
    [businessType, templates],
  );
  const [templateChoice, setTemplateChoice] = useState<string | null>(null);
  const selectedTemplate = templateChoice ?? recommended;

  return (
    <form action={completeOnboarding} className="onboarding-form">
      <input name="organizationId" type="hidden" value={organizationId} />
      <ol className="stepper" aria-label={labels.onboarding}>
        {[
          labels.language,
          labels.businessType,
          labels.businessInfo,
          labels.recommendedTemplate,
          labels.basicSettings,
        ].map((label, index) => (
          <li
            className={
              step === index + 1 ? "active" : step > index + 1 ? "done" : ""
            }
            key={label}
          >
            <span>{index + 1}</span>
            {label}
          </li>
        ))}
      </ol>

      <fieldset hidden={step !== 1}>
        <legend>{labels.language}</legend>
        <div className="choice-grid">
          <label className="choice-card">
            <input
              checked={locale === "id"}
              name="locale"
              onChange={() => setLocale("id")}
              type="radio"
              value="id"
            />
            Bahasa Indonesia
          </label>
          <label className="choice-card">
            <input
              checked={locale === "en"}
              name="locale"
              onChange={() => setLocale("en")}
              type="radio"
              value="en"
            />
            English
          </label>
        </div>
      </fieldset>

      <fieldset hidden={step !== 2}>
        <legend>{labels.businessType}</legend>
        <select
          name="businessType"
          onChange={(event) => {
            setBusinessType(event.target.value);
            setTemplateChoice(null);
          }}
          value={businessType}
        >
          <option value="general">General SME / UMKM Umum</option>
          <option value="retail">Retail / Ritel</option>
          <option value="online_seller">Online Seller / Penjual Online</option>
          <option value="trading">Trading / Perdagangan</option>
          <option value="distributor">Distributor</option>
          <option value="service">Service / Jasa</option>
          <option value="consulting">Consulting / Konsultan</option>
          <option value="other">Other / Lainnya</option>
        </select>
      </fieldset>

      <fieldset hidden={step !== 3}>
        <legend>{labels.businessInfo}</legend>
        <label>
          {labels.organizationName}
          <input
            defaultValue={initialName}
            maxLength={120}
            name="businessName"
            required
          />
        </label>
        <label>
          {labels.businessAddress}
          <textarea maxLength={500} name="businessAddress" rows={3} />
        </label>
        <div className="two-column-form">
          <label>
            {labels.phone}
            <input maxLength={40} name="phone" />
          </label>
          <label>
            {labels.taxIdentifier}
            <input maxLength={60} name="taxIdentifier" />
          </label>
        </div>
      </fieldset>

      <fieldset hidden={step !== 4}>
        <legend>{labels.recommendedTemplate}</legend>
        <div className="template-grid">
          {templates.map((template) => (
            <label
              className={`choice-card ${selectedTemplate === template.key ? "selected" : ""}`}
              key={template.key}
            >
              <input
                checked={selectedTemplate === template.key}
                name="templateKey"
                onChange={() => setTemplateChoice(template.key)}
                type="radio"
                value={template.key}
              />
              <strong>{template.names[locale]}</strong>
              <small>{template.descriptions[locale]}</small>
              {recommended === template.key ? <em>Recommended</em> : null}
            </label>
          ))}
        </div>
      </fieldset>

      <fieldset hidden={step !== 5}>
        <legend>{labels.basicSettings}</legend>
        <div className="two-column-form">
          <label>
            {labels.baseCurrency}
            <input
              defaultValue={initialCurrency}
              maxLength={3}
              minLength={3}
              name="currency"
              pattern="[A-Za-z]{3}"
              required
            />
          </label>
          <label>
            {labels.timezone}
            <select defaultValue="Asia/Jakarta" name="timezone">
              <option>Asia/Jakarta</option>
              <option>Asia/Makassar</option>
              <option>Asia/Jayapura</option>
              <option>UTC</option>
            </select>
          </label>
          <label>
            {labels.dateFormat}
            <select defaultValue="DD/MM/YYYY" name="dateFormat">
              <option>DD/MM/YYYY</option>
              <option>MM/DD/YYYY</option>
              <option>YYYY-MM-DD</option>
            </select>
          </label>
        </div>
      </fieldset>

      <div className="wizard-actions">
        <button
          className="button secondary"
          disabled={step === 1}
          onClick={() => setStep((current) => Math.max(1, current - 1))}
          type="button"
        >
          {labels.back}
        </button>
        {step < 5 ? (
          <button
            className="button primary"
            onClick={() => setStep((current) => Math.min(5, current + 1))}
            type="button"
          >
            {labels.next}
          </button>
        ) : (
          <button className="button primary" type="submit">
            {labels.finishSetup}
          </button>
        )}
      </div>
    </form>
  );
}
