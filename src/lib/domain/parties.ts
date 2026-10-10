export const partyRoleKinds = ["customer", "supplier"] as const;
export const partyStatuses = ["active", "archived"] as const;
export const partyTaxStatuses = ["not_set", "non_taxable", "taxable"] as const;
export const partyAddressKinds = [
  "billing",
  "shipping",
  "office",
  "other",
] as const;

export type PartyCustomValueType =
  | "text"
  | "long_text"
  | "integer"
  | "decimal"
  | "boolean"
  | "date"
  | "datetime"
  | "single_select"
  | "multi_select";

export function parsePartyCustomValue(
  valueType: PartyCustomValueType,
  rawValue: string,
): unknown {
  const value = rawValue.trim();
  switch (valueType) {
    case "integer": {
      if (!/^-?\d+$/.test(value)) throw new Error("invalid_custom_integer");
      return Number.parseInt(value, 10);
    }
    case "decimal": {
      if (!/^-?\d+(?:\.\d+)?$/.test(value))
        throw new Error("invalid_custom_decimal");
      return Number(value);
    }
    case "boolean":
      if (value !== "true" && value !== "false")
        throw new Error("invalid_custom_boolean");
      return value === "true";
    case "multi_select":
      return value
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
    default:
      return value;
  }
}
