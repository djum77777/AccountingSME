"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

const organizationSchema = z.object({
  name: z.string().trim().min(1).max(120),
  currency: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z]{3}$/),
});

export async function createOrganization(formData: FormData) {
  const input = organizationSchema.parse({
    name: formData.get("name"),
    currency: formData.get("currency"),
  });
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_organization", {
    organization_name: input.name,
    currency_code: input.currency,
  });

  if (error) throw new Error(error.message);
  revalidatePath("/app");
  redirect(`/app/onboarding/${String(data)}`);
}
