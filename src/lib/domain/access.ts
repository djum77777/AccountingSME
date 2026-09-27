export const membershipRoles = ["owner", "admin_accountant", "staff"] as const;
export type MembershipRole = (typeof membershipRoles)[number];

export const membershipStatuses = [
  "invited",
  "active",
  "suspended",
  "deactivated",
] as const;
export type MembershipStatus = (typeof membershipStatuses)[number];

export const permissions = [
  "organization.manage",
  "customization.manage",
  "members.read",
  "members.invite",
  "members.activate",
  "members.change_role",
  "audit.read",
  "storage.read",
  "storage.write",
  "accounting.read",
  "accounting.post",
  "accounting.initialize",
] as const;
export type Permission = (typeof permissions)[number];

const rolePermissions: Record<MembershipRole, ReadonlySet<Permission>> = {
  owner: new Set(permissions),
  admin_accountant: new Set([
    "members.read",
    "audit.read",
    "storage.read",
    "storage.write",
    "accounting.read",
    "accounting.post",
  ]),
  staff: new Set(["storage.read", "storage.write"]),
};

export function roleHasPermission(
  role: MembershipRole,
  permission: Permission,
): boolean {
  return rolePermissions[role].has(permission);
}
