import { randomUUID } from "node:crypto";
import Link from "next/link";
import {
  createCatalogItem,
  createCategory,
  createLocation,
  createUnit,
  initializeInventory,
  postInventoryMovement,
  postStockCount,
  postTransfer,
  setCatalogItemStatus,
} from "@/app/actions/inventory";
import { getInventoryData } from "@/data/inventory";
import { getTranslations } from "@/lib/i18n/server";

const today = () => new Date().toISOString().slice(0, 10);
const hiddenOrganization = (organizationId: string) => (
  <input name="organizationId" type="hidden" value={organizationId} />
);

function ProductAndLocationFields({
  products,
  locations,
}: {
  products: Array<{
    id: string;
    sku: string;
    name: string;
    inventory_tracked: boolean;
  }>;
  locations: Array<{ id: string; code: string; name: string }>;
}) {
  return (
    <>
      <label>
        Product / Produk
        <select name="productId" required>
          {products
            .filter((product) => product.inventory_tracked)
            .map((product) => (
              <option key={product.id} value={product.id}>
                {product.sku} · {product.name}
              </option>
            ))}
        </select>
      </label>
      <label>
        Location / Lokasi
        <select name="locationId" required>
          {locations.map((location) => (
            <option key={location.id} value={location.id}>
              {location.code} · {location.name}
            </option>
          ))}
        </select>
      </label>
    </>
  );
}

export default async function InventoryPage({
  params,
}: {
  params: Promise<{ organizationId: string }>;
}) {
  const { organizationId } = await params;
  const [t, data] = await Promise.all([
    getTranslations(),
    getInventoryData(organizationId),
  ]);
  const trackedProducts = data.products.filter(
    (item) => item.inventory_tracked,
  );
  const assetAccounts = data.accounts.filter(
    (account) => account.category === "asset",
  );
  const offsetAccounts = data.accounts.filter((account) =>
    ["asset", "equity", "expense"].includes(account.category),
  );

  return (
    <section>
      <div className="section-heading">
        <div>
          <p className="eyebrow">Phase 4 · Movement-based inventory</p>
          <h1>{t.inventory}</h1>
          <p>
            {data.organization.display_name} ·{" "}
            {data.organization.base_currency_code}
          </p>
        </div>
        <div className="button-row compact">
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/accounting`}
          >
            {t.accounting}
          </Link>
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/settings/customization`}
          >
            {t.customization}
          </Link>
        </div>
      </div>
      <p className="notice">{t.inventoryNotice}</p>

      {!data.accountingReady ? (
        <div className="card setup-card">
          <h2>Accounting setup required / Akuntansi harus disiapkan</h2>
          <p>
            Initialize the chart of accounts and an open period before
            inventory.
          </p>
          <Link
            className="button primary"
            href={`/app/organizations/${organizationId}/accounting`}
          >
            {t.accounting}
          </Link>
        </div>
      ) : !data.initialized ? (
        <form action={initializeInventory} className="card setup-card">
          {hiddenOrganization(organizationId)}
          <h2>{t.initializeInventory}</h2>
          <p>
            Creates PCS, HOUR, and the MAIN location. More units and locations
            can be added later.
          </p>
          <button
            className="button primary"
            disabled={!data.canManage}
            type="submit"
          >
            {t.initializeInventory}
          </button>
        </form>
      ) : (
        <div className="settings-stack">
          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">01</p>
                <h2>{t.productServiceMasters}</h2>
              </div>
              <p>Stable SKU and metadata; services never carry stock.</p>
            </div>
            <div className="inventory-master-grid">
              <form action={createCategory} className="sub-card inventory-form">
                {hiddenOrganization(organizationId)}
                <h3>Category / Kategori</h3>
                <label>
                  Code
                  <input name="code" required />
                </label>
                <label>
                  Name
                  <input name="name" required />
                </label>
                <button className="button secondary" disabled={!data.canManage}>
                  Add category
                </button>
              </form>
              <form action={createUnit} className="sub-card inventory-form">
                {hiddenOrganization(organizationId)}
                <h3>Unit / Satuan</h3>
                <label>
                  Code
                  <input name="code" required />
                </label>
                <label>
                  Name
                  <input name="name" required />
                </label>
                <label>
                  Symbol
                  <input name="symbol" required />
                </label>
                <label>
                  Quantity decimals
                  <input
                    defaultValue="0"
                    max="8"
                    min="0"
                    name="quantityScale"
                    type="number"
                  />
                </label>
                <button className="button secondary" disabled={!data.canManage}>
                  Add unit
                </button>
              </form>
              <form action={createLocation} className="sub-card inventory-form">
                {hiddenOrganization(organizationId)}
                <h3>Location / Lokasi</h3>
                <label>
                  Code
                  <input name="code" required />
                </label>
                <label>
                  Name
                  <input name="name" required />
                </label>
                <button className="button secondary" disabled={!data.canManage}>
                  Add location
                </button>
              </form>
            </div>
            <form
              action={createCatalogItem}
              className="configuration-form inventory-item-form"
            >
              {hiddenOrganization(organizationId)}
              <label>
                Type
                <select name="itemKind">
                  <option value="product">Product</option>
                  <option value="service">Service</option>
                </select>
              </label>
              <label>
                Name
                <input name="name" required />
              </label>
              <label>
                SKU
                <input name="sku" required />
              </label>
              <label>
                Barcode
                <input name="barcode" />
              </label>
              <label>
                Category
                <select name="categoryId">
                  <option value="">None</option>
                  {data.categories
                    .filter((x) => x.status === "active")
                    .map((x) => (
                      <option key={x.id} value={x.id}>
                        {x.code} · {x.name}
                      </option>
                    ))}
                </select>
              </label>
              <label>
                Unit
                <select name="unitId">
                  {data.units
                    .filter((x) => x.status === "active")
                    .map((x) => (
                      <option key={x.id} value={x.id}>
                        {x.code} · {x.symbol}
                      </option>
                    ))}
                </select>
              </label>
              <label className="check-label">
                <input name="inventoryTracked" type="checkbox" /> Track
                inventory
              </label>
              <label>
                Inventory asset account
                <select name="inventoryAccountId">
                  <option value="">Select when tracked</option>
                  {assetAccounts.map((x) => (
                    <option key={x.id} value={x.id}>
                      {x.code} · {x.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Low-stock threshold
                <input
                  defaultValue="0"
                  inputMode="decimal"
                  name="lowStockThreshold"
                />
              </label>
              <button className="button primary" disabled={!data.canManage}>
                Add item
              </button>
            </form>
            <div className="accounting-table">
              <div className="inventory-item-row table-header">
                <span>SKU</span>
                <span>Item</span>
                <span>Kind</span>
                <span>Tracked</span>
                <span>Status / action</span>
              </div>
              {data.products.map((item) => (
                <div className="inventory-item-row" key={item.id}>
                  <span>{item.sku}</span>
                  <strong>{item.name}</strong>
                  <span>{item.item_kind}</span>
                  <span>{item.inventory_tracked ? "yes" : "no"}</span>
                  <form action={setCatalogItemStatus} className="inline-form">
                    {hiddenOrganization(organizationId)}
                    <input name="productId" type="hidden" value={item.id} />
                    <input
                      name="status"
                      type="hidden"
                      value={item.status === "active" ? "inactive" : "active"}
                    />
                    <span>
                      {item.status} · {item.low_stock_threshold}
                    </span>
                    <button
                      className="text-button"
                      disabled={!data.canManage}
                      type="submit"
                    >
                      {item.status === "active" ? "Deactivate" : "Reactivate"}
                    </button>
                  </form>
                </div>
              ))}
            </div>
          </section>

          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">02</p>
                <h2>{t.inventoryValuation}</h2>
              </div>
              <p>Calculated state; never directly editable.</p>
            </div>
            <div className="accounting-table">
              <div className="inventory-value-row table-header">
                <span>Product</span>
                <span>Location</span>
                <span>Quantity</span>
                <span>Average cost</span>
                <span>Value</span>
              </div>
              {data.valuation.map((row) => (
                <div
                  className="inventory-value-row"
                  key={`${row.product_id}-${row.location_id}`}
                >
                  <span>
                    {row.sku} · {row.product_name}
                  </span>
                  <span>{row.location_code}</span>
                  <span>{row.quantity_on_hand}</span>
                  <span>{row.average_unit_cost}</span>
                  <strong>{row.inventory_value}</strong>
                </div>
              ))}
            </div>
            <h3>{t.lowStock}</h3>
            <div className="metadata-list">
              {data.lowStock.map((row) => (
                <article key={`${row.product_id}-${row.location_id}`}>
                  <p>
                    <strong>
                      {row.sku} · {row.product_name}
                    </strong>
                    <span>{row.location_name}</span>
                  </p>
                  <span>
                    {row.quantity_on_hand} ≤ {row.low_stock_threshold}
                  </span>
                </article>
              ))}
            </div>
          </section>

          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">03</p>
                <h2>{t.stockMovement}</h2>
              </div>
              <p>
                Every change records source, reason, quantity, value, and
                journal.
              </p>
            </div>
            <form
              action={postInventoryMovement}
              className="configuration-form inventory-movement-form"
            >
              {hiddenOrganization(organizationId)}
              <input
                name="idempotencyKey"
                type="hidden"
                value={`movement-${randomUUID()}`}
              />
              <ProductAndLocationFields
                locations={data.locations}
                products={data.products}
              />
              <label>
                Movement
                <select name="movementKind">
                  <option value="opening">Opening stock</option>
                  <option value="stock_in">Stock in</option>
                  <option value="stock_out">Stock out</option>
                  <option value="adjustment_in">Adjustment in</option>
                  <option value="adjustment_out">Adjustment out</option>
                  <option value="damage_loss">Damage / loss</option>
                </select>
              </label>
              <label>
                Date
                <input defaultValue={today()} name="movementDate" type="date" />
              </label>
              <label>
                Quantity
                <input inputMode="decimal" name="quantity" required />
              </label>
              <label>
                Inbound unit cost
                <input inputMode="decimal" name="unitCost" />
              </label>
              <label>
                Offset account
                <select name="offsetAccountId">
                  {offsetAccounts.map((x) => (
                    <option key={x.id} value={x.id}>
                      {x.code} · {x.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Reference
                <input name="sourceReference" />
              </label>
              <label>
                Reason
                <input name="reason" required />
              </label>
              <button
                className="button primary"
                disabled={!data.canManage || trackedProducts.length === 0}
              >
                Post movement
              </button>
            </form>
          </section>

          <div className="accounting-form-grid">
            <form action={postStockCount} className="card accounting-form">
              {hiddenOrganization(organizationId)}
              <input
                name="idempotencyKey"
                type="hidden"
                value={`count-${randomUUID()}`}
              />
              <h2>Stock count / Hitung stok</h2>
              <ProductAndLocationFields
                locations={data.locations}
                products={data.products}
              />
              <label>
                Date
                <input defaultValue={today()} name="movementDate" type="date" />
              </label>
              <label>
                Counted quantity
                <input inputMode="decimal" name="countedQuantity" required />
              </label>
              <label>
                Unit cost only if no cost exists
                <input inputMode="decimal" name="unitCostIfEmpty" />
              </label>
              <label>
                Variance account
                <select name="offsetAccountId">
                  {offsetAccounts.map((x) => (
                    <option key={x.id} value={x.id}>
                      {x.code} · {x.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Reason
                <input name="reason" required />
              </label>
              <button
                className="button primary"
                disabled={!data.canManage || trackedProducts.length === 0}
              >
                Post count variance
              </button>
            </form>
            <form action={postTransfer} className="card accounting-form">
              {hiddenOrganization(organizationId)}
              <input
                name="idempotencyKey"
                type="hidden"
                value={`transfer-${randomUUID()}`}
              />
              <h2>Location transfer / Pindah lokasi</h2>
              <label>
                Product
                <select name="productId">
                  {trackedProducts.map((x) => (
                    <option key={x.id} value={x.id}>
                      {x.sku} · {x.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                From
                <select name="fromLocationId">
                  {data.locations.map((x) => (
                    <option key={x.id} value={x.id}>
                      {x.code} · {x.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                To
                <select name="toLocationId">
                  {data.locations.map((x) => (
                    <option key={x.id} value={x.id}>
                      {x.code} · {x.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Date
                <input defaultValue={today()} name="movementDate" type="date" />
              </label>
              <label>
                Quantity
                <input inputMode="decimal" name="quantity" required />
              </label>
              <label>
                Reason
                <input name="reason" required />
              </label>
              <button
                className="button primary"
                disabled={
                  !data.canManage ||
                  trackedProducts.length === 0 ||
                  data.locations.length < 2
                }
              >
                Post transfer
              </button>
            </form>
          </div>

          <section className="card settings-section">
            <div className="settings-heading">
              <div>
                <p className="eyebrow">04</p>
                <h2>{t.movementHistory}</h2>
              </div>
              <p>Immutable before/after costing evidence.</p>
            </div>
            <div className="accounting-table">
              <div className="inventory-history-row table-header">
                <span>Date</span>
                <span>Kind</span>
                <span>Product</span>
                <span>Location</span>
                <span>Qty Δ / after</span>
                <span>Cost / value Δ</span>
              </div>
              {data.movements.map((row) => {
                const product = data.products.find(
                  (x) => x.id === row.product_id,
                );
                const location = data.locations.find(
                  (x) => x.id === row.location_id,
                );
                return (
                  <div className="inventory-history-row" key={row.id}>
                    <span>{row.movement_date}</span>
                    <span>{row.movement_kind}</span>
                    <span>{product?.sku ?? row.product_id}</span>
                    <span>{location?.code ?? row.location_id}</span>
                    <span>
                      {row.quantity_delta} / {row.quantity_after}
                    </span>
                    <span>
                      {row.applied_unit_cost} / {row.value_delta}
                    </span>
                  </div>
                );
              })}
            </div>
          </section>
        </div>
      )}
    </section>
  );
}
