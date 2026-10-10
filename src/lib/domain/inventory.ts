const DECIMAL_PATTERN = /^(\d+)(?:\.(\d+))?$/;

export const INVENTORY_QUANTITY_SCALE = 8;

export const inventoryMovementKinds = [
  "opening",
  "stock_in",
  "stock_out",
  "adjustment_in",
  "adjustment_out",
  "damage_loss",
] as const;

export type InventoryMovementKind = (typeof inventoryMovementKinds)[number];

export function normalizeInventoryDecimal(
  value: string,
  options: { allowZero?: boolean } = {},
): string {
  const normalized = value.trim();
  const match = DECIMAL_PATTERN.exec(normalized);
  if (!match) throw new Error("invalid_inventory_decimal");
  const fraction = match[2] ?? "";
  if (fraction.length > INVENTORY_QUANTITY_SCALE)
    throw new Error("inventory_precision_exceeded");
  const fixed = `${match[1]}.${fraction.padEnd(INVENTORY_QUANTITY_SCALE, "0")}`;
  if (!options.allowZero && BigInt(match[1] + fraction.padEnd(8, "0")) === 0n)
    throw new Error("positive_inventory_decimal_required");
  return fixed;
}
