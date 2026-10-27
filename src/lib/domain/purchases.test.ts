import { describe, expect, it } from "vitest";
import { normalizePurchaseDecimal } from "./purchases";

describe("normalizePurchaseDecimal", () => {
  it("normalizes money and quantity without floating point", () => {
    expect(normalizePurchaseDecimal("50000", 4)).toBe("50000.0000");
    expect(normalizePurchaseDecimal("10.25", 8)).toBe("10.25000000");
  });

  it("supports explicit zero only when requested", () => {
    expect(normalizePurchaseDecimal("0", 4, { allowZero: true })).toBe(
      "0.0000",
    );
    expect(() => normalizePurchaseDecimal("0", 4)).toThrow(
      "positive_purchase_decimal_required",
    );
  });

  it("rejects signs, exponent notation, and excess precision", () => {
    expect(() => normalizePurchaseDecimal("-1", 4)).toThrow();
    expect(() => normalizePurchaseDecimal("1e3", 4)).toThrow();
    expect(() => normalizePurchaseDecimal("1.00001", 4)).toThrow(
      "purchase_precision_exceeded",
    );
  });
});
