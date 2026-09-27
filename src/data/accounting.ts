import "server-only";

import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

export async function getAccountingData(rawOrganizationId: string) {
  const organizationId = z.uuid().parse(rawOrganizationId);
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) throw new Error("authentication_required");

  const [
    organization,
    configuration,
    profile,
    accounts,
    periods,
    journals,
    ledger,
    membership,
  ] = await Promise.all([
    supabase
      .from("organizations")
      .select("display_name,base_currency_code")
      .eq("id", organizationId)
      .single(),
    supabase
      .from("organization_configurations")
      .select("template_key")
      .eq("organization_id", organizationId)
      .maybeSingle(),
    supabase
      .from("accounting_profiles")
      .select("template_key,amount_scale,initialized_at")
      .eq("organization_id", organizationId)
      .maybeSingle(),
    supabase
      .from("accounts")
      .select("id,code,name,category,normal_balance,status,is_control_account")
      .eq("organization_id", organizationId)
      .order("code"),
    supabase
      .from("accounting_periods")
      .select("id,name,starts_on,ends_on,status,close_reason,reopen_reason")
      .eq("organization_id", organizationId)
      .order("starts_on"),
    supabase
      .from("journal_entries")
      .select(
        "id,entry_number,accounting_date,description,kind,status,total_debit,total_credit,reversal_entry_id",
      )
      .eq("organization_id", organizationId)
      .order("entry_number", { ascending: false })
      .limit(25),
    supabase
      .from("general_ledger")
      .select(
        "journal_entry_id,entry_number,accounting_date,account_code,account_name,debit,credit,line_number",
      )
      .eq("organization_id", organizationId)
      .order("entry_number", { ascending: false })
      .limit(100),
    supabase
      .from("organization_memberships")
      .select("role")
      .eq("organization_id", organizationId)
      .eq("user_id", userId)
      .eq("status", "active")
      .single(),
  ]);

  if (
    organization.error ||
    configuration.error ||
    profile.error ||
    accounts.error ||
    periods.error ||
    journals.error ||
    ledger.error ||
    membership.error
  )
    throw new Error("accounting_data_unavailable");

  let trialBalance: unknown[] = [];
  if (profile.data) {
    const result = await supabase.rpc("get_trial_balance", {
      target_organization_id: organizationId,
      target_through_date: null,
    });
    if (result.error) throw new Error("trial_balance_unavailable");
    trialBalance = result.data ?? [];
  }

  return {
    organization: organization.data,
    suggestedTemplate: configuration.data?.template_key ?? "general_sme",
    profile: profile.data,
    accounts: accounts.data ?? [],
    periods: periods.data ?? [],
    journals: journals.data ?? [],
    ledger: ledger.data ?? [],
    trialBalance: trialBalance as Array<Record<string, unknown>>,
    role: String(membership.data.role),
    canPost: ["owner", "admin_accountant"].includes(
      String(membership.data.role),
    ),
    isOwner: membership.data.role === "owner",
  };
}
