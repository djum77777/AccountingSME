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
    /* CLI fallback below. */
  }
  const configured = { ...file, ...process.env };
  if (configured.SUPABASE_SERVICE_ROLE_KEY) return configured;
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

const configuration = localConfiguration();
const url = configuration.NEXT_PUBLIC_SUPABASE_URL ?? configuration.API_URL;
const publishableKey =
  configuration.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? configuration.ANON_KEY;
const serviceKey = configuration.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !publishableKey || !serviceKey)
  throw new Error("Local Supabase credentials are required");

const suffix = crypto.randomUUID();
const email = `phase6-concurrency-${suffix}@example.test`;
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

async function call(name, args) {
  const result = await owner.rpc(name, args);
  if (result.error) throw result.error;
  return result.data;
}

const organizationId = await call("create_organization", {
  organization_name: `Purchase concurrency ${suffix}`,
  currency_code: "IDR",
});
await call("initialize_accounting", {
  target_organization_id: organizationId,
  selected_template_key: "retail",
  first_period_start: "2026-01-01",
  first_period_end: "2026-12-31",
});
await call("initialize_inventory", { target_organization_id: organizationId });
const supplierId = await call("create_party", {
  target_organization_id: organizationId,
  target_legal_name: "Concurrent Supplier",
  target_display_name: "Concurrent Supplier",
  target_is_customer: false,
  target_is_supplier: true,
  target_customer_terms: 0,
  target_supplier_terms: 30,
  target_customer_reference: null,
  target_supplier_reference: `SUP-${suffix}`,
  target_tax_identifier: null,
  target_tax_registration_name: null,
  target_tax_registration_address: null,
  target_tax_status: "not_set",
  target_notes: null,
});

const [units, locations, accounts] = await Promise.all([
  owner
    .from("organization_units")
    .select("id")
    .eq("organization_id", organizationId)
    .eq("code", "PCS")
    .single(),
  owner
    .from("inventory_locations")
    .select("id")
    .eq("organization_id", organizationId)
    .eq("code", "MAIN")
    .single(),
  owner
    .from("accounts")
    .select("id,system_purpose")
    .eq("organization_id", organizationId)
    .in("system_purpose", ["inventory", "cash", "accounts_payable"]),
]);
if (units.error || locations.error || accounts.error)
  throw new Error("Purchase concurrency fixture unavailable");
const account = (purpose) =>
  accounts.data.find((row) => row.system_purpose === purpose)?.id;
const inventoryAccount = account("inventory");
const cashAccount = account("cash");
if (!inventoryAccount || !cashAccount)
  throw new Error("Purchase concurrency accounts unavailable");

const productId = await call("create_catalog_item", {
  target_organization_id: organizationId,
  target_item_kind: "product",
  target_name: "Concurrent purchase product",
  target_sku: `PUR-${suffix}`,
  target_barcode: null,
  target_category_id: null,
  target_unit_id: units.data.id,
  target_inventory_tracked: true,
  target_inventory_account_id: inventoryAccount,
  target_low_stock_threshold: "0",
});
const purchaseId = await call("create_purchase_draft", {
  target_organization_id: organizationId,
  target_supplier_party_id: supplierId,
  target_supplier_invoice_number: `INV-${suffix}`,
  target_invoice_date: "2026-05-01",
  target_due_date: "2026-05-31",
  target_payment_mode: "credit",
  target_inventory_location_id: locations.data.id,
  target_cash_account_id: null,
  target_document_discount_amount: "0",
  target_additional_cost_amount: "0",
  target_notes: "Concurrency fixture",
});
await call("add_purchase_line", {
  target_organization_id: organizationId,
  target_purchase_id: purchaseId,
  target_catalog_item_id: productId,
  target_quantity: "10",
  target_unit_price: "50000",
  target_line_discount_amount: "0",
  target_line_additional_cost_amount: "0",
  target_expense_account_id: null,
  target_description: "Concurrent stock",
});

const confirmationKey = `purchase-confirm-race-${suffix}`;
const confirmations = await Promise.all([
  owner.rpc("confirm_purchase", {
    target_organization_id: organizationId,
    target_purchase_id: purchaseId,
    target_idempotency_key: confirmationKey,
  }),
  owner.rpc("confirm_purchase", {
    target_organization_id: organizationId,
    target_purchase_id: purchaseId,
    target_idempotency_key: confirmationKey,
  }),
]);
if (confirmations.some((result) => result.error))
  throw confirmations.find((result) => result.error).error;

const movements = await owner
  .from("inventory_operations")
  .select("id", { count: "exact", head: true })
  .eq("organization_id", organizationId)
  .eq("source_type", "purchase");
if (movements.error || movements.count !== 1)
  throw new Error(
    `Expected one purchase movement, received ${movements.count}`,
  );

const allocation = [{ purchase_id: purchaseId, amount: "500000" }];
const payments = await Promise.all([
  owner.rpc("post_supplier_payment", {
    target_organization_id: organizationId,
    target_supplier_party_id: supplierId,
    target_payment_date: "2026-05-10",
    target_cash_account_id: cashAccount,
    target_source_reference: "race-a",
    target_allocations: allocation,
    target_idempotency_key: `payment-race-a-${suffix}`,
  }),
  owner.rpc("post_supplier_payment", {
    target_organization_id: organizationId,
    target_supplier_party_id: supplierId,
    target_payment_date: "2026-05-10",
    target_cash_account_id: cashAccount,
    target_source_reference: "race-b",
    target_allocations: allocation,
    target_idempotency_key: `payment-race-b-${suffix}`,
  }),
]);
const successes = payments.filter((result) => !result.error);
const failures = payments.filter((result) => result.error);
if (successes.length !== 1 || failures.length !== 1)
  throw new Error(
    "Concurrent full payments must produce one success and one rejection",
  );

const openItem = await owner
  .from("purchase_open_items")
  .select("outstanding_amount,status")
  .eq("organization_id", organizationId)
  .eq("purchase_id", purchaseId)
  .single();
if (openItem.error) throw openItem.error;
if (openItem.data.outstanding_amount !== 0 || openItem.data.status !== "paid")
  throw new Error(
    `Unexpected settlement state: ${JSON.stringify(openItem.data)}`,
  );

console.log(
  "PASS: duplicate confirmation produced one movement, and concurrent full payments allowed exactly one settlement",
);
