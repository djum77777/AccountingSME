import { describe, expect, it } from "vitest";
import { getDictionary, isLocale } from "./dictionaries";

describe("i18n dictionaries", () => {
  it("supports Indonesian and English", () => {
    expect(isLocale("id")).toBe(true);
    expect(isLocale("en")).toBe(true);
    expect(isLocale("fr")).toBe(false);
  });

  it("keeps both dictionaries structurally aligned", () => {
    expect(Object.keys(getDictionary("id")).sort()).toEqual(
      Object.keys(getDictionary("en")).sort(),
    );
  });
});
