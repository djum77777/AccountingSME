"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createAdminClient } from "@/lib/supabase/admin";
import { membershipRoles } from "@/lib/domain/access";
import { getPublicEnvironment } from "@/lib/env/public";
import { createClient } from "@/lib/supabase/server";

const invitationSchema = z.object({
  organizationId: z.uuid(),
  email: z.email(),
  role: z.enum(membershipRoles),
});

const membershipCommandSchema = z.object({
  organizationId: z.uuid(),
  membershipId: z.uuid(),
});

export async function inviteMember(formData: FormData) {
  const input = invitationSchema.parse({
    organizationId: formData.get("organizationId"),
    email: formData.get("email"),
    role: formData.get("role"),
  });
  const supabase = await createClient();

  // Confirm the actor is an owner before the server-only admin invitation.
  const { data: claimsData } = await supabase.auth.getClaims();
  const actorUserId = claimsData?.claims?.sub;
  if (!actorUserId) throw new Error("authentication_required");
  const { data: actorMembership, error: permissionError } = await supabase
    .from("organization_memberships")
    .select("id")
    .eq("organization_id", input.organizationId)
    .eq("user_id", actorUserId)
    .eq("role", "owner")
    .eq("status", "active")
    .maybeSingle();
  if (permissionError || !actorMembership) throw new Error("permission_denied");

  const admin = createAdminClient();
  const { data: invited, error: inviteError } =
    await admin.auth.admin.inviteUserByEmail(input.email, {
      redirectTo: `${getPublicEnvironment().NEXT_PUBLIC_APP_URL}/auth/callback`,
    });
  if (inviteError) throw new Error(inviteError.message);

  const { error } = await supabase.rpc("invite_member", {
    target_organization_id: input.organizationId,
    invited_user_id: invited.user.id,
    invited_email: input.email,
    invited_role: input.role,
  });
  if (error) throw new Error(error.message);
  revalidatePath(`/app/organizations/${input.organizationId}/members`);
}

export async function activateMember(formData: FormData) {
  const input = membershipCommandSchema.parse({
    organizationId: formData.get("organizationId"),
    membershipId: formData.get("membershipId"),
  });
  const supabase = await createClient();
  const { error } = await supabase.rpc("activate_member", {
    target_membership_id: input.membershipId,
  });
  if (error) throw new Error(error.message);
  revalidatePath(`/app/organizations/${input.organizationId}/members`);
}

export async function deactivateMember(formData: FormData) {
  const input = membershipCommandSchema.parse({
    organizationId: formData.get("organizationId"),
    membershipId: formData.get("membershipId"),
  });
  const supabase = await createClient();
  const { error } = await supabase.rpc("deactivate_member", {
    target_membership_id: input.membershipId,
  });
  if (error) throw new Error(error.message);
  revalidatePath(`/app/organizations/${input.organizationId}/members`);
}

export async function changeMemberRole(formData: FormData) {
  const input = membershipCommandSchema
    .extend({ role: z.enum(membershipRoles) })
    .parse({
      organizationId: formData.get("organizationId"),
      membershipId: formData.get("membershipId"),
      role: formData.get("role"),
    });
  const supabase = await createClient();
  const { error } = await supabase.rpc("change_member_role", {
    target_membership_id: input.membershipId,
    new_role: input.role,
  });
  if (error) throw new Error(error.message);
  revalidatePath(`/app/organizations/${input.organizationId}/members`);
}
