"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import {
  normalizeAccountingAmount,
  parseAccountingAmount,
} from "@/lib/domain/accounting/money";
import { templateKeys } from "@/lib/domain/customization";
import { createClient } from "@/lib/supabase/server";

const id = z.uuid();
const date = z.iso.date();
const text = (formData: FormData, key: string) =>
  String(formData.get(key) ?? "").trim();

async function rpc(name: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message);
  return data;
}

function path(organizationId: string) {
  return `/app/organizations/${organizationId}/accounting`;
}

function journalLines(formData: FormData) {
  return Array.from({ length: 4 }, (_, index) => {
    const accountId = text(formData, `accountId${index}`);
    const debitRaw = text(formData, `debit${index}`) || "0";
    const creditRaw = text(formData, `credit${index}`) || "0";
    if (!accountId) return null;
    const debit = normalizeAccountingAmount(debitRaw);
    const credit = normalizeAccountingAmount(creditRaw);
    if (parseAccountingAmount(debit) < 0n || parseAccountingAmount(credit) < 0n)
      throw new Error("negative_amount_forbidden");
    if (
      parseAccountingAmount(debit) === 0n &&
      parseAccountingAmount(credit) === 0n
    )
      return null;
    return {
      account_id: id.parse(accountId),
      debit,
      credit,
      description: text(formData, `lineDescription${index}`),
    };
  }).filter((line) => line !== null);
}

export async function initializeAccounting(formData: FormData) {
  const organizationId = id.parse(text(formData, "organizationId"));
  await rpc("initialize_accounting", {
    target_organization_id: organizationId,
    selected_template_key: z
      .enum(templateKeys)
      .parse(text(formData, "templateKey")),
    first_period_start: date.parse(text(formData, "periodStart")),
    first_period_end: date.parse(text(formData, "periodEnd")),
  });
  revalidatePath(path(organizationId));
}

export async function createSubaccount(formData: FormData) {
  const organizationId = id.parse(text(formData, "organizationId"));
  await rpc("create_subaccount", {
    target_organization_id: organizationId,
    target_parent_account_id: id.parse(text(formData, "parentAccountId")),
    target_code: z
      .string()
      .regex(/^[A-Z0-9][A-Z0-9.-]{0,19}$/)
      .parse(text(formData, "code").toUpperCase()),
    target_name: z.string().min(1).max(120).parse(text(formData, "name")),
    target_category: z
      .enum(["asset", "liability", "equity", "income", "expense"])
      .parse(text(formData, "category")),
    target_normal_balance: z
      .enum(["debit", "credit"])
      .parse(text(formData, "normalBalance")),
  });
  revalidatePath(path(organizationId));
}

export async function renameAccount(formData: FormData) {
  const organizationId = id.parse(text(formData, "organizationId"));
  await rpc("rename_account", {
    target_account_id: id.parse(text(formData, "accountId")),
    target_name: z.string().min(1).max(120).parse(text(formData, "name")),
  });
  revalidatePath(path(organizationId));
}

export async function deactivateAccount(formData: FormData) {
  const organizationId = id.parse(text(formData, "organizationId"));
  await rpc("deactivate_account", {
    target_account_id: id.parse(text(formData, "accountId")),
  });
  revalidatePath(path(organizationId));
}

async function post(formData: FormData, opening: boolean) {
  const organizationId = id.parse(text(formData, "organizationId"));
  const common = {
    target_organization_id: organizationId,
    target_accounting_date: date.parse(text(formData, "accountingDate")),
    target_description: z
      .string()
      .min(1)
      .max(500)
      .parse(text(formData, "description")),
    target_lines: journalLines(formData),
    target_idempotency_key: z
      .string()
      .min(8)
      .max(200)
      .parse(text(formData, "idempotencyKey")),
  };
  await rpc(
    opening ? "post_opening_balance" : "post_journal",
    opening
      ? common
      : {
          ...common,
          target_source_reference: text(formData, "sourceReference") || null,
        },
  );
  revalidatePath(path(organizationId));
}

export async function postManualJournal(formData: FormData) {
  await post(formData, false);
}
export async function postOpeningBalance(formData: FormData) {
  await post(formData, true);
}

export async function reverseJournal(formData: FormData) {
  const organizationId = id.parse(text(formData, "organizationId"));
  await rpc("reverse_journal", {
    target_journal_entry_id: id.parse(text(formData, "journalId")),
    target_accounting_date: date.parse(text(formData, "accountingDate")),
    target_reason: z.string().min(3).max(500).parse(text(formData, "reason")),
    target_idempotency_key: z
      .string()
      .min(8)
      .max(200)
      .parse(text(formData, "idempotencyKey")),
  });
  revalidatePath(path(organizationId));
}

async function changePeriod(formData: FormData, rpcName: string) {
  const organizationId = id.parse(text(formData, "organizationId"));
  await rpc(rpcName, {
    target_period_id: id.parse(text(formData, "periodId")),
    target_reason: z.string().min(3).max(500).parse(text(formData, "reason")),
  });
  revalidatePath(path(organizationId));
}
export async function closePeriod(formData: FormData) {
  await changePeriod(formData, "close_accounting_period");
}
export async function reopenPeriod(formData: FormData) {
  await changePeriod(formData, "reopen_accounting_period");
}
