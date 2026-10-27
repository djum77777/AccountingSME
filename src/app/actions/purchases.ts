"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import {
  normalizePurchaseDecimal,
  purchasePaymentModes,
} from "@/lib/domain/purchases";
import { createClient } from "@/lib/supabase/server";

const uuid = z.uuid();
const isoDate = z.iso.date();
const text = (formData: FormData, key: string) =>
  String(formData.get(key) ?? "").trim();
const optionalUuid = (value: string) => (value ? uuid.parse(value) : null);
const money = (value: string, allowZero = false) =>
  normalizePurchaseDecimal(value || "0", 4, { allowZero });

async function rpc(name: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message);
  return data;
}

function refresh(organizationId: string) {
  revalidatePath(`/app/organizations/${organizationId}/purchases`);
  revalidatePath(`/app/organizations/${organizationId}/inventory`);
  revalidatePath(`/app/organizations/${organizationId}/accounting`);
}

export async function createPurchaseDraft(formData: FormData) {
  const organizationId = uuid.parse(text(formData, "organizationId"));
  const paymentMode = z
    .enum(purchasePaymentModes)
    .parse(text(formData, "paymentMode"));
  await rpc("create_purchase_draft", {
    target_organization_id: organizationId,
    target_supplier_party_id: uuid.parse(text(formData, "supplierPartyId")),
    target_supplier_invoice_number:
      text(formData, "supplierInvoiceNumber") || null,
    target_invoice_date: isoDate.parse(text(formData, "invoiceDate")),
    target_due_date: isoDate.parse(text(formData, "dueDate")),
    target_payment_mode: paymentMode,
    target_inventory_location_id: optionalUuid(
      text(formData, "inventoryLocationId"),
    ),
    target_cash_account_id:
      paymentMode === "cash"
        ? uuid.parse(text(formData, "cashAccountId"))
        : null,
    target_document_discount_amount: money(
      text(formData, "documentDiscountAmount"),
      true,
    ),
    target_additional_cost_amount: money(
      text(formData, "additionalCostAmount"),
      true,
    ),
    target_notes: text(formData, "notes") || null,
  });
  refresh(organizationId);
}

export async function addPurchaseLine(formData: FormData) {
  const organizationId = uuid.parse(text(formData, "organizationId"));
  await rpc("add_purchase_line", {
    target_organization_id: organizationId,
    target_purchase_id: uuid.parse(text(formData, "purchaseId")),
    target_catalog_item_id: uuid.parse(text(formData, "catalogItemId")),
    target_quantity: normalizePurchaseDecimal(text(formData, "quantity"), 8),
    target_unit_price: money(text(formData, "unitPrice"), true),
    target_line_discount_amount: money(
      text(formData, "lineDiscountAmount"),
      true,
    ),
    target_line_additional_cost_amount: money(
      text(formData, "lineAdditionalCostAmount"),
      true,
    ),
    target_expense_account_id: optionalUuid(text(formData, "expenseAccountId")),
    target_description: text(formData, "description") || null,
  });
  refresh(organizationId);
}

export async function confirmPurchase(formData: FormData) {
  const organizationId = uuid.parse(text(formData, "organizationId"));
  await rpc("confirm_purchase", {
    target_organization_id: organizationId,
    target_purchase_id: uuid.parse(text(formData, "purchaseId")),
    target_idempotency_key: z
      .string()
      .min(8)
      .max(200)
      .parse(text(formData, "idempotencyKey")),
  });
  refresh(organizationId);
}

export async function postSupplierPayment(formData: FormData) {
  const organizationId = uuid.parse(text(formData, "organizationId"));
  const [purchaseValue, supplierValue] = text(
    formData,
    "purchaseAllocation",
  ).split("|");
  const purchaseId = uuid.parse(purchaseValue);
  const supplierId = uuid.parse(supplierValue);
  await rpc("post_supplier_payment", {
    target_organization_id: organizationId,
    target_supplier_party_id: supplierId,
    target_payment_date: isoDate.parse(text(formData, "paymentDate")),
    target_cash_account_id: uuid.parse(text(formData, "cashAccountId")),
    target_source_reference: text(formData, "sourceReference") || null,
    target_allocations: [
      {
        purchase_id: purchaseId,
        amount: money(text(formData, "amount")),
      },
    ],
    target_idempotency_key: z
      .string()
      .min(8)
      .max(200)
      .parse(text(formData, "idempotencyKey")),
  });
  refresh(organizationId);
}

export async function postPurchaseCredit(formData: FormData) {
  const organizationId = uuid.parse(text(formData, "organizationId"));
  const [lineValue, purchaseValue] = text(formData, "purchaseLine").split("|");
  await rpc("post_purchase_credit", {
    target_organization_id: organizationId,
    target_purchase_id: uuid.parse(purchaseValue),
    target_credit_date: isoDate.parse(text(formData, "creditDate")),
    target_reason: z.string().min(3).max(500).parse(text(formData, "reason")),
    target_lines: [
      {
        purchase_line_id: uuid.parse(lineValue),
        quantity: normalizePurchaseDecimal(text(formData, "quantity"), 8),
        credit_amount: money(text(formData, "creditAmount")),
      },
    ],
    target_idempotency_key: z
      .string()
      .min(8)
      .max(200)
      .parse(text(formData, "idempotencyKey")),
  });
  refresh(organizationId);
}
