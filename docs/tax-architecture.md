# Tax Architecture

## 1. Principle and scope

Indonesian tax logic is configurable, versioned, effective-dated, and reviewable. Tax law, rates, eligibility, registration thresholds, withholding, invoice requirements, and filing formats may change. No permanent rate or eligibility assumption is hard-coded into sales, purchase, expense, or UI components.

The product does not claim automatic tax compliance. Qualified Indonesian tax/accounting professionals must approve supported rules, calculations, wording, mappings, and effective dates before production use.

## 2. Separation of responsibilities

- The **tax catalog** stores curated rule-set versions and their authority/review provenance.
- The **organization tax profile** records registrations, elections, applicability, and effective dates.
- The **tax engine** selects eligible rules for a transaction context, calculates a proposal deterministically, and returns accounting intents.
- The **accounting engine** validates and posts resulting journal lines.
- The **reporting engine** uses stored tax snapshots; it does not recalculate history using current rules.

UI, OCR, and imports may suggest tax codes but cannot silently determine or post uncertain tax treatment.

## 3. Rule model

Each immutable tax rule version contains:

- stable rule family/type and jurisdiction;
- rate or tier structure;
- calculation base and inclusion/exclusion behavior;
- eligibility criteria and required organization/party/product attributes;
- rounding method and sequence;
- effective start and optional end date;
- ledger mapping requirements;
- authority/source citation, reviewer, approval state, and publication timestamp;
- engine compatibility/schema version.

Overlapping active rules in the same scope are rejected unless an explicit priority/composition policy is reviewed. Published rule versions are never edited; corrections create a successor version and document remediation needs.

## 4. Organization tax profile

Profiles are organization-owned, effective-dated, and audited. They may include taxpayer/registration attributes, enabled tax regimes, reporting preferences, and reviewed exemptions. Sensitive identifiers are encrypted or otherwise strongly protected and omitted from routine logs.

Changing a profile affects only transactions whose tax point occurs under the new effective state. Historical transactions retain their applied snapshot.

## 5. Calculation contract

Input includes organization, transaction kind, dates (including explicitly defined tax point), currency, party/product classification, line amounts/discounts, location/jurisdiction context if relevant, and requested tax treatment. Output includes selected rule version, eligibility decision, taxable base, rate, tax amount, rounding/residual detail, warnings, override state, and proposed ledger mappings.

Calculations use decimal arithmetic. The line-versus-document calculation and rounding order must be centrally defined and professionally approved. Every confirmed transaction persists enough input and output to reproduce its calculation.

## 6. Effective dating and change management

Rule selection uses the professionally approved tax-point date, not server time. Future rules can be staged and tested before their start date. Publication requires maker/checker review where feasible, automated regression fixtures, and a change note identifying affected flows and reports.

When guidance changes retroactively, the system does not rewrite posted records. It identifies potentially affected transactions and supports a reviewed adjustment/reversal workflow.

## 7. Overrides and uncertainty

Manual override requires permission, reason, original proposal retention, resulting calculation snapshot, and audit event. High-risk overrides may require owner or accountant approval. Ambiguous OCR/import tax data always produces `review_required`; it cannot become a confirmed tax treatment automatically.

## 8. Posting and reporting

Tax rule outputs map through protected organization accounts constrained by account type. The accounting engine owns final debit/credit construction. Tax reports disclose rule version, profile version, period, rounding basis, overrides, and unresolved warnings. Filing/export formats are separate adapters with their own versions and approval.

## 9. Required professional-review questions

- Which Indonesian tax types/regimes are in MVP, and which organizations/transactions are eligible?
- What date determines rule applicability for invoices, payments, advances, returns, and corrections?
- Are prices tax-inclusive or exclusive by default, and can this vary by line/document/customer?
- What rounding precision/order applies at line, document, journal, and filing level?
- How are discounts, shipping, fees, returns, bad debt, credit notes, and partial payments treated?
- Which input/output/withholding accounts and document evidence are required?
- Which taxpayer identifiers and invoice numbering/format rules must be validated?
- What rules apply to marketplaces, cross-region/cross-border sales, imports, and digital services?
- What retention, audit evidence, filing exports, and amendment workflows are required?
- Which rates, thresholds, exemptions, and effective dates are authoritative at launch?

Answers become versioned rule specifications and test fixtures, not informal code comments.
