"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import {
  customFieldEntityTypes,
  customizableEntityKeys,
  customValueTypes,
  moduleKeys,
  normalizeConfigurationKey,
  templateKeys,
} from "@/lib/domain/customization";
import { locales } from "@/lib/i18n/dictionaries";
import { createClient } from "@/lib/supabase/server";

const organizationIdSchema = z.uuid();

function text(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}

async function rpc(name: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message);
}

export async function completeOnboarding(formData: FormData) {
  const input = z
    .object({
      organizationId: organizationIdSchema,
      locale: z.enum(locales),
      businessType: z.string().regex(/^[a-z][a-z0-9_]*$/),
      businessName: z.string().min(1).max(120),
      businessAddress: z.string().max(500),
      phone: z.string().max(40),
      taxIdentifier: z.string().max(60),
      templateKey: z.enum(templateKeys),
      currency: z
        .string()
        .toUpperCase()
        .regex(/^[A-Z]{3}$/),
      timezone: z.string().min(1).max(80),
      dateFormat: z.enum(["DD/MM/YYYY", "MM/DD/YYYY", "YYYY-MM-DD"]),
    })
    .parse({
      organizationId: text(formData, "organizationId"),
      locale: text(formData, "locale"),
      businessType: text(formData, "businessType"),
      businessName: text(formData, "businessName"),
      businessAddress: text(formData, "businessAddress"),
      phone: text(formData, "phone"),
      taxIdentifier: text(formData, "taxIdentifier"),
      templateKey: text(formData, "templateKey"),
      currency: text(formData, "currency"),
      timezone: text(formData, "timezone"),
      dateFormat: text(formData, "dateFormat"),
    });

  await rpc("complete_organization_onboarding", {
    target_organization_id: input.organizationId,
    selected_locale: input.locale,
    selected_business_type: input.businessType,
    selected_business_name: input.businessName,
    selected_business_address: input.businessAddress,
    selected_phone: input.phone,
    selected_tax_identifier: input.taxIdentifier,
    selected_template_key: input.templateKey,
    selected_currency_code: input.currency,
    selected_timezone: input.timezone,
    selected_date_format: input.dateFormat,
  });
  revalidatePath("/app");
  redirect(`/app/organizations/${input.organizationId}/settings/customization`);
}

export async function setModuleVisibility(formData: FormData) {
  const organizationId = organizationIdSchema.parse(
    text(formData, "organizationId"),
  );
  const moduleKey = z.enum(moduleKeys).parse(text(formData, "moduleKey"));
  await rpc("set_module_visibility", {
    target_organization_id: organizationId,
    target_module_key: moduleKey,
    visible: text(formData, "visible") === "true",
  });
  revalidatePath(`/app/organizations/${organizationId}/settings/customization`);
}

export async function setDisplayLabelAlias(formData: FormData) {
  const input = z
    .object({
      organizationId: organizationIdSchema,
      entityKey: z.enum(customizableEntityKeys),
      locale: z.enum(locales),
      singular: z.string().min(1).max(60),
      plural: z.string().min(1).max(60),
    })
    .parse({
      organizationId: text(formData, "organizationId"),
      entityKey: text(formData, "entityKey"),
      locale: text(formData, "locale"),
      singular: text(formData, "singular"),
      plural: text(formData, "plural"),
    });
  await rpc("set_display_label_alias", {
    target_organization_id: input.organizationId,
    target_entity_key: input.entityKey,
    target_locale: input.locale,
    singular: input.singular,
    plural: input.plural,
  });
  revalidatePath(
    `/app/organizations/${input.organizationId}/settings/customization`,
  );
}

export async function createCustomField(formData: FormData) {
  const organizationId = organizationIdSchema.parse(
    text(formData, "organizationId"),
  );
  await rpc("create_custom_field", {
    target_organization_id: organizationId,
    target_field_key: normalizeConfigurationKey(text(formData, "fieldKey")),
    target_entity_type: z
      .enum(customFieldEntityTypes)
      .parse(text(formData, "entityType")),
    target_value_type: z
      .enum(customValueTypes)
      .parse(text(formData, "valueType")),
    label_id: z.string().min(1).max(80).parse(text(formData, "labelId")),
    label_en: z.string().min(1).max(80).parse(text(formData, "labelEn")),
  });
  revalidatePath(`/app/organizations/${organizationId}/settings/customization`);
}

export async function archiveCustomField(formData: FormData) {
  const organizationId = organizationIdSchema.parse(
    text(formData, "organizationId"),
  );
  await rpc("set_custom_field_status", {
    target_definition_id: z.uuid().parse(text(formData, "definitionId")),
    target_status: "inactive",
  });
  revalidatePath(`/app/organizations/${organizationId}/settings/customization`);
}

export async function createCustomDimension(formData: FormData) {
  const organizationId = organizationIdSchema.parse(
    text(formData, "organizationId"),
  );
  await rpc("create_custom_dimension", {
    target_organization_id: organizationId,
    target_dimension_key: normalizeConfigurationKey(
      text(formData, "dimensionKey"),
    ),
    label_id: z.string().min(1).max(80).parse(text(formData, "labelId")),
    label_en: z.string().min(1).max(80).parse(text(formData, "labelEn")),
  });
  revalidatePath(`/app/organizations/${organizationId}/settings/customization`);
}

export async function addCustomDimensionValue(formData: FormData) {
  const organizationId = organizationIdSchema.parse(
    text(formData, "organizationId"),
  );
  await rpc("add_custom_dimension_value", {
    target_dimension_id: z.uuid().parse(text(formData, "dimensionId")),
    target_value_code: text(formData, "valueCode"),
    label_id: z.string().min(1).max(80).parse(text(formData, "labelId")),
    label_en: z.string().min(1).max(80).parse(text(formData, "labelEn")),
  });
  revalidatePath(`/app/organizations/${organizationId}/settings/customization`);
}

export async function createSavedView(formData: FormData) {
  const organizationId = organizationIdSchema.parse(
    text(formData, "organizationId"),
  );
  const columns = text(formData, "columns")
    .split(",")
    .map((item) => normalizeConfigurationKey(item))
    .filter(Boolean);
  await rpc("create_saved_view", {
    target_organization_id: organizationId,
    target_entity_type: z
      .enum(customFieldEntityTypes)
      .parse(text(formData, "entityType")),
    target_name: z.string().min(1).max(80).parse(text(formData, "name")),
    target_columns: columns,
    target_is_shared: formData.get("isShared") === "on",
  });
  revalidatePath(`/app/organizations/${organizationId}/settings/customization`);
}

export async function upsertFormFieldConfiguration(formData: FormData) {
  const organizationId = organizationIdSchema.parse(
    text(formData, "organizationId"),
  );
  const roles = ["owner", "admin_accountant", "staff"].filter(
    (role) => formData.get(`role_${role}`) === "on",
  );
  await rpc("upsert_form_field_configuration", {
    target_organization_id: organizationId,
    target_form_key: z
      .enum(["contact", "expense", "sale", "purchase", "product", "project"])
      .parse(text(formData, "formKey")),
    target_field_key: normalizeConfigurationKey(text(formData, "fieldKey")),
    target_section_key:
      normalizeConfigurationKey(text(formData, "sectionKey")) || "main",
    target_sort_order: z.coerce
      .number()
      .int()
      .min(0)
      .parse(text(formData, "sortOrder")),
    target_required: formData.get("required") === "on",
    target_visible: formData.get("visible") === "on",
    target_default_value: text(formData, "defaultValue") || null,
    target_role_visibility: roles.length ? roles : ["owner"],
  });
  revalidatePath(`/app/organizations/${organizationId}/settings/customization`);
}

export async function resetOrganizationConfiguration(formData: FormData) {
  const organizationId = organizationIdSchema.parse(
    text(formData, "organizationId"),
  );
  await rpc("reset_organization_configuration", {
    target_organization_id: organizationId,
  });
  revalidatePath(`/app/organizations/${organizationId}/settings/customization`);
}
