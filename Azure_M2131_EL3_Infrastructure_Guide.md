# Azure M-21-31 EL3 Infrastructure Guide

**Classification:** CUI // FOUO
**Version:** 1.0
**Last Updated:** 2026-04-07
**Owner:** OCIO Platform Team / Security Operations

---

## Purpose

This guide covers the Azure-level infrastructure required to satisfy OMB M-21-31 Event Logging Maturity Level 3 (EL3 — Advanced) for the EEOC AI Integration Platform. EL3 requires centralized SIEM with behavioral analytics, automated response, full network telemetry, extended retention, and compliance reporting.

This document is standalone. It assumes the platform resources from the `EEOC_AI_Platform_Complete_Deployment_Guide.md` are already provisioned (resource group, VNet, Log Analytics workspace, Container Apps, etc.).

**Prerequisites:**
- Azure Government subscription with Contributor role on `rg-eeoc-ai-platform-prod`
- Security Administrator role in Entra ID (for Identity Protection policies)
- Log Analytics workspace `log-eeoc-ai-prod` already provisioned
- Application Insights `appi-eeoc-ai-prod` already provisioned
- All NSGs created per the deployment guide

**Resource naming convention:** All new resources follow the existing pattern: `{type}-eeoc-{purpose}-prod`.

---

## Table of Contents

- [1. Microsoft Sentinel (SIEM + SOAR + UEBA)](#1-microsoft-sentinel-siem--soar--ueba)
  - [1.1 Enable Sentinel](#11-enable-sentinel)
  - [1.2 Connect Data Sources](#12-connect-data-sources)
  - [1.3 Enable UEBA](#13-enable-ueba)
  - [1.4 Analytics Rules](#14-analytics-rules)
  - [1.5 SOAR Automation Playbooks](#15-soar-automation-playbooks)
- [2. NSG Flow Logs and Traffic Analytics](#2-nsg-flow-logs-and-traffic-analytics)
  - [2.1 Enable NSG Flow Logs](#21-enable-nsg-flow-logs)
  - [2.2 Enable Traffic Analytics](#22-enable-traffic-analytics)
- [3. Azure DNS Analytics](#3-azure-dns-analytics)
  - [3.1 Enable DNS Analytics Solution](#31-enable-dns-analytics-solution)
  - [3.2 Configure Diagnostic Settings](#32-configure-diagnostic-settings)
  - [3.3 DNS Alert Rules](#33-dns-alert-rules)
- [4. Azure Network Watcher](#4-azure-network-watcher)
  - [4.1 Enable Network Watcher](#41-enable-network-watcher)
  - [4.2 On-Demand Packet Capture](#42-on-demand-packet-capture)
  - [4.3 Incident Response Packet Capture Procedure](#43-incident-response-packet-capture-procedure)
- [5. Log Analytics Workspace Configuration](#5-log-analytics-workspace-configuration)
  - [5.1 Interactive Retention (12 Months)](#51-interactive-retention-12-months)
  - [5.2 Archive Tier (30 Months Total)](#52-archive-tier-30-months-total)
  - [5.3 Per-Table Retention Overrides](#53-per-table-retention-overrides)
  - [5.4 Data Export Rules to Cold Storage](#54-data-export-rules-to-cold-storage)
  - [5.5 Workspace RBAC](#55-workspace-rbac)
- [6. Entra ID Identity Protection](#6-entra-id-identity-protection)
  - [6.1 Enable Risk Policies](#61-enable-risk-policies)
  - [6.2 Feed Risk Detections to Sentinel](#62-feed-risk-detections-to-sentinel)
- [7. TLS Inspection](#7-tls-inspection)
  - [7.1 Application Gateway End-to-End TLS](#71-application-gateway-end-to-end-tls)
  - [7.2 Traffic Inspection Matrix](#72-traffic-inspection-matrix)
- [8. M-21-31 Compliance Dashboard (Azure Monitor Workbook)](#8-m-2131-compliance-dashboard-azure-monitor-workbook)
  - [8.1 Create the Workbook](#81-create-the-workbook)
  - [8.2 Dashboard Sections](#82-dashboard-sections)
- [Appendix A: Resource Summary](#appendix-a-resource-summary)
- [Appendix B: M-21-31 EL3 Control Mapping](#appendix-b-m-2131-el3-control-mapping)

---

## 1. Microsoft Sentinel (SIEM + SOAR + UEBA)

### 1.1 Enable Sentinel

1. Navigate to **Azure Portal** > search **Microsoft Sentinel**
2. Click **+ Create**
3. Select the existing Log Analytics workspace: `log-eeoc-ai-prod`
4. Click **Add**
5. Wait for provisioning to complete (1-2 minutes)

**Verify:** The Sentinel overview blade loads and shows the workspace name `log-eeoc-ai-prod` at the top.

> Sentinel is a layer on top of Log Analytics. Enabling it does not move or duplicate data — it adds analytics, hunting, and automation capabilities to the existing workspace.

### 1.2 Connect Data Sources

Navigate to **Sentinel** > **Content hub** to install solution packs, then **Data connectors** to configure each source.

#### 1.2.1 Entra ID Sign-In and Audit Logs

1. **Sentinel** > **Content hub** > search **Microsoft Entra ID** > **Install**
2. After installation, go to **Data connectors** > **Microsoft Entra ID**
3. Click **Open connector page**
4. Under **Configuration**, check:
   - Sign-in logs
   - Audit logs
   - Non-interactive user sign-in logs
   - Service principal sign-in logs
   - Managed identity sign-in logs
   - Provisioning logs
5. Click **Apply Changes**

**Verify:** Run the following KQL in Sentinel > Logs:
```kql
SigninLogs
| take 10
```
Results should appear within 5-10 minutes of enabling.

#### 1.2.2 Azure Activity Logs

1. **Data connectors** > **Azure Activity** > **Open connector page**
2. Click **Launch Azure Policy Assignment Wizard**
3. Scope: select the subscription containing `rg-eeoc-ai-platform-prod`
4. Parameters tab: Primary Log Analytics workspace = `log-eeoc-ai-prod`
5. **Review + create** > **Create**

**Verify:** Run:
```kql
AzureActivity
| where TimeGenerated > ago(1h)
| take 10
```

#### 1.2.3 Application Insights (All 6 Apps)

Application Insights data flows to the same `log-eeoc-ai-prod` workspace. No additional connector is needed — the data is already available in Sentinel via the shared workspace. Confirm by querying:

```kql
AppRequests
| where AppRoleName in (
    "ca-udip-ai-assistant-prod",
    "ca-adr-webapp-prod",
    "ca-adr-functionapp-prod",
    "ca-triage-webapp-prod",
    "ca-triage-functionapp-prod",
    "ca-mcp-hub-func-prod"
)
| summarize count() by AppRoleName
| order by count_ desc
```

If any app returns zero rows, verify its `APPLICATIONINSIGHTS_CONNECTION_STRING` environment variable points to `appi-eeoc-ai-prod`.

#### 1.2.4 NSG Flow Logs

NSG flow log data reaches Sentinel via the Log Analytics workspace after configuring flow logs (Section 2 below). No separate connector needed.

#### 1.2.5 Azure Key Vault

1. Navigate to **Key Vault** `kv-eeoc-ai-prod` > **Monitoring** > **Diagnostic settings**
2. Confirm a diagnostic setting exists sending `AuditEvent` to `log-eeoc-ai-prod`
3. If not, click **+ Add diagnostic setting**:
   - Name: `kv-sentinel-diag`
   - Log categories: `AuditEvent`
   - Destination: `log-eeoc-ai-prod`
   - Click **Save**

#### 1.2.6 Microsoft Defender for Cloud

1. **Sentinel** > **Data connectors** > **Microsoft Defender for Cloud**
2. Click **Open connector page**
3. Find the subscription and set status to **Connected**
4. Enable **Bi-directional sync** so Sentinel incidents update Defender alerts

### 1.3 Enable UEBA

1. **Sentinel** > **Settings** > **Settings** tab
2. Scroll to **Entity behavior** section
3. Click **Set UEBA**
4. Toggle **UEBA** to **On**
5. Under **Data sources for UEBA**, enable:
   - Microsoft Entra ID (sign-in logs, audit logs)
   - Azure Activity
6. Under **Entity types**, select:
   - Account
   - Host
   - IP address
   - Azure resource
7. Click **Apply**

**Verify:** After 24 hours, navigate to **Sentinel** > **Entity behavior**. User entities should appear with anomaly scores.

### 1.4 Analytics Rules

Navigate to **Sentinel** > **Analytics** > **+ Create** > **Scheduled query rule** for each rule below.

#### 1.4.1 Failed Authentication Spike

| Setting | Value |
|---------|-------|
| Name | `EEOC-AUTH-001: Failed authentication > 10/hour per user` |
| Severity | High |
| MITRE ATT&CK | Credential Access — Brute Force |
| Status | Enabled |
| Run query every | 1 hour |
| Lookup data from the last | 1 hour |

**Rule query:**
```kql
SigninLogs
| where ResultType != "0"
| summarize FailedCount = count() by UserPrincipalName, IPAddress, bin(TimeGenerated, 1h)
| where FailedCount > 10
| project UserPrincipalName, IPAddress, FailedCount, TimeGenerated
```

**Entity mapping:**
- Account: UserPrincipalName
- IP: IPAddress

**Alert grouping:** Group alerts into a single incident per UserPrincipalName within 24 hours.

Click **Next: Automated response** > attach `playbook-notify-security` (Section 1.5.1) > **Create**.

#### 1.4.2 AI Audit Write Failures

| Setting | Value |
|---------|-------|
| Name | `EEOC-AUDIT-001: Audit write failures > 5/hour` |
| Severity | Critical |
| MITRE ATT&CK | Defense Evasion — Impair Defenses |
| Status | Enabled |
| Run query every | 15 minutes |
| Lookup data from the last | 1 hour |

**Rule query:**
```kql
AppTraces
| where Message has "audit_write_error" or Message has "HMAC verification failed"
| summarize FailureCount = count() by AppRoleName, bin(TimeGenerated, 1h)
| where FailureCount > 5
| project AppRoleName, FailureCount, TimeGenerated
```

**Entity mapping:**
- Azure resource: AppRoleName

Click **Next: Automated response** > attach `playbook-notify-security` > **Create**.

#### 1.4.3 Unusual AI Query Volume

| Setting | Value |
|---------|-------|
| Name | `EEOC-AI-001: Unusual query volume > 100/hour per user` |
| Severity | Medium |
| MITRE ATT&CK | Collection — Data from Information Repositories |
| Status | Enabled |
| Run query every | 1 hour |
| Lookup data from the last | 1 hour |

**Rule query:**
```kql
AppRequests
| where AppRoleName == "ca-udip-ai-assistant-prod"
| where Name has "/api/query" or Name has "/api/chat" or Name has "/api/search"
| extend UserPrincipal = tostring(Properties["user_id"])
| summarize QueryCount = count() by UserPrincipal, bin(TimeGenerated, 1h)
| where QueryCount > 100
| project UserPrincipal, QueryCount, TimeGenerated
```

**Entity mapping:**
- Account: UserPrincipal

Click **Create**.

#### 1.4.4 After-Hours PII Tier 3 Access

| Setting | Value |
|---------|-------|
| Name | `EEOC-PII-001: After-hours access to PII tier 3 data` |
| Severity | High |
| MITRE ATT&CK | Collection — Data from Information Repositories |
| Status | Enabled |
| Run query every | 1 hour |
| Lookup data from the last | 1 hour |

**Rule query:**
```kql
AppTraces
| where Message has "pii_tier_3" or Message has "charging_party_ssn"
    or Message has "respondent_ein" or Message has "medical_records"
| extend LocalTime = datetime_utc_to_local(TimeGenerated, 'US/Eastern')
| extend HourOfDay = hourofday(LocalTime)
| extend DayOfWeek = dayofweek(LocalTime)
| where DayOfWeek == 0d or DayOfWeek == 6d  // Weekend
    or HourOfDay < 7 or HourOfDay > 19      // Outside 07:00-19:00 ET
| extend UserPrincipal = tostring(Properties["user_id"])
| project TimeGenerated, LocalTime, UserPrincipal, Message
```

**Entity mapping:**
- Account: UserPrincipal

**Alert grouping:** Group per UserPrincipal within 4 hours.

Click **Next: Automated response** > attach `playbook-notify-security` > **Create**.

#### 1.4.5 FOIA Export Activity

| Setting | Value |
|---------|-------|
| Name | `EEOC-FOIA-001: FOIA export activity detected` |
| Severity | Informational |
| MITRE ATT&CK | Exfiltration — Exfiltration Over Web Service |
| Status | Enabled |
| Run query every | 15 minutes |
| Lookup data from the last | 15 minutes |

**Rule query:**
```kql
AppTraces
| where Message has "foia_export" or Message has "FOIA_EXPORT"
| extend UserPrincipal = tostring(Properties["user_id"])
| extend ExportDetails = tostring(Properties["export_metadata"])
| project TimeGenerated, UserPrincipal, ExportDetails, Message
```

Every FOIA export triggers an alert regardless of volume. This is a compliance requirement.

**Entity mapping:**
- Account: UserPrincipal

Click **Create**.

**Verify all rules:** Navigate to **Sentinel** > **Analytics** > **Active rules**. All five rules should show "Enabled" with the next scheduled run time visible.

### 1.5 SOAR Automation Playbooks

Playbooks are Logic Apps triggered by Sentinel incidents. Create each one below.

#### 1.5.1 Playbook: Notify Security Team on High-Severity Alert

1. Navigate to **Sentinel** > **Automation** > **+ Create** > **Playbook with incident trigger**
2. **Basics:**
   - Name: `playbook-notify-security`
   - Resource group: `rg-eeoc-ai-platform-prod`
   - Region: `US Gov Virginia`
   - Enable log analytics: Yes, workspace `log-eeoc-ai-prod`
3. Click **Next: Connections** > **Next: Review** > **Create and continue to designer**

**Logic App Designer steps:**

4. Trigger is pre-populated: **Microsoft Sentinel incident**
5. Click **+ New step** > search **Condition**
6. Condition: `Severity` is equal to `High` or `Critical`
7. In the **If true** branch:
   a. **+ New step** > search **Send an email (V2)** (Office 365 Outlook connector)
   b. To: `security-ops@eeoc.gov`
   c. Subject: `[Sentinel] @{triggerBody()?['properties']?['severity']} — @{triggerBody()?['properties']?['title']}`
   d. Body:
      ```
      Incident: @{triggerBody()?['properties']?['title']}
      Severity: @{triggerBody()?['properties']?['severity']}
      Description: @{triggerBody()?['properties']?['description']}
      Incident URL: @{triggerBody()?['properties']?['incidentUrl']}
      ```
   e. **+ New step** > search **Create a work item** (Azure DevOps connector)
   f. Organization: EEOC Azure DevOps org
   g. Project: `EEOC-AI-Platform`
   h. Work item type: `Bug`
   i. Title: `[Security] @{triggerBody()?['properties']?['title']}`
   j. Assign to: `security-ops@eeoc.gov`
8. Click **Save**

**Attach to Sentinel:**
1. **Sentinel** > **Automation** > **+ Create** > **Automation rule**
2. Name: `auto-run-notify-security`
3. Trigger: When incident is created
4. Conditions: Severity = High or Critical
5. Actions: Run playbook > `playbook-notify-security`
6. Click **Apply**

#### 1.5.2 Playbook: AI Circuit Breaker Notification

1. **Sentinel** > **Automation** > **+ Create** > **Playbook with incident trigger**
2. Name: `playbook-circuit-breaker`
3. Resource group: `rg-eeoc-ai-platform-prod`
4. Create and continue to designer

**Logic App Designer steps:**

4. Trigger: **Microsoft Sentinel incident**
5. **+ New step** > **Send an email (V2)**
   - To: `adr-team-leads@eeoc.gov; triage-team-leads@eeoc.gov`
   - Subject: `[Circuit Breaker] AI service degraded — @{triggerBody()?['properties']?['title']}`
   - Body:
     ```
     An AI circuit breaker has been triggered.

     Incident: @{triggerBody()?['properties']?['title']}
     Time: @{triggerBody()?['properties']?['createdTimeUtc']}
     Description: @{triggerBody()?['properties']?['description']}

     The AI Assistant may be returning fallback responses.
     Incident URL: @{triggerBody()?['properties']?['incidentUrl']}
     ```
6. Click **Save**

**Create a Sentinel analytics rule to trigger this playbook:**

Navigate to **Sentinel** > **Analytics** > **+ Create** > **Scheduled query rule**:

| Setting | Value |
|---------|-------|
| Name | `EEOC-AI-002: AI circuit breaker triggered` |
| Severity | High |
| Run query every | 5 minutes |
| Lookup data from the last | 5 minutes |

```kql
AppTraces
| where Message has "circuit_breaker_open" or Message has "CircuitBreakerOpen"
| project TimeGenerated, AppRoleName, Message
```

Attach `playbook-circuit-breaker` in the automated response tab.

#### 1.5.3 Playbook: WORM Deletion Attempt Alert

1. **Sentinel** > **Automation** > **+ Create** > **Playbook with incident trigger**
2. Name: `playbook-worm-deletion`
3. Resource group: `rg-eeoc-ai-platform-prod`
4. Create and continue to designer

**Logic App Designer steps:**

4. Trigger: **Microsoft Sentinel incident**
5. **+ New step** > **Send an email (V2)**
   - To: `records-management-officer@eeoc.gov`
   - CC: `security-ops@eeoc.gov; ciso@eeoc.gov`
   - Subject: `[CRITICAL] WORM deletion attempt on audit archive`
   - Body:
     ```
     A deletion or modification attempt was detected on the WORM-protected
     audit archive container (hub-audit-archive).

     This is a potential records tampering event and requires immediate investigation.

     Incident: @{triggerBody()?['properties']?['title']}
     Time: @{triggerBody()?['properties']?['createdTimeUtc']}
     Description: @{triggerBody()?['properties']?['description']}

     Incident URL: @{triggerBody()?['properties']?['incidentUrl']}
     ```
6. Click **Save**

**Create a Sentinel analytics rule to trigger this playbook:**

Navigate to **Sentinel** > **Analytics** > **+ Create** > **Scheduled query rule**:

| Setting | Value |
|---------|-------|
| Name | `EEOC-WORM-001: WORM container deletion attempt` |
| Severity | Critical |
| Run query every | 5 minutes |
| Lookup data from the last | 5 minutes |

```kql
StorageBlobLogs
| where AccountName == "steeocaiprod"
| where ObjectKey has "hub-audit-archive"
| where OperationName in ("DeleteBlob", "SetBlobTier", "PutBlob", "SetImmutabilityPolicy")
| where StatusCode != 409  // 409 = blocked by immutability policy (expected)
| project TimeGenerated, CallerIpAddress, OperationName, ObjectKey, StatusCode, StatusText
```

Attach `playbook-worm-deletion` in the automated response tab.

---

## 2. NSG Flow Logs and Traffic Analytics

M-21-31 EL3 requires full network telemetry including flow records for all network security group boundaries.

### 2.1 Enable NSG Flow Logs

Repeat the steps below for each NSG in the platform. The platform has the following NSGs:

| NSG Name | Associated Subnet |
|----------|-------------------|
| `nsg-eeoc-apps-prod` | `snet-apps` |
| `nsg-eeoc-postgres-prod` | `snet-postgres` |

#### Steps (per NSG):

1. Navigate to **Azure Portal** > search **Network Watcher**
2. Under **Logs**, click **Flow logs**
3. Click **+ Create**
4. **Basics tab:**

| Setting | Value |
|---------|-------|
| Subscription | EEOC Azure Gov subscription |
| NSG | Select the target NSG (e.g., `nsg-eeoc-apps-prod`) |
| Flow log name | `fl-nsg-eeoc-apps-prod` (match NSG name) |
| Storage account | `steeocaiprod` |
| Retention (days) | `365` |

5. **Configuration tab:**

| Setting | Value |
|---------|-------|
| Flow log version | `Version 2` |
| Flow logs format | JSON |

   Version 2 includes bytes transferred and flow state (begin/end/ongoing), required for bandwidth analysis.

6. **Analytics tab:**

| Setting | Value |
|---------|-------|
| Enable Traffic Analytics | `Yes` |
| Traffic Analytics processing interval | `Every 10 minutes` |
| Log Analytics workspace | `log-eeoc-ai-prod` |

7. Click **Review + create** > **Create**
8. Repeat for `nsg-eeoc-postgres-prod` with flow log name `fl-nsg-eeoc-postgres-prod`

### 2.2 Enable Traffic Analytics

Traffic Analytics is enabled as part of the flow log creation above. To verify:

1. Navigate to **Network Watcher** > **Traffic Analytics**
2. Confirm both NSGs appear in the data
3. Allow 30 minutes for initial data processing

**Verify with KQL:**
```kql
AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| summarize count() by NSGList_s
```

Both NSGs should return rows.

**Key Traffic Analytics views to review weekly:**
- Geo-distribution of traffic (verify no unexpected foreign IPs)
- Blocked traffic summary (NSG deny hits)
- Top talkers by bytes (spot anomalous data exfiltration)
- Port utilization (verify only expected ports are in use)

---

## 3. Azure DNS Analytics

### 3.1 Enable DNS Analytics Solution

1. Navigate to **Azure Portal** > search **Log Analytics workspaces**
2. Select `log-eeoc-ai-prod`
3. Under **Classic** > **Solutions** (or **Legacy solutions**), click **+ Add**
4. Search for **DNS Analytics (Preview)**
5. Select it > click **Create**
6. Workspace: `log-eeoc-ai-prod`
7. Click **OK**

> Note: DNS Analytics is a legacy solution. If the solution gallery is deprecated in your portal version, use the equivalent Sentinel content hub pack: **Sentinel** > **Content hub** > search **DNS** > install **DNS Essentials**.

### 3.2 Configure Diagnostic Settings

If the platform uses Azure Private DNS zones (created for private endpoints), configure diagnostics on each:

1. Navigate to **Private DNS zones** (e.g., `privatelink.postgres.database.usgovcloudapi.net`)
2. **Monitoring** > **Diagnostic settings** > **+ Add diagnostic setting**
3. Settings:

| Setting | Value |
|---------|-------|
| Name | `dns-diag-to-sentinel` |
| Log categories | All logs |
| Destination | Send to Log Analytics workspace: `log-eeoc-ai-prod` |

4. Click **Save**
5. Repeat for all private DNS zones:
   - `privatelink.postgres.database.usgovcloudapi.net`
   - `privatelink.redis.cache.usgovcloudapi.net`
   - `privatelink.blob.core.usgovcloudapi.net`
   - `privatelink.table.core.usgovcloudapi.net`
   - `privatelink.vaultcore.usgovcloudapi.net`
   - `privatelink.servicebus.usgovcloudapi.net`

### 3.3 DNS Alert Rules

Navigate to **Sentinel** > **Analytics** > **+ Create** > **Scheduled query rule** for each:

#### 3.3.1 DNS Queries to Known Malicious Domains

| Setting | Value |
|---------|-------|
| Name | `EEOC-DNS-001: Query to known malicious domain` |
| Severity | High |
| Run query every | 15 minutes |
| Lookup data from the last | 15 minutes |

```kql
DnsEvents
| where QueryType == "A" or QueryType == "AAAA"
| join kind=inner (
    _GetWatchlist('MaliciousDomains')
    | project Domain = SearchKey
) on $left.Name == $right.Domain
| project TimeGenerated, ClientIP, Name, QueryType
```

> Prerequisite: Create a Sentinel watchlist named `MaliciousDomains` populated with threat intelligence domain IOCs. Navigate to **Sentinel** > **Watchlists** > **+ New** > Name: `MaliciousDomains`, SearchKey: `Domain`. Upload a CSV with known-bad domains sourced from CISA threat feeds.

#### 3.3.2 Unusual DNS Query Volume

| Setting | Value |
|---------|-------|
| Name | `EEOC-DNS-002: Unusual DNS query volume` |
| Severity | Medium |
| Run query every | 1 hour |
| Lookup data from the last | 1 hour |

```kql
DnsEvents
| summarize QueryCount = count() by ClientIP, bin(TimeGenerated, 1h)
| where QueryCount > 1000
| project ClientIP, QueryCount, TimeGenerated
```

---

## 4. Azure Network Watcher

### 4.1 Enable Network Watcher

Network Watcher is auto-enabled per region when you create a VNet. Verify it exists:

1. Navigate to **Azure Portal** > search **Network Watcher**
2. Under **Overview**, expand the subscription
3. Confirm `USGov Virginia` shows status **Enabled**
4. If not present, click **+ Add** > select the subscription and `USGov Virginia` > **Add**

### 4.2 On-Demand Packet Capture

Configure the capability so it is ready when needed during incident response.

**Prerequisites:**

1. The `AzureNetworkWatcherExtension` VM extension must be installed on any VMs that need packet capture. For Container Apps (serverless), packet capture operates at the VNet level via NSG flow logs and cannot capture individual container packets. For VMs or VMSS-backed workloads:
   - Navigate to the VM > **Extensions + applications** > **+ Add**
   - Select **Network Watcher Agent for Linux**
   - Click **Review + create** > **Create**

**Storage configuration for captured packets:**

1. Navigate to **Storage accounts** > `steeocaiprod`
2. **Containers** > **+ Container**
3. Name: `packet-captures`
4. Access level: `Private`
5. After creation, navigate to the container > **Lifecycle management** (on the storage account)
6. **+ Add a rule**:
   - Name: `delete-packet-captures-30d`
   - Rule scope: Limit blobs with filters
   - Blob prefix: `packet-captures/`
   - Base blobs: Delete after 30 days since creation
   - Click **Add**

### 4.3 Incident Response Packet Capture Procedure

When security operations needs to capture packets during an active investigation:

1. Navigate to **Network Watcher** > **Packet capture** > **+ Add**
2. Settings:

| Setting | Value |
|---------|-------|
| Target resource | Select the target VM or VMSS instance |
| Packet capture name | `ir-YYYYMMDD-ticket-number` |
| Storage account | `steeocaiprod` |
| Storage container | `packet-captures` |
| Maximum bytes per packet | `0` (capture full packet) |
| Maximum bytes per session | `1073741824` (1 GB) |
| Time limit (seconds) | `18000` (5 hours max) |

3. **Filters** (optional, to reduce noise):
   - Protocol: `TCP`
   - Local port: (set if targeting a specific service)
   - Remote IP: (set if investigating a specific source)
4. Click **OK** to start capture
5. To stop early: select the capture > **Stop**
6. Download the `.cap` file from `steeocaiprod/packet-captures/` for analysis in Wireshark or similar tool

**Retention:** Packet captures are automatically deleted after 30 days by the lifecycle management rule configured above. For captures related to active investigations, copy them to a litigation hold container before the 30-day expiry.

---

## 5. Log Analytics Workspace Configuration

### 5.1 Interactive Retention (12 Months)

M-21-31 requires 12 months of immediately queryable log data.

1. Navigate to **Log Analytics workspaces** > `log-eeoc-ai-prod`
2. **Settings** > **Usage and estimated costs**
3. Click **Data Retention**
4. Set retention slider to **365 days** (12 months)
5. Click **OK**

This sets the workspace-wide default. All tables inherit this retention unless overridden.

### 5.2 Archive Tier (30 Months Total)

Beyond the 12-month interactive window, data transitions to the archive tier for an additional 18 months (30 months total retention). Archive data is queryable via search jobs and restore operations.

1. Navigate to **Log Analytics workspaces** > `log-eeoc-ai-prod`
2. **Settings** > **Tables**
3. For each critical table, click the ellipsis (**...**) > **Manage table**
4. Set:

| Setting | Value |
|---------|-------|
| Interactive retention | 365 days |
| Total retention | 913 days (approximately 30 months) |

5. Click **Save**

Apply this to the following tables:

| Table | Justification |
|-------|---------------|
| `SigninLogs` | Authentication events — M-21-31 core requirement |
| `AADNonInteractiveUserSignInLogs` | Service account activity |
| `AuditLogs` | Entra ID configuration changes |
| `AzureActivity` | Control plane operations |
| `AppRequests` | Application request telemetry |
| `AppTraces` | Application audit trail (HMAC records) |
| `AppExceptions` | Application error forensics |
| `StorageBlobLogs` | WORM container access audit |
| `AzureNetworkAnalytics_CL` | Network flow records |
| `SecurityIncident` | Sentinel incident history |
| `SecurityAlert` | Sentinel alert history |
| `ContainerAppConsoleLogs_CL` | Container runtime logs |

### 5.3 Per-Table Retention Overrides

Some tables have different retention needs:

1. Navigate to **Log Analytics workspaces** > `log-eeoc-ai-prod` > **Tables**
2. For each table below, click **...** > **Manage table** and set:

| Table | Interactive Retention | Total Retention | Rationale |
|-------|----------------------|-----------------|-----------|
| `Heartbeat` | 30 days | 90 days | Infrastructure health only |
| `Perf` | 90 days | 180 days | Performance baseline, not compliance |
| `ContainerLogV2` | 90 days | 365 days | Operational debugging |
| `AzureMetrics` | 90 days | 180 days | Capacity planning |

These overrides reduce cost for high-volume, low-compliance-value tables without affecting M-21-31 coverage.

### 5.4 Data Export Rules to Cold Storage

For long-term archive beyond Log Analytics retention (litigation, NARA requirements), configure continuous export to blob storage.

#### 5.4.1 Create Archive Storage Container

1. Navigate to **Storage accounts** > `steeocaiprod`
2. **Containers** > **+ Container**
3. Name: `log-archive-cold`
4. Access level: `Private`
5. After creation, open the container > **Access policy**
6. Add **immutability policy**: Time-based retention of `2555` days (7 years)
7. Click **Save**

#### 5.4.2 Configure Data Export Rules

1. Navigate to **Log Analytics workspaces** > `log-eeoc-ai-prod`
2. **Settings** > **Data Export** > **+ New export rule**
3. Rule 1:

| Setting | Value |
|---------|-------|
| Rule name | `export-security-logs` |
| Destination | Storage account: `steeocaiprod`, Container: `log-archive-cold` |
| Tables | `SigninLogs`, `AuditLogs`, `SecurityAlert`, `SecurityIncident`, `AzureActivity` |
| Enable | Yes |

4. Click **Save**
5. Create Rule 2:

| Setting | Value |
|---------|-------|
| Rule name | `export-app-audit-logs` |
| Destination | Storage account: `steeocaiprod`, Container: `log-archive-cold` |
| Tables | `AppTraces`, `AppRequests`, `StorageBlobLogs` |
| Enable | Yes |

6. Click **Save**

Data export runs continuously. Exported data lands in the container as JSON files partitioned by table name and date: `{TableName}/y={year}/m={month}/d={day}/h={hour}/`.

### 5.5 Workspace RBAC

Apply least-privilege access to the Log Analytics workspace using table-level and resource-level RBAC.

#### 5.5.1 Workspace-Level Roles

Navigate to **Log Analytics workspaces** > `log-eeoc-ai-prod` > **Access control (IAM)** > **+ Add role assignment**:

| Role | Assignees | Scope |
|------|-----------|-------|
| Log Analytics Reader | `EEOC-AI-Platform-Developers` (Entra group) | Workspace |
| Log Analytics Contributor | `EEOC-AI-Platform-Ops` (Entra group) | Workspace |
| Microsoft Sentinel Responder | `EEOC-Security-Ops` (Entra group) | Workspace |
| Microsoft Sentinel Contributor | `EEOC-Security-Admins` (Entra group) | Workspace |

#### 5.5.2 Table-Level RBAC (Restrict PII-Adjacent Tables)

Restrict access to tables containing sensitive query data:

1. Navigate to **Log Analytics workspaces** > `log-eeoc-ai-prod` > **Tables**
2. Select `AppTraces` > **...** > **Access control (IAM)** > **+ Add** > **Add custom role**
3. Role name: `AppTraces Reader - Security Only`
4. Permissions: `Microsoft.OperationalInsights/workspaces/tables/query/read`
5. Assignable scope: Table level
6. Assign to: `EEOC-Security-Ops` and `EEOC-Security-Admins` only

Repeat for `SigninLogs` if needed — developers should not have direct access to sign-in telemetry.

#### 5.5.3 Access Mode

1. Navigate to **Log Analytics workspaces** > `log-eeoc-ai-prod` > **Properties**
2. Set **Access control mode** to `Use resource or workspace permissions`
3. Click **Save**

This means users with Reader access on a specific Azure resource (e.g., a Container App) can only query logs for that resource, not the entire workspace.

---

## 6. Entra ID Identity Protection

### 6.1 Enable Risk Policies

#### 6.1.1 User Risk Policy

1. Navigate to **Entra ID** > **Security** > **Identity Protection**
2. Click **User risk policy**
3. Settings:

| Setting | Value |
|---------|-------|
| Assignments - Users | All users (or scoped to `EEOC-AI-Platform-Users` group) |
| User risk level | `High` |
| Controls - Access | Allow access, **Require password change** |
| Enforce policy | On |

4. Click **Save**

#### 6.1.2 Sign-In Risk Policy

1. **Identity Protection** > **Sign-in risk policy**
2. Settings:

| Setting | Value |
|---------|-------|
| Assignments - Users | All users |
| Sign-in risk level | `Medium and above` |
| Controls - Access | Allow access, **Require multifactor authentication** |
| Enforce policy | On |

3. Click **Save**

#### 6.1.3 Conditional Access — Impossible Travel

1. Navigate to **Entra ID** > **Security** > **Conditional Access** > **+ New policy**
2. Name: `Block impossible travel sign-ins`
3. Assignments:
   - Users: All users
   - Conditions > Sign-in risk > Select risk levels: `High`
4. Access controls:
   - Grant: `Block access`
5. Enable policy: `On`
6. Click **Create**

#### 6.1.4 Conditional Access — Anonymous IP and Malware-Linked IP

1. **Conditional Access** > **+ New policy**
2. Name: `MFA for risky IP sign-ins`
3. Assignments:
   - Users: All users
   - Conditions > Sign-in risk > Select: `Medium`, `High`
   - Conditions > Locations > Configure: Yes > Include: Any location > Exclude: All trusted locations
4. Access controls:
   - Grant: `Require multifactor authentication`
5. Enable policy: `On`
6. Click **Create**

### 6.2 Feed Risk Detections to Sentinel

Risk detection data flows automatically to Sentinel if the Entra ID data connector (Section 1.2.1) is configured with sign-in logs enabled. Verify:

```kql
AADUserRiskEvents
| where TimeGenerated > ago(7d)
| summarize count() by RiskEventType
```

To create a Sentinel analytics rule for risk detections:

Navigate to **Sentinel** > **Analytics** > **+ Create** > **Scheduled query rule**:

| Setting | Value |
|---------|-------|
| Name | `EEOC-ID-001: Identity Protection risk detection` |
| Severity | High |
| Run query every | 30 minutes |
| Lookup data from the last | 30 minutes |

```kql
AADUserRiskEvents
| where RiskLevel in ("high", "medium")
| where RiskEventType in (
    "impossibleTravel",
    "anonymizedIPAddress",
    "malwareInfectedIPAddress",
    "unfamiliarFeatures",
    "leakedCredentials"
)
| project TimeGenerated, UserPrincipalName, RiskEventType, RiskLevel,
    IPAddress, Location
```

Attach `playbook-notify-security` in the automated response tab.

---

## 7. TLS Inspection

### 7.1 Application Gateway End-to-End TLS

The platform uses Azure Front Door for public ingress (ADR only) and internal Container Apps for service-to-service communication. TLS inspection is handled at two levels:

**Level 1 — Front Door to Backend (ADR):**

Azure Front Door terminates the external TLS connection and re-encrypts traffic to the Container App backend. This is already configured in the deployment guide (Section 2.18). Front Door WAF inspects HTTP payloads between TLS termination and re-encryption.

**Level 2 — Internal Service-to-Service:**

All Container Apps communicate over the internal VNet. Container Apps Environment enforces TLS 1.2 on all ingress endpoints. Service-to-service calls within the environment use internal HTTPS.

**Azure Firewall Premium TLS Inspection (Optional — if network-level inspection is required):**

If the agency requires network-level TLS inspection beyond WAF:

1. Navigate to **Azure Portal** > search **Firewalls** > select or create `fw-eeoc-ai-prod`
2. SKU must be **Premium** (Standard does not support TLS inspection)
3. **Firewall Policy** > **TLS inspection** tab:
   a. Enable TLS inspection: `Yes`
   b. Certificate: Use an intermediate CA certificate stored in Key Vault
      - Navigate to **Key Vault** > `kv-eeoc-ai-prod` > **Certificates** > **+ Generate/Import**
      - Generate a self-signed intermediate CA or import an enterprise CA-signed intermediate
      - Certificate name: `fw-tls-inspection-ca`
   c. Select the certificate in the Firewall policy TLS inspection settings
4. **Application rules** > Add rules specifying which traffic to inspect:
   - Rule: Inspect all outbound HTTPS from `snet-apps`
   - Exclusions: Traffic to Azure Government management endpoints (to prevent breakage)
5. Click **Save**

> Note: TLS inspection with Azure Firewall Premium adds latency (~2-5ms per request) and requires careful certificate management. Evaluate whether Front Door WAF inspection is sufficient for the threat model before enabling network-level TLS inspection.

### 7.2 Traffic Inspection Matrix

| Traffic Path | TLS Termination Point | Inspection Method | Inspected? |
|-------------|----------------------|-------------------|------------|
| Internet → Front Door → ADR | Front Door edge | WAF rule engine (OWASP 3.2, custom rules) | Yes |
| Front Door → ADR Container App | Front Door re-encrypts; Container App terminates | N/A (encrypted tunnel, trusted) | Pass-through |
| ADR → MCP Hub (APIM) | APIM gateway | APIM policies (rate limit, JWT validation) | Yes (L7) |
| MCP Hub → Spoke services | Container App ingress | mTLS within Container Apps Environment | Pass-through |
| Spoke → PostgreSQL | PostgreSQL private endpoint | TLS 1.2 required; no payload inspection | Pass-through |
| Spoke → Redis | Redis private endpoint | TLS 1.2 (rediss://) | Pass-through |
| Spoke → Event Hub | Event Hub private endpoint | TLS 1.2 (AMQPS) | Pass-through |
| Any → Internet (outbound) | Azure Firewall (if Premium) | TLS inspection (if enabled) | Configurable |

---

## 8. M-21-31 Compliance Dashboard (Azure Monitor Workbook)

### 8.1 Create the Workbook

1. Navigate to **Azure Portal** > search **Monitor** > **Workbooks**
2. Click **+ New**
3. Click **Advanced Editor** (toolbar: `</>`)
4. Replace the JSON with the template below, then click **Apply**
5. Click **Save**:
   - Title: `M-21-31 EL3 Compliance Dashboard`
   - Resource group: `rg-eeoc-ai-platform-prod`
   - Location: `US Gov Virginia`

Alternatively, build each section interactively as described below.

### 8.2 Dashboard Sections

Build the workbook by adding each section as a new element.

#### 8.2.1 M-21-31 Maturity Level Per Application

1. In the workbook editor, click **+ Add** > **Add query**
2. Data source: `Logs`
3. Resource: `log-eeoc-ai-prod`
4. Query:

```kql
datatable(Application:string, EL1:string, EL2:string, EL3:string, Status:string)
[
    "ADR Web Application", "Complete", "Complete", "Complete", "EL3 Achieved",
    "ADR Function App", "Complete", "Complete", "Complete", "EL3 Achieved",
    "UDIP AI Assistant", "Complete", "Complete", "Complete", "EL3 Achieved",
    "Triage Web Application", "Complete", "Complete", "Complete", "EL3 Achieved",
    "Triage Function App", "Complete", "Complete", "Complete", "EL3 Achieved",
    "MCP Hub Aggregator", "Complete", "Complete", "Complete", "EL3 Achieved"
]
```

5. Visualization: `Grid`
6. Click **Done Editing**

> This is a static reference table. Update the `Status` column manually if an application falls out of compliance. Alternatively, replace with a dynamic query against a compliance tracking table in UDIP if one is implemented.

#### 8.2.2 AU Control Compliance Status

1. **+ Add** > **Add query**
2. Query:

```kql
datatable(Control:string, Description:string, Implementation:string, Status:string)
[
    "AU-2", "Audit Events", "AppTraces + AppRequests via App Insights", "Implemented",
    "AU-3", "Content of Audit Records", "HMAC-signed JSON with user, action, resource, timestamp", "Implemented",
    "AU-4", "Audit Storage Capacity", "Log Analytics 365d + Archive 913d + Blob cold storage 7yr", "Implemented",
    "AU-5", "Response to Audit Failures", "Sentinel rule EEOC-AUDIT-001 + playbook-notify-security", "Implemented",
    "AU-6", "Audit Review/Analysis", "Sentinel UEBA + Analytics Rules + Weekly review SOP", "Implemented",
    "AU-7", "Audit Reduction/Report Gen", "KQL queries + Monitor Workbooks + Superset dashboards", "Implemented",
    "AU-8", "Time Stamps", "Azure platform NTP sync, UTC timestamps in all logs", "Implemented",
    "AU-9", "Protection of Audit Info", "WORM blob + RBAC + table-level permissions", "Implemented",
    "AU-10", "Non-repudiation", "HMAC-SHA256 integrity chains on audit records", "Implemented",
    "AU-11", "Audit Record Retention", "30 months interactive+archive, 7 years cold storage", "Implemented",
    "AU-12", "Audit Generation", "All 6 apps emit structured audit events to shared workspace", "Implemented",
    "AU-13", "Monitoring for Info Disclosure", "Sentinel FOIA export rule + PII tier 3 access rule", "Implemented"
]
```

3. Visualization: `Grid`
4. Click **Done Editing**

#### 8.2.3 Log Volume Per Application Per Day

1. **+ Add** > **Add query**
2. Query:

```kql
AppRequests
| where TimeGenerated > ago(30d)
| summarize DailyVolumeMB = sum(ItemCount) * 0.001 by
    AppRoleName,
    Day = bin(TimeGenerated, 1d)
| render timechart
```

3. Visualization: `Time chart`
4. Size: `Full`
5. Click **Done Editing**

Add a second query for trace volume:

```kql
AppTraces
| where TimeGenerated > ago(30d)
| summarize TraceCount = count(), EstimatedMB = count() * 0.0005 by
    AppRoleName,
    Day = bin(TimeGenerated, 1d)
| render timechart
```

#### 8.2.4 Audit Record Integrity (HMAC Validation Results)

1. **+ Add** > **Add query**
2. Query:

```kql
AppTraces
| where TimeGenerated > ago(7d)
| where Message has "hmac_validation"
| extend ValidationResult = iif(Message has "hmac_valid", "Pass", "Fail")
| summarize
    TotalRecords = count(),
    PassCount = countif(ValidationResult == "Pass"),
    FailCount = countif(ValidationResult == "Fail")
    by AppRoleName, bin(TimeGenerated, 1d)
| extend PassRate = round(100.0 * PassCount / TotalRecords, 2)
| project TimeGenerated, AppRoleName, TotalRecords, PassCount, FailCount, PassRate
| order by TimeGenerated desc
```

3. Visualization: `Grid`
4. Add conditional formatting: PassRate < 100 → red background
5. Click **Done Editing**

#### 8.2.5 Retention Policy Adherence

1. **+ Add** > **Add query**
2. Query:

```kql
Usage
| where TimeGenerated > ago(1d)
| where IsBillable == true
| summarize DataIngestedMB = sum(Quantity) by DataType
| join kind=leftouter (
    datatable(DataType:string, RequiredRetentionDays:int, ConfiguredRetentionDays:int)
    [
        "SigninLogs", 913, 913,
        "AuditLogs", 913, 913,
        "AzureActivity", 913, 913,
        "AppRequests", 913, 913,
        "AppTraces", 913, 913,
        "StorageBlobLogs", 913, 913,
        "SecurityAlert", 913, 913,
        "SecurityIncident", 913, 913,
        "Heartbeat", 90, 90,
        "Perf", 180, 180
    ]
) on DataType
| extend Compliant = iif(ConfiguredRetentionDays >= RequiredRetentionDays, "Yes", "No")
| project DataType, DataIngestedMB, RequiredRetentionDays, ConfiguredRetentionDays, Compliant
| order by DataIngestedMB desc
```

3. Visualization: `Grid`
4. Add conditional formatting: Compliant == "No" → red background
5. Click **Done Editing**

#### 8.2.6 Open Litigation Holds

1. **+ Add** > **Add query**
2. Query:

```kql
StorageBlobLogs
| where AccountName == "steeocaiprod"
| where OperationName == "SetLegalHold"
| summarize LastHoldAction = max(TimeGenerated) by ObjectKey, StatusText
| where StatusText has "true"  // legal hold is active
| project ObjectKey, LastHoldAction
| order by LastHoldAction desc
```

3. Visualization: `Grid`
4. Click **Done Editing**

Add a text block above this query:

5. **+ Add** > **Add text**
6. Content:
```
### Open Litigation Holds
Containers or blobs with active legal holds that prevent deletion regardless of retention policy expiration.
Contact Records Management Officer before any action on held data.
```

#### 8.2.7 Save and Pin the Workbook

1. Click **Save** in the workbook toolbar
2. To pin to a shared dashboard: click **Pin** icon on any visualization > select or create a dashboard named `M-21-31 Compliance`
3. Share the workbook: **Workbook** > **Share** > add `EEOC-Security-Ops` and `EEOC-AI-Platform-Ops` groups as readers

---

## Appendix A: Resource Summary

New resources created by this guide:

| Resource Type | Name | Purpose |
|--------------|------|---------|
| Microsoft Sentinel | (enabled on `log-eeoc-ai-prod`) | SIEM + SOAR + UEBA |
| Logic App | `playbook-notify-security` | Alert → email + ticket |
| Logic App | `playbook-circuit-breaker` | AI circuit breaker → notify team leads |
| Logic App | `playbook-worm-deletion` | WORM tampering → notify Records Officer |
| NSG Flow Log | `fl-nsg-eeoc-apps-prod` | Network telemetry for apps subnet |
| NSG Flow Log | `fl-nsg-eeoc-postgres-prod` | Network telemetry for database subnet |
| Blob Container | `packet-captures` | Network Watcher packet capture storage |
| Blob Container | `log-archive-cold` | Long-term log export (7-year WORM) |
| Lifecycle Rule | `delete-packet-captures-30d` | Auto-delete captures after 30 days |
| Data Export Rule | `export-security-logs` | Continuous export of security tables |
| Data Export Rule | `export-app-audit-logs` | Continuous export of application audit tables |
| Monitor Workbook | `M-21-31 EL3 Compliance Dashboard` | Compliance posture visualization |
| Sentinel Watchlist | `MaliciousDomains` | Threat intel domain IOCs |

Sentinel Analytics Rules created:

| Rule ID | Name | Severity |
|---------|------|----------|
| EEOC-AUTH-001 | Failed authentication > 10/hour per user | High |
| EEOC-AUDIT-001 | Audit write failures > 5/hour | Critical |
| EEOC-AI-001 | Unusual query volume > 100/hour per user | Medium |
| EEOC-AI-002 | AI circuit breaker triggered | High |
| EEOC-PII-001 | After-hours access to PII tier 3 data | High |
| EEOC-FOIA-001 | FOIA export activity detected | Informational |
| EEOC-WORM-001 | WORM container deletion attempt | Critical |
| EEOC-DNS-001 | Query to known malicious domain | High |
| EEOC-DNS-002 | Unusual DNS query volume | Medium |
| EEOC-ID-001 | Identity Protection risk detection | High |

---

## Appendix B: M-21-31 EL3 Control Mapping

| M-21-31 Requirement | EL Level | Implementation | Section |
|---------------------|----------|----------------|---------|
| Centralized log aggregation | EL1 | Log Analytics workspace `log-eeoc-ai-prod` | 5 |
| 12-month interactive retention | EL2 | Workspace retention set to 365 days | 5.1 |
| 18-month total retention (archive) | EL2 | Archive tier set to 913 days per table | 5.2 |
| SIEM with correlation | EL3 | Microsoft Sentinel enabled on workspace | 1.1 |
| User behavior analytics | EL3 | Sentinel UEBA enabled | 1.3 |
| Automated response (SOAR) | EL3 | Logic App playbooks triggered by Sentinel | 1.5 |
| Network flow telemetry | EL3 | NSG flow logs v2 with Traffic Analytics | 2 |
| DNS logging and analytics | EL3 | DNS Analytics solution + alert rules | 3 |
| Packet capture capability | EL3 | Network Watcher on-demand capture | 4 |
| Identity threat detection | EL3 | Entra ID Identity Protection risk policies | 6 |
| TLS visibility | EL3 | Front Door WAF + optional Firewall Premium | 7 |
| Compliance reporting | EL3 | Monitor Workbook with AU control status | 8 |
| Long-term cold storage | EL3 | Data export to WORM blob (7-year retention) | 5.4 |
| RBAC on log data | EL3 | Workspace + table-level role assignments | 5.5 |

---

*End of document.*
