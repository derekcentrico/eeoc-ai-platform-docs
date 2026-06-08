# Email: ARC / Non-ARC Database Separation and Document Vectorization

**Author:** Derek Gordon

**To:** Carlton Hadden, CIO
**CC:** Office of General Counsel, Elahi, Sudha
**Subject:** Two-database separation, document vectorization, and the de-identification OGC asked to review

---

This responds to the two requests from our last review: keep ARC charge data
from sharing a database with OCHCO, CFO, and other office data, and make Alfresco
documents searchable by meaning while keeping access locked to the people who may
see the underlying charge. The two are coupled, so this note covers both and ends
with a concrete redaction sample for OGC to rule on.

The build is staged. The database separation and the metadata search are live.
The full document-text path is built but turned off, and stays off until OGC
approves what de-identification produces. The rest of this note explains each
piece and where the controls sit.

---

## 1. Two Databases on One Server

ARC charge data and the non-ARC office data now live in separate PostgreSQL
databases on the same Flexible Server instance:

- `arc_analytics` - charge-centric data: charges, ADR outcomes, investigations,
  charge-scoped documents and their embeddings.
- `enterprise` - OCHCO, CFO, and HR data, plus documents that have no parent
  charge.

One server keeps the cost and operational footprint flat; two databases mean ARC
charge data and office data never share a schema or a connection. Backups run at
the Flexible Server level and cover both databases, so backup isolation is not
part of this separation - the boundary is the schema and connection, with access
within each database enforced by the row-level access rules in section 3. The AI
layer holds a connection to each and queries both when a question spans sources,
but every query runs under the access rules of the database it touches.

```
                 PostgreSQL Flexible Server (one instance)
   ┌──────────────────────────────┐   ┌──────────────────────────────┐
   │        arc_analytics         │   │          enterprise          │
   │  charges, ADR, investigations│   │   OCHCO / CFO / HR, non-charge│
   │  charge-scoped documents     │   │   documents                  │
   └───────────────┬──────────────┘   └───────────────┬──────────────┘
                   │                                   │
                   └──────────────┬────────────────────┘
                                  │
                       ┌──────────┴──────────┐
                       │   AI Assistant       │
                       │   federated retrieval│
                       └──────────────────────┘
```

Existing OCHCO and CFO data was the only data that moved; no application reads it
yet, so the move carried low risk. The charge database was renamed in place. The
cutover steps are written down in the `eeoc-data-analytics-and-dashboard`
repository, in `Database_Separation_Cutover_Runbook.md`.

---

## 2. Document Vectorization in Three Phases

Vectorization turns a document into numbers that capture its meaning, so a search
for "retaliation after FMLA leave" can find the right position statement even when
those exact words do not appear. The risk is that this same math can surface a
document a user is not allowed to see, if the link to the parent charge is not
enforced at search time. The phasing below exists so OGC and OCIO can approve the
sensitive parts only after seeing what they produce.

| Phase | What is vectorized | PII exposure | RBAC enforcement | Status |
|---|---|---|---|---|
| 1 | Document metadata only (title, type, office, region, charge number, dates) | None - no document body | Row-level security on the document registry: region, office, domain, PII tier | **Live** |
| 2 | Body text of documents with no PII after redaction | None after redaction | Same row-level security, plus the federated intersection guard | Built, gated off (`ALFRESCO_PHASE2_NONPII_ENABLED=false`) |
| 3 | Body text of PII-bearing documents, stored **redacted only** | Redacted before any text is stored | Same controls; raw text never enters the store | Built, gated off (`ALFRESCO_PHASE3_PII_ENABLED=false`) |

A fourth control sits over Phases 2 and 3: review mode
(`ALFRESCO_REDACTION_REVIEW_MODE=true`, the default). While it is on, the
redaction stage writes its output to a review table and writes **nothing** to the
chunk store or the vector index. This is the control that lets OGC see exactly
what de-identification produces before any document text - redacted or not -
enters the search system. With the shipped defaults, the entire body-text path is
inert; only Phase 1 metadata flows.

---

## 3. Intersection Access: A Result Must Clear Both Gates

ARC enforces access at the case level - if you cannot see charge
`2024-CHI-00413`, you cannot see it at all. The platform adds an enterprise-wide
layer: domain and application grants that say which data domains (for example
`ochco`, `cfo`) and PII tiers a user may reach. A document search can cross both
worlds, so the rule is deny-by-default at the intersection: a result is returned
only when the user passes **both** gates.

- **Source gate (in the database).** Row-level security on each database filters
  every query by region, office, domain, and PII tier before a row is returned.
  A charge-scoped document inherits its charge's region and office, so the same
  predicate that protects the charge protects its documents.
- **Systemwide gate (in the retrieval layer).** On top of the database filter,
  the retrieval layer re-checks the user's domain grant and PII tier and keeps a
  row only if it clears both. The two gates are an AND, not an OR.

A worked example: an investigator with full ARC access to a charge but no
`benefits` domain grant can retrieve that charge's documents and will **not**
retrieve any OCHCO benefits document, even on a query that matches it
semantically. Every retrieval writes a signed, seven-year audit record that
records how many rows each database returned and how many survived the
intersection guard, so the filtering is provable after the fact.

A subtle failure mode drove one design choice. Earlier, the row-level policies on
the charge and document tables were written as separate rules that PostgreSQL
combines with OR - so a non-PII charge in the wrong region was visible to
everyone, because the "non-PII" rule passed on its own. The policies are now a
single combined rule that requires region AND office AND domain AND PII tier
together. Privileged reviewers (the Director, Legal Counsel, and Admin roles)
bypass the region and office gates but never the PII-tier gate.

---

## 4. What De-Identification Strips - For OGC

This is the part OGC asked to rule on. Before any document body is chunked or
embedded, it passes through a redaction stage. Two layers run:

1. Pattern matching for structured identifiers - Social Security numbers, email
   addresses, phone numbers, employer identification numbers, ZIP codes, and
   dates of birth. These use the same rules already applied to the charge
   narratives OGC reviews today, so a document is de-identified the same way a
   narrative is.
2. Named-entity recognition for free-text identifiers - person names and
   locations. Each name is replaced with a stable token derived from the
   platform's salted one-way hash - the same keyed PII hash used across the
   platform, with the salt held in Key Vault - so the same person reads as the
   same token throughout a document and an analyst can still follow who did what
   without seeing the name. The salt is what stops someone from reversing a token
   back to a name by precomputing hashes of common names.

Each document produces a manifest: a count of how many identifiers of each kind
were removed. That manifest, and the redacted text, are what land in the review
table for OGC to read.

### 4.1 Sample

Source position-statement excerpt (illustrative, not a real charge):

```
Charging Party Maria Gonzalez (SSN 412-55-9087, DOB 03/14/1979) reported the
incident to her supervisor, James Whitfield, on May 2. She can be reached at
mgonzalez@example.com or (312) 555-0148. Respondent Acme Logistics (EIN
36-4099210) is located at 200 W Adams St, Chicago, IL 60606.
```

After redaction, this is what enters the review table - and, only with OGC
approval and Phase 3 turned on, the vector store:

```
Charging Party [NAME_8f3a1c0d] (SSN [SSN_REDACTED], DOB [DOB_REDACTED]) reported
the incident to her supervisor, [NAME_b71e09a4], on May 2. She can be reached at
[EMAIL_REDACTED] or [PHONE_REDACTED]. Respondent [NAME_2d5fa6b1] (EIN
[EIN_REDACTED]) is located at [ADDR_REDACTED], [ADDR_REDACTED], IL [ZIP_REDACTED].
```

De-identification manifest for this excerpt:

| Category | Removed |
|---|---|
| Name | 3 |
| SSN | 1 |
| Date of birth | 1 |
| Email | 1 |
| Phone | 1 |
| EIN | 1 |
| Address | 2 |
| ZIP | 1 |

The same person reads as the same token across the document - Maria Gonzalez is
`[NAME_8f3a1c0d]` wherever she appears - so the text stays usable for analysis
while the identity is gone. The manifest above is the evidence OGC reviews to
decide whether the output is de-identified enough to approve Phase 2, Phase 3, or
neither.

---

## What Changes and What Stays the Same

**What does not change:**

- ARC case-level access. A user who cannot see a charge still cannot see it, its
  documents, or its embeddings.
- The de-identification rules. Documents are stripped with the same patterns
  already used on charge narratives.
- The default posture. The full document-text path ships off. Only Phase 1
  metadata is live.

**What is added:**

- A clean split between ARC charge data and non-ARC office data, on one server.
- Semantic search over document metadata today, and over document text once OGC
  approves the de-identification output.
- A deny-by-default intersection rule that reconciles ARC case-level access with
  enterprise-wide domain grants, with a signed audit record on every retrieval.

The decision in front of OGC is narrow: review the redaction output in the review
table and decide whether to approve Phase 2 (non-PII document text), Phase 3
(PII-bearing document text, stored redacted), or to keep both off pending changes
to what is stripped. Nothing in Phase 2 or Phase 3 moves until that decision.
