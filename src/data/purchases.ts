import "server-only";

import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

export async function getPurchasesData(rawOrganizationId: string) {
  const organizationId = z.uuid().parse(rawOrganizationId);
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) throw new Error("authentication_required");

  const supplierRoles = await supabase
    .from("party_roles")
    .select("party_id,payment_term_days")
    .eq("organization_id", organizationId)
    .eq("role_kind", "supplier")
    .eq("status", "active");
  if (supplierRoles.error) throw new Error("purchase_data_unavailable");
  const supplierIds = supplierRoles.data.map((role) => role.party_id);

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
    supplierIds.length
      ? supabase
          .from("parties")
          .select("id,display_name,tax_identifier,status")
          .eq("organization_id", organizationId)
          .eq("status", "active")
          .in("id", supplierIds)
          .order("display_name")
      : Promise.resolve({ data: [], error: null }),
    supabase
      .from("products")
      .select("id,item_kind,name,sku,inventory_tracked,status")
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .order("sku"),
    supabase
      .from("inventory_locations")
      .select("id,code,name,status")
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .order("code"),
    supabase
      .from("accounts")
      .select("id,code,name,category,system_purpose,status")
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .order("code"),
    supabase
      .from("purchase_documents")
      .select(
        "id,document_number,supplier_party_id,supplier_name_snapshot,supplier_invoice_number,invoice_date,due_date,payment_mode,subtotal_amount,total_amount,status,notes,posted_at",
      )
      .eq("organization_id", organizationId)
      .order("created_at", { ascending: false })
      .limit(100),
    supabase
      .from("purchase_lines")
      .select(
        "id,purchase_id,line_number,line_kind,catalog_item_id,description_snapshot,quantity,unit_price,base_amount,posted_amount,expense_account_id",
      )
      .eq("organization_id", organizationId)
      .order("line_number"),
    supabase
      .from("purchase_open_items")
      .select(
        "purchase_id,document_number,supplier_party_id,supplier_name_snapshot,invoice_date,due_date,total_amount,paid_amount,credited_amount,outstanding_amount,status",
      )
      .eq("organization_id", organizationId)
      .gt("outstanding_amount", 0)
      .order("due_date"),
    supabase.rpc("get_ap_aging", {
      target_organization_id: organizationId,
      target_as_of_date: new Date().toISOString().slice(0, 10),
    }),
    supabase
      .from("supplier_payments")
      .select(
        "id,payment_number,supplier_party_id,payment_date,amount,source_reference,journal_entry_id",
      )
      .eq("organization_id", organizationId)
      .order("posted_at", { ascending: false })
      .limit(50),
    supabase
      .from("supplier_payment_allocations")
      .select("id,payment_id,purchase_id,allocated_amount")
      .eq("organization_id", organizationId),
    supabase
      .from("purchase_credits")
      .select("id,credit_number,purchase_id,credit_date,reason,total_amount")
      .eq("organization_id", organizationId)
      .order("posted_at", { ascending: false })
      .limit(50),
    supabase
      .from("purchase_posting_links")
      .select(
        "purchase_id,purchase_line_id,inventory_operation_id,journal_entry_id",
      )
      .eq("organization_id", organizationId),
  ]);
  if (results.some((result) => result.error))
    throw new Error("purchase_data_unavailable");

  const [
    organization,
    membership,
    suppliers,
    products,
    locations,
    accounts,
    purchases,
    lines,
    openItems,
    aging,
    payments,
    allocations,
    credits,
    postingLinks,
  ] = results;
  const role = String(membership.data?.role);
  return {
    organization: organization.data!,
    canManage: role === "owner" || role === "admin_accountant",
    suppliers: suppliers.data ?? [],
    products: products.data ?? [],
    locations: locations.data ?? [],
    accounts: accounts.data ?? [],
    purchases: purchases.data ?? [],
    lines: lines.data ?? [],
    openItems: openItems.data ?? [],
    aging: (aging.data ?? []) as Array<{
      purchase_id: string;
      document_number: string;
      supplier_name: string;
      due_date: string;
      outstanding_amount: number | string;
      aging_bucket: string;
    }>,
    payments: payments.data ?? [],
    allocations: allocations.data ?? [],
    credits: credits.data ?? [],
    postingLinks: postingLinks.data ?? [],
  };
}
