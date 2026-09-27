import { describe, expect, it } from "vitest";
import { normalizeCurrencyCode } from "./currency";

describe("normalizeCurrencyCode", () => {
  it("accepts configurable ISO-style currency codes", () => {
    expect(normalizeCurrencyCode("idr")).toBe("IDR");
    expect(normalizeCurrencyCode(" usd ")).toBe("USD");
  });

  it("rejects display labels and malformed values", () => {
    expect(() => normalizeCurrencyCode("Rp")).toThrow();
    expect(() => normalizeCurrencyCode("US dollars")).toThrow();
  });
});
