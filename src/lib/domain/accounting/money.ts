const DECIMAL_PATTERN = /^([+-]?)(\d+)(?:\.(\d+))?$/;
export const ACCOUNTING_AMOUNT_SCALE = 4;

export function parseAccountingAmount(value: string): bigint {
  const normalized = value.trim();
  const match = DECIMAL_PATTERN.exec(normalized);
  if (!match) throw new Error("invalid_decimal_amount");
  const fraction = match[3] ?? "";
  if (fraction.length > ACCOUNTING_AMOUNT_SCALE)
    throw new Error("amount_precision_exceeded");
  const sign = match[1] === "-" ? -1n : 1n;
  const units = BigInt(match[2]);
  const minor = BigInt(fraction.padEnd(ACCOUNTING_AMOUNT_SCALE, "0"));
  return sign * (units * 10n ** BigInt(ACCOUNTING_AMOUNT_SCALE) + minor);
}

export function normalizeAccountingAmount(value: string): string {
  const amount = parseAccountingAmount(value);
  const sign = amount < 0n ? "-" : "";
  const absolute = amount < 0n ? -amount : amount;
  const divisor = 10n ** BigInt(ACCOUNTING_AMOUNT_SCALE);
  return `${sign}${absolute / divisor}.${String(absolute % divisor).padStart(ACCOUNTING_AMOUNT_SCALE, "0")}`;
}
