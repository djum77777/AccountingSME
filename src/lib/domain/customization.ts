export const templateKeys = [
  "general_sme",
  "retail",
  "online_seller",
  "trading_distributor",
  "service",
] as const;
export type TemplateKey = (typeof templateKeys)[number];

export const moduleKeys = [
  "dashboard",
  "contacts",
  "expenses",
  "cash_bank",
  "sales",
  "purchases",
  "inventory",
  "projects",
  "marketplaces",
  "branches",
  "reports",
  "tax",
  "settings",
] as const;
export type ModuleKey = (typeof moduleKeys)[number];

export const customizableEntityKeys = [
  "customer",
  "supplier",
  "product",
  "service",
  "project",
  "branch",
  "marketplace",
  "invoice",
  "bill",
] as const;

export const customFieldEntityTypes = [
  "contact",
  "expense",
  "cash_transaction",
  "sale",
  "purchase",
  "product",
  "project",
] as const;

export const customValueTypes = [
  "text",
  "long_text",
  "integer",
  "decimal",
  "boolean",
  "date",
  "datetime",
  "single_select",
  "multi_select",
] as const;

export const protectedConfigurationKeys = new Set([
  "organization_id",
  "owner_user_id",
  "membership_role",
  "posting_status",
  "journal_balance",
  "debit",
  "credit",
  "ledger_account_id",
  "inventory_costing_method",
  "weighted_average_cost",
  "row_level_security",
  "audit_event",
]);

export function isProtectedConfigurationKey(key: string): boolean {
  return protectedConfigurationKeys.has(key);
}

export function normalizeConfigurationKey(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}
