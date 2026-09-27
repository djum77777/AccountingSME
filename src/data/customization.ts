import "server-only";

import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

export async function getOnboardingData(rawOrganizationId: string) {
  const organizationId = z.uuid().parse(rawOrganizationId);
  const supabase = await createClient();
  const [organizationResult, templatesResult, configurationResult] =
    await Promise.all([
      supabase
        .from("organizations")
        .select("id, display_name, base_currency_code, default_locale")
        .eq("id", organizationId)
        .single(),
      supabase
        .from("business_templates")
        .select(
          "template_key, name_i18n, description_i18n, recommended_business_types, version",
        )
        .eq("is_active", true)
        .order("template_key"),
      supabase
        .from("organization_configurations")
        .select(
          "template_key, business_type, business_name, business_address, phone, tax_identifier, locale, timezone, date_format",
        )
        .eq("organization_id", organizationId)
        .maybeSingle(),
    ]);

  if (
    organizationResult.error ||
    templatesResult.error ||
    configurationResult.error
  ) {
    throw new Error("onboarding_data_unavailable");
  }

  return {
    organizationId,
    organization: {
      name: String(organizationResult.data.display_name),
      currency: String(organizationResult.data.base_currency_code),
      locale: String(organizationResult.data.default_locale),
    },
    configuration: configurationResult.data,
    templates: (templatesResult.data ?? []).map((template) => ({
      key: String(template.template_key),
      version: Number(template.version),
      names: template.name_i18n as Record<string, string>,
      descriptions: template.description_i18n as Record<string, string>,
      recommendedBusinessTypes: (template.recommended_business_types ?? []).map(
        String,
      ),
    })),
  };
}

export async function getCustomizationData(rawOrganizationId: string) {
  const organizationId = z.uuid().parse(rawOrganizationId);
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) throw new Error("authentication_required");

  const [
    organization,
    configuration,
    modules,
    aliases,
    fields,
    dimensions,
    dimensionValues,
    forms,
    formFields,
    views,
    membership,
    canManage,
  ] = await Promise.all([
    supabase
      .from("organizations")
      .select("display_name, base_currency_code")
      .eq("id", organizationId)
      .single(),
    supabase
      .from("organization_configurations")
      .select(
        "template_key, template_version, business_type, locale, timezone, date_format",
      )
      .eq("organization_id", organizationId)
      .maybeSingle(),
    supabase
      .from("organization_modules")
      .select("module_key, is_visible, sort_order, source")
      .eq("organization_id", organizationId)
      .order("sort_order"),
    supabase
      .from("display_label_aliases")
      .select("id, entity_key, locale, singular_label, plural_label, source")
      .eq("organization_id", organizationId)
      .order("entity_key"),
    supabase
      .from("custom_field_definitions")
      .select(
        "id, field_key, entity_type, value_type, label_i18n, status, version",
      )
      .eq("organization_id", organizationId)
      .order("created_at"),
    supabase
      .from("custom_dimension_definitions")
      .select("id, dimension_key, label_i18n, status, version")
      .eq("organization_id", organizationId)
      .order("created_at"),
    supabase
      .from("custom_dimension_values")
      .select("id, dimension_id, value_code, label_i18n, status")
      .eq("organization_id", organizationId)
      .order("sort_order"),
    supabase
      .from("form_configurations")
      .select("id, form_key, version, source")
      .eq("organization_id", organizationId)
      .order("form_key"),
    supabase
      .from("form_configuration_fields")
      .select(
        "id, form_configuration_id, field_key, section_key, sort_order, is_required, is_visible, default_value, role_visibility",
      )
      .eq("organization_id", organizationId)
      .order("sort_order"),
    supabase
      .from("saved_views")
      .select("id, entity_type, name, columns_config, is_shared, status")
      .eq("organization_id", organizationId)
      .order("created_at"),
    supabase
      .from("organization_memberships")
      .select("role")
      .eq("organization_id", organizationId)
      .eq("user_id", userId)
      .eq("status", "active")
      .single(),
    supabase.rpc("can_manage_customization", {
      target_organization_id: organizationId,
    }),
  ]);

  const results = [
    organization,
    modules,
    aliases,
    fields,
    dimensions,
    dimensionValues,
    forms,
    formFields,
    views,
    membership,
    canManage,
  ];
  if (results.some((result) => result.error))
    throw new Error("customization_data_unavailable");

  return {
    organization: organization.data,
    configuration: configuration.data,
    modules: modules.data ?? [],
    aliases: aliases.data ?? [],
    fields: fields.data ?? [],
    dimensions: dimensions.data ?? [],
    dimensionValues: dimensionValues.data ?? [],
    forms: forms.data ?? [],
    formFields: formFields.data ?? [],
    views: views.data ?? [],
    canManage: canManage.data === true,
  };
}
