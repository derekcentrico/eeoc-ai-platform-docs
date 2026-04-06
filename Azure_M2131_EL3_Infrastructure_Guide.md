# M-21-31 EL3 Infrastructure Guide — Azure Sentinel, Flow Logs, DNS, UBA

**Date:** 2026-04-06
**Author:** Derek Gordon, OCIO Platform Team
**Audience:** EEOC OCIO staff with Azure Government Portal access
**Prerequisites:** All application-level logging from Prompts 42-44 deployed (HMAC audit on ARC Integration API, MCP Hub, OGC Trial Tool). Log Analytics workspace and Application Insights already provisioned per `Azure_Full_Deployment_Guide.md`.

This guide covers infrastructure-level M-21-31 Event Logging Tier 3 (EL3) requirements. EL3 adds behavioral analytics, automated response, network telemetry, and centralized SIEM correlation on top of the application-level structured logging already in place.

**What this does NOT cover:** Application code changes (already done), database-level logging (PostgreSQL `log_statement` and `pgaudit`), or Key Vault secret rotation procedures.

---

## Resource naming conventions

All resources follow the naming pattern from `Azure_Full_Deployment_Guide.md`:

| Resource | Name |
|----------|------|
| Resource Group | `rg-eeoc-ai-platform-prod` |
| Log Analytics Workspace | `law-eeoc-ai-prod` |
| Sentinel | (enabled on `law-eeoc-ai-prod`) |
| Application Insights | `appi-eeoc-ai-prod` |
| VNet | `vnet-eeoc-ai-platform` |
| Storage (audit archive) | `steeocaiaudit` |
| Storage (NSG flow logs) | `steeocflowlogs` |

---

## Section 1: Log Analytics workspace configuration

The workspace likely already exists from the Container Apps environment deployment. If not, create it first. Either way, these retention and export settings must be applied.

### 1.1 Verify or create the workspace

1. Azure Portal → **Log Analytics workspaces**
2. If `law-eeoc-ai-prod` exists, open it. If not:
   - **Create** → Resource group: `rg-eeoc-ai-platform-prod`
   - Name: `law-eeoc-ai-prod`
   - Region: `USGov Virginia`
   - Pricing tier: **Pay-per-GB** (default)
   - **Review + create** → **Create**

### 1.2 Set interactive retention to 12 months

M-21-31 requires 12 months of interactive (hot) query capability.

1. Open `law-eeoc-ai-prod` → **Usage and estimated costs** → **Data Retention**
2. Set retention to **365 days**
3. Click **OK**

### 1.3 Configure archive tier (18 months beyond interactive)

Total retention target: 30 months (12 interactive + 18 archive). Archived data is queryable via `search` jobs, not instant KQL.

1. Open `law-eeoc-ai-prod` → **Tables**
2. For each table listed below, click the table → **Manage table** → set **Total retention period** to **912 days** (30 months):

| Table | Reason |
|-------|--------|
| `SecurityEvent` | Auth events, logon failures |
| `SigninLogs` | Entra ID sign-in activity |
| `AuditLogs` | Entra ID directory changes |
| `AzureActivity` | ARM control plane operations |
| `ContainerAppConsoleLogs` | Application stdout/stderr |
| `AppTraces` | Application Insights traces |
| `AppRequests` | Application Insights HTTP requests |
| `AppExceptions` | Application Insights exceptions |
| `AzureDiagnostics` | NSG flow logs, DNS, PostgreSQL |
| `BehaviorAnalytics` | Sentinel UEBA output |
| `SecurityAlert` | Sentinel alerts |
| `SecurityIncident` | Sentinel incidents |

3. Tables not in this list use the workspace default (365 days).

### 1.4 Data export rules (cold storage backup)

Export log data to blob storage for long-term cold retention beyond 30 months if required by NARA schedule.

1. Open `law-eeoc-ai-prod` → **Data Export** → **New export rule**
2. Rule name: `export-security-cold`
3. Source tables: `SecurityEvent`, `SigninLogs`, `AuditLogs`, `SecurityAlert`, `SecurityIncident`
4. Destination: Storage account `steeocaiaudit` → container `law-cold-export`
5. **Save**

Create the destination container first:
1. **Storage accounts** → `steeocaiaudit` → **Containers** → **+ Container**
2. Name: `law-cold-export`
3. Public access: **None**
4. Enable immutable storage with a **2555-day** WORM policy (matches NARA 7-year retention on audit blobs)

### 1.5 Workspace RBAC

Control who can query what. Don't give everyone full reader access.

1. Open `law-eeoc-ai-prod` → **Access control (IAM)** → **Add role assignment**
2. Assign these roles:

| Role | Assignee | Scope |
|------|----------|-------|
| Log Analytics Reader | OCIO Platform Team group | Workspace |
| Log Analytics Reader | ISSO | Workspace |
| Log Analytics Contributor | Security Operations group | Workspace |
| Sentinel Responder | SOC Analysts group | Workspace (after Sentinel enabled) |
| Sentinel Contributor | SOC Lead | Workspace |
| Monitoring Reader | App team leads | Resource group (not workspace — limits to metrics only) |

---

## Section 2: Microsoft Sentinel

Sentinel is the SIEM/SOAR component for EL3. It layers on top of the Log Analytics workspace — not a separate resource.

### 2.1 Enable Sentinel

1. Azure Portal → search **Microsoft Sentinel** → **Create**
2. Select workspace: `law-eeoc-ai-prod`
3. **Add** — this enables Sentinel features on the existing workspace

After it provisions (takes a few minutes), you'll land on the Sentinel overview blade.

### 2.2 Connect data sources

Navigate to **Sentinel** → **Data connectors**. Enable each connector below.

#### 2.2.1 Entra ID (Azure AD) sign-in and audit logs

1. Find **Azure Active Directory** connector → **Open connector page**
2. Check: **Sign-in logs**, **Audit logs**, **Non-interactive sign-in logs**, **Service principal sign-in logs**, **Managed identity sign-in logs**, **Provisioning logs**
3. Click **Apply Changes**

Requires: Global Administrator or Security Administrator on the tenant.

#### 2.2.2 Azure Activity logs

1. Find **Azure Activity** connector → **Open connector page**
2. Click **Launch Azure Policy Assignment Wizard**
3. Scope: subscription `EEOC-Production`
4. Target workspace: `law-eeoc-ai-prod`
5. **Create**

This streams all ARM control-plane activity (resource creates, deletes, RBAC changes) into Sentinel.

#### 2.2.3 Application Insights (all 6 apps)

Application Insights data already flows to the same Log Analytics workspace (`appi-eeoc-ai-prod` is workspace-based). Sentinel can query `AppTraces`, `AppRequests`, `AppExceptions` directly — no additional connector needed.

Verify: Open `appi-eeoc-ai-prod` → **Properties** → confirm **Workspace** is `law-eeoc-ai-prod`.

#### 2.2.4 NSG flow logs

Covered in Section 3 below. Once NSG flow logs are enabled and sent to `law-eeoc-ai-prod`, Sentinel can query `AzureNetworkAnalytics_CL` directly.

#### 2.2.5 Microsoft Defender for Cloud

1. Find **Microsoft Defender for Cloud** connector → **Open connector page**
2. Enable **Bi-directional sync** for the subscription
3. This feeds vulnerability findings and security recommendations into Sentinel

#### 2.2.6 Azure Key Vault diagnostics

1. **Key Vault** → `kv-eeoc-ai-prod` → **Diagnostic settings** → **Add diagnostic setting**
2. Name: `kv-to-sentinel`
3. Logs: **AuditEvent** (all sub-categories)
4. Destination: **Send to Log Analytics workspace** → `law-eeoc-ai-prod`
5. **Save**

This captures every secret read, write, and delete — critical for AU-9 (audit protection) and detecting unauthorized key access.

### 2.3 Enable UEBA (User and Entity Behavior Analytics)

UEBA builds behavioral baselines for users and entities, then flags anomalies.

1. **Sentinel** → **Entity behavior** → **Entity behavior settings**
2. Toggle **UEBA** to **On**
3. Data sources: select **Azure Active Directory** and **Azure Activity**
4. Entity types: **User**, **IP**, **Host**
5. Click **Apply**

UEBA takes 7-14 days to build a baseline. During that period, expect noise — don't tune alert thresholds until the baseline stabilizes.

### 2.4 Analytics rules

Navigate to **Sentinel** → **Analytics** → **Create** → **Scheduled query rule** for each rule below.

#### Rule 1: Excessive failed authentication

Detects brute-force or credential-stuffing attempts.

- Name: `EEOC - Excessive Failed Logins`
- Severity: **High**
- MITRE ATT&CK: **Credential Access / Brute Force (T1110)**
- Query:
```kql
SigninLogs
| where TimeGenerated > ago(1h)
| where ResultType !in ("0", "50125", "50140")   // exclude success and expected MFA prompts
| summarize FailedCount = count(), DistinctApps = dcount(AppDisplayName) by UserPrincipalName, IPAddress
| where FailedCount > 10
| project UserPrincipalName, IPAddress, FailedCount, DistinctApps
```
- Query frequency: **1 hour**
- Lookup period: **1 hour**
- Alert threshold: generate alert when query returns **more than 0** results
- Entity mapping: Account → `UserPrincipalName`, IP → `IPAddress`

#### Rule 2: Audit write failures

Application-level HMAC audit writes are retried once, then dumped to stderr (AU-5 behavior from Prompts 42-44). If the writes are failing, something is wrong with the storage backend.

- Name: `EEOC - Audit Write Failures`
- Severity: **High**
- MITRE ATT&CK: **Defense Evasion / Indicator Removal (T1070)**
- Query:
```kql
ContainerAppConsoleLogs
| where TimeGenerated > ago(1h)
| where Log_s contains "Audit write failed" or Log_s contains "audit_write_failure" or Log_s contains "audit_event_failed"
| summarize FailureCount = count() by ContainerAppName_s
| where FailureCount > 5
```
- Query frequency: **1 hour**
- Lookup period: **1 hour**
- Alert threshold: **more than 0** results
- Entity mapping: Host → `ContainerAppName_s`

#### Rule 3: Unusual AI query volume

A single user making >100 AI queries/hour is either a misconfigured automation or data exfiltration.

- Name: `EEOC - Unusual AI Query Volume`
- Severity: **Medium**
- MITRE ATT&CK: **Collection / Data from Information Repositories (T1213)**
- Query:
```kql
AppTraces
| where TimeGenerated > ago(1h)
| where Message contains "CHAT_REQUEST" or Message contains "SQL_EXECUTED"
| extend parsed = parse_json(Message)
| extend username = tostring(parsed.username)
| summarize QueryCount = count() by username
| where QueryCount > 100
```
- Query frequency: **1 hour**
- Lookup period: **1 hour**
- Alert threshold: **more than 0** results
- Entity mapping: Account → `username`

#### Rule 4: After-hours PII tier 3 access

PII tier 3 is the highest sensitivity level (SSN, medical records). Access outside business hours warrants review.

- Name: `EEOC - After-Hours PII Tier 3 Access`
- Severity: **Medium**
- MITRE ATT&CK: **Collection / Data from Information Repositories (T1213)**
- Query:
```kql
AppTraces
| where TimeGenerated > ago(24h)
| where Message contains "protected_categories_accessed"
| extend parsed = parse_json(Message)
| extend pii_tier = tostring(parsed.pii_tier), username = tostring(parsed.username)
| where pii_tier == "3"
| extend HourET = datetime_part("hour", TimeGenerated - 5h)   // Eastern Time offset
| where HourET < 6 or HourET > 20   // before 6 AM or after 8 PM ET
| project TimeGenerated, username, pii_tier, HourET
```
- Query frequency: **24 hours** (run at 6 AM ET)
- Lookup period: **24 hours**
- Alert threshold: **more than 0** results
- Entity mapping: Account → `username`

Note: Eastern Time offset is hardcoded to UTC-5. Adjust for daylight saving if needed, or use a lookup table.

#### Rule 5: FOIA export activity

Every FOIA export triggers an alert. Not necessarily malicious, but must be tracked for chain-of-custody.

- Name: `EEOC - FOIA Export Activity`
- Severity: **Informational**
- MITRE ATT&CK: **Exfiltration / Exfiltration Over Web Service (T1567)**
- Query:
```kql
AppTraces
| where TimeGenerated > ago(1h)
| where Message contains "FOIA_EXPORT" or Message contains "foia-export"
| extend parsed = parse_json(Message)
| extend username = tostring(parsed.username), export_id = tostring(parsed.export_id)
| project TimeGenerated, username, export_id
```
- Query frequency: **1 hour**
- Lookup period: **1 hour**
- Alert threshold: **more than 0** results
- Entity mapping: Account → `username`

### 2.5 Automation playbooks (Logic Apps)

Sentinel SOAR uses Logic Apps for automated incident response. Create three playbooks.

#### Playbook 1: High-severity alert — email + ServiceNow ticket

1. **Sentinel** → **Automation** → **Create** → **Playbook with incident trigger**
2. Name: `playbook-high-severity-alert`
3. Resource group: `rg-eeoc-ai-platform-prod`
4. Enable managed identity: **Yes** (system-assigned)
5. **Create and continue to designer**

Logic App workflow:

```
Trigger: Microsoft Sentinel incident
  ↓
Condition: Severity equals "High" or "Critical"
  ↓ (Yes branch)
Action: Send email (Office 365)
  To: security-team@eeoc.gov
  Subject: [Sentinel] High Severity: {incident title}
  Body: Incident #{incident number} — {description}
         Status: {status}
         Entities: {entities list}
         Link: {incident URL}
  ↓
Action: Create record (ServiceNow)
  Table: incident
  Short description: [Sentinel] {incident title}
  Description: {description}
  Urgency: 1 - High
  Assignment group: OCIO Security Operations
```

If ServiceNow connector isn't available yet, substitute with an HTTP webhook to the ticketing system or a Teams channel message.

6. **Save**
7. Back in **Sentinel** → **Automation** → **Create** → **Automation rule**
   - Name: `auto-run-high-severity`
   - Trigger: **When incident is created**
   - Condition: Severity **is** High or Critical
   - Action: **Run playbook** → `playbook-high-severity-alert`
   - **Apply**

#### Playbook 2: AI circuit breaker — notify team leads

When the AI assistant trips a circuit breaker (rate limit exceeded, model timeout, repeated failures), notify ADR and Triage team leads.

1. **Create** → **Playbook with alert trigger**
2. Name: `playbook-ai-circuit-breaker`
3. Logic App workflow:

```
Trigger: Microsoft Sentinel alert
  ↓
Condition: Alert name contains "Circuit" or "AI" or "Unusual AI Query"
  ↓ (Yes branch)
Action: Post message (Microsoft Teams)
  Team: EEOC AI Platform
  Channel: #incidents
  Message: ⚠ AI Circuit Breaker Alert
           {alert description}
           Time: {alert time}
           Entities: {entities}
  ↓
Action: Send email (Office 365)
  To: adr-lead@eeoc.gov; triage-lead@eeoc.gov
  Subject: AI Circuit Breaker Triggered
  Body: {alert description}
```

4. **Save** → Create automation rule as in Playbook 1, matching alert name pattern.

#### Playbook 3: WORM deletion attempt — notify Records Management

If someone attempts to delete a blob in a WORM-protected container, the storage account will reject it. But the attempt itself indicates either misconfiguration or malicious intent.

1. **Create** → **Playbook with alert trigger**
2. Name: `playbook-worm-deletion-attempt`
3. Logic App workflow:

```
Trigger: Microsoft Sentinel alert
  ↓
Action: Send email (Office 365)
  To: records-management@eeoc.gov; security-team@eeoc.gov
  Subject: WORM Deletion Attempt Detected
  Body: Someone attempted to delete a blob in a WORM-protected audit archive.
        Container: {extract from alert}
        Caller: {extract from alert}
        Time: {alert time}
        The deletion was BLOCKED by the immutability policy.
        Investigate why this was attempted.
```

4. **Save** → Create automation rule matching storage-related deletion alerts.

To generate the Sentinel alert for WORM deletion attempts, add an analytics rule:

- Name: `EEOC - WORM Blob Deletion Attempt`
- Severity: **High**
- Query:
```kql
StorageBlobLogs
| where TimeGenerated > ago(1h)
| where OperationName == "DeleteBlob" and StatusCode == 409
| where Uri contains "archive"
| project TimeGenerated, CallerIpAddress, Uri, StatusText, AccountName
```
- Query frequency: **1 hour**
- Lookup period: **1 hour**

---

## Section 3: NSG flow logs

NSG flow logs capture every allowed/denied network flow through Network Security Groups. Required by M-21-31 EL3 for network telemetry.

### 3.1 Create storage account for flow logs

Flow logs generate significant volume — use a dedicated storage account.

1. **Create a resource** → search **Storage account**
2. Name: `steeocflowlogs`
3. Resource group: `rg-eeoc-ai-platform-prod`
4. Region: `USGov Virginia`
5. Redundancy: **LRS** (flow logs are queryable in Log Analytics — blob is backup)
6. **Networking** tab: Private endpoint in `snet-storage`
7. **Review + create** → **Create**

### 3.2 Enable flow logs on all NSGs

1. Azure Portal → search **Network Watcher** → **NSG flow logs** → **Create**
2. Repeat for each NSG attached to the platform VNet subnets. If the VNet has a single NSG, one flow log config suffices.

For each NSG:

| Setting | Value |
|---------|-------|
| NSG | Select from `vnet-eeoc-ai-platform` |
| Storage account | `steeocflowlogs` |
| Retention (days) | `365` |
| Flow log version | **Version 2** (includes bytes transferred) |
| Traffic Analytics | **Enabled** |
| Traffic Analytics processing interval | **Every 10 minutes** |
| Log Analytics workspace | `law-eeoc-ai-prod` |

3. **Review + create** → **Create**

### 3.3 Verify flow logs are arriving

Wait 15-20 minutes after enabling, then run in Log Analytics:

```kql
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| summarize count() by FlowDirection_s, FlowStatus_s
```

You should see rows for `I` (inbound) and `O` (outbound), `A` (allowed) and `D` (denied).

---

## Section 4: Azure DNS Analytics

DNS telemetry detects data exfiltration via DNS tunneling and connections to known-malicious domains.

### 4.1 Enable DNS Analytics solution

1. Azure Portal → search **Solutions** (under Log Analytics) or go to **Marketplace** → search **DNS Analytics**
2. If the legacy solution is unavailable in Gov Cloud, use the Sentinel **DNS** data connector instead:
   - **Sentinel** → **Data connectors** → **DNS (Preview)** → **Open connector page**
   - Follow the instructions to install the DNS agent on the DNS servers or enable diagnostic logging on Azure DNS zones

### 4.2 Configure diagnostic settings on Azure DNS zones

If the platform uses Azure DNS for internal resolution:

1. **DNS zones** → select the zone (e.g., `eeoc-ai-platform.internal`)
2. **Diagnostic settings** → **Add diagnostic setting**
3. Name: `dns-to-sentinel`
4. Logs: all categories
5. Destination: **Send to Log Analytics workspace** → `law-eeoc-ai-prod`
6. **Save**

### 4.3 DNS alert rules

Add these as Sentinel analytics rules (same process as Section 2.4):

#### DNS query to known-malicious domain

- Name: `EEOC - DNS Query to Malicious Domain`
- Severity: **High**
- Query:
```kql
DnsEvents
| where TimeGenerated > ago(1h)
| where Name has_any (
    "evil.com",           // placeholder — replace with threat intel feed
    "malware-c2.net"      // placeholder
)
| project TimeGenerated, ClientIP, Name, QueryType
```

In production, replace the placeholder list with a Sentinel Threat Intelligence feed:
1. **Sentinel** → **Threat intelligence** → **Data connectors**
2. Enable **Microsoft Threat Intelligence** (built-in feed, no extra cost)
3. This auto-populates the `ThreatIntelligenceIndicator` table
4. Rewrite the rule to join against it:

```kql
DnsEvents
| where TimeGenerated > ago(1h)
| join kind=inner (
    ThreatIntelligenceIndicator
    | where Active == true
    | where NetworkDestinationDomainName != ""
) on $left.Name == $right.NetworkDestinationDomainName
| project TimeGenerated, ClientIP, Name, ThreatType, ConfidenceScore
```

#### Unusual DNS query volume

Possible DNS tunneling — thousands of queries to a single domain in a short window.

- Name: `EEOC - Unusual DNS Query Volume`
- Severity: **Medium**
- Query:
```kql
DnsEvents
| where TimeGenerated > ago(1h)
| summarize QueryCount = count() by ClientIP, Name
| where QueryCount > 500
| project ClientIP, Name, QueryCount
```

---

## Section 5: Azure Network Watcher

Network Watcher provides on-demand packet capture for incident response and connection troubleshooting.

### 5.1 Enable Network Watcher

1. Azure Portal → search **Network Watcher**
2. If not already enabled for `USGov Virginia`, it auto-provisions when you first use a feature. Verify:
   - **Network Watcher** → **Overview** → confirm `USGov Virginia` is listed
   - If not listed: **Subscriptions** → your subscription → **Resource providers** → search `Microsoft.Network` → **Register** (if not registered)

### 5.2 Configure packet capture capability

Packet capture is on-demand — not always running. Set up the capability so SOC analysts can trigger it during incidents.

1. **Network Watcher** → **Packet capture** → this shows the capture management interface
2. No captures are running by default. To set up a capture during an incident:
   - **Add** → select the target VM or VMSS (Container Apps use Kubernetes nodes managed by Azure — packet capture applies to the underlying node if accessible)
   - Maximum bytes per packet: `1500` (full packet)
   - Maximum bytes per session: `1073741824` (1 GB)
   - Time limit: `18000` seconds (5 hours max per capture)
   - Storage account: `steeocflowlogs`
   - File path: leave default

### 5.3 Incident response procedure for packet capture

Document this procedure in the Incident Response runbook:

1. SOC analyst opens **Network Watcher** → **Packet capture** → **Add**
2. Select the resource exhibiting suspicious traffic
3. Add filters if known:
   - Protocol: TCP/UDP
   - Local/remote IP
   - Local/remote port
4. Start capture
5. Reproduce or wait for the suspicious activity
6. Stop capture → download `.cap` file from `steeocflowlogs`
7. Analyze in Wireshark or Network Watcher's built-in topology view
8. Retention: captured `.cap` files expire after **30 days** in storage. If needed for legal proceedings, copy to the WORM archive container before expiration.

### 5.4 Connection troubleshooting

Network Watcher also provides non-capture diagnostics:

- **Connection troubleshoot**: test connectivity between two resources (replaces ad-hoc `curl` tests)
- **IP flow verify**: check if an NSG rule allows/denies a specific flow
- **Next hop**: verify routing tables

These don't require pre-configuration — they're available out of the box once Network Watcher is enabled.

---

## Section 6: Entra ID Identity Protection

Identity Protection flags risky sign-ins and user accounts using Microsoft's threat intelligence.

### 6.1 Enable Identity Protection

1. Azure Portal → search **Entra ID** (or **Azure Active Directory**) → **Security** → **Identity Protection**
2. This blade is always available — no separate resource to create

### 6.2 Risk-based conditional access policies

#### Policy 1: Block high-risk sign-ins

1. **Entra ID** → **Security** → **Conditional Access** → **New policy**
2. Name: `EEOC - Block High Risk Sign-ins`
3. Assignments:
   - Users: **All users** (exclude break-glass accounts)
   - Cloud apps: **All cloud apps**
   - Conditions → **Sign-in risk**: **High**
4. Access controls → Grant: **Block access**
5. Enable policy: **On**
6. **Create**

#### Policy 2: Require MFA for medium-risk sign-ins

1. **New policy**
2. Name: `EEOC - MFA on Medium Risk Sign-in`
3. Assignments:
   - Users: **All users**
   - Cloud apps: **All cloud apps**
   - Conditions → **Sign-in risk**: **Medium**
4. Access controls → Grant: **Require multifactor authentication**
5. Enable policy: **On**
6. **Create**

#### Policy 3: Require password change for high-risk users

1. **New policy**
2. Name: `EEOC - Password Change for High Risk Users`
3. Assignments:
   - Users: **All users**
   - Conditions → **User risk**: **High**
4. Access controls → Grant: **Require password change** + **Require multifactor authentication**
5. Enable policy: **On**
6. **Create**

### 6.3 Feed risk detections into Sentinel

This is automatic if the Entra ID data connector (Section 2.2.1) is enabled. Sign-in risk events appear in `SigninLogs` with `RiskLevelDuringSignIn` and `RiskState` columns. Identity Protection alerts also appear in `SecurityAlert`.

Verify with:
```kql
SigninLogs
| where TimeGenerated > ago(7d)
| where RiskLevelDuringSignIn != "none"
| project TimeGenerated, UserPrincipalName, RiskLevelDuringSignIn, RiskState, IPAddress
```

### 6.4 Alert rules for identity-based threats

These are built-in Sentinel templates. Enable them from **Sentinel** → **Analytics** → **Rule templates**:

| Template name | What it detects |
|---------------|----------------|
| Anomalous sign-in from unusual location | Impossible travel |
| Sign-in from anonymous IP address | Tor, VPN anonymizers |
| Sign-in from malware-linked IP | Known botnet infrastructure |
| Unfamiliar sign-in properties | New device/browser/location combination |
| Leaked credentials | Credentials found on paste sites or dark web |

For each: click the template → **Create rule** → accept defaults or adjust threshold → **Create**.

---

## Section 7: TLS inspection

M-21-31 EL3 requires visibility into encrypted traffic for the network boundary. Two options depending on architecture.

### Option A: Azure Firewall Premium with TLS inspection

Use this if traffic between the internet and Container Apps passes through Azure Firewall.

1. **Azure Firewall** → upgrade to **Premium** tier if not already
2. **Firewall Policy** → **TLS Inspection** → **Enabled**
3. Create or import an intermediate CA certificate:
   - **Key Vault** → `kv-eeoc-ai-prod` → **Certificates** → **Generate/Import**
   - Name: `firewall-tls-inspection-ca`
   - Type: **Self-signed** (for internal inspection) or **CA-signed** (if enterprise CA available)
   - Subject: `CN=EEOC-AI-Platform-TLS-Inspection`
4. In Firewall Policy → **TLS Inspection** → select the certificate from Key Vault
5. Configure which traffic gets inspected:

| Traffic | Inspect? | Reason |
|---------|----------|--------|
| Inbound from internet to Container Apps | **No** — terminated at Front Door/App Gateway | TLS already terminates before reaching firewall |
| Outbound from Container Apps to Azure OpenAI | **No** — service endpoint, no exfiltration risk | Internal Azure backbone |
| Outbound from Container Apps to ARC endpoints | **Yes** if leaving VNet | External dependency |
| Outbound to Azure Storage/Key Vault | **No** — private endpoints | Traffic stays in VNet |
| Outbound to the internet (if any) | **Yes** | Catch data exfiltration |

### Option B: Application Gateway with end-to-end TLS

Use this if Front Door terminates external TLS and Application Gateway handles internal routing.

1. Application Gateway already configured per `Azure_Full_Deployment_Guide.md` (Front Door for ADR)
2. For end-to-end TLS: **Application Gateway** → **Listeners** → verify **HTTPS** with valid cert
3. **Backend settings** → enable **HTTPS** → upload backend authentication certificate
4. This gives the Application Gateway visibility into request/response headers for WAF rules

Both approaches are valid for M-21-31. Document which one is deployed and submit the decision in the SSP (System Security Plan) under SC-8 and SC-23.

---

## Section 8: Compliance dashboard (Azure Monitor Workbook)

Build a single-pane dashboard for M-21-31 compliance posture.

### 8.1 Create the workbook

1. Azure Portal → **Monitor** → **Workbooks** → **New**
2. Name: `EEOC M-21-31 Compliance Dashboard`
3. Resource group: `rg-eeoc-ai-platform-prod`

### 8.2 Add dashboard sections

Use the visual editor. Each section below is a separate workbook group.

#### Section A: M-21-31 maturity level per application

Add a **Query** tile with visualization **Grid**:

```kql
let apps = datatable(App:string, EL_Target:string) [
    "ARC Integration API", "EL3",
    "MCP Hub Functions", "EL3",
    "OGC Trial Tool", "EL3",
    "ADR Mediation", "EL3",
    "OFS Triage", "EL3",
    "UDIP Analytics", "EL3"
];
let audit_status = AppTraces
| where TimeGenerated > ago(24h)
| where Message contains "HMAC" or Message contains "RecordHMAC"
| extend App = case(
    Message contains "arc-integration", "ARC Integration API",
    Message contains "hub", "MCP Hub Functions",
    Message contains "ogc" or Message contains "trial", "OGC Trial Tool",
    Message contains "adr" or Message contains "mediation", "ADR Mediation",
    Message contains "triage", "OFS Triage",
    Message contains "udip" or Message contains "analytics", "UDIP Analytics",
    "Unknown"
)
| summarize AuditRecords24h = count() by App;
apps
| join kind=leftouter audit_status on App
| extend AuditRecords24h = coalesce(AuditRecords24h, 0)
| extend EL_Status = iff(AuditRecords24h > 0, "Active", "No audit data")
| project App, EL_Target, EL_Status, AuditRecords24h
| order by App asc
```

#### Section B: AU control compliance status

Add a **Text** tile (markdown) — manually maintained, updated after each control assessment:

```markdown
| Control | Status | Evidence |
|---------|--------|----------|
| AU-2 (Auditable events) | Implemented | Structured JSON logging on all 6 apps |
| AU-3 (Content of audit records) | Implemented | 18+ fields per record, HMAC signed |
| AU-4 (Audit storage capacity) | Implemented | 2555-day WORM blob + 365d table retention |
| AU-5 (Response to audit failures) | Implemented | Retry + stderr fallback per app |
| AU-6 (Audit review) | Implemented | Sentinel analytics rules + this dashboard |
| AU-9 (Protection of audit info) | Implemented | HMAC integrity, WORM immutability |
| AU-10 (Non-repudiation) | Implemented | HMAC-SHA256 per record |
| AU-11 (Audit retention) | Implemented | 7-year NARA schedule, WORM policy |
| AU-12 (Audit generation) | Implemented | All apps emit structured audit events |
```

#### Section C: Log volume per application per day

Add a **Query** tile with visualization **Bar chart**:

```kql
AppTraces
| where TimeGenerated > ago(7d)
| extend App = case(
    AppRoleName contains "arc-integration", "ARC Integration API",
    AppRoleName contains "mcp-hub" or AppRoleName contains "hub-functions", "MCP Hub",
    AppRoleName contains "ogc" or AppRoleName contains "trial-tool", "OGC Trial Tool",
    AppRoleName contains "adr" or AppRoleName contains "mediation", "ADR Mediation",
    AppRoleName contains "triage", "OFS Triage",
    AppRoleName contains "udip" or AppRoleName contains "analytics", "UDIP Analytics",
    AppRoleName
)
| summarize LogCount = count() by App, bin(TimeGenerated, 1d)
| order by TimeGenerated asc
```

Chart settings: X-axis = `TimeGenerated`, Y-axis = `LogCount`, Series = `App`.

#### Section D: HMAC validation results

Add a **Query** tile to track audit record integrity. This queries the application-level audit tables for records where HMAC can be revalidated.

```kql
// check for audit write failures (proxy for HMAC issues)
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where Log_s contains "Audit write failed" or Log_s contains "audit_write_failure" or Log_s contains "RecordHMAC"
| summarize
    WriteFailures = countif(Log_s contains "Audit write failed" or Log_s contains "audit_write_failure"),
    HMACRecords = countif(Log_s contains "RecordHMAC")
| extend IntegrityStatus = iff(WriteFailures == 0, "All writes succeeded", strcat(WriteFailures, " failures detected"))
```

For full HMAC revalidation, run the offline verification script documented in each repo's CHANGES.md against the Table Storage audit records.

#### Section E: Retention policy adherence

Add a **Query** tile:

```kql
Usage
| where TimeGenerated > ago(30d)
| where IsBillable == true
| summarize DataGB = sum(Quantity) / 1000 by DataType, bin(TimeGenerated, 1d)
| where DataGB > 0
| order by TimeGenerated desc
```

Add a **Text** tile:

```markdown
**Retention targets:**
- Interactive (hot): 365 days — set at workspace level
- Archive: 912 days total (547 days archive beyond interactive)
- WORM blob archive: 2555 days (7 years per NARA)
- Cold export: `law-cold-export` container in `steeocaiaudit`
```

#### Section F: Open litigation holds

Add a **Query** tile (queries the UDIP litigation hold table created by Prompt 41):

```kql
// If litigation holds are stored in PostgreSQL, this won't work via KQL.
// Alternative: the FOIA export API (Prompt 40) exposes /api/litigation-holds.
// Poll that endpoint from a Logic App and write results to a custom Log Analytics table.
//
// Placeholder query against a custom table:
LitigationHolds_CL
| where IsActive_b == true
| project HoldName_s, HoldDate_t, CaseNumbers_s, RequestedBy_s, ExpirationDate_t
| order by HoldDate_t desc
```

If the custom table isn't set up, replace this tile with a **Link** tile pointing to the UDIP admin panel litigation hold page.

### 8.3 Pin the workbook to a shared dashboard

1. In the workbook → **Save** → Resource group: `rg-eeoc-ai-platform-prod`
2. **Pin to dashboard** (each section individually, or the whole workbook)
3. **Dashboard** → **Share** → add the security team and ISSO as viewers

---

## Section 9: Verification checklist

After completing all sections above, verify:

### Sentinel
- [ ] Sentinel enabled on `law-eeoc-ai-prod`
- [ ] Entra ID connector: sign-in logs and audit logs flowing
- [ ] Azure Activity connector: ARM events flowing
- [ ] UEBA enabled — initial baseline building
- [ ] All 5 custom analytics rules active (check **Sentinel** → **Analytics** → **Active rules**)
- [ ] WORM deletion attempt rule active
- [ ] 3 automation playbooks created and linked to automation rules
- [ ] Defender for Cloud connector bidirectional sync enabled

### NSG flow logs
- [ ] Flow logs enabled on all NSGs in `vnet-eeoc-ai-platform`
- [ ] Version 2 confirmed (check flow log properties)
- [ ] Traffic Analytics processing (run the verification KQL from Section 3.3)
- [ ] Retention set to 365 days
- [ ] Storage account `steeocflowlogs` receiving data

### DNS Analytics
- [ ] DNS diagnostic settings configured on Azure DNS zones
- [ ] Threat intelligence feed connected in Sentinel
- [ ] DNS alert rules active (malicious domain, unusual volume)

### Network Watcher
- [ ] Enabled in `USGov Virginia`
- [ ] Packet capture tested (start/stop a test capture, download the .cap file)
- [ ] Incident response procedure documented in runbook

### Log Analytics
- [ ] Interactive retention: 365 days
- [ ] Archive retention on key tables: 912 days
- [ ] Data export rule active (check `law-cold-export` container has data)
- [ ] RBAC roles assigned per Section 1.5

### Identity Protection
- [ ] 3 conditional access policies active (block high-risk, MFA medium-risk, password change)
- [ ] Risk detections flowing to Sentinel (run the verification KQL from Section 6.3)

### TLS inspection
- [ ] Decision documented (Firewall Premium or App Gateway)
- [ ] Relevant traffic flows inspected per the table in Section 7

### Compliance dashboard
- [ ] Workbook saved and shared with security team
- [ ] All 6 sections rendering data (some may show zeros until baseline builds)
- [ ] Pinned to shared Azure Dashboard

---

## NIST 800-53 control mapping

This guide addresses the following controls at the infrastructure level:

| Control | Title | How addressed |
|---------|-------|---------------|
| AU-4 | Audit Log Storage Capacity | 12-month hot + 18-month archive + 7-year WORM blob |
| AU-5 | Response to Audit Processing Failures | Sentinel rule on audit write failures → automated playbook |
| AU-6 | Audit Record Review, Analysis, and Reporting | Sentinel analytics rules + compliance dashboard |
| AU-9 | Protection of Audit Information | WORM immutability, workspace RBAC, HMAC integrity |
| AU-12 | Audit Record Generation | All 6 apps emit structured JSON with HMAC; NSG flow logs; DNS logs |
| IR-4 | Incident Handling | SOAR playbooks, packet capture procedure |
| IR-5 | Incident Monitoring | Sentinel incident queue, UEBA anomalies |
| RA-5 | Vulnerability Monitoring | Defender for Cloud connector, Sentinel correlation |
| SC-7 | Boundary Protection | NSG flow logs, Traffic Analytics |
| SC-8 | Transmission Confidentiality | TLS inspection documentation |
| SC-23 | Session Authenticity | TLS inspection, Entra ID sign-in risk |
| SI-4 | System Monitoring | Sentinel UEBA, analytics rules, compliance dashboard |
| IA-5(13) | Authenticator Management / Expiration | Identity Protection risk-based conditional access |
| AC-2(12) | Account Management / Account Monitoring | UEBA, after-hours access rule, sign-in risk policies |

---

## Ongoing operations

### Weekly
- Review Sentinel incident queue. Close resolved incidents, escalate open ones.
- Check the compliance dashboard workbook for gaps (zero audit records from any app = problem).

### Monthly
- Review UEBA anomaly trends. Adjust analytics rule thresholds if false positive rate is too high.
- Verify NSG flow log retention (365 days) hasn't been accidentally changed.
- Run HMAC validation script against audit table samples (offline, per repo documentation).

### Quarterly
- Review and update conditional access policies as the user population changes.
- Update the `AU control compliance status` markdown tile in the workbook.
- Test all 3 SOAR playbooks end-to-end (create a test incident, verify email + ticket creation).
- Review and refresh the threat intelligence indicator list if using a custom feed.

### Annually
- Verify 7-year WORM retention policy on all audit archive containers.
- Confirm cold export data in `law-cold-export` is intact and queryable via storage blob search jobs.
- Update this guide for any Azure service changes in Gov Cloud.
