# SimpleChat — Feature Inventory and Adoption Analysis for the Platform AI Assistant

**From:** Derek Gordon, EEOC Platform Architect
**Date:** June 2, 2026
**Subject:** Which SimpleChat modules to adopt, wire similarly, or skip in the governed Assistant

---

## Executive Summary

SimpleChat (microsoft/simplechat) is a Microsoft open-source sample chat application built on
Azure OpenAI, Azure AI Search, Cosmos DB, and Document Intelligence. As a standalone deployment
it is the wrong fit for case work — it has no NARA-grade AI audit, no PII redaction before the
model, no legal-output guardrails, and per-instance RBAC that does not align with our unified
access control. That analysis lives in the CIO decision email and is not repeated here.

This document covers the other half of the question: SimpleChat ships several **feature patterns**
worth pulling into our own Assistant, where they would run behind the controls SimpleChat lacks.
The point is not to import SimpleChat code — it is a sample with its own identity and role model —
but to reimplement the useful patterns inside the Assistant, behind the existing audit logger, PII
redaction, and RBAC.

Governing rule for everything below: any feature that **makes an AI call** (metadata extraction,
classification, content safety) must route through the HMAC-signed WORM audit logger and PII
redaction; any feature that **stores documents** must respect row-level security and the unified
access model, not a per-instance role table.

---

## Adopt — high value, clear fit

| Feature (SimpleChat name) | What it does | Why it fits EEOC | Effort | Governance overlay required |
|---|---|---|---|---|
| **Ephemeral (single-conversation) documents** | Upload a file available only for the current chat; never indexed | Lets an attorney drop a deposition or exhibit into one session without persisting it to a shared index — common for one-off review | Low | Still runs through PII redaction + audit; nothing written to the vector store or retained past the session |
| **Structure-aware chunking** | Chunking tuned to content type rather than fixed-size splits | This is the real investment. Deposition-aware chunking (page:line, Q-and-A turns, condensed four-up transcripts, colloquy) is the capability that matters most to OGC and is where a generic chunker fails | Moderate–High | Improves citation fidelity; no new AI-call surface |
| **Enhanced Citation** | Links answers to source page numbers (or timestamps) | Extend our existing citation to deposition **page:line**, so the AI points at the exact line a witness gave an answer | Low–Moderate | Pairs with structure-aware chunking; verification stays on |
| **Metadata Extraction** | Auto keyword, summary, and author/date inference on ingest | Useful for exhibit and deposition intake — surfaces a summary and key terms without manual tagging | Moderate | Extraction is an AI call → must be audited and PII-masked like any other generation |
| **Document Classification** | Custom document types with color coding | Organizes case documents (transcript, exhibit, motion, correspondence) for faster retrieval and filtering | Low–Moderate | Classification labels are metadata; if AI-assisted, audit the call |

---

## Consider — medium value, situational

| Feature | What it does | Why it might fit | Effort | Notes |
|---|---|---|---|---|
| **Feedback System** | Thumbs up/down on AI responses with an admin dashboard | Feeds the signals our RelianceScorer and ModelDriftDetector already consume; the backend exists, this adds the capture UI and a dashboard | Low | Tie ratings into the existing drift/reliance pipeline rather than a separate store |
| **File Processing Logs** | Per-file ingestion pipeline visibility | Operational insight into deposition/exhibit parsing — which files chunked cleanly, which failed | Low | Logs must mask PII; surface to admins only |
| **Content Safety pre-screen** | Azure AI Content Safety review before the model processes a message | Additive guardrail in front of our legal stop sequences and cite-or-silence | Low | Complement, not replace, existing guardrails |
| **Governed office/group workspaces** | Shared per-group document spaces with role-based access | A governed, role-scoped shared space per office could replace ad-hoc document sharing | Moderate | Must bind to the unified access model and ARC roles — not SimpleChat's standalone Admin/CreateGroup roles |

---

## Skip or defer — not a current need or a governance risk

| Feature | Disposition | Rationale |
|---|---|---|
| **Audio transcription (Azure Speech)** | Defer — build on request only | Staff do not transcribe audio for casework. Same Azure endpoint we can wire behind our audit layer in days if an office ever asks; not a gap |
| **Video transcription / OCR (Azure Video Indexer)** | Defer — build on request only | Same as above; no current staff need |
| **Image generation (DALL-E)** | Skip | No casework use |
| **Bing Web Search augmentation** | Skip | External egress from the model context — a data-boundary risk our CISO would not accept inside the FedRAMP posture |
| **SQL Database Agents (auto schema discovery)** | Skip — already covered | We already run governed text-to-SQL in UDAP with AST validation; SimpleChat's pattern adds little and its auto-discovery widens the query surface |

---

## Implementation guidance

1. **Reimplement, do not import.** SimpleChat is a sample with its own identity, role table, and
   Cosmos schema. Pull the pattern, not the code, into the Assistant's existing modules.
2. **Sequence by the real need.** Structure-aware (deposition-aware) chunking and enhanced page:line
   citation are the highest-value pair and should lead; the others are additive UX and operations.
3. **Every AI-call feature inherits the platform controls automatically.** Metadata extraction,
   classification, and content safety route through `ai_audit_logger` (HMAC dual-write to Table +
   7-year WORM Blob) and PII redaction the same way settlement drafting and triage classification
   already do. This is why adding them is wiring, not a new compliance build.
4. **Every storage feature inherits RLS and unified RBAC.** Ephemeral documents, classification
   labels, and office workspaces bind to the existing access model, so an analyst never sees another
   office's documents.

---

## Related documents

- CIO decision email — standalone SimpleChat / Open WebUI vs. the platform Assistant (governance
  comparison and recommendation)
- `platform-docs/Leadership_AI_Assistant_Architecture.md` — current Assistant architecture
- AI audit logging pattern (HMAC dual-write, WORM retention) — platform AI governance reference
