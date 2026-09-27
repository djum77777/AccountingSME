import "server-only";

import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

export type OrganizationSummary = {
  id: string;
  displayName: string;
  baseCurrencyCode: string;
  defaultLocale: string;
};

export type MembershipSummary = {
  id: string;
  email: string;
  role: string;
  status: string;
  userId: string | null;
};

export async function listOrganizations(): Promise<OrganizationSummary[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("organizations")
    .select("id, display_name, base_currency_code, default_locale")
    .order("created_at");
  if (error) throw new Error("organizations_unavailable");

  return (data ?? []).map((organization) => ({
    id: String(organization.id),
    displayName: String(organization.display_name),
    baseCurrencyCode: String(organization.base_currency_code),
    defaultLocale: String(organization.default_locale),
  }));
}

export async function getOrganizationMembers(rawOrganizationId: string) {
  const organizationId = z.uuid().parse(rawOrganizationId);
  const supabase = await createClient();
  const [organizationResult, membersResult, entitlementResult] =
    await Promise.all([
      supabase
        .from("organizations")
        .select("display_name, base_currency_code")
        .eq("id", organizationId)
        .single(),
      supabase
        .from("organization_memberships")
        .select("id, invite_email, role, status, user_id")
        .eq("organization_id", organizationId)
        .order("created_at"),
      supabase
        .from("organization_entitlements")
        .select("active_seat_limit")
        .eq("organization_id", organizationId)
        .single(),
    ]);

  if (
    organizationResult.error ||
    membersResult.error ||
    entitlementResult.error
  ) {
    throw new Error("organization_members_unavailable");
  }

  const memberships: MembershipSummary[] = (membersResult.data ?? []).map(
    (membership) => ({
      id: String(membership.id),
      email: String(membership.invite_email),
      role: String(membership.role),
      status: String(membership.status),
      userId: membership.user_id ? String(membership.user_id) : null,
    }),
  );

  return {
    organization: {
      displayName: String(organizationResult.data.display_name),
      baseCurrencyCode: String(organizationResult.data.base_currency_code),
    },
    activeSeatLimit: Number(entitlementResult.data.active_seat_limit),
    memberships,
  };
}
