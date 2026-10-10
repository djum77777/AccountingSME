import "server-only";

import { z } from "zod";
import { partyRoleKinds } from "@/lib/domain/parties";
import { createClient } from "@/lib/supabase/server";

async function context(rawOrganizationId: string) {
  const organizationId = z.uuid().parse(rawOrganizationId);
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) throw new Error("authentication_required");
  return { organizationId, supabase, userId };
}

export async function getPartyDirectory(
  rawOrganizationId: string,
  options: { query?: string; role?: string; includeArchived?: boolean } = {},
) {
  const { organizationId, supabase, userId } = await context(rawOrganizationId);
  const role = options.role ? z.enum(partyRoleKinds).parse(options.role) : null;
  const [organization, membership, parties, aliases] = await Promise.all([
    supabase
      .from("organizations")
      .select("display_name")
      .eq("id", organizationId)
      .single(),
    supabase
      .from("organization_memberships")
      .select("role")
      .eq("organization_id", organizationId)
      .eq("user_id", userId)
      .eq("status", "active")
      .single(),
    supabase.rpc("search_parties", {
      target_organization_id: organizationId,
      target_query: options.query?.trim() || null,
      target_role: role,
      target_include_archived: options.includeArchived ?? false,
    }),
    supabase
      .from("display_label_aliases")
      .select("entity_key,locale,singular_label,plural_label")
      .eq("organization_id", organizationId)
      .in("entity_key", ["customer", "supplier"])
      .eq("is_active", true),
  ]);
  if (organization.error || membership.error || parties.error || aliases.error)
    throw new Error("party_directory_unavailable");
  const membershipRole = String(membership.data!.role);
  return {
    organization: organization.data!,
    parties: (parties.data ?? []) as Array<{
      id: string;
      legal_name: string;
      display_name: string;
      status: "active" | "archived";
      tax_identifier: string | null;
      roles: string[];
      primary_email: string | null;
      primary_phone: string | null;
      updated_at: string;
    }>,
    aliases: aliases.data ?? [],
    canManage:
      membershipRole === "owner" || membershipRole === "admin_accountant",
  };
}

export async function getPartyDetail(
  rawOrganizationId: string,
  rawPartyId: string,
) {
  const { organizationId, supabase, userId } = await context(rawOrganizationId);
  const partyId = z.uuid().parse(rawPartyId);
  const [
    organization,
    membership,
    party,
    roles,
    contacts,
    addresses,
    fieldDefinitions,
    fieldValues,
  ] = await Promise.all([
    supabase
      .from("organizations")
      .select("display_name")
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
      .from("parties")
      .select(
        "id,legal_name,display_name,tax_identifier,tax_registration_name,tax_registration_address,tax_status,notes,status,archived_at,created_at,updated_at",
      )
      .eq("organization_id", organizationId)
      .eq("id", partyId)
      .single(),
    supabase
      .from("party_roles")
      .select(
        "role_kind,payment_term_days,external_reference,status,created_at,updated_at",
      )
      .eq("organization_id", organizationId)
      .eq("party_id", partyId),
    supabase
      .from("party_contacts")
      .select(
        "id,contact_name,job_title,email,phone,is_primary,status,created_at",
      )
      .eq("organization_id", organizationId)
      .eq("party_id", partyId)
      .order("is_primary", { ascending: false }),
    supabase
      .from("party_addresses")
      .select(
        "id,address_kind,label,address_line_1,address_line_2,city,province,postal_code,country_code,is_primary,status,created_at",
      )
      .eq("organization_id", organizationId)
      .eq("party_id", partyId)
      .order("is_primary", { ascending: false }),
    supabase
      .from("custom_field_definitions")
      .select(
        "id,field_key,value_type,label_i18n,help_text_i18n,options,is_required,version",
      )
      .eq("organization_id", organizationId)
      .eq("entity_type", "contact")
      .eq("status", "active")
      .order("created_at"),
    supabase
      .from("custom_field_values")
      .select("id,definition_id,definition_version,value,updated_at")
      .eq("organization_id", organizationId)
      .eq("entity_type", "contact")
      .eq("entity_id", partyId),
  ]);
  const results = [
    organization,
    membership,
    party,
    roles,
    contacts,
    addresses,
    fieldDefinitions,
    fieldValues,
  ];
  if (results.some((result) => result.error))
    throw new Error("party_detail_unavailable");
  const membershipRole = String(membership.data!.role);
  return {
    organization: organization.data!,
    party: party.data!,
    roles: roles.data ?? [],
    contacts: contacts.data ?? [],
    addresses: addresses.data ?? [],
    fieldDefinitions: fieldDefinitions.data ?? [],
    fieldValues: fieldValues.data ?? [],
    canManage:
      membershipRole === "owner" || membershipRole === "admin_accountant",
  };
}
