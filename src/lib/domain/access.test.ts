import { describe, expect, it } from "vitest";
import { roleHasPermission } from "./access";

describe("roleHasPermission", () => {
  it("reserves membership activation for owners", () => {
    expect(roleHasPermission("owner", "members.activate")).toBe(true);
    expect(roleHasPermission("admin_accountant", "members.activate")).toBe(
      false,
    );
    expect(roleHasPermission("staff", "members.activate")).toBe(false);
  });

  it("does not grant organization management to staff", () => {
    expect(roleHasPermission("staff", "organization.manage")).toBe(false);
  });

  it("allows accountant posting but keeps initialization owner-only", () => {
    expect(roleHasPermission("owner", "accounting.initialize")).toBe(true);
    expect(roleHasPermission("admin_accountant", "accounting.post")).toBe(true);
    expect(roleHasPermission("admin_accountant", "accounting.initialize")).toBe(
      false,
    );
    expect(roleHasPermission("staff", "accounting.read")).toBe(false);
  });

  it("allows owners and accountants to manage inventory but denies staff", () => {
    expect(roleHasPermission("owner", "inventory.manage")).toBe(true);
    expect(roleHasPermission("admin_accountant", "inventory.read")).toBe(true);
    expect(roleHasPermission("admin_accountant", "inventory.manage")).toBe(
      true,
    );
    expect(roleHasPermission("staff", "inventory.read")).toBe(false);
  });
});
