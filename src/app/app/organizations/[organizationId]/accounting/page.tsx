import { randomUUID } from "node:crypto";
import Link from "next/link";
import {
  closePeriod,
  createSubaccount,
  deactivateAccount,
  initializeAccounting,
  postManualJournal,
  postOpeningBalance,
  reopenPeriod,
  renameAccount,
  reverseJournal,
} from "@/app/actions/accounting";
import { getAccountingData } from "@/data/accounting";
import { templateKeys } from "@/lib/domain/customization";
import { getTranslations } from "@/lib/i18n/server";

const today = () => new Date().toISOString().slice(0, 10);

function OrganizationInput({ id }: { id: string }) {
  return <input name="organizationId" type="hidden" value={id} />;
}

function JournalForm({
  organizationId,
  accounts,
  opening,
  canPost,
}: {
  organizationId: string;
  accounts: Array<{ id: string; code: string; name: string; status: string }>;
  opening: boolean;
  canPost: boolean;
}) {
  return (
    <form
      action={opening ? postOpeningBalance : postManualJournal}
      className="card accounting-form"
    >
      <OrganizationInput id={organizationId} />
      <input
        name="idempotencyKey"
        type="hidden"
        value={`${opening ? "opening" : "journal"}-${randomUUID()}`}
      />
      <div className="settings-heading">
        <div>
          <p className="eyebrow">
            {opening ? "Opening balance" : "Manual journal"}
          </p>
          <h2>
            {opening
              ? "Saldo awal / Opening balance"
              : "Jurnal manual / Manual journal"}
          </h2>
        </div>
        <p>Amounts use an exact four-decimal boundary.</p>
      </div>
      <div className="two-column-form">
        <label>
          Date / Tanggal
          <input
            defaultValue={today()}
            name="accountingDate"
            required
            type="date"
          />
        </label>
        <label>
          Description / Keterangan
          <input name="description" required />
        </label>
        {!opening ? (
          <label>
            Source reference
            <input name="sourceReference" />
          </label>
        ) : null}
      </div>
      <div
        className="journal-line-grid journal-line-heading"
        aria-hidden="true"
      >
        <span>Account / Akun</span>
        <span>Debit</span>
        <span>Credit</span>
        <span>Description</span>
      </div>
      {Array.from({ length: 4 }, (_, index) => (
        <div className="journal-line-grid" key={index}>
          <select
            aria-label={`Line ${index + 1} account`}
            name={`accountId${index}`}
            required={index < 2}
          >
            <option value="">Select account</option>
            {accounts
              .filter((account) => account.status === "active")
              .map((account) => (
                <option key={account.id} value={account.id}>
                  {account.code} · {account.name}
                </option>
              ))}
          </select>
          <input
            aria-label={`Line ${index + 1} debit`}
            inputMode="decimal"
            name={`debit${index}`}
            placeholder="0.0000"
          />
          <input
            aria-label={`Line ${index + 1} credit`}
            inputMode="decimal"
            name={`credit${index}`}
            placeholder="0.0000"
          />
          <input
            aria-label={`Line ${index + 1} description`}
            name={`lineDescription${index}`}
          />
        </div>
      ))}
      <button className="button primary" disabled={!canPost} type="submit">
        Post / Posting
      </button>
    </form>
  );
}

export default async function AccountingPage({
  params,
}: {
  params: Promise<{ organizationId: string }>;
}) {
  const { organizationId } = await params;
  const [t, data] = await Promise.all([
    getTranslations(),
    getAccountingData(organizationId),
  ]);

  return (
    <section>
      <div className="section-heading">
        <div>
          <p className="eyebrow">Phase 3 · Ledger foundation</p>
          <h1>{t.accounting}</h1>
          <p>
            {data.organization.display_name} ·{" "}
            {data.organization.base_currency_code}
          </p>
        </div>
        <div className="button-row compact">
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/settings/customization`}
          >
            {t.customization}
          </Link>
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/members`}
          >
            {t.members}
          </Link>
        </div>
      </div>
      <p className="notice">{t.accountingNotice}</p>

      {!data.profile ? (
        <form action={initializeAccounting} className="card setup-card">
          <OrganizationInput id={organizationId} />
          <h2>{t.initializeAccounting}</h2>
          <p className="fine-print">
            This chart is an Indonesian SME starting structure, not a
            professionally approved accounting policy.
          </p>
          <label>
            Template
            <select defaultValue={data.suggestedTemplate} name="templateKey">
              {templateKeys.map((key) => (
                <option key={key}>{key}</option>
              ))}
            </select>
          </label>
          <div className="two-column-form">
            <label>
              Period start
              <input
                defaultValue="2026-01-01"
                name="periodStart"
                required
                type="date"
              />
            </label>
            <label>
              Period end
              <input
                defaultValue="2026-12-31"
                name="periodEnd"
                required
                type="date"
              />
            </label>
          </div>
          <button className="button primary full" type="submit">
            {t.initializeAccounting}
          </button>
        </form>
      ) : (
        <div className="settings-stack">
          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">01</p>
                <h2>{t.chartOfAccounts}</h2>
              </div>
              <p>
                {data.profile.template_key} · scale {data.profile.amount_scale}
              </p>
            </div>
            <div className="accounting-table">
              <div className="accounting-row table-header">
                <span>Code</span>
                <span>Account</span>
                <span>Category</span>
                <span>Status</span>
              </div>
              {data.accounts.map((account) => (
                <div className="accounting-row" key={account.id}>
                  <span>{account.code}</span>
                  <strong>{account.name}</strong>
                  <span>{account.category}</span>
                  <span>{account.status}</span>
                </div>
              ))}
            </div>
            {data.isOwner ? (
              <>
                <form action={createSubaccount} className="configuration-form">
                  <OrganizationInput id={organizationId} />
                  <label>
                    Parent
                    <select name="parentAccountId">
                      {data.accounts
                        .filter((account) => account.status === "active")
                        .map((account) => (
                          <option key={account.id} value={account.id}>
                            {account.code} · {account.name}
                          </option>
                        ))}
                    </select>
                  </label>
                  <label>
                    Code
                    <input name="code" placeholder="5210" required />
                  </label>
                  <label>
                    Name
                    <input name="name" required />
                  </label>
                  <label>
                    Category
                    <select name="category">
                      <option>asset</option>
                      <option>liability</option>
                      <option>equity</option>
                      <option>income</option>
                      <option>expense</option>
                    </select>
                  </label>
                  <label>
                    Normal balance
                    <select name="normalBalance">
                      <option>debit</option>
                      <option>credit</option>
                    </select>
                  </label>
                  <button className="button secondary" type="submit">
                    Add subaccount
                  </button>
                </form>
                <div className="metadata-list">
                  {data.accounts.map((account) => (
                    <article key={`manage-${account.id}`}>
                      <p>
                        <strong>{account.code}</strong>
                        <span>{account.name}</span>
                      </p>
                      <div className="inline-form">
                        <form action={renameAccount} className="inline-form">
                          <OrganizationInput id={organizationId} />
                          <input
                            name="accountId"
                            type="hidden"
                            value={account.id}
                          />
                          <input
                            aria-label={`Rename ${account.code}`}
                            defaultValue={account.name}
                            name="name"
                          />
                          <button className="text-button" type="submit">
                            Rename
                          </button>
                        </form>
                        {account.status === "active" &&
                        !account.is_control_account ? (
                          <form action={deactivateAccount}>
                            <OrganizationInput id={organizationId} />
                            <input
                              name="accountId"
                              type="hidden"
                              value={account.id}
                            />
                            <button
                              className="text-button danger"
                              type="submit"
                            >
                              Deactivate
                            </button>
                          </form>
                        ) : null}
                      </div>
                    </article>
                  ))}
                </div>
              </>
            ) : null}
          </section>

          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">02</p>
                <h2>{t.accountingPeriods}</h2>
              </div>
              <p>Owner-only close and reopen.</p>
            </div>
            <div className="metadata-list">
              {data.periods.map((period) => (
                <article key={period.id}>
                  <p>
                    <strong>{period.name}</strong>
                    <span>
                      {period.starts_on} — {period.ends_on} · {period.status}
                    </span>
                  </p>
                  {data.isOwner ? (
                    <form
                      action={
                        period.status === "open" ? closePeriod : reopenPeriod
                      }
                      className="inline-form"
                    >
                      <OrganizationInput id={organizationId} />
                      <input name="periodId" type="hidden" value={period.id} />
                      <input
                        aria-label="Period change reason"
                        name="reason"
                        placeholder="Reason"
                        required
                      />
                      <button className="button secondary" type="submit">
                        {period.status === "open" ? "Close" : "Reopen"}
                      </button>
                    </form>
                  ) : null}
                </article>
              ))}
            </div>
          </section>

          <div className="accounting-form-grid">
            <JournalForm
              accounts={data.accounts}
              canPost={data.canPost}
              organizationId={organizationId}
              opening
            />
            <JournalForm
              accounts={data.accounts}
              canPost={data.canPost}
              organizationId={organizationId}
              opening={false}
            />
          </div>

          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">03</p>
                <h2>{t.journalHistory}</h2>
              </div>
              <p>Posted entries are immutable; corrections use reversal.</p>
            </div>
            <div className="metadata-list">
              {data.journals.map((journal) => (
                <article key={journal.id}>
                  <p>
                    <strong>
                      #{journal.entry_number} · {journal.description}
                    </strong>
                    <span>
                      {journal.accounting_date} · {journal.kind} ·{" "}
                      {journal.status} · {journal.total_debit}
                    </span>
                  </p>
                  {data.canPost &&
                  journal.status === "posted" &&
                  journal.kind !== "reversal" ? (
                    <form action={reverseJournal} className="inline-form">
                      <OrganizationInput id={organizationId} />
                      <input
                        name="journalId"
                        type="hidden"
                        value={journal.id}
                      />
                      <input
                        name="idempotencyKey"
                        type="hidden"
                        value={`reversal-${journal.id}`}
                      />
                      <input
                        aria-label="Reversal date"
                        defaultValue={today()}
                        name="accountingDate"
                        type="date"
                      />
                      <input
                        aria-label="Reversal reason"
                        name="reason"
                        placeholder="Reason"
                        required
                      />
                      <button className="text-button danger" type="submit">
                        Reverse
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
                <h2>{t.generalLedger}</h2>
              </div>
              <p>Posted and reversed source entries only.</p>
            </div>
            <div className="accounting-table ledger-table">
              <div className="ledger-row table-header">
                <span>Date</span>
                <span>Journal</span>
                <span>Account</span>
                <span>Debit</span>
                <span>Credit</span>
              </div>
              {data.ledger.map((line) => (
                <div
                  className="ledger-row"
                  key={`${line.journal_entry_id}-${line.line_number}`}
                >
                  <span>{line.accounting_date}</span>
                  <span>#{line.entry_number}</span>
                  <span>
                    {line.account_code} · {line.account_name}
                  </span>
                  <span>{line.debit}</span>
                  <span>{line.credit}</span>
                </div>
              ))}
            </div>
          </section>

          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">05</p>
                <h2>{t.trialBalance}</h2>
              </div>
              <p>Derived from the general ledger.</p>
            </div>
            <div className="accounting-table ledger-table">
              <div className="ledger-row table-header">
                <span>Code</span>
                <span>Account</span>
                <span>Debit total</span>
                <span>Credit total</span>
                <span>Balance</span>
              </div>
              {data.trialBalance.map((account) => (
                <div className="ledger-row" key={String(account.account_id)}>
                  <span>{String(account.account_code)}</span>
                  <span>{String(account.account_name)}</span>
                  <span>{String(account.total_debit)}</span>
                  <span>{String(account.total_credit)}</span>
                  <span>
                    {String(account.debit_balance)} /{" "}
                    {String(account.credit_balance)}
                  </span>
                </div>
              ))}
            </div>
          </section>
        </div>
      )}
    </section>
  );
}
