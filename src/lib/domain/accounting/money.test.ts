import { describe, expect, it } from "vitest";
import { normalizeAccountingAmount, parseAccountingAmount } from "./money";

describe("accounting amount boundary", () => {
  it("parses fixed-scale decimals without binary floating point", () => {
    expect(parseAccountingAmount("1000000.125")).toBe(10000001250n);
    expect(normalizeAccountingAmount("1.2")).toBe("1.2000");
  });

  it("rejects excess precision and exponent notation", () => {
    expect(() => parseAccountingAmount("1.00001")).toThrow(
      "amount_precision_exceeded",
    );
    expect(() => parseAccountingAmount("1e6")).toThrow(
      "invalid_decimal_amount",
    );
  });
});
