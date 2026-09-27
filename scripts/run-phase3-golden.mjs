import { execFileSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";

const statusOutput =
  process.platform === "win32"
    ? execFileSync(
        process.env.ComSpec ?? "cmd.exe",
        ["/d", "/s", "/c", "npx supabase status -o env"],
        { encoding: "utf8" },
      )
    : execFileSync("npx", ["supabase", "status", "-o", "env"], {
        encoding: "utf8",
      });
const status = Object.fromEntries(
  statusOutput
    .split(/\r?\n/)
    .filter((line) => line.includes("="))
    .map((line) => {
      const separator = line.indexOf("=");
      return [
        line.slice(0, separator),
        line.slice(separator + 1).replace(/^"|"$/g, ""),
      ];
    }),
);

const suffix = crypto.randomUUID();
const email = `toko-maju-jaya-${suffix}@example.test`;
const password = `Golden-${suffix}-Aa1!`;
const admin = createClient(status.API_URL, status.SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});
const created = await admin.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
});
if (created.error) throw created.error;

const owner = createClient(status.API_URL, status.ANON_KEY, {
  auth: { persistSession: false },
});
const signIn = await owner.auth.signInWithPassword({ email, password });
if (signIn.error) throw signIn.error;
const organization = await owner.rpc("create_organization", {
  organization_name: "Toko Maju Jaya",
  currency_code: "IDR",
});
if (organization.error) throw organization.error;
const organizationId = organization.data;
const initialized = await owner.rpc("initialize_accounting", {
  target_organization_id: organizationId,
  selected_template_key: "retail",
  first_period_start: "2026-01-01",
  first_period_end: "2026-12-31",
});
if (initialized.error) throw initialized.error;

const accounts = await owner
  .from("accounts")
  .select("id,code,name,system_purpose")
  .eq("organization_id", organizationId)
  .in("system_purpose", ["cash", "owner_capital"]);
if (accounts.error) throw accounts.error;
const cash = accounts.data.find((account) => account.system_purpose === "cash");
const capital = accounts.data.find(
  (account) => account.system_purpose === "owner_capital",
);
if (!cash || !capital) throw new Error("Golden accounts unavailable");

const opening = await owner.rpc("post_opening_balance", {
  target_organization_id: organizationId,
  target_accounting_date: "2026-01-01",
  target_description: "Toko Maju Jaya opening balance",
  target_lines: [
    { account_id: cash.id, debit: "1000000.0000", credit: "0" },
    { account_id: capital.id, debit: "0", credit: "1000000.0000" },
  ],
  target_idempotency_key: `golden-opening-${suffix}`,
});
if (opening.error) throw opening.error;

const reversal = await owner.rpc("reverse_journal", {
  target_journal_entry_id: opening.data,
  target_accounting_date: "2026-01-31",
  target_reason: "Golden scenario reversal",
  target_idempotency_key: `golden-reversal-${suffix}`,
});
if (reversal.error) throw reversal.error;

const trialBalance = await owner.rpc("get_trial_balance", {
  target_organization_id: organizationId,
  target_through_date: "2026-01-31",
});
if (trialBalance.error) throw trialBalance.error;
const net = trialBalance.data.reduce(
  (total, row) =>
    total +
    BigInt(String(row.debit_balance).replace(".", "")) +
    BigInt(String(row.credit_balance).replace(".", "")),
  0n,
);
if (net !== 0n)
  throw new Error(`Golden Trial Balance did not net to zero: ${net}`);

const journals = await owner
  .from("journal_entries")
  .select(
    "id,kind,status,total_debit,total_credit,reversal_of_id,reversal_entry_id",
  )
  .in("id", [opening.data, reversal.data])
  .order("entry_number");
if (journals.error) throw journals.error;
const audit = await owner
  .from("audit_events")
  .select("action,target_id")
  .eq("organization_id", organizationId)
  .in("action", ["opening_balance.posted", "journal.reversed"]);
if (audit.error) throw audit.error;
if (audit.data.length !== 2)
  throw new Error("Golden audit evidence is incomplete");

console.log(
  JSON.stringify(
    {
      result: "PASS",
      organization: "Toko Maju Jaya",
      opening: `${cash.name} Dr 1,000,000 / ${capital.name} Cr 1,000,000`,
      openingJournalId: opening.data,
      reversalJournalId: reversal.data,
      journalLifecycle: journals.data,
      trialBalanceNet: "0.0000",
      auditActions: audit.data.map((event) => event.action).sort(),
    },
    null,
    2,
  ),
);
