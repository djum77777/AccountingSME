import { describe, expect, it } from "vitest";
import {
  isProtectedConfigurationKey,
  moduleKeys,
  normalizeConfigurationKey,
  templateKeys,
} from "./customization";

describe("customization boundaries", () => {
  it("exposes all five stable SME template keys", () => {
    expect(templateKeys).toEqual([
      "general_sme",
      "retail",
      "online_seller",
      "trading_distributor",
      "service",
    ]);
  });

  it("keeps accounting and security keys protected", () => {
    expect(isProtectedConfigurationKey("journal_balance")).toBe(true);
    expect(isProtectedConfigurationKey("row_level_security")).toBe(true);
    expect(isProtectedConfigurationKey("customer_label")).toBe(false);
  });

  it("normalizes user-facing names into stable metadata keys", () => {
    expect(normalizeConfigurationKey("Client Type")).toBe("client_type");
  });

  it("allows module visibility only for the declared navigation modules", () => {
    expect(moduleKeys).toContain("marketplaces");
    expect(moduleKeys).not.toContain("journal_math");
  });
});
