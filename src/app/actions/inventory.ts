"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import {
  inventoryMovementKinds,
  normalizeInventoryDecimal,
} from "@/lib/domain/inventory";
import { createClient } from "@/lib/supabase/server";

const id = z.uuid();
const date = z.iso.date();
const code = z.string().regex(/^[A-Z0-9][A-Z0-9_-]{0,19}$/);
const text = (formData: FormData, key: string) =>
  String(formData.get(key) ?? "").trim();
const optionalId = (value: string) => (value ? id.parse(value) : null);

async function rpc(name: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message);
}

function inventoryPath(organizationId: string) {
  return `/app/organizations/${organizationId}/inventory`;
}

function organizationId(formData: FormData) {
  return id.parse(text(formData, "organizationId"));
}

function finish(targetOrganizationId: string) {
  revalidatePath(inventoryPath(targetOrganizationId));
  revalidatePath(`/app/organizations/${targetOrganizationId}/accounting`);
}

export async function initializeInventory(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  await rpc("initialize_inventory", {
    target_organization_id: targetOrganizationId,
  });
  finish(targetOrganizationId);
}

export async function createCategory(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  await rpc("create_product_category", {
    target_organization_id: targetOrganizationId,
    target_code: code.parse(text(formData, "code").toUpperCase()),
    target_name: z.string().min(1).max(120).parse(text(formData, "name")),
  });
  finish(targetOrganizationId);
}

export async function createUnit(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  await rpc("create_inventory_unit", {
    target_organization_id: targetOrganizationId,
    target_code: code.parse(text(formData, "code").toUpperCase()),
    target_name: z.string().min(1).max(80).parse(text(formData, "name")),
    target_symbol: z.string().min(1).max(16).parse(text(formData, "symbol")),
    target_quantity_scale: z.coerce
      .number()
      .int()
      .min(0)
      .max(8)
      .parse(text(formData, "quantityScale")),
  });
  finish(targetOrganizationId);
}

export async function createLocation(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  await rpc("create_inventory_location", {
    target_organization_id: targetOrganizationId,
    target_code: code.parse(text(formData, "code").toUpperCase()),
    target_name: z.string().min(1).max(120).parse(text(formData, "name")),
  });
  finish(targetOrganizationId);
}

export async function createCatalogItem(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const itemKind = z
    .enum(["product", "service"])
    .parse(text(formData, "itemKind"));
  const inventoryTracked =
    itemKind === "product" && text(formData, "inventoryTracked") === "on";
  await rpc("create_catalog_item", {
    target_organization_id: targetOrganizationId,
    target_item_kind: itemKind,
    target_name: z.string().min(1).max(160).parse(text(formData, "name")),
    target_sku: z.string().min(1).max(60).parse(text(formData, "sku")),
    target_barcode: z.string().max(80).parse(text(formData, "barcode")) || null,
    target_category_id: optionalId(text(formData, "categoryId")),
    target_unit_id: id.parse(text(formData, "unitId")),
    target_inventory_tracked: inventoryTracked,
    target_inventory_account_id: inventoryTracked
      ? id.parse(text(formData, "inventoryAccountId"))
      : null,
    target_low_stock_threshold: inventoryTracked
      ? normalizeInventoryDecimal(text(formData, "lowStockThreshold") || "0", {
          allowZero: true,
        })
      : "0",
  });
  finish(targetOrganizationId);
}

export async function setCatalogItemStatus(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  await rpc("set_catalog_item_status", {
    target_organization_id: targetOrganizationId,
    target_product_id: id.parse(text(formData, "productId")),
    target_status: z
      .enum(["active", "inactive"])
      .parse(text(formData, "status")),
  });
  finish(targetOrganizationId);
}

export async function postInventoryMovement(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const movementKind = z
    .enum(inventoryMovementKinds)
    .parse(text(formData, "movementKind"));
  const inbound = ["opening", "stock_in", "adjustment_in"].includes(
    movementKind,
  );
  await rpc("post_inventory_movement", {
    target_organization_id: targetOrganizationId,
    target_product_id: id.parse(text(formData, "productId")),
    target_location_id: id.parse(text(formData, "locationId")),
    target_movement_date: date.parse(text(formData, "movementDate")),
    target_movement_kind: movementKind,
    target_quantity: normalizeInventoryDecimal(text(formData, "quantity")),
    target_unit_cost: inbound
      ? normalizeInventoryDecimal(text(formData, "unitCost"))
      : null,
    target_offset_account_id: id.parse(text(formData, "offsetAccountId")),
    target_reason: z.string().min(3).max(500).parse(text(formData, "reason")),
    target_source_reference:
      z.string().max(200).parse(text(formData, "sourceReference")) || null,
    target_idempotency_key: z
      .string()
      .min(8)
      .max(200)
      .parse(text(formData, "idempotencyKey")),
  });
  finish(targetOrganizationId);
}

export async function postStockCount(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  const emptyCost = text(formData, "unitCostIfEmpty");
  await rpc("post_inventory_stock_count", {
    target_organization_id: targetOrganizationId,
    target_product_id: id.parse(text(formData, "productId")),
    target_location_id: id.parse(text(formData, "locationId")),
    target_movement_date: date.parse(text(formData, "movementDate")),
    target_counted_quantity: normalizeInventoryDecimal(
      text(formData, "countedQuantity"),
      { allowZero: true },
    ),
    target_unit_cost_if_empty: emptyCost
      ? normalizeInventoryDecimal(emptyCost)
      : null,
    target_offset_account_id: id.parse(text(formData, "offsetAccountId")),
    target_reason: z.string().min(3).max(500).parse(text(formData, "reason")),
    target_idempotency_key: z
      .string()
      .min(8)
      .max(200)
      .parse(text(formData, "idempotencyKey")),
  });
  finish(targetOrganizationId);
}

export async function postTransfer(formData: FormData) {
  const targetOrganizationId = organizationId(formData);
  await rpc("post_inventory_transfer", {
    target_organization_id: targetOrganizationId,
    target_product_id: id.parse(text(formData, "productId")),
    target_from_location_id: id.parse(text(formData, "fromLocationId")),
    target_to_location_id: id.parse(text(formData, "toLocationId")),
    target_movement_date: date.parse(text(formData, "movementDate")),
    target_quantity: normalizeInventoryDecimal(text(formData, "quantity")),
    target_reason: z.string().min(3).max(500).parse(text(formData, "reason")),
    target_idempotency_key: z
      .string()
      .min(8)
      .max(200)
      .parse(text(formData, "idempotencyKey")),
  });
  finish(targetOrganizationId);
}
