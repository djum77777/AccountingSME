import "server-only";

import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

export async function getInventoryData(rawOrganizationId: string) {
  const organizationId = z.uuid().parse(rawOrganizationId);
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) throw new Error("authentication_required");

  const results = await Promise.all([
    supabase
      .from("organizations")
      .select("display_name,base_currency_code")
      .eq("id", organizationId)
      .single(),
    supabase
      .from("organization_memberships")
      .select("role")
      .eq("organization_id", organizationId)
      .eq("user_id", userId)
      .eq("status", "active")
      .single(),
    supabase
      .from("accounting_profiles")
      .select("initialized_at")
      .eq("organization_id", organizationId)
      .maybeSingle(),
    supabase
      .from("product_categories")
      .select("id,code,name,status")
      .eq("organization_id", organizationId)
      .order("code"),
    supabase
      .from("organization_units")
      .select("id,code,name,symbol,quantity_scale,status")
      .eq("organization_id", organizationId)
      .order("code"),
    supabase
      .from("inventory_locations")
      .select("id,code,name,is_default,status")
      .eq("organization_id", organizationId)
      .order("code"),
    supabase
      .from("products")
      .select(
        "id,item_kind,name,sku,barcode,category_id,unit_id,inventory_tracked,inventory_account_id,low_stock_threshold,status",
      )
      .eq("organization_id", organizationId)
      .order("sku"),
    supabase
      .from("accounts")
      .select("id,code,name,category,status")
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .order("code"),
    supabase
      .from("inventory_valuation")
      .select(
        "product_id,sku,product_name,location_id,location_code,location_name,quantity_on_hand,average_unit_cost,inventory_value,last_movement_date",
      )
      .eq("organization_id", organizationId)
      .order("sku"),
    supabase
      .from("inventory_low_stock")
      .select(
        "product_id,sku,product_name,location_id,location_code,location_name,quantity_on_hand,low_stock_threshold",
      )
      .eq("organization_id", organizationId)
      .order("sku"),
    supabase
      .from("inventory_movements")
      .select(
        "id,operation_id,product_id,location_id,movement_kind,movement_date,quantity_delta,applied_unit_cost,value_delta,quantity_after,value_after,average_cost_after,reason",
      )
      .eq("organization_id", organizationId)
      .order("created_at", { ascending: false })
      .limit(100),
  ]);

  if (results.some((result) => result.error))
    throw new Error("inventory_data_unavailable");

  const [
    organization,
    membership,
    accountingProfile,
    categories,
    units,
    locations,
    products,
    accounts,
    valuation,
    lowStock,
    movements,
  ] = results;
  const role = String(membership.data?.role);

  return {
    organization: organization.data!,
    role,
    canManage: role === "owner" || role === "admin_accountant",
    accountingReady: Boolean(accountingProfile.data),
    initialized:
      (units.data?.length ?? 0) > 0 && (locations.data?.length ?? 0) > 0,
    categories: categories.data ?? [],
    units: units.data ?? [],
    locations: locations.data ?? [],
    products: products.data ?? [],
    accounts: accounts.data ?? [],
    valuation: valuation.data ?? [],
    lowStock: lowStock.data ?? [],
    movements: movements.data ?? [],
  };
}
