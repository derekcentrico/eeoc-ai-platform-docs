# OFP Investigative Toolkit Request vs. OGC Trial Tool — Cross-Comparison

**From:** Derek Gordon, EEOC Platform Architect  
**Date:** April 22, 2026  
**Subject:** Investigative Toolkit Request — Existing Capability Overlap and Platform Alignment

---

## Executive Summary

The OFP Investigative Toolkit request describes a cloud-based application hosting discrete, task-specific AI tools with structured inputs, hidden prompts, and multi-format outputs (text, DOCX, EML, XLSX). **This architecture already exists.** The OGC Trial Tool, built on the same Azure OpenAI / AI Foundry stack as ADR Portal and UDIP, provides exactly this pattern today — a web-based directory of AI tools with file upload, structured inputs, static prompts, and multi-format output. The requested toolkit can be delivered as a new module within the existing platform rather than built from scratch.

---

## Architecture Alignment

| OFP Requirement | Already Built in Trial Tool |
|---|---|
| Internal, cloud-based application | Azure Government App Service (FedRAMP High authorized) |
| Directory of discrete, task-specific tools | Dashboard with 9 AI tools, each with its own UI, prompt, and output format |
| Structured data inputs (text fields, file upload) | Case name text input, multi-file upload (PDF, DOCX, TXT), drag-drop via Dropzone.js |
| Non-visible, static prompt sent with user data | Every tool has a server-side system prompt invisible to the user; prompt text stored in `full_context_llm.py` |
| Generative AI service call on submit | Azure OpenAI GPT-4o via managed identity; provider-agnostic abstraction supports Azure AI Foundry as well |
| Output displayed as text and/or file download | Markdown text display, plus DOCX, EML, and XLSX export already implemented |
| Adding tools on an ongoing basis | Feature-flagged tool architecture (`FEATURE_QA=1`, `FEATURE_TIMELINE=1`, etc.) — new tools are additive, not disruptive |

**Key point:** The Trial Tool uses the same Azure OpenAI deployment and AI Foundry model provider abstraction as ADR Portal and UDIP. All three share `foundry_model_provider.py`, the same NARA-compliant audit logger, and the same managed identity authentication to Azure OpenAI. This is not a coincidence — it was designed as a shared platform layer.

---

## Tool-by-Tool Comparison

### 1. RFP Response Analysis Tool

| Aspect | OFP Request | Trial Tool Equivalent |
|---|---|---|
| **Purpose** | Compare an RFI against its response; identify gaps, objections, and what was provided | **Q&A Tool** — extracts exact answers from uploaded documents against specific questions; returns direct evidence with citations |
| **Inputs** | Charge number (text), RFI upload, RFI Response upload | Case ID (text), document uploads (PDF/DOCX/TXT), question (text) |
| **Prompt pattern** | "Closely review the RFI and RFI Response..." with structured output (bulleted list, per-request analysis) | "Extract exact quotes from the provided evidence..." with structured output (DIRECT EVIDENCE, INDIRECT EVIDENCE sections, citations) |
| **Output** | Multi-line text with introductory metadata and per-request breakdown | Markdown text with document/page/line citations |
| **Gap** | Trial Tool Q&A is question-driven, not document-comparison-driven. A new "Document Comparison" tool would wrap the same LLM call with a comparison-specific prompt. The upload pipeline, text extraction, and output rendering already exist. **Estimated lift: new prompt + new route, 1-2 days.** |

### 2. Rebuttal Request Tool

| Aspect | OFP Request | Trial Tool Equivalent |
|---|---|---|
| **Purpose** | Extract facts from a position statement, generate a structured rebuttal questionnaire, output as EML | **Impeachment Kit** — finds contradictions in depositions; **FOIA Export** — generates multi-format output packages including EML |
| **Inputs** | Charge number (text), position statement upload | Case ID, document uploads, proposition (text) |
| **Prompt pattern** | "Create a list of all facts... include citation to page and paragraph... generate EML with subject line and body" | "Find contradictions to this proposition..." with citations |
| **Output** | EML file with structured body (fact list, rebuttal questions, boilerplate text) | Markdown text with citations; EML generation exists in FOIA export |
| **Gap** | The fact-extraction and citation patterns exist. EML generation exists. A new "Rebuttal Generator" tool would combine the fact-extraction prompt with the EML output pipeline. **Estimated lift: new prompt + EML template wiring, 2-3 days.** |

### 3. Charge, Position Statement, & Rebuttal Analysis Tool

| Aspect | OFP Request | Trial Tool Equivalent |
|---|---|---|
| **Purpose** | Not fully specified in request, but implies cross-document analysis of charge + position statement + rebuttal | **Case Summary** — summarizes full case across all uploaded documents; **Comparator Analysis** — identifies treatment disparities; **Issue Matrix** — maps claims to facts |
| **Gap** | The multi-document analysis pattern is the Trial Tool's core strength. A charge/PS/rebuttal analysis tool would use the same document ingestion pipeline with an investigation-specific prompt. **Estimated lift: new prompt, 1-2 days.** |

### 4. Unstructured Inquiry Summary Tool

| Aspect | OFP Request | Trial Tool Equivalent |
|---|---|---|
| **Purpose** | Not fully specified, but implies summarizing unstructured inquiry data | **Case Summary** — summarizes unstructured case documents across depositions and exhibits |
| **Gap** | The summarization pattern exists. An inquiry-specific variant would need a tailored prompt for investigation-stage documents vs. litigation-stage documents. **Estimated lift: new prompt, 1 day.** |

---

## What the Trial Tool Already Has That OFP Will Need

These capabilities are not mentioned in the OFP request but are required for any production AI tool at EEOC:

| Capability | Status | Why It Matters |
|---|---|---|
| **NARA 7-year AI audit logging** | Built, WORM-enforced | Every AI generation is HMAC-signed and archived. Required by NARA and validated during 2025 OIG inquiry. |
| **FedRAMP High compliance** | Built, documented | Azure Government, managed identity auth, Key Vault secrets, CSP headers, CSRF protection. |
| **Section 508 / WCAG 2.1 AA** | Built, audited | 4.5:1 contrast, keyboard navigation, screen reader support. Federal law. |
| **Document processing pipeline** | Built | PDF text extraction, OCR (Tesseract), DOCX parsing, witness deduction, deduplication. |
| **Role-based access control** | Built | Attorney, supervisory attorney, deputy, director, admin roles via Entra ID groups. |
| **PII protection** | Built | HMAC-SHA256 hashing of user identifiers, no PII in logs. |
| **Stop sequences for legal AI** | Built | `["Legal Advice:", "Legal Conclusion:"]` on all legal-adjacent calls. |
| **Human-in-the-loop enforcement** | Built | Every AI output includes "system-generated, must be reviewed by staff" notice — exactly what OFP's prompts specify. |

---

## Delivery Approach

**Option A — Extend the Trial Tool** (recommended)

Add an "Investigative Tools" module to the existing Trial Tool. Each OFP tool becomes a new route with its own prompt template, sharing the existing:
- Document upload and text extraction pipeline
- Azure OpenAI / AI Foundry model provider
- AI audit logging (NARA compliance)
- Multi-format output (text, DOCX, EML, XLSX)
- Authentication, RBAC, and session management
- 508-compliant UI templates

The 4 requested tools could ship within 2-3 weeks. The "10-25 additional tools in 12 months" goal is realistic — each new tool is primarily a new prompt + route, not new infrastructure.

**Option B — Standalone Application**

Build a separate "Investigative Toolkit" application from scratch. This would duplicate every platform capability listed above. Not recommended unless there is a hard organizational boundary requiring separate deployments.

**Option C — Shared Tool Framework** (if OFP prefers independence)

Extract the shared platform layer (model provider, audit logger, document processor, output generators) into a shared library. OFP builds their own Flask app using that library. They get independence on UI and deployment while reusing the compliance-critical infrastructure. Middle ground if Option A feels too coupled.

---

## Summary Table

| OFP Requested Tool | Closest Trial Tool Feature | What's Missing | Effort |
|---|---|---|---|
| RFP Response Analysis | Q&A Tool + document pipeline | Comparison-specific prompt | 1-2 days |
| Rebuttal Request | Impeachment Kit + FOIA Export (EML) | Fact-extraction prompt + EML template | 2-3 days |
| Charge/PS/Rebuttal Analysis | Case Summary + Issue Matrix | Investigation-stage prompt | 1-2 days |
| Unstructured Inquiry Summary | Case Summary | Inquiry-specific prompt | 1 day |
| Directory / main page | Dashboard | OFP tool listing | 1 day |
| **10-25 future tools** | Feature-flag architecture | New prompts per tool | ~1-2 days each |

**Total for initial 4 tools + directory: approximately 2-3 weeks**, including testing and 508 compliance review.

---

## Bottom Line

OFP is describing an application pattern that already exists. The prompts are different, the user base is different, but the architecture — cloud app, structured inputs, hidden prompts, AI service call, formatted output — is identical to what ships today in the Trial Tool and ADR Portal. Building this on the existing platform means OFP gets NARA compliance, FedRAMP authorization, 508 accessibility, and AI audit logging on day one instead of building it from scratch.

Happy to walk through the Trial Tool demo or the shared architecture in more detail.
