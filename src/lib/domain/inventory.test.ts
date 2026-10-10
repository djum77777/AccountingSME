import { describe, expect, it } from "vitest";
import { normalizeInventoryDecimal } from "./inventory";

describe("normalizeInventoryDecimal", () => {
  it("normalizes quantities without binary floating point", () => {
    expect(normalizeInventoryDecimal("10.25")).toBe("10.25000000");
  });

  it("allows explicit zero only where the workflow supports it", () => {
    expect(normalizeInventoryDecimal("0", { allowZero: true })).toBe(
      "0.00000000",
    );
    expect(() => normalizeInventoryDecimal("0")).toThrow(
      "positive_inventory_decimal_required",
    );
  });

  it("rejects negative, excessive precision, and non-decimal input", () => {
    expect(() => normalizeInventoryDecimal("-1")).toThrow(
      "invalid_inventory_decimal",
    );
    expect(() => normalizeInventoryDecimal("1.123456789")).toThrow(
      "inventory_precision_exceeded",
    );
    expect(() => normalizeInventoryDecimal("1e3")).toThrow(
      "invalid_inventory_decimal",
    );
  });
});
