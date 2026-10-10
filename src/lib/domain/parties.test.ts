import { describe, expect, it } from "vitest";
import { parsePartyCustomValue } from "./parties";

describe("parsePartyCustomValue", () => {
  it("parses decimals as JSON numbers for Phase 2 metadata validation", () => {
    expect(parsePartyCustomValue("decimal", " 12.50 ")).toBe(12.5);
  });

  it("parses typed values and comma-separated selections", () => {
    expect(parsePartyCustomValue("integer", "42")).toBe(42);
    expect(parsePartyCustomValue("boolean", "true")).toBe(true);
    expect(parsePartyCustomValue("multi_select", "gold, retail, ")).toEqual([
      "gold",
      "retail",
    ]);
  });

  it("rejects malformed typed values", () => {
    expect(() => parsePartyCustomValue("integer", "1.5")).toThrow(
      "invalid_custom_integer",
    );
    expect(() => parsePartyCustomValue("boolean", "yes")).toThrow(
      "invalid_custom_boolean",
    );
  });
});
