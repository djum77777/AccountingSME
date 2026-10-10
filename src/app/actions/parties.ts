"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import {
  parsePartyCustomValue,
  partyAddressKinds,
  partyStatuses,
  partyTaxStatuses,
  type PartyCustomValueType,
} from "@/lib/domain/parties";
import { createClient } from "@/lib/supabase/server";

const id = z.uuid();
const text = (formData: FormData, key: string) =>
  String(formData.get(key) ?? "").trim();
const optional = (value: string) => value || null;
const checked = (formData: FormData, key: string) =>
  text(formData, key) === "on";
const boundedText = (value: string, maximum: number) =>
  z.string().max(maximum).parse(value);

async function rpc<T>(name: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message);
  return data as T;
}

function organizationId(formData: FormData) {
  return id.parse(text(formData, "organizationId"));
}

function partyPath(targetOrganizationId: string, partyId?: string) {
  return partyId
    ? `/app/organizations/${targetOrganizationId}/parties/${partyId}`
    : `/app/organizations/${targetOrganizationId}/parties`;
}

function partyPayload(formData: FormData) {
  const isCustomer = checked(formData, "isCustomer");
  const isSupplier = checked(formData, "isSupplier");
  if (!isCustomer && !isSupplier) throw new Error("party_role_required");
  return {
    target_legal_name: z
      .string()
      .min(1)
      .max(160)
      .parse(text(formData, "legalName")),
    target_display_name: z
      .string()
      .min(1)
      .max(160)
      .parse(text(formData, "displayName")),
    target_is_customer: isCustomer,
    target_is_supplier: isSupplier,
    target_customer_terms: z.coerce
      .number()
      .int()
      .min(0)
      .max(3650)
      .parse(text(formData, "customerPaymentTermDays") || "0"),
    target_supplier_terms: z.coerce
      .number()
      .int()
      .min(0)
      .max(3650)
      .parse(text(formData, "supplierPaymentTermDays") || "0"),
    target_customer_reference: optional(
      boundedText(text(formData, "customerExternalReference"), 100),
    ),
    target_supplier_reference: optional(
      boundedText(text(formData, "supplierExternalReference"), 100),
    ),
    target_tax_identifier: optional(
      boundedText(text(formData, "taxIdentifier"), 80),
    ),
    target_tax_registration_name: optional(
      boundedText(text(formData, "taxRegistrationName"), 160),
    ),
    target_tax_registration_address: optional(
      boundedText(text(formData, "taxRegistrationAddress"), 1000),
    ),
    target_tax_status: z
      .enum(partyTaxStatuses)
      .parse(text(formData, "taxStatus") || "not_set"),
    target_notes: optional(boundedText(text(formData, "notes"), 4000)),
  };
}

export type DuplicateCheckState = {
  matches: Array<{
    partyId: string;
    displayName: string;
    status: string;
    reasons: string[];
    matchScore: number;
  }>;
  checked: boolean;
};

export async function checkPartyDuplicates(
  _priorState: DuplicateCheckState,
  formData: FormData,
): Promise<DuplicateCheckState> {
  const targetOrganizationId = organizationId(formData);
  const rows = await rpc<
    Array<{
      party_id: string;
      display_name: string;
      status: string;
      reasons: string[];
      match_score: number;
    }>
  >("search_party_duplicates", {
    target_organization_id: targetOrganizationId,
    target_name: boundedText(text(formData, "displayName"), 160),
    target_email: boundedText(text(formData, "email"), 254),
    target_phone: boundedText(text(formData, "phone"), 60),
    target_tax_identifier: boundedText(text(formData, "taxIdentifier"), 80),
    target_exclude_party_id: null,
  });
  return {
    checked: true,
    matches: (rows ?? []).map((row) => ({
      partyId: row.party_id,
      displayName: row.display_name,
      status: row.status,
      reasons: row.reasons,
      matchScore: row.match_score,
    })),
  };
}

export async function createParty(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const partyId = await rpc<string>("create_party", {
    target_organization_id: targetOrganizationId,
    ...partyPayload(formData),
  });
  const email = text(formData, "email");
  const phone = text(formData, "phone");
  if (email || phone) {
    await rpc("add_party_contact", {
      target_organization_id: targetOrganizationId,
      target_party_id: partyId,
      target_contact_name: text(formData, "displayName"),
      target_job_title: null,
      target_email: email ? z.string().email().max(254).parse(email) : null,
      target_phone: optional(boundedText(phone, 60)),
      target_is_primary: true,
    });
  }
  revalidatePath(partyPath(targetOrganizationId));
  redirect(partyPath(targetOrganizationId, partyId));
}

export async function updateParty(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const targetPartyId = id.parse(text(formData, "partyId"));
  await rpc("update_party", {
    target_organization_id: targetOrganizationId,
    target_party_id: targetPartyId,
    ...partyPayload(formData),
  });
  revalidatePath(partyPath(targetOrganizationId));
  revalidatePath(partyPath(targetOrganizationId, targetPartyId));
}

export async function setPartyStatus(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const targetPartyId = id.parse(text(formData, "partyId"));
  await rpc("set_party_status", {
    target_organization_id: targetOrganizationId,
    target_party_id: targetPartyId,
    target_status: z.enum(partyStatuses).parse(text(formData, "status")),
  });
  revalidatePath(partyPath(targetOrganizationId));
  revalidatePath(partyPath(targetOrganizationId, targetPartyId));
}

export async function addPartyContact(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const targetPartyId = id.parse(text(formData, "partyId"));
  const email = text(formData, "email");
  const phone = text(formData, "phone");
  if (!email && !phone) throw new Error("party_contact_method_required");
  await rpc("add_party_contact", {
    target_organization_id: targetOrganizationId,
    target_party_id: targetPartyId,
    target_contact_name: z
      .string()
      .min(1)
      .max(160)
      .parse(text(formData, "contactName")),
    target_job_title: optional(boundedText(text(formData, "jobTitle"), 120)),
    target_email: email ? z.string().email().max(254).parse(email) : null,
    target_phone: optional(boundedText(phone, 60)),
    target_is_primary: checked(formData, "isPrimary"),
  });
  revalidatePath(partyPath(targetOrganizationId, targetPartyId));
}

export async function addPartyAddress(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const targetPartyId = id.parse(text(formData, "partyId"));
  await rpc("add_party_address", {
    target_organization_id: targetOrganizationId,
    target_party_id: targetPartyId,
    target_address_kind: z
      .enum(partyAddressKinds)
      .parse(text(formData, "addressKind")),
    target_label: z.string().min(1).max(80).parse(text(formData, "label")),
    target_address_line_1: z
      .string()
      .min(1)
      .max(240)
      .parse(text(formData, "addressLine1")),
    target_address_line_2: optional(
      boundedText(text(formData, "addressLine2"), 240),
    ),
    target_city: optional(boundedText(text(formData, "city"), 120)),
    target_province: optional(boundedText(text(formData, "province"), 120)),
    target_postal_code: optional(boundedText(text(formData, "postalCode"), 24)),
    target_country_code: z
      .string()
      .regex(/^[A-Za-z]{2}$/)
      .transform((value) => value.toUpperCase())
      .parse(text(formData, "countryCode") || "ID"),
    target_is_primary: checked(formData, "isPrimary"),
  });
  revalidatePath(partyPath(targetOrganizationId, targetPartyId));
}

export async function setPartyCustomField(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const targetPartyId = id.parse(text(formData, "partyId"));
  const valueType = text(formData, "valueType") as PartyCustomValueType;
  await rpc("set_party_custom_field_value", {
    target_organization_id: targetOrganizationId,
    target_party_id: targetPartyId,
    target_definition_id: id.parse(text(formData, "definitionId")),
    target_value: parsePartyCustomValue(valueType, text(formData, "value")),
  });
  revalidatePath(partyPath(targetOrganizationId, targetPartyId));
}
