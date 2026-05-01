# Draft Email — OCIO Response to OCHCO Benefits Overpayment Tool Request

**To:** Sharon [OCHCO]
**From:** Derek Gordon, OCIO
**CC:** Siva
**Subject:** RE: OCHCO Benefits Coding Tool — What OCIO Can Deliver

---

Sharon,

Thanks for the conversation with Siva and for flagging the benefits overpayment
issue. We reviewed the Core HCM scope slide and your team's needs, and I want to
outline what OCIO can deliver within the constraints OPM has set.

## What we can build

Payroll and benefits are explicitly out of scope for Core HCM, which means EEOC
retains full latitude to build tooling in this area without conflicting with OPM's
directive.

We have an existing AI platform (already in ATO review) that includes data
ingestion, anomaly detection, audit logging, dashboard infrastructure, and an
**AI Assistant** that EEOC staff already use for case-related work. We can
extend it with a **Benefits Coding Validation and Overpayment Detection** module
that does the following:

1. **AI Assistant integration** — The most immediate value. Once benefits data
   is connected, HR specialists can ask questions in plain English through the
   same AI Assistant the agency already uses: "Show me all open overpayment
   cases from Q2," "What's the error rate for FEHB enrollments this year,"
   "Pull the benefits action history for case 12345." The assistant
   automatically respects role-based access — a specialist sees only what
   their role permits, a manager sees their team's data, and leadership sees
   aggregate trends. No separate login, no new tool to learn.

2. **Pre-submission validation** — Before a personnel action is finalized, the
   tool cross-references the benefits coding (FEHB, FEGLI, TSP, FERS/CSRS
   elections) against the action type, employee record, and OPM coding rules.
   Mismatches are flagged before they reach payroll.

3. **Post-processing anomaly detection** — For actions already processed, a
   batch review identifies coding patterns that historically correlate with
   overpayments: duplicate deductions, plan codes that don't match eligibility,
   coverage changes without a qualifying life event, etc.

4. **Overpayment case tracking** — When an error is confirmed, the tool
   generates an overpayment record with the affected pay periods, calculated
   dollar impact, and the corrective action code needed. This gives your team
   a clean audit trail for debt collection or waiver processing.

5. **Natural-language search across HR data** — Beyond overpayments, the AI
   Assistant becomes a research tool for OCHCO. Staff can query benefits
   election data, personnel action history, and coding patterns without
   writing reports or pulling exports. The system enforces the same access
   controls as the web UI — it will not return data the user's role does not
   permit.

6. **Dashboard and reporting** — Leadership visibility into error rates by
   action type, processing office, and time period. Trend analysis to identify
   systemic issues vs. one-off mistakes.

All AI-assisted analysis carries a signed audit log with 7-year retention per
NARA requirements, and every flagged item requires human review before any
corrective action is taken. No automated changes to employee records.

## What we need from OCHCO to move forward

To scope and build this correctly, we need answers to the following:

1. **Source system access** — Where does benefits coding currently live? Is it
   in NFC's payroll system, an internal EEOC database, or a combination? What
   system of record holds the SF-52 / personnel action data before it goes to
   NFC?

2. **Data format and feed** — Can we get a read-only data feed (API, database
   view, or scheduled file export) from the payroll/benefits system? What
   format — CSV, fixed-width, database connection? How frequently is it
   updated?

3. **Error taxonomy** — Does OCHCO maintain a list of the most common coding
   errors and their root causes? Even an informal list from the team would
   help us build the validation rules. How many overpayment cases per year are
   we talking about, roughly?

4. **Business rules source** — Where are the OPM coding rules documented? Are
   they in the Guide to Processing Personnel Actions (GPPA), a local SOP, or
   tribal knowledge? We need the authoritative source to build validation
   logic.

5. **Integration constraints** — Are there any systems OCHCO uses that OPM has
   flagged as needing to sunset under Core HCM? We want to make sure we
   integrate with systems that will persist, not ones being retired.

6. **User base and access** — Who would use the tool? HR specialists only, or
   also managers who initiate actions? How many users, and do they all have
   EEOC network accounts (Entra ID)?

7. **Timeline and priority** — Is this tied to the mid-year funding request
   mentioned in your note? What's the desired go-live, and is there a
   particular pain point (e.g., a specific benefit type or action type) we
   should target first for a pilot?

8. **Search and query scope** — Beyond overpayment detection, the AI
   Assistant can answer ad-hoc questions against any benefits data we
   ingest ("How many FEHB enrollments changed last quarter?", "What's
   our error rate by action type?"). What data sets would be most
   valuable for your team to be able to search conversationally? This
   helps us decide what to connect first.

9. **OCHCO AI champion** — Per your suggestion, who should be our day-to-day
   point of contact for requirements and testing?

## Regarding Copilot training

Glad the Phase I training was well received. We are happy to continue
coordinating with Judith's team on the no-cost AI training opportunities
through TEDD. Once we have the survey feedback summary, we can align Phase II
content with the areas where staff want deeper coverage.

Happy to set up a working session with your designated contact to walk through
the architecture and start scoping. Let us know who to coordinate with and
we'll get time on the calendar.

Derek
