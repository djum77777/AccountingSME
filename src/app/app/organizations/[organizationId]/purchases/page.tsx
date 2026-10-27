import { randomUUID } from "node:crypto";
import Link from "next/link";
import {
  addPurchaseLine,
  confirmPurchase,
  createPurchaseDraft,
  postPurchaseCredit,
  postSupplierPayment,
} from "@/app/actions/purchases";
import { getPurchasesData } from "@/data/purchases";
import { getTranslations } from "@/lib/i18n/server";

const dateOffset = (days: number) => {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString().slice(0, 10);
};

const hiddenOrganization = (organizationId: string) => (
  <input name="organizationId" type="hidden" value={organizationId} />
);

export default async function PurchasesPage({
  params,
}: {
  params: Promise<{ organizationId: string }>;
}) {
  const { organizationId } = await params;
  const [t, data] = await Promise.all([
    getTranslations(),
    getPurchasesData(organizationId),
  ]);
  const drafts = data.purchases.filter(
    (purchase) => purchase.status === "draft",
  );
  const expenseAccounts = data.accounts.filter(
    (account) => account.category === "expense",
  );
  const cashAccounts = data.accounts.filter(
    (account) =>
      account.system_purpose === "cash" || account.system_purpose === "bank",
  );
  const returnablePurchaseIds = new Set(
    data.purchases
      .filter(
        (purchase) =>
          (purchase.payment_mode === "credit" &&
            ["posted", "partially_paid"].includes(purchase.status)) ||
          (purchase.payment_mode === "cash" && purchase.status === "paid"),
      )
      .map((purchase) => purchase.id),
  );
  const creditableLines = data.lines.filter((line) =>
    returnablePurchaseIds.has(line.purchase_id),
  );
  const linesByPurchase = Map.groupBy(data.lines, (line) => line.purchase_id);
  const linksByPurchase = Map.groupBy(
    data.postingLinks,
    (link) => link.purchase_id,
  );

  return (
    <section>
      <div className="section-heading">
        <div>
          <p className="eyebrow">Phase 6 · Purchases & AP</p>
          <h1>{t.purchases}</h1>
          <p>
            {data.organization.display_name} ·{" "}
            {data.organization.base_currency_code}
          </p>
        </div>
        <div className="button-row compact">
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/parties`}
          >
            {t.parties}
          </Link>
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/inventory`}
          >
            {t.inventory}
          </Link>
          <Link
            className="button secondary"
            href={`/app/organizations/${organizationId}/accounting`}
          >
            {t.accounting}
          </Link>
        </div>
      </div>
      <p className="notice">{t.purchaseNotice}</p>

      <div className="settings-stack">
        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">01</p>
              <h2>{t.createPurchaseDraft}</h2>
            </div>
            <p>
              Product or service · cash or credit / Produk atau jasa · tunai
              atau kredit
            </p>
          </div>
          <form
            action={createPurchaseDraft}
            className="configuration-form purchase-form"
          >
            {hiddenOrganization(organizationId)}
            <label>
              {t.supplier}
              <select name="supplierPartyId" required>
                {data.suppliers.map((supplier) => (
                  <option key={supplier.id} value={supplier.id}>
                    {supplier.display_name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              {t.supplierInvoice}
              <input name="supplierInvoiceNumber" />
            </label>
            <label>
              {t.invoiceDate}
              <input
                defaultValue={dateOffset(0)}
                name="invoiceDate"
                type="date"
                required
              />
            </label>
            <label>
              {t.dueDate}
              <input
                defaultValue={dateOffset(30)}
                name="dueDate"
                type="date"
                required
              />
            </label>
            <label>
              {t.paymentMode}
              <select name="paymentMode">
                <option value="credit">{t.creditPurchase}</option>
                <option value="cash">{t.cashPurchase}</option>
              </select>
            </label>
            <label>
              Location / Lokasi
              <select name="inventoryLocationId">
                <option value="">Service only / Hanya jasa</option>
                {data.locations.map((location) => (
                  <option key={location.id} value={location.id}>
                    {location.code} · {location.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Cash / bank account · Akun kas / bank
              <select name="cashAccountId">
                <option value="">Credit purchase / Pembelian kredit</option>
                {cashAccounts.map((account) => (
                  <option key={account.id} value={account.id}>
                    {account.code} · {account.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              {t.documentDiscount}
              <input
                defaultValue="0"
                inputMode="decimal"
                name="documentDiscountAmount"
              />
            </label>
            <label>
              {t.additionalCost}
              <input
                defaultValue="0"
                inputMode="decimal"
                name="additionalCostAmount"
              />
            </label>
            <label>
              {t.notes}
              <input name="notes" />
            </label>
            <button
              className="button primary"
              disabled={!data.canManage || data.suppliers.length === 0}
            >
              {t.createPurchaseDraft}
            </button>
          </form>
        </section>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">02</p>
              <h2>{t.purchaseLines}</h2>
            </div>
            <p>Drafts remain editable until one atomic confirmation.</p>
          </div>
          <form
            action={addPurchaseLine}
            className="configuration-form purchase-line-form"
          >
            {hiddenOrganization(organizationId)}
            <label>
              Draft / Draf
              <select name="purchaseId" required>
                {drafts.map((purchase) => (
                  <option key={purchase.id} value={purchase.id}>
                    {purchase.document_number} ·{" "}
                    {purchase.supplier_name_snapshot}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Product / service · Produk / jasa
              <select name="catalogItemId" required>
                {data.products.map((product) => (
                  <option key={product.id} value={product.id}>
                    {product.sku} · {product.name} ({product.item_kind})
                  </option>
                ))}
              </select>
            </label>
            <label>
              Quantity / Kuantitas
              <input inputMode="decimal" name="quantity" required />
            </label>
            <label>
              Unit price / Harga satuan
              <input inputMode="decimal" name="unitPrice" required />
            </label>
            <label>
              Line discount / Diskon baris
              <input
                defaultValue="0"
                inputMode="decimal"
                name="lineDiscountAmount"
              />
            </label>
            <label>
              Line cost / Biaya baris
              <input
                defaultValue="0"
                inputMode="decimal"
                name="lineAdditionalCostAmount"
              />
            </label>
            <label>
              Service expense / Beban jasa
              <select name="expenseAccountId">
                <option value="">Product line / Baris produk</option>
                {expenseAccounts.map((account) => (
                  <option key={account.id} value={account.id}>
                    {account.code} · {account.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Description / Deskripsi
              <input name="description" />
            </label>
            <button
              className="button secondary"
              disabled={
                !data.canManage ||
                drafts.length === 0 ||
                data.products.length === 0
              }
            >
              {t.add}
            </button>
          </form>
          <div className="accounting-table">
            <div className="purchase-draft-row table-header">
              <span>Document</span>
              <span>Supplier</span>
              <span>Dates</span>
              <span>Lines</span>
              <span>Action</span>
            </div>
            {drafts.map((purchase) => {
              const lines = linesByPurchase.get(purchase.id) ?? [];
              return (
                <div className="purchase-draft-row" key={purchase.id}>
                  <strong>{purchase.document_number}</strong>
                  <span>{purchase.supplier_name_snapshot}</span>
                  <span>
                    {purchase.invoice_date} → {purchase.due_date}
                  </span>
                  <span>
                    {lines.length} ·{" "}
                    {lines
                      .map((line) => line.description_snapshot)
                      .join(", ") || "—"}
                  </span>
                  <form action={confirmPurchase} className="inline-form">
                    {hiddenOrganization(organizationId)}
                    <input
                      name="purchaseId"
                      type="hidden"
                      value={purchase.id}
                    />
                    <input
                      name="idempotencyKey"
                      type="hidden"
                      value={`confirm-${randomUUID()}`}
                    />
                    <button
                      className="button primary"
                      disabled={!data.canManage || lines.length === 0}
                    >
                      {t.confirmPurchase}
                    </button>
                  </form>
                </div>
              );
            })}
          </div>
        </section>

        <div className="accounting-form-grid">
          <form action={postSupplierPayment} className="card accounting-form">
            {hiddenOrganization(organizationId)}
            <input
              name="idempotencyKey"
              type="hidden"
              value={`payment-${randomUUID()}`}
            />
            <h2>{t.supplierPayments}</h2>
            <label>
              Invoice / Faktur
              <select name="purchaseAllocation" required>
                {data.openItems.map((item) => (
                  <option
                    key={item.purchase_id}
                    value={`${item.purchase_id}|${item.supplier_party_id}`}
                  >
                    {item.document_number} · {item.supplier_name_snapshot} ·{" "}
                    {item.outstanding_amount}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Date / Tanggal
              <input
                defaultValue={dateOffset(0)}
                name="paymentDate"
                type="date"
                required
              />
            </label>
            <label>
              Amount / Jumlah
              <input inputMode="decimal" name="amount" required />
            </label>
            <label>
              Cash / bank · Kas / bank
              <select name="cashAccountId" required>
                {cashAccounts.map((account) => (
                  <option key={account.id} value={account.id}>
                    {account.code} · {account.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Reference / Referensi
              <input name="sourceReference" />
            </label>
            <button
              className="button primary"
              disabled={!data.canManage || data.openItems.length === 0}
            >
              {t.supplierPayments}
            </button>
          </form>

          <form action={postPurchaseCredit} className="card accounting-form">
            {hiddenOrganization(organizationId)}
            <input
              name="idempotencyKey"
              type="hidden"
              value={`credit-${randomUUID()}`}
            />
            <h2>{t.supplierCredits}</h2>
            <label>
              Purchase line / Baris pembelian
              <select name="purchaseLine" required>
                {creditableLines.map((line) => (
                  <option
                    key={line.id}
                    value={`${line.id}|${line.purchase_id}`}
                  >
                    {line.description_snapshot} · {line.quantity}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Date / Tanggal
              <input
                defaultValue={dateOffset(0)}
                name="creditDate"
                type="date"
                required
              />
            </label>
            <label>
              Quantity / Kuantitas
              <input inputMode="decimal" name="quantity" required />
            </label>
            <label>
              Credit amount / Nilai kredit
              <input inputMode="decimal" name="creditAmount" required />
            </label>
            <label>
              Reason / Alasan
              <input name="reason" required />
            </label>
            <button
              className="button primary"
              disabled={!data.canManage || creditableLines.length === 0}
            >
              {t.supplierCredits}
            </button>
          </form>
        </div>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">03</p>
              <h2>{t.apAging}</h2>
            </div>
            <p>As of today / Per hari ini</p>
          </div>
          <div className="accounting-table">
            <div className="ap-aging-row table-header">
              <span>Invoice</span>
              <span>Supplier</span>
              <span>Due</span>
              <span>{t.outstanding}</span>
              <span>Bucket</span>
            </div>
            {data.aging.map((item) => (
              <div className="ap-aging-row" key={item.purchase_id}>
                <strong>{item.document_number}</strong>
                <span>{item.supplier_name}</span>
                <span>{item.due_date}</span>
                <span>{item.outstanding_amount}</span>
                <span>{item.aging_bucket}</span>
              </div>
            ))}
          </div>
        </section>

        <section className="card settings-section">
          <div className="settings-heading">
            <div>
              <p className="eyebrow">04</p>
              <h2>{t.purchaseHistory}</h2>
            </div>
            <p>{t.linkedEvidence}</p>
          </div>
          <div className="accounting-table">
            <div className="purchase-history-row table-header">
              <span>Document</span>
              <span>Supplier</span>
              <span>Total</span>
              <span>Status</span>
              <span>Inventory / journals</span>
            </div>
            {data.purchases.map((purchase) => {
              const links = linksByPurchase.get(purchase.id) ?? [];
              return (
                <div className="purchase-history-row" key={purchase.id}>
                  <span>
                    <strong>{purchase.document_number}</strong>
                    <small>{purchase.supplier_invoice_number || "—"}</small>
                  </span>
                  <span>{purchase.supplier_name_snapshot}</span>
                  <span>{purchase.total_amount}</span>
                  <span className={`status-pill ${purchase.status}`}>
                    {purchase.status}
                  </span>
                  <span>
                    {links.filter((link) => link.inventory_operation_id).length}{" "}
                    inventory ·{" "}
                    {new Set(links.map((link) => link.journal_entry_id)).size}{" "}
                    journals
                  </span>
                </div>
              );
            })}
          </div>
          <div className="purchase-ledger-summary">
            <p>
              {data.payments.length} payments / pembayaran ·{" "}
              {data.allocations.length} allocations / alokasi
            </p>
            <p>{data.credits.length} supplier credits / kredit pemasok</p>
          </div>
        </section>
      </div>
    </section>
  );
}
