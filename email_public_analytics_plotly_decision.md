Subject: Public Analytics - Plotly as the Tableau Replacement and the Public Data Boundary

Siva,

We need to put charts and data on the agency public website, and we want to stop
paying for and depending on Tableau to do it. Here is the direction I am
proposing, the reasoning behind each choice, and where the security boundary
sits so we are all comfortable that nothing internal can leak to the public
internet. RBAC was the first constraint I designed around, not the last.

---

**The decision in one line**

Use the open-source Plotly stack to pre-render a small set of curated,
de-identified charts to a private store, served to the public only through Front
Door with a WAF. Keep Superset for internal staff. No third-party reporting SaaS,
no live database path from the public internet.

---

**1. Charting library: Plotly (open source), not Dash Enterprise**

plotly.py 6.8.0 and plotly.js 3.5.1 are MIT licensed, so they clear our
no-GPL gate and add no licensing cost. Dash Enterprise is a separate paid product
whose value is managed hosting plus a turnkey auth and RBAC console. We already
run our own FedRAMP-High Azure environment and our own Entra ID and Login.gov
identity stack, so that value is redundant for us. Everything we need, including
access control and embedding, is doable on the free libraries. We are not buying
Dash Enterprise.

**2. We keep Superset; we are not replacing it**

Superset is our internal business-intelligence tool for staff: ad-hoc SQL
exploration, cross-filter dashboards, and scheduled reports, already wired to
row-level security and already accessibility-hardened. Tableau is the thing we
are replacing, and Tableau was never our internal tool. Superset also cannot
serve anonymous public traffic safely, so it was never going to be the public
mechanism regardless. The two tools serve different audiences, so they run side
by side. Superset keeps full ARC access for staff. Plotly is deliberately the
opposite: it is locked to the small scrubbed public dataset and cannot see ARC
case data at all. In the AI assistant, staff stay on the internal ARC data by
default; when they explicitly ask for a public chart, that one question is routed
onto the locked dataset and rendered with Plotly. The routing is an explicit
command, not a guess, so the data boundary is deterministic and auditable.

**3. Delivery: pre-render to a private store, serve through Front Door**

A scheduled job rebuilds each chart from the public dataset once a day and writes
the artifacts to a blob container. The container has public blob access turned
off. The only public ingress is Front Door with a WAF and rate limiting, reading
the container over a private origin. The publisher authenticates with a managed
identity. There is no open database port to the internet and no live query path a
visitor can reach.

**4. The data boundary (this is the part to scrutinize)**

The public data lives in its own database, physically separate from the
ARC-driven analytics database. It is not computed by reading the ARC case or
vector data. It is loaded only from a specially scrubbed feed pushed from IRD.
The transport is not finalized, so the loader takes a manual scrubbed CSV today
and an automated IRD transform later through the same interface. Several controls
stack here:

- The separate database has no link to the ARC database. A connection to the
  public database cannot query ARC tables at all, because the two are isolated
  databases with no cross-database access.
- The data holds aggregate counts only, never detail rows and never PII columns.
- Small-cell suppression is enforced twice: the loader drops any group with fewer
  than ten charges, and database constraints reject such a row if it slips
  through, so no figure can be traced back to an individual.
- A dedicated role, `public_analytics_reader`, can SELECT the aggregates and
  nothing else. The publisher and the AI assistant's public-chart mode both
  connect as this role.

Net effect: even a careless query in the public path returns aggregate, suppressed
numbers, because the role literally cannot see anything else.

**5. Accessibility (Section 508 is not optional)**

Plotly charts, like Tableau's, are not screen-reader or keyboard accessible on
their own. So every public chart ships three ways: a static image, an accessible
data table with proper table semantics, and the interactive figure. The page is
built so the image and the data table work with no JavaScript at all; the
interactive chart is added on top only when the browser supports it. The data
table is always present and is the authoritative text alternative. Colors are
chosen to meet contrast minimums and to stay distinguishable for colorblind users,
and color is never the only way a value is conveyed. This is a higher and more
predictable accessibility floor than a third-party embedded visualization we do
not fully control.

---

**What is built and what is left**

Built and tested: the data boundary (schema, suppression, restricted role), the
shared Plotly rendering engine with the accessible data table, the daily publisher
job, and the public page with its no-JavaScript baseline.

Remaining before go-live: the infrastructure provisioning (Front Door private
origin, the managed-identity role assignment, customer-managed keys and private
endpoints) needs an infrastructure review, and the new public surface needs an
ISSM threat-model review and a pre-deployment security pass before it is exposed.

---

**Review considerations**

A few points raised in review that the design accounts for:

- Front Door origin authorization. Disabling public blob access is necessary but
  not sufficient; the storage origin must also be locked to Front Door so the blob
  is reachable only through Front Door and its WAF, never directly. Managed-identity
  origin authentication is not supported with a Private Link origin, so the
  infrastructure review will pick a supported pattern: either a Private Link origin
  served through short-lived SAS-authorized requests, or a non-Private-Link origin
  using Front Door managed-identity origin authentication with the storage firewall
  restricted to the Front Door service. This is an explicit infrastructure-review item.
- Differencing attacks. Per-cell k-anonymity does not by itself stop an attacker
  who subtracts overlapping aggregates. We mitigate by publishing a small curated
  set of mostly single-dimension aggregates and avoiding overlapping cross-tabs of
  the same population that would enable differencing. Any new public chart is
  reviewed for this before it is added.
- Manual CSV ingestion. The interim CSV path is constrained: the loader validates
  every row against a fixed column allow-list, rejects unexpected columns, casts
  counts and rates to strict numeric types, and inserts only through parameterized
  queries (no string-built SQL), which closes both SQL and CSV injection. It
  re-enforces k-anonymity at load with database CHECK constraints as a backstop and
  runs as a write-only role. The data is scrubbed upstream by IRD; CSV is a stopgap
  until the IRD transform is wired through the same loader interface.
- Accessibility. The interactive chart is hidden from assistive technology
  (aria-hidden) because the data table is the authoritative alternative; this
  avoids a screen reader announcing an unreadable visualization.

Happy to walk through the boundary diagram whenever works for you.

Derek
