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
const email = `phase4-concurrency-${suffix}@example.test`;
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
  organization_name: `Inventory concurrency ${suffix}`,
  currency_code: "IDR",
});
await call("initialize_accounting", {
  target_organization_id: organizationId,
  selected_template_key: "retail",
  first_period_start: "2026-01-01",
  first_period_end: "2026-12-31",
});
await call("initialize_inventory", { target_organization_id: organizationId });

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
    .in("system_purpose", ["inventory", "owner_capital"]),
]);
if (units.error || locations.error || accounts.error)
  throw new Error("Inventory concurrency fixture unavailable");
const inventoryAccount = accounts.data.find(
  (account) => account.system_purpose === "inventory",
)?.id;
const capitalAccount = accounts.data.find(
  (account) => account.system_purpose === "owner_capital",
)?.id;
if (!inventoryAccount || !capitalAccount)
  throw new Error("Inventory fixture accounts unavailable");
const productId = await call("create_catalog_item", {
  target_organization_id: organizationId,
  target_item_kind: "product",
  target_name: "Concurrent product",
  target_sku: `RACE-${suffix}`,
  target_barcode: null,
  target_category_id: null,
  target_unit_id: units.data.id,
  target_inventory_tracked: true,
  target_inventory_account_id: inventoryAccount,
  target_low_stock_threshold: "0",
});

const base = {
  target_organization_id: organizationId,
  target_product_id: productId,
  target_location_id: locations.data.id,
  target_movement_date: "2026-03-01",
  target_movement_kind: "stock_in",
  target_quantity: "10",
  target_offset_account_id: capitalAccount,
  target_reason: "Concurrent receipt",
  target_source_reference: "race-test",
};
const [first, second] = await Promise.all([
  owner.rpc("post_inventory_movement", {
    ...base,
    target_unit_cost: "10000",
    target_idempotency_key: `inventory-race-a-${suffix}`,
  }),
  owner.rpc("post_inventory_movement", {
    ...base,
    target_unit_cost: "14000",
    target_idempotency_key: `inventory-race-b-${suffix}`,
  }),
]);
if (first.error) throw first.error;
if (second.error) throw second.error;

const state = await owner
  .from("inventory_cost_states")
  .select("quantity_on_hand,inventory_value,average_unit_cost,version")
  .eq("organization_id", organizationId)
  .eq("product_id", productId)
  .eq("location_id", locations.data.id)
  .single();
if (state.error) throw state.error;
if (
  state.data.quantity_on_hand !== 20 ||
  state.data.inventory_value !== 240000 ||
  state.data.average_unit_cost !== 12000 ||
  state.data.version !== 2
)
  throw new Error(
    `Unexpected concurrent inventory state: ${JSON.stringify(state.data)}`,
  );

const movements = await owner
  .from("inventory_movements")
  .select("id", { count: "exact", head: true })
  .eq("organization_id", organizationId)
  .eq("product_id", productId);
const journals = await owner
  .from("journal_entries")
  .select("id", { count: "exact", head: true })
  .eq("organization_id", organizationId)
  .eq("kind", "system");
if (movements.error || movements.count !== 2)
  throw new Error(`Expected two movements, received ${movements.count}`);
if (journals.error || journals.count !== 2)
  throw new Error(`Expected two journals, received ${journals.count}`);
console.log(
  "PASS: simultaneous receipts serialized to quantity 20, value 240000, and average cost 12000",
);
