# Azure MCP Hub Setup Guide

**Purpose:** Step-by-step instructions for configuring the EEOC MCP Hub using Azure's native services through the Azure Portal. No custom hub service to build — the hub functionality is assembled from Azure managed services.

**Audience:** EEOC OCIO staff with Azure Portal access. Written as click-by-click instructions.

**Prerequisites:** Azure Government subscription, Global Administrator or Contributor role, familiarity with Azure Portal navigation.

---

## Architecture Overview

Instead of a custom Python service, the MCP Hub is assembled from five Azure managed services:

| Function | Azure Service | What It Does |
|----------|--------------|--------------|
| MCP routing & tool aggregation | Azure API Management (APIM) | Routes tool calls to spokes, aggregates tool catalogs, manages auth |
| Spoke hosting | Azure Container Apps | Hosts ADR, Triage, UDIP, ARC Integration API, OGC Trial Tool |
| Event routing | Azure Event Grid | Routes case lifecycle events between spokes |
| Audit logging | Azure Table Storage + Blob (WORM) | Immutable 7-year audit trail |
| Secret management | Azure Key Vault | HMAC secrets, hash salts, spoke credentials |

The spokes (ADR, Triage, UDIP, etc.) each expose a `POST /mcp` endpoint. Azure API Management sits in front, providing a single unified MCP endpoint that routes to the correct spoke based on tool name.

```
AI Consumer → Azure API Management (single /mcp endpoint)
                    ↓ routes by tool name prefix
              ┌─────┼─────┬──────┬───────┐
              ↓     ↓     ↓      ↓       ↓
            ADR  Triage  UDIP  OGC TT  ARC API
          (10)   (9)   (3+N)   (3)     (11)
```

---

## Step 1: Create the Resource Group

1. Open Azure Portal → **Resource groups** → **Create**
2. Subscription: `EEOC-Production` (or appropriate subscription)
3. Resource group name: `rg-mcp-hub-prod`
4. Region: `USGov Virginia` (or appropriate government region)
5. Tags:
   - `Environment`: `Production`
   - `Project`: `MCP-Hub`
   - `CostCenter`: `OCIO-AI-Platform`
   - `DataClassification`: `AI_AUDIT`
6. Click **Review + create** → **Create**

---

## Step 2: Create the Virtual Network

All hub components communicate over a private VNet. No public internet exposure.

1. **Resource groups** → `rg-mcp-hub-prod` → **Create** → search "Virtual Network"
2. Name: `vnet-mcp-hub`
3. Region: Same as resource group
4. Address space: `10.100.0.0/16`
5. Subnets:
   - `snet-apim`: `10.100.1.0/24` (API Management)
   - `snet-apps`: `10.100.2.0/24` (Container Apps environment)
   - `snet-storage`: `10.100.3.0/24` (Private endpoints for storage)
   - `snet-keyvault`: `10.100.4.0/24` (Private endpoint for Key Vault)
6. Click **Review + create** → **Create**

---

## Step 3: Create Key Vault

1. **Create** → search "Key Vault"
2. Name: `kv-mcp-hub-prod`
3. Region: Same
4. Pricing tier: `Standard`
5. **Networking** tab:
   - Connectivity method: `Private endpoint`
   - Create private endpoint in `snet-keyvault`
6. **Access configuration** tab:
   - Permission model: `Azure role-based access control`
7. Click **Review + create** → **Create**

**After creation, add these secrets:**

| Secret Name | Value | Purpose |
|-------------|-------|---------|
| `MCP-WEBHOOK-SECRET-ADR` | Generate 32+ char random string | HMAC key for ADR event validation |
| `MCP-WEBHOOK-SECRET-ARC-INTEGRATION` | Generate 32+ char random string | HMAC key for ARC Integration API events |
| `MCP-WEBHOOK-SECRET-TRIAGE` | Generate 32+ char random string | HMAC key for Triage events (reserved) |
| `HUB-AUDIT-HASH-SALT` | Generate 32+ char random string | Salt for hashing caller OIDs in audit logs |

To add each secret:
1. Open `kv-mcp-hub-prod` → **Secrets** → **Generate/Import**
2. Upload options: `Manual`
3. Name: (from table above)
4. Value: (generate using PowerShell: `[System.Web.Security.Membership]::GeneratePassword(40,10)`)
5. Click **Create**

---

## Step 4: Create Storage Account (Audit)

1. **Create** → search "Storage account"
2. Name: `stmcphubaudit` (must be globally unique)
3. Region: Same
4. Performance: `Standard`
5. Redundancy: `GRS` (geo-redundant for compliance)
6. **Networking** tab:
   - Network access: `Disable public access and use private access`
   - Add private endpoint in `snet-storage`
7. Click **Review + create** → **Create**

**After creation, configure:**

### Create audit table:
1. Open storage account → **Tables** → **+ Table**
2. Name: `hubauditlog`

### Create audit blob container with WORM:
1. **Containers** → **+ Container**
2. Name: `hub-audit-archive`
3. Public access level: `Private`
4. After creation, open the container → **Access policy**
5. Enable **immutable blob storage** → **Add policy**
6. Policy type: `Time-based retention`
7. Retention period: `2555` days (7 years + 1 day)
8. Click **Save**

Verify: Try to delete a blob in this container — it should fail. The WORM policy prevents all deletions for 2555 days.

---

## Step 5: Create Entra ID App Registrations

Each spoke and the hub itself needs an app registration in Entra ID.

### Hub App Registration:

1. **Microsoft Entra ID** → **App registrations** → **New registration**
2. Name: `EEOC-MCP-Hub`
3. Supported account types: `Single tenant`
4. Redirect URI: (leave blank for M2M)
5. Click **Register**

**After creation:**

6. **App roles** → **Create app role**:
   - Display name: `Hub Read`
   - Value: `Hub.Read`
   - Allowed member types: `Applications`
   - Description: `Read access to MCP Hub tools`
   - Click **Apply**
7. Repeat for `Hub.Write`

8. **Certificates & secrets** → **New client secret**
   - Description: `Hub M2M Secret`
   - Expiry: `24 months`
   - Copy the secret value immediately (shown only once)
   - Store in Key Vault as `HUB-CLIENT-SECRET`

9. Copy the **Application (client) ID** and **Directory (tenant) ID** — you'll need these for APIM configuration.

### Spoke App Registrations:

Repeat the above for each spoke, creating app roles specific to each:

| Spoke | App Name | App Roles |
|-------|----------|-----------|
| ADR | `EEOC-ADR-Mediation` | `MCP.Read`, `MCP.Write` |
| Triage | `EEOC-OFS-Triage` | `MCP.Read`, `MCP.Write` |
| UDIP | `EEOC-UDIP-Analytics` | `Analytics.Read`, `Analytics.Write` |
| OGC Trial Tool | `EEOC-OGC-TrialTool` | `MCP.Read`, `MCP.Write` |
| ARC Integration API | `EEOC-ARC-Integration` | `ARC.Read`, `ARC.Write` |

**Grant hub access to each spoke:**

For each spoke app registration:
1. Open the spoke's app registration → **API permissions** → **Add a permission**
2. Select **My APIs** → select the spoke app
3. Select **Application permissions** → check the Read role
4. Click **Add permissions**
5. Click **Grant admin consent** (requires admin role)

For UDIP specifically: grant `Analytics.Read` (not `MCP.Read`).

---

## Step 6: Create Azure API Management Instance

This is the MCP Hub routing layer.

1. **Create** → search "API Management"
2. Name: `apim-mcp-hub`
3. Region: Same
4. Organization name: `EEOC`
5. Administrator email: (your admin email)
6. Pricing tier: `Standard v2` (supports VNet integration)
7. **Virtual network** tab:
   - Connectivity type: `Internal` (no public internet access)
   - Virtual network: `vnet-mcp-hub`
   - Subnet: `snet-apim`
8. Click **Review + create** → **Create**

Note: APIM provisioning takes 30-45 minutes.

---

## Step 7: Configure APIM as MCP Hub

### 7a. Create Backend Services (one per spoke)

For each spoke:

1. Open `apim-mcp-hub` → **Backends** → **+ Add**
2. Name: (e.g., `adr-spoke`, `triage-spoke`, `udip-spoke`)
3. Type: `Custom URL`
4. Runtime URL: (spoke's internal URL, e.g., `https://adr-app.internal.azurecontainerapps.io`)
5. **Authorization** → **Authorization credentials**:
   - Scheme: `Bearer`
   - For UDIP: configure OBO flow (see Step 8)
   - For others: configure managed identity token acquisition
6. Click **Create**

### 7b. Create the Unified MCP API

1. **APIs** → **+ Add API** → **HTTP**
2. Display name: `MCP Hub`
3. Name: `mcp-hub`
4. URL suffix: `mcp`
5. Click **Create**

### 7c. Add Operations

1. **+ Add operation**
   - Display name: `MCP JSON-RPC`
   - HTTP verb: `POST`
   - URL: `/`
   - Click **Save**

### 7d. Add Inbound Policy for Tool Routing

1. Select the POST operation → **Inbound processing** → **Code editor**
2. Paste this policy:

```xml
<policies>
    <inbound>
        <base />
        <!-- Validate Entra ID bearer token -->
        <validate-azure-ad-token tenant-id="{{tenant-id}}" header-name="Authorization"
            failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
            <client-application-ids>
                <application-id>{{hub-client-id}}</application-id>
            </client-application-ids>
            <required-claims>
                <claim name="roles" match="any">
                    <value>Hub.Read</value>
                    <value>Hub.Write</value>
                </claim>
            </required-claims>
        </validate-azure-ad-token>

        <!-- Generate request ID for audit correlation -->
        <set-header name="X-Request-ID" exists-action="skip">
            <value>@(Guid.NewGuid().ToString())</value>
        </set-header>

        <!-- Parse JSON-RPC body to determine routing -->
        <set-variable name="jsonrpc-method" value="@{
            var body = context.Request.Body.As<JObject>(preserveContent: true);
            return body?["method"]?.ToString() ?? "";
        }" />
        <set-variable name="tool-name" value="@{
            var body = context.Request.Body.As<JObject>(preserveContent: true);
            var p = body?["params"];
            return p?["name"]?.ToString() ?? p?["tool"]?.ToString() ?? "";
        }" />

        <!-- Route based on tool name prefix -->
        <choose>
            <!-- tools/list: aggregate from all spokes (handled in backend) -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("jsonrpc-method") == "tools/list")">
                <!-- Fan out to all spokes, merge results -->
                <!-- This requires a custom policy fragment or backend logic -->
                <set-backend-service backend-id="hub-aggregator" />
            </when>

            <!-- ADR tools (adr.*) -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("tool-name").StartsWith("adr."))">
                <set-backend-service backend-id="adr-spoke" />
            </when>

            <!-- Triage tools (ofs-triage.*) -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("tool-name").StartsWith("ofs-triage."))">
                <set-backend-service backend-id="triage-spoke" />
            </when>

            <!-- UDIP tools (udip.*) -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("tool-name").StartsWith("udip."))">
                <set-backend-service backend-id="udip-spoke" />
            </when>

            <!-- ARC tools (arc.*) -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("tool-name").StartsWith("arc."))">
                <set-backend-service backend-id="arc-spoke" />
            </when>

            <!-- OGC tools (trial.*) -->
            <when condition="@(context.Variables.GetValueOrDefault<string>("tool-name").StartsWith("trial."))">
                <set-backend-service backend-id="ogc-spoke" />
            </when>

            <!-- Default: return error -->
            <otherwise>
                <return-response>
                    <set-status code="400" reason="Unknown tool" />
                    <set-body>{"jsonrpc":"2.0","error":{"code":-32601,"message":"Tool not found"}}</set-body>
                </return-response>
            </otherwise>
        </choose>
    </inbound>
    <outbound>
        <base />
        <!-- Log to audit table (via named value or backend call) -->
        <log-to-eventhub logger-id="hub-audit-logger" partition-id="0">@{
            return new JObject(
                new JProperty("RequestID", context.Request.Headers.GetValueOrDefault("X-Request-ID", "")),
                new JProperty("ToolName", context.Variables.GetValueOrDefault<string>("tool-name")),
                new JProperty("StatusCode", context.Response.StatusCode),
                new JProperty("LatencyMs", context.Elapsed.TotalMilliseconds),
                new JProperty("Timestamp", DateTime.UtcNow.ToString("o"))
            ).ToString();
        }</log-to-eventhub>
    </outbound>
</policies>
```

3. Replace `{{tenant-id}}` and `{{hub-client-id}}` with actual values (or use APIM Named Values)
4. Click **Save**

### 7e. Configure Named Values

1. **Named values** → **+ Add**
2. Add each:
   - `tenant-id`: your Entra tenant ID
   - `hub-client-id`: hub app registration client ID
   - `adr-scope`: `api://adr-client-id/.default`
   - `triage-scope`: `api://triage-client-id/.default`
   - `udip-scope`: `api://udip-client-id/.default`

---

## Step 8: Configure OBO for UDIP

UDIP enforces row-level security using the caller's regional identity from their Entra token. The hub must pass the original caller's identity through to UDIP, not its own managed identity.

1. Open hub app registration (`EEOC-MCP-Hub`) → **API permissions**
2. Add permission for UDIP: `Analytics.Read` (delegated, not application)
3. In APIM, create a policy fragment for UDIP routing that:
   - Extracts the original caller's bearer token from the inbound request
   - Uses MSAL On-Behalf-Of flow to exchange it for a UDIP-scoped token
   - Forwards the OBO token to the UDIP backend

APIM OBO policy for UDIP backend:

```xml
<when condition="@(context.Variables.GetValueOrDefault<string>("tool-name").StartsWith("udip."))">
    <!-- Extract original caller's token -->
    <set-variable name="original-token" value="@{
        return context.Request.Headers.GetValueOrDefault("Authorization", "").Replace("Bearer ", "");
    }" />
    <!-- Exchange via OBO for UDIP-scoped token -->
    <send-request mode="new" response-variable-name="obo-response">
        <set-url>https://login.microsoftonline.us/{{tenant-id}}/oauth2/v2.0/token</set-url>
        <set-method>POST</set-method>
        <set-header name="Content-Type" exists-action="override">
            <value>application/x-www-form-urlencoded</value>
        </set-header>
        <set-body>@{
            return $"grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&client_id={{hub-client-id}}&client_secret={{hub-client-secret}}&assertion={context.Variables["original-token"]}&scope={{udip-scope}}&requested_token_use=on_behalf_of";
        }</set-body>
    </send-request>
    <set-header name="Authorization" exists-action="override">
        <value>@{
            var oboResult = ((IResponse)context.Variables["obo-response"]).Body.As<JObject>();
            return "Bearer " + oboResult["access_token"].ToString();
        }</value>
    </set-header>
    <set-backend-service backend-id="udip-spoke" />
</when>
```

**Important:** Store `hub-client-secret` as an APIM Named Value of type "Secret" (backed by Key Vault reference).

---

## Step 9: Configure Event Grid for Inter-Spoke Events

1. **Create** → search "Event Grid Topic"
2. Name: `evgt-mcp-hub-events`
3. Region: Same
4. Click **Create**

### Create Event Subscriptions:

For ADR case events → Event Grid:
1. Open topic → **+ Event Subscription**
2. Name: `adr-case-events`
3. Endpoint type: `Web Hook`
4. Endpoint URL: (ADR's internal URL + `/api/v1/events`)
5. Filter: Event Type = `case.status_changed`, `case.created`, `case.closed`

For ARC Integration API events → ADR:
1. **+ Event Subscription**
2. Name: `arc-events-to-adr`
3. Endpoint: ADR's events endpoint
4. Filter: Source = `arc-integration-api`

---

## Step 10: Configure Health Monitoring

1. Open `apim-mcp-hub` → **Health probes**
2. Add probe for each backend:
   - Name: `adr-health`
   - Backend: `adr-spoke`
   - Path: `/healthz`
   - Interval: `60` seconds
3. Repeat for each spoke

### Azure Monitor Alerts:

1. **Monitor** → **Alerts** → **Create alert rule**
2. Resource: `apim-mcp-hub`
3. Condition: `Backend Response Time > 30 seconds`
4. Action: Email notification to OCIO team
5. Repeat for: 4xx rate > 10%, 5xx rate > 1%, overall availability < 99%

---

## Step 11: Configure Audit Logging

APIM provides built-in request/response logging. Configure it to write to the audit storage account.

1. Open `apim-mcp-hub` → **Diagnostic settings** → **+ Add diagnostic setting**
2. Name: `hub-audit-diagnostics`
3. Select: `GatewayLogs`, `AllMetrics`
4. Destination: **Send to Log Analytics workspace** (create one if needed)
5. Also: **Archive to a storage account** → select `stmcphubaudit`
6. Click **Save**

For the WORM blob archive with full request/response payloads, the APIM outbound policy (Step 7d) logs to Event Hub, which triggers an Azure Function that writes to the `hub-audit-archive` blob container.

---

## Step 12: Connection Sequence

Follow this exact order. Do not skip gates.

### Phase 1: Hub Infrastructure
- [ ] APIM deployed and healthy (`/healthz` returns 200)
- [ ] VNet peering configured to spoke networks
- [ ] Key Vault accessible from APIM
- [ ] Entra ID token validation working (test with Postman)
- [ ] Audit logging writing to Table Storage and Blob
- [ ] WORM policy verified (try to delete a blob — should fail)

### Phase 2: ARC Integration API (first spoke)
- [ ] Backend `arc-spoke` added to APIM
- [ ] Health probe passing
- [ ] `arc.` prefixed tools routable
- [ ] Write-back tools return correct responses
- [ ] Event Grid subscription receiving ARC events
- [ ] X-Request-ID propagating to spoke and back

### Phase 3: ADR
- [ ] Backend `adr-spoke` added
- [ ] All 10 ADR tools callable through APIM
- [ ] ADR events flowing to Event Grid
- [ ] Request ID correlation verified in both APIM logs and ADR audit tables

### Phase 4: OFS Triage
- [ ] Backend `triage-spoke` added
- [ ] Read tools return live data
- [ ] Async submit_case pattern documented in APIM developer portal
- [ ] Charge metadata auto-population through ARC spoke working

### Phase 5: UDIP (after OBO configured)
- [ ] OBO policy working (verify with a user who has region groups)
- [ ] UDIP queries return regionally scoped data (NOT empty results)
- [ ] Dynamic tool catalog appears correctly (run dbt, verify new tools show up)

### Phase 6: OGC Trial Tool
- [ ] Entra ID auth live on Trial Tool
- [ ] MCP server endpoint responding
- [ ] 3 tools callable through APIM

### Phase 7: Cross-Spoke Verification
- [ ] AI query touching 2+ spokes returns correct combined result
- [ ] Request ID correlates across APIM + spoke audit logs

---

## Tool Catalog Aggregation

APIM does not natively aggregate `tools/list` responses from multiple spokes. Two approaches:

### Option A: Static catalog in APIM (simpler, manual updates)

1. Create an APIM **Policy fragment** that returns a static merged tool catalog
2. Update the catalog when spokes add/remove tools
3. Pros: Simple, no additional services
4. Cons: Manual maintenance, doesn't handle UDIP's dynamic catalog

### Option B: Lightweight aggregator function (recommended)

1. Deploy a small Azure Function (`func-mcp-hub-aggregator`) that:
   - Calls `tools/list` on each registered spoke every 5 minutes
   - Merges results, prefixes tool names with spoke name
   - Caches in Redis
   - Returns merged catalog on request
2. Configure as APIM backend `hub-aggregator`
3. Route `tools/list` requests to this function
4. Handles UDIP's dynamic catalog automatically

The aggregator function is the only custom code needed. It's ~200 lines of Python, not a full service.

---

## Configuration Reference

| Setting | Location | Value |
|---------|----------|-------|
| APIM Internal URL | APIM → Overview | `https://apim-mcp-hub.azure-api.usgovcloudapi.net` |
| Hub Client ID | Entra ID → App registrations | (from Step 5) |
| Hub Tenant ID | Entra ID → Overview | (your tenant ID) |
| Key Vault URI | Key Vault → Overview | `https://kv-mcp-hub-prod.vault.usgovcloudapi.net/` |
| Storage Connection | Storage Account → Access keys | (connection string, store in Key Vault) |
| ADR Spoke URL | Container Apps → ADR → Overview | Internal FQDN |
| Triage Spoke URL | Container Apps → Triage → Overview | Internal FQDN |
| UDIP Spoke URL | Container Apps → UDIP → Overview | Internal FQDN |
| ARC Integration URL | Container Apps → ARC API → Overview | Internal FQDN |
| OGC Trial Tool URL | Container Apps → OGC → Overview | Internal FQDN |

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| 401 on all requests | Token validation misconfigured | Check APIM validate-azure-ad-token policy matches app registration |
| UDIP returns empty results | OBO not working, hub's identity has no region claim | Verify OBO policy, check token has region groups |
| Tool not found | Tool name doesn't match routing prefix | Check APIM choose/when conditions match spoke prefix |
| High latency on UDIP queries | Connection pool exhaustion | Check UDIP's PgBouncer (Prompt 23) |
| Events not routing | Event Grid subscription misconfigured | Check Event Grid subscription filters and endpoint URLs |
| Audit blobs can't be deleted | WORM policy working correctly | This is expected — data is immutable for 7 years |
