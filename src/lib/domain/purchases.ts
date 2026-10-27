const DECIMAL_PATTERN = /^(\d+)(?:\.(\d+))?$/;

export const purchasePaymentModes = ["cash", "credit"] as const;

export function normalizePurchaseDecimal(
  value: string,
  scale: 4 | 8,
  options: { allowZero?: boolean } = {},
): string {
  const match = DECIMAL_PATTERN.exec(value.trim());
  if (!match) throw new Error("invalid_purchase_decimal");
  const fraction = match[2] ?? "";
  if (fraction.length > scale) throw new Error("purchase_precision_exceeded");
  const digits = match[1] + fraction.padEnd(scale, "0");
  if (!options.allowZero && BigInt(digits) === 0n)
    throw new Error("positive_purchase_decimal_required");
  return `${match[1]}.${fraction.padEnd(scale, "0")}`;
}
