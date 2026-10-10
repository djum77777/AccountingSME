"use client";

import Link from "next/link";
import { useActionState } from "react";
import {
  checkPartyDuplicates,
  createParty,
  type DuplicateCheckState,
} from "@/app/actions/parties";

const initialState: DuplicateCheckState = { checked: false, matches: [] };

export function PartyCreateForm({
  organizationId,
  canManage,
  labels,
}: {
  organizationId: string;
  canManage: boolean;
  labels: {
    customer: string;
    supplier: string;
    duplicateCheck: string;
    duplicateNone: string;
    duplicateWarning: string;
    create: string;
  };
}) {
  const [state, duplicateAction, checking] = useActionState(
    checkPartyDuplicates,
    initialState,
  );

  return (
    <form action={createParty} className="party-create-form">
      <input name="organizationId" type="hidden" value={organizationId} />
      <div className="configuration-form party-core-fields">
        <label>
          Legal name / Nama resmi
          <input name="legalName" required />
        </label>
        <label>
          Display name / Nama tampilan
          <input name="displayName" required />
        </label>
        <label>
          Email
          <input name="email" type="email" />
        </label>
        <label>
          Phone / Telepon
          <input name="phone" />
        </label>
        <label>
          Tax ID / NPWP
          <input name="taxIdentifier" />
        </label>
      </div>

      <div className="role-term-grid">
        <section className="sub-card">
          <label className="check-label">
            <input defaultChecked name="isCustomer" type="checkbox" />
            {labels.customer}
          </label>
          <label>
            Payment term days / Termin hari
            <input
              defaultValue="0"
              max="3650"
              min="0"
              name="customerPaymentTermDays"
              type="number"
            />
          </label>
          <label>
            External reference / Referensi eksternal
            <input name="customerExternalReference" />
          </label>
        </section>
        <section className="sub-card">
          <label className="check-label">
            <input name="isSupplier" type="checkbox" />
            {labels.supplier}
          </label>
          <label>
            Payment term days / Termin hari
            <input
              defaultValue="0"
              max="3650"
              min="0"
              name="supplierPaymentTermDays"
              type="number"
            />
          </label>
          <label>
            External reference / Referensi eksternal
            <input name="supplierExternalReference" />
          </label>
        </section>
      </div>

      <details className="party-optional-section">
        <summary>Tax metadata & notes / Data pajak & catatan</summary>
        <div className="configuration-form">
          <label>
            Tax status / Status pajak
            <select defaultValue="not_set" name="taxStatus">
              <option value="not_set">Not set / Belum diisi</option>
              <option value="non_taxable">Non-taxable / Non-PKP</option>
              <option value="taxable">Taxable / PKP</option>
            </select>
          </label>
          <label>
            Tax registration name / Nama pajak
            <input name="taxRegistrationName" />
          </label>
          <label>
            Tax registration address / Alamat pajak
            <textarea name="taxRegistrationAddress" rows={2} />
          </label>
          <label>
            Notes / Catatan
            <textarea name="notes" rows={2} />
          </label>
        </div>
      </details>

      {state.checked ? (
        <div className={state.matches.length ? "duplicate-alert" : "notice"}>
          <strong>
            {state.matches.length
              ? labels.duplicateWarning
              : labels.duplicateNone}
          </strong>
          {state.matches.length ? (
            <ul>
              {state.matches.map((match) => (
                <li key={match.partyId}>
                  <Link
                    href={`/app/organizations/${organizationId}/parties/${match.partyId}`}
                  >
                    {match.displayName}
                  </Link>{" "}
                  · {match.reasons.join(", ")} · {match.status}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}

      <div className="button-row">
        <button
          className="button secondary"
          disabled={!canManage || checking}
          formAction={duplicateAction}
          type="submit"
        >
          {checking ? "…" : labels.duplicateCheck}
        </button>
        <button className="button primary" disabled={!canManage} type="submit">
          {labels.create}
        </button>
      </div>
    </form>
  );
}
