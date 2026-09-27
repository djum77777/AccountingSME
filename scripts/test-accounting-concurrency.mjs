import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";

function parseEnvironment(text) {
  return Object.fromEntries(
    text
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("#") && line.includes("="))
      .map((line) => {
        const separator = line.indexOf("=");
        return [
          line.slice(0, separator),
          line.slice(separator + 1).replace(/^"|"$/g, ""),
        ];
      }),
  );
}

function localConfiguration() {
  let file = {};
  try {
    file = parseEnvironment(readFileSync(".env.local", "utf8"));
  } catch {
    // CI can obtain disposable local credentials from the Supabase CLI below.
  }
  const configured = { ...file, ...process.env };
  if (!configured.SUPABASE_SERVICE_ROLE_KEY) {
    const output =
      process.platform === "win32"
        ? execFileSync(
            process.env.ComSpec ?? "cmd.exe",
            ["/d", "/s", "/c", "npx supabase status -o env"],
            { encoding: "utf8" },
          )
        : execFileSync("npx", ["supabase", "status", "-o", "env"], {
            encoding: "utf8",
          });
    const cli = parseEnvironment(output);
    return {
      ...configured,
      NEXT_PUBLIC_SUPABASE_URL: cli.API_URL,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: cli.ANON_KEY,
      SUPABASE_SERVICE_ROLE_KEY: cli.SERVICE_ROLE_KEY,
    };
  }
  return configured;
}

const configuration = localConfiguration();
const url = configuration.NEXT_PUBLIC_SUPABASE_URL ?? configuration.API_URL;
const publishableKey =
  configuration.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? configuration.ANON_KEY;
const serviceKey = configuration.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !publishableKey || !serviceKey)
  throw new Error("Local Supabase credentials are required");

const suffix = crypto.randomUUID();
const email = `phase3-concurrency-${suffix}@example.test`;
const password = `Test-${suffix}-Aa1!`;
const admin = createClient(url, serviceKey, {
  auth: { persistSession: false },
});
const created = await admin.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
});
if (created.error) throw created.error;

const owner = createClient(url, publishableKey, {
  auth: { persistSession: false },
});
const signedIn = await owner.auth.signInWithPassword({ email, password });
if (signedIn.error) throw signedIn.error;

const organization = await owner.rpc("create_organization", {
  organization_name: `Concurrency ${suffix}`,
  currency_code: "IDR",
});
if (organization.error) throw organization.error;
const organizationId = organization.data;

const initialized = await owner.rpc("initialize_accounting", {
  target_organization_id: organizationId,
  selected_template_key: "general_sme",
  first_period_start: "2026-01-01",
  first_period_end: "2026-12-31",
});
if (initialized.error) throw initialized.error;

const accounts = await owner
  .from("accounts")
  .select("id,system_purpose")
  .eq("organization_id", organizationId)
  .in("system_purpose", ["cash", "owner_capital"]);
if (accounts.error) throw accounts.error;
const cash = accounts.data.find(
  (account) => account.system_purpose === "cash",
)?.id;
const capital = accounts.data.find(
  (account) => account.system_purpose === "owner_capital",
)?.id;
if (!cash || !capital)
  throw new Error("Concurrency fixture accounts unavailable");

const request = {
  target_organization_id: organizationId,
  target_accounting_date: "2026-03-01",
  target_description: "Concurrent journal",
  target_source_reference: "race-test",
  target_lines: [
    { account_id: cash, debit: "125.0000", credit: "0" },
    { account_id: capital, debit: "0", credit: "125.0000" },
  ],
  target_idempotency_key: `concurrent-${suffix}`,
};
const [first, second] = await Promise.all([
  owner.rpc("post_journal", request),
  owner.rpc("post_journal", request),
]);
if (first.error) throw first.error;
if (second.error) throw second.error;
if (first.data !== second.data)
  throw new Error("Concurrent calls returned different journal IDs");

const journalCount = await owner
  .from("journal_entries")
  .select("id", { count: "exact", head: true })
  .eq("organization_id", organizationId)
  .eq("idempotency_key", request.target_idempotency_key);
if (journalCount.error) throw journalCount.error;
if (journalCount.count !== 1)
  throw new Error(`Expected one journal, received ${journalCount.count}`);

const lineCount = await owner
  .from("journal_lines")
  .select("id", { count: "exact", head: true })
  .eq("journal_entry_id", first.data);
if (lineCount.error) throw lineCount.error;
if (lineCount.count !== 2)
  throw new Error(`Expected two complete lines, received ${lineCount.count}`);

console.log(
  "PASS: two simultaneous posting requests returned one complete balanced journal",
);
