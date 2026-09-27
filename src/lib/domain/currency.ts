const isoCurrencyCode = /^[A-Z]{3}$/;

export function normalizeCurrencyCode(value: string): string {
  const normalized = value.trim().toUpperCase();
  if (!isoCurrencyCode.test(normalized)) {
    throw new Error("Currency must be a three-letter ISO 4217 code.");
  }
  return normalized;
}
