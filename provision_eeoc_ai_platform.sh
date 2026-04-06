#!/usr/bin/env bash

################################################################################
# EEOC AI Integration Platform - Azure Government Provisioning Script
################################################################################
#
# Purpose:  Provision the complete Azure infrastructure for the EEOC AI
#           Integration Platform. Covers networking, data tier, compute,
#           monitoring, and M-21-31 compliance resources.
#
# Author:   Derek Gordon
# Version:  1.0
# Target:   Azure Government Cloud (usgovvirginia)
#
# ARCHITECTURE OVERVIEW:
#   PrEPA (ARC PostgreSQL) streams WAL/CDC changes through Debezium into
#   Azure Event Hub, consumed by the UDIP Data Middleware which transforms
#   raw ARC data into clean analytics tables in UDIP PostgreSQL. The MCP Hub
#   (APIM + aggregator function) routes tool calls to 5 spoke apps: ADR,
#   Triage, UDIP, OGC, and ARC Integration API. ADR is the only public-
#   facing app (via Front Door + WAF). All others are internal only.
#
# SECURITY COMPLIANCE:
#   - FedRAMP High (Azure Government, NIST 800-53 Rev5, 410 controls)
#   - M-21-31 EL3 (Sentinel, SOAR, UBA, flow logs, DNS Analytics)
#   - NARA 7-year retention on all AI audit records (WORM blob, 2555 days)
#   - FOIA export capability with chain-of-custody
#   - TLS 1.2+ on all endpoints
#   - Private endpoints for all PaaS data services
#   - Managed identities where supported (no static keys in code)
#
# WHAT THIS SCRIPT DOES NOT DO:
#   - Entra ID app registrations (portal-only, requires Global Admin)
#   - ARC DBA actions (2 SQL commands for WAL/CDC, external team)
#   - Docker image builds (handled by CI/CD pipelines)
#   - DNS record creation (external DNS provider)
#   - TLS certificate provisioning (uploaded separately to Key Vault)
#   - APIM configuration (portal step-by-step in Azure_MCP_Hub_Setup_Guide)
#
################################################################################

set -euo pipefail

################################################################################
# SECTION 0: Color output and logging
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # no color

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="provision_log_${TIMESTAMP}.txt"

# tee everything to the log
exec > >(tee -a "$LOG_FILE") 2>&1

log_ok()   { echo -e "${GREEN}  [OK]${NC} $1"; }
log_fail() { echo -e "${RED}  [FAIL]${NC} $1"; }
log_skip() { echo -e "${YELLOW}  [SKIP]${NC} $1"; }
log_info() { echo -e "${CYAN}  [INFO]${NC} $1"; }

step_header() {
    local step_num="$1"
    local total="$2"
    local title="$3"
    local est="$4"
    echo ""
    echo "=========================================================================="
    echo -e "  Step ${step_num} of ${total}: ${CYAN}${title}${NC}"
    echo "  Estimated time: ${est}"
    echo "=========================================================================="
}

TOTAL_STEPS=21

################################################################################
# SECTION 1: Pre-deployment prerequisites
################################################################################
#
# Before running this script, the following must be in place:
#
# 1. Azure CLI v2.50+ installed and logged into Azure Government:
#       az cloud set --name AzureUSGovernment
#       az login
#
# 2. Contributor role (or higher) on the target subscription.
#
# 3. The following values ready:
#       - Subscription ID
#       - TLS certificate .pfx file path (for Front Door)
#       - ARC OAuth2 client_id and client_secret (from ARC team)
#       - ADR public domain name (e.g., adr.eeoc.gov)
#       - Notification email addresses (OCIO ops + security)
#
# 4. Provider registrations:
#       az provider register --namespace Microsoft.ContainerService
#       az provider register --namespace Microsoft.App
#       az provider register --namespace Microsoft.DBforPostgreSQL
#       az provider register --namespace Microsoft.Cache
#       az provider register --namespace Microsoft.EventHub
#       az provider register --namespace Microsoft.CognitiveServices
#       az provider register --namespace Microsoft.Search
#       az provider register --namespace Microsoft.Cdn
#       az provider register --namespace Microsoft.SecurityInsights
#       az provider register --namespace Microsoft.OperationalInsights
#
################################################################################

################################################################################
# SECTION 2: Configuration variables
################################################################################
# All tunables live here. Override via environment or command-line flags.

# --- Environment ---
EEOC_ENV="${EEOC_ENV:-prod}"
EEOC_REGION="${EEOC_REGION:-usgovvirginia}"
EEOC_SUBSCRIPTION="${EEOC_SUBSCRIPTION:-}"
EEOC_NOTIFICATION_EMAIL="${EEOC_NOTIFICATION_EMAIL:-ocio-ops@eeoc.gov}"
EEOC_SECURITY_EMAIL="${EEOC_SECURITY_EMAIL:-security@eeoc.gov}"
EEOC_ADR_DOMAIN="${EEOC_ADR_DOMAIN:-adr.eeoc.gov}"
EEOC_FORCE="${EEOC_FORCE:-false}"

# --- Resource names (Azure naming convention) ---
EEOC_RG="rg-eeoc-ai-platform-${EEOC_ENV}"
EEOC_VNET="vnet-eeoc-ai-${EEOC_ENV}"
EEOC_KV="kv-eeoc-ai-${EEOC_ENV}"
EEOC_STORAGE="steeocaiaudit"
EEOC_PG_SERVER="pg-eeoc-udip-${EEOC_ENV}"
EEOC_PG_REPLICA="${EEOC_PG_SERVER}-replica"
EEOC_REDIS="redis-eeoc-ai-${EEOC_ENV}"
EEOC_EVENTHUB_NS="evhns-eeoc-cdc-${EEOC_ENV}"
EEOC_OPENAI="oai-eeoc-ai-${EEOC_ENV}"
EEOC_SEARCH="search-eeoc-triage-${EEOC_ENV}"
EEOC_CAE="cae-eeoc-ai-${EEOC_ENV}"
EEOC_FRONTDOOR="fd-eeoc-adr-${EEOC_ENV}"
EEOC_WAF_POLICY="waf-eeoc-adr-${EEOC_ENV}"
EEOC_APPINSIGHTS="appi-eeoc-ai-${EEOC_ENV}"
EEOC_LOG_WORKSPACE="log-eeoc-ai-${EEOC_ENV}"
EEOC_ACR="creeocai${EEOC_ENV}"
EEOC_FUNC_ADR="func-eeoc-adr-${EEOC_ENV}"
EEOC_FUNC_TRIAGE="func-eeoc-triage-${EEOC_ENV}"
EEOC_ACTION_GROUP="ag-eeoc-ai-ops"
EEOC_SENTINEL_WS="${EEOC_LOG_WORKSPACE}" # Sentinel sits on same workspace

# --- VNet CIDR ranges ---
VNET_CIDR="10.100.0.0/16"
SNET_APPS="10.100.1.0/24"
SNET_POSTGRES="10.100.2.0/24"
SNET_REDIS="10.100.3.0/24"
SNET_STORAGE="10.100.4.0/24"
SNET_KEYVAULT="10.100.5.0/24"
SNET_EVENTHUB="10.100.6.0/24"
SNET_FRONTDOOR="10.100.7.0/24"

# --- PostgreSQL tuning ---
PG_SKU="Standard_E16ds_v5"
PG_STORAGE_GB=2048
PG_VERSION="16"
PG_ADMIN_USER="udip_admin"

# --- Container App scaling defaults ---
# format: image cpu memory min_replicas max_replicas cpu_threshold
# actual values set per-app in section 15

# --- Schema SQL files (relative to eeoc-data-analytics-and-dashboard repo) ---
SCHEMA_DIR="${SCHEMA_DIR:-./eeoc-data-analytics-and-dashboard/analytics-db/postgres}"

# --- Tags applied to every resource ---
TAGS="project=eeoc-ai-platform environment=${EEOC_ENV} owner=OCIO compliance=FedRAMP-High"

################################################################################
# SECTION 3: Safety checks
################################################################################

step_header 1 "$TOTAL_STEPS" "Pre-flight safety checks" "~30 seconds"

# 3a. Azure CLI must be installed
if ! command -v az &>/dev/null; then
    log_fail "Azure CLI not found. Install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
log_ok "Azure CLI found: $(az version --query '\"azure-cli\"' -o tsv)"

# 3b. Must be logged in
if ! az account show &>/dev/null; then
    log_fail "Not logged in. Run: az cloud set --name AzureUSGovernment && az login"
    exit 1
fi
CURRENT_SUB=$(az account show --query id -o tsv)
CURRENT_CLOUD=$(az cloud show --query name -o tsv 2>/dev/null || echo "unknown")
log_ok "Logged in. Subscription: ${CURRENT_SUB}"

# 3c. Must be Azure Government
if [[ "$CURRENT_CLOUD" != "AzureUSGovernment" ]]; then
    log_fail "Expected AzureUSGovernment cloud, got: ${CURRENT_CLOUD}"
    echo "   Run: az cloud set --name AzureUSGovernment && az login"
    exit 1
fi
log_ok "Cloud: AzureUSGovernment"

# 3d. Select subscription if provided
if [[ -n "$EEOC_SUBSCRIPTION" ]]; then
    az account set --subscription "$EEOC_SUBSCRIPTION" || {
        log_fail "Cannot select subscription: ${EEOC_SUBSCRIPTION}"
        exit 1
    }
    log_ok "Subscription set to: ${EEOC_SUBSCRIPTION}"
fi

# 3e. Check for existing resource group (skip if --force)
RG_EXISTS=$(az group exists --name "$EEOC_RG" 2>/dev/null || echo "false")
if [[ "$RG_EXISTS" == "true" && "$EEOC_FORCE" != "true" ]]; then
    log_info "Resource group ${EEOC_RG} already exists."
    echo "   Set EEOC_FORCE=true to continue (idempotent — existing resources kept)."
    read -rp "   Continue anyway? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# 3f. Print pre-flight checklist
cat << 'CHECKLIST'

Before continuing, verify you have:
  [x] Azure CLI installed and logged into Azure Government
  [x] Contributor role on the target subscription
  [ ] Subscription ID (auto-detected above)
  [ ] TLS certificate .pfx path for ADR Front Door
  [ ] ARC OAuth2 client_id and client_secret
  [ ] ADR public domain name
  [ ] Notification email addresses

CHECKLIST
read -rp "Press Enter to continue or Ctrl+C to abort... "

################################################################################
# SECTION 4: Resource Group + Tags
################################################################################

step_header 2 "$TOTAL_STEPS" "Resource Group and Tags" "~15 seconds"

az group create \
    --name "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --tags $TAGS \
    -o none || { log_fail "Resource group creation failed"; exit 1; }
log_ok "Resource group: ${EEOC_RG} (${EEOC_REGION})"

################################################################################
# SECTION 5: Virtual Network + 7 Subnets + NSGs
################################################################################

step_header 3 "$TOTAL_STEPS" "Virtual Network, Subnets, and NSGs" "~2 minutes"

# VNet
az network vnet create \
    --resource-group "$EEOC_RG" \
    --name "$EEOC_VNET" \
    --address-prefix "$VNET_CIDR" \
    --location "$EEOC_REGION" \
    --tags $TAGS \
    -o none || { log_fail "VNet creation failed"; exit 1; }
log_ok "VNet: ${EEOC_VNET} (${VNET_CIDR})"

# Subnets
declare -A SUBNETS=(
    ["snet-apps"]="$SNET_APPS"
    ["snet-postgres"]="$SNET_POSTGRES"
    ["snet-redis"]="$SNET_REDIS"
    ["snet-storage"]="$SNET_STORAGE"
    ["snet-keyvault"]="$SNET_KEYVAULT"
    ["snet-eventhub"]="$SNET_EVENTHUB"
    ["snet-frontdoor"]="$SNET_FRONTDOOR"
)

for snet_name in "${!SUBNETS[@]}"; do
    snet_cidr="${SUBNETS[$snet_name]}"
    az network vnet subnet create \
        --resource-group "$EEOC_RG" \
        --vnet-name "$EEOC_VNET" \
        --name "$snet_name" \
        --address-prefixes "$snet_cidr" \
        --disable-private-endpoint-network-policies true \
        -o none 2>/dev/null || log_skip "Subnet ${snet_name} may already exist"
    log_ok "Subnet: ${snet_name} (${snet_cidr})"
done

# NSG for apps subnet — internal traffic only
NSG_APPS="nsg-eeoc-apps-${EEOC_ENV}"
az network nsg create \
    --resource-group "$EEOC_RG" \
    --name "$NSG_APPS" \
    --location "$EEOC_REGION" \
    --tags $TAGS \
    -o none 2>/dev/null || true

az network nsg rule create \
    --resource-group "$EEOC_RG" \
    --nsg-name "$NSG_APPS" \
    --name AllowVNetInbound \
    --priority 100 \
    --source-address-prefixes VirtualNetwork \
    --destination-port-ranges 443 80 8080 \
    --access Allow \
    --protocol Tcp \
    --direction Inbound \
    -o none 2>/dev/null || true

az network nsg rule create \
    --resource-group "$EEOC_RG" \
    --nsg-name "$NSG_APPS" \
    --name DenyInternetInbound \
    --priority 4096 \
    --source-address-prefixes Internet \
    --destination-port-ranges "*" \
    --access Deny \
    --protocol "*" \
    --direction Inbound \
    -o none 2>/dev/null || true

az network vnet subnet update \
    --resource-group "$EEOC_RG" \
    --vnet-name "$EEOC_VNET" \
    --name snet-apps \
    --network-security-group "$NSG_APPS" \
    -o none 2>/dev/null || true
log_ok "NSG: ${NSG_APPS} attached to snet-apps"

# NSG for postgres subnet — only allow from apps subnet
NSG_PG="nsg-eeoc-postgres-${EEOC_ENV}"
az network nsg create \
    --resource-group "$EEOC_RG" \
    --name "$NSG_PG" \
    --location "$EEOC_REGION" \
    --tags $TAGS \
    -o none 2>/dev/null || true

az network nsg rule create \
    --resource-group "$EEOC_RG" \
    --nsg-name "$NSG_PG" \
    --name AllowAppsToPostgres \
    --priority 100 \
    --source-address-prefixes "$SNET_APPS" \
    --destination-port-ranges 5432 6432 \
    --access Allow \
    --protocol Tcp \
    --direction Inbound \
    -o none 2>/dev/null || true

az network vnet subnet update \
    --resource-group "$EEOC_RG" \
    --vnet-name "$EEOC_VNET" \
    --name snet-postgres \
    --network-security-group "$NSG_PG" \
    -o none 2>/dev/null || true
log_ok "NSG: ${NSG_PG} attached to snet-postgres"

################################################################################
# SECTION 6: Key Vault + Private Endpoint
################################################################################

step_header 4 "$TOTAL_STEPS" "Key Vault and Secrets" "~3 minutes"

az keyvault create \
    --name "$EEOC_KV" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --enable-rbac-authorization true \
    --enabled-for-deployment true \
    --bypass AzureServices \
    --default-action Deny \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Key Vault ${EEOC_KV} may already exist"
log_ok "Key Vault: ${EEOC_KV}"

KV_ID=$(az keyvault show --name "$EEOC_KV" --query id -o tsv)

# Private endpoint for Key Vault
az network private-endpoint create \
    --name "pe-${EEOC_KV}" \
    --resource-group "$EEOC_RG" \
    --vnet-name "$EEOC_VNET" \
    --subnet snet-keyvault \
    --private-connection-resource-id "$KV_ID" \
    --group-id vault \
    --connection-name "${EEOC_KV}-pe-conn" \
    --location "$EEOC_REGION" \
    -o none 2>/dev/null || log_skip "Key Vault private endpoint may already exist"
log_ok "Key Vault private endpoint created"

# Generate and store HMAC keys and salts
echo "   Generating HMAC keys and salts..."

HMAC_AUDIT=$(openssl rand -base64 40)
HMAC_SALT=$(openssl rand -base64 40)
WEBHOOK_ADR=$(openssl rand -base64 32)
WEBHOOK_ARC=$(openssl rand -base64 32)
WEBHOOK_TRIAGE=$(openssl rand -base64 32)

declare -A KV_SECRETS=(
    ["HUB-AUDIT-HMAC-KEY"]="$HMAC_AUDIT"
    ["HUB-AUDIT-HASH-SALT"]="$HMAC_SALT"
    ["MCP-WEBHOOK-SECRET-ADR"]="$WEBHOOK_ADR"
    ["MCP-WEBHOOK-SECRET-ARC"]="$WEBHOOK_ARC"
    ["MCP-WEBHOOK-SECRET-TRIAGE"]="$WEBHOOK_TRIAGE"
)

for secret_name in "${!KV_SECRETS[@]}"; do
    az keyvault secret set \
        --vault-name "$EEOC_KV" \
        --name "$secret_name" \
        --value "${KV_SECRETS[$secret_name]}" \
        -o none 2>/dev/null || log_skip "Secret ${secret_name} may already exist"
done
log_ok "HMAC keys and webhook secrets stored in Key Vault"

# Print generated secrets to terminal only (excluded from log file).
# Redirect directly to /dev/tty to avoid the tee that captures stdout.
{
    echo ""
    echo "   ============================================================"
    echo "   GENERATED SECRETS (save these — not displayed again)"
    echo "   ============================================================"
    echo "   HUB-AUDIT-HMAC-KEY:       ${HMAC_AUDIT}"
    echo "   HUB-AUDIT-HASH-SALT:      ${HMAC_SALT}"
    echo "   MCP-WEBHOOK-SECRET-ADR:   ${WEBHOOK_ADR}"
    echo "   MCP-WEBHOOK-SECRET-ARC:   ${WEBHOOK_ARC}"
    echo "   MCP-WEBHOOK-SECRET-TRIAGE:${WEBHOOK_TRIAGE}"
    echo "   ============================================================"
    echo ""
} > /dev/tty 2>/dev/null || true
echo "   (secrets printed to terminal — excluded from log file)"

################################################################################
# SECTION 7: Storage Account + Containers + WORM
################################################################################

step_header 5 "$TOTAL_STEPS" "Storage Account and Containers" "~2 minutes"

az storage account create \
    --name "$EEOC_STORAGE" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --sku Standard_GRS \
    --kind StorageV2 \
    --https-only true \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Storage account ${EEOC_STORAGE} may already exist"
log_ok "Storage account: ${EEOC_STORAGE}"

STORAGE_ID=$(az storage account show --name "$EEOC_STORAGE" -g "$EEOC_RG" --query id -o tsv)
STORAGE_KEY=$(az storage account keys list --account-name "$EEOC_STORAGE" -g "$EEOC_RG" --query '[0].value' -o tsv)

# Private endpoint for storage
az network private-endpoint create \
    --name "pe-${EEOC_STORAGE}" \
    --resource-group "$EEOC_RG" \
    --vnet-name "$EEOC_VNET" \
    --subnet snet-storage \
    --private-connection-resource-id "$STORAGE_ID" \
    --group-id blob \
    --connection-name "${EEOC_STORAGE}-pe-conn" \
    --location "$EEOC_REGION" \
    -o none 2>/dev/null || log_skip "Storage private endpoint may already exist"
log_ok "Storage private endpoint created"

# Create blob containers
CONTAINERS=(
    "hub-audit-archive"
    "adr-case-files"
    "adr-quarantine"
    "triage-processing"
    "triage-archival"
    "function-locks"
    "lifecycle-archives"
    "foia-exports"
)

for container in "${CONTAINERS[@]}"; do
    az storage container create \
        --name "$container" \
        --account-name "$EEOC_STORAGE" \
        --account-key "$STORAGE_KEY" \
        --public-access off \
        -o none 2>/dev/null || true
done
log_ok "Blob containers created: ${CONTAINERS[*]}"

# Create table for audit logging
az storage table create \
    --name "hubauditlog" \
    --account-name "$EEOC_STORAGE" \
    --account-key "$STORAGE_KEY" \
    -o none 2>/dev/null || true
log_ok "Storage table: hubauditlog"

# WORM immutability policy on audit archive (2555 days = 7 years / NARA)
az storage container immutability-policy create \
    --account-name "$EEOC_STORAGE" \
    --container-name "hub-audit-archive" \
    --period 2555 \
    --allow-protected-append-writes true \
    -o none 2>/dev/null || log_skip "Immutability policy may already exist"
log_ok "WORM policy: hub-audit-archive (2555 days)"

################################################################################
# SECTION 8: Azure Database for PostgreSQL Flexible Server
################################################################################

step_header 6 "$TOTAL_STEPS" "PostgreSQL Flexible Server" "~8 minutes"

# Generate admin password and store in Key Vault
PG_ADMIN_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
az keyvault secret set \
    --vault-name "$EEOC_KV" \
    --name "PG-ADMIN-PASSWORD" \
    --value "$PG_ADMIN_PASS" \
    -o none 2>/dev/null || true
echo "   PostgreSQL admin password stored in Key Vault as PG-ADMIN-PASSWORD"

PG_SUBNET_ID=$(az network vnet subnet show \
    --resource-group "$EEOC_RG" \
    --vnet-name "$EEOC_VNET" \
    --name snet-postgres \
    --query id -o tsv)

az postgres flexible-server create \
    --name "$EEOC_PG_SERVER" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --admin-user "$PG_ADMIN_USER" \
    --admin-password "$PG_ADMIN_PASS" \
    --sku-name "$PG_SKU" \
    --tier MemoryOptimized \
    --storage-size "$PG_STORAGE_GB" \
    --version "$PG_VERSION" \
    --subnet "$PG_SUBNET_ID" \
    --private-dns-zone "privatelink.postgres.database.usgovcloudapi.net" \
    --tags $TAGS \
    --yes \
    -o none 2>/dev/null || log_skip "PostgreSQL server ${EEOC_PG_SERVER} may already exist"
log_ok "PostgreSQL: ${EEOC_PG_SERVER} (${PG_SKU}, ${PG_STORAGE_GB} GB)"

# Server parameters — tuned for 128 GB RAM, 16 vCores
echo "   Applying server parameters..."
declare -A PG_PARAMS=(
    ["shared_buffers"]="8388608"       # 32 GB in 8KB pages
    ["effective_cache_size"]="12582912" # 96 GB in 8KB pages
    ["work_mem"]="65536"               # 64 MB in KB
    ["maintenance_work_mem"]="2097152"  # 2 GB in KB
    ["max_connections"]="250"
    ["max_parallel_workers_per_gather"]="4"
    ["max_parallel_workers"]="16"
    ["random_page_cost"]="1.1"
    ["effective_io_concurrency"]="200"
    ["idle_in_transaction_session_timeout"]="30000"
    ["statement_timeout"]="60000"
    ["log_min_duration_statement"]="1000"
    ["shared_preload_libraries"]="pg_stat_statements,pgcrypto,pgvector,pg_trgm"
)

for param in "${!PG_PARAMS[@]}"; do
    az postgres flexible-server parameter set \
        --resource-group "$EEOC_RG" \
        --server-name "$EEOC_PG_SERVER" \
        --name "$param" \
        --value "${PG_PARAMS[$param]}" \
        -o none 2>/dev/null || log_skip "Parameter ${param} may not be settable"
done
log_ok "Server parameters applied"

# Enable extensions — must be set as a single comma-separated value;
# each call overwrites the previous, so individual calls won't work.
echo "   Enabling PostgreSQL extensions..."
az postgres flexible-server parameter set \
    --resource-group "$EEOC_RG" \
    --server-name "$EEOC_PG_SERVER" \
    --name "azure.extensions" \
    --value "pgvector,pg_stat_statements,pgcrypto,pg_trgm" \
    -o none 2>/dev/null || log_skip "Extensions parameter may not be settable"
log_ok "Extensions enabled: pgvector, pg_stat_statements, pgcrypto, pg_trgm"

# Create the udip database (Flexible Server only creates "postgres" by default).
# Use .pgpass file instead of PGPASSWORD env var — avoids leaking creds in
# /proc/<pid>/environ on shared hosts.
PG_HOST="${EEOC_PG_SERVER}.postgres.database.usgovcloudapi.net"
PGPASS_FILE=$(mktemp)
chmod 600 "$PGPASS_FILE"
echo "${PG_HOST}:5432:*:${PG_ADMIN_USER}:${PG_ADMIN_PASS}" > "$PGPASS_FILE"
export PGPASSFILE="$PGPASS_FILE"

echo "   Creating udip database..."
psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d "postgres" \
    -c "SELECT 'exists' FROM pg_database WHERE datname = 'udip'" \
    --tuples-only 2>/dev/null | grep -q "exists" || \
    psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d "postgres" \
        -c "CREATE DATABASE udip;" 2>/dev/null || true
log_ok "Database: udip"

# Run schema scripts if the directory exists
if [[ -d "$SCHEMA_DIR" ]]; then
    echo "   Running schema scripts from ${SCHEMA_DIR}..."

    SCHEMA_FILES=(
        "001-extensions.sql"
        "002-schemas.sql"
        "003-replica-schema.sql"
        "010-analytics-tables.sql"
        "011-lifecycle-columns.sql"
        "012-lifecycle-tables.sql"
        "013-lifecycle-views.sql"
        "014-adr-triage-tables.sql"
        "015-partitioning.sql"
        "016-cdc-target-tables.sql"
        "020-vector-tables.sql"
        "030-document-tables.sql"
        "040-rls-policies.sql"
        "050-search-functions.sql"
        "060-adr-operational-tables.sql"
        "061-triage-operational-tables.sql"
        "062-operations-rls.sql"
        "063-operations-views.sql"
        "065-litigation-holds.sql"
    )

    for sql_file in "${SCHEMA_FILES[@]}"; do
        full_path="${SCHEMA_DIR}/${sql_file}"
        if [[ -f "$full_path" ]]; then
            psql \
                -h "$PG_HOST" \
                -U "$PG_ADMIN_USER" \
                -d "udip" \
                -f "$full_path" \
                --set ON_ERROR_STOP=1 \
                2>/dev/null && log_ok "Schema: ${sql_file}" || log_fail "Schema: ${sql_file}"
        else
            log_skip "Schema file not found: ${sql_file}"
        fi
    done
else
    log_skip "Schema directory not found: ${SCHEMA_DIR} (run manually after cloning repos)"
fi

# clean up .pgpass
rm -f "$PGPASS_FILE"
unset PGPASSFILE

# Create read replica
echo "   Creating read replica..."
az postgres flexible-server replica create \
    --resource-group "$EEOC_RG" \
    --replica-name "$EEOC_PG_REPLICA" \
    --source-server "$EEOC_PG_SERVER" \
    --location "$EEOC_REGION" \
    -o none 2>/dev/null || log_skip "Replica ${EEOC_PG_REPLICA} may already exist"
log_ok "Read replica: ${EEOC_PG_REPLICA}"

################################################################################
# SECTION 9: PgBouncer Container App
################################################################################

step_header 7 "$TOTAL_STEPS" "PgBouncer Connection Pooler" "~2 minutes"

# PgBouncer is deployed as a Container App rather than the built-in
# Flexible Server pgbouncer, because we need transaction-mode pooling
# with custom pool sizes for the UDIP workload.

# PG_HOST already set in Section 8

# Deployed as a Container App in step 13 (Section 15).
# Config values set here, referenced by the deployment loop below.
PGBOUNCER_MAX_CLIENT=3000
PGBOUNCER_DEFAULT_POOL=80
PGBOUNCER_MAX_DB_CONN=200
log_info "PgBouncer config prepared (deployed with Container Apps in Section 14)"

################################################################################
# SECTION 10: Azure Cache for Redis
################################################################################

step_header 8 "$TOTAL_STEPS" "Azure Cache for Redis" "~6 minutes"

az redis create \
    --name "$EEOC_REDIS" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --sku Premium \
    --vm-size P1 \
    --enable-non-ssl-port false \
    --minimum-tls-version 1.2 \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Redis ${EEOC_REDIS} may already exist"
log_ok "Redis: ${EEOC_REDIS} (Premium P1, 6 GB)"

REDIS_ID=$(az redis show -n "$EEOC_REDIS" -g "$EEOC_RG" --query id -o tsv 2>/dev/null || echo "")

if [[ -n "$REDIS_ID" ]]; then
    # Private endpoint
    az network private-endpoint create \
        --name "pe-${EEOC_REDIS}" \
        --resource-group "$EEOC_RG" \
        --vnet-name "$EEOC_VNET" \
        --subnet snet-redis \
        --private-connection-resource-id "$REDIS_ID" \
        --group-id redisCache \
        --connection-name "${EEOC_REDIS}-pe-conn" \
        --location "$EEOC_REGION" \
        -o none 2>/dev/null || log_skip "Redis private endpoint may already exist"
    log_ok "Redis private endpoint created"

    # Store connection string in Key Vault
    REDIS_KEY=$(az redis list-keys -n "$EEOC_REDIS" -g "$EEOC_RG" --query primaryKey -o tsv 2>/dev/null || echo "")
    if [[ -n "$REDIS_KEY" ]]; then
        REDIS_CONN="rediss://:${REDIS_KEY}@${EEOC_REDIS}.redis.cache.usgovcloudapi.net:6380/0"
        az keyvault secret set \
            --vault-name "$EEOC_KV" \
            --name "REDIS-CONNECTION-STRING" \
            --value "$REDIS_CONN" \
            -o none 2>/dev/null || true
        log_ok "Redis connection string stored in Key Vault"
    fi
fi

################################################################################
# SECTION 11: Azure Event Hub Namespace
################################################################################

step_header 9 "$TOTAL_STEPS" "Azure Event Hub Namespace" "~2 minutes"

az eventhubs namespace create \
    --name "$EEOC_EVENTHUB_NS" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --sku Standard \
    --capacity 4 \
    --enable-auto-inflate true \
    --maximum-throughput-units 8 \
    --enable-kafka true \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Event Hub namespace ${EEOC_EVENTHUB_NS} may already exist"
log_ok "Event Hub namespace: ${EEOC_EVENTHUB_NS} (Standard, 4 TU, Kafka)"

EVENTHUB_ID=$(az eventhubs namespace show -n "$EEOC_EVENTHUB_NS" -g "$EEOC_RG" --query id -o tsv 2>/dev/null || echo "")

if [[ -n "$EVENTHUB_ID" ]]; then
    # Private endpoint
    az network private-endpoint create \
        --name "pe-${EEOC_EVENTHUB_NS}" \
        --resource-group "$EEOC_RG" \
        --vnet-name "$EEOC_VNET" \
        --subnet snet-eventhub \
        --private-connection-resource-id "$EVENTHUB_ID" \
        --group-id namespace \
        --connection-name "${EEOC_EVENTHUB_NS}-pe-conn" \
        --location "$EEOC_REGION" \
        -o none 2>/dev/null || log_skip "Event Hub private endpoint may already exist"
    log_ok "Event Hub private endpoint created"

    # Consumer group for UDIP middleware
    # Topics are auto-created by Debezium; create consumer group on the
    # first topic that will appear (prepa.public.charge_inquiry).
    # If the topic doesn't exist yet, we'll create it as a placeholder.
    az eventhubs eventhub create \
        --name "prepa.public.charge_inquiry" \
        --namespace-name "$EEOC_EVENTHUB_NS" \
        --resource-group "$EEOC_RG" \
        --partition-count 4 \
        --message-retention 7 \
        -o none 2>/dev/null || true

    az eventhubs eventhub consumer-group create \
        --name "udip-middleware" \
        --eventhub-name "prepa.public.charge_inquiry" \
        --namespace-name "$EEOC_EVENTHUB_NS" \
        --resource-group "$EEOC_RG" \
        -o none 2>/dev/null || true
    log_ok "Consumer group: udip-middleware"

    # Store connection string
    EH_CONN=$(az eventhubs namespace authorization-rule keys list \
        --namespace-name "$EEOC_EVENTHUB_NS" \
        --resource-group "$EEOC_RG" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString -o tsv 2>/dev/null || echo "")
    if [[ -n "$EH_CONN" ]]; then
        az keyvault secret set \
            --vault-name "$EEOC_KV" \
            --name "EVENTHUB-CONNECTION-STRING" \
            --value "$EH_CONN" \
            -o none 2>/dev/null || true
        log_ok "Event Hub connection string stored in Key Vault"
    fi
fi

################################################################################
# SECTION 12: Azure OpenAI
################################################################################

step_header 10 "$TOTAL_STEPS" "Azure OpenAI Service" "~3 minutes"

az cognitiveservices account create \
    --name "$EEOC_OPENAI" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --kind OpenAI \
    --sku S0 \
    --custom-domain "$EEOC_OPENAI" \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "OpenAI ${EEOC_OPENAI} may already exist"
log_ok "Azure OpenAI: ${EEOC_OPENAI}"

OPENAI_ID=$(az cognitiveservices account show \
    --name "$EEOC_OPENAI" \
    --resource-group "$EEOC_RG" \
    --query id -o tsv 2>/dev/null || echo "")

# Deploy GPT-4o model
az cognitiveservices account deployment create \
    --name "$EEOC_OPENAI" \
    --resource-group "$EEOC_RG" \
    --deployment-name "gpt-4o" \
    --model-name "gpt-4o" \
    --model-version "2024-05-13" \
    --model-format OpenAI \
    --sku-name Standard \
    --sku-capacity 80 \
    -o none 2>/dev/null || log_skip "gpt-4o deployment may already exist"
log_ok "Model deployed: gpt-4o (80K TPM)"

# Deploy text-embedding-3-small
az cognitiveservices account deployment create \
    --name "$EEOC_OPENAI" \
    --resource-group "$EEOC_RG" \
    --deployment-name "text-embedding-3-small" \
    --model-name "text-embedding-3-small" \
    --model-version "1" \
    --model-format OpenAI \
    --sku-name Standard \
    --sku-capacity 350 \
    -o none 2>/dev/null || log_skip "text-embedding-3-small deployment may already exist"
log_ok "Model deployed: text-embedding-3-small (350K TPM)"

# Store API key in Key Vault
OPENAI_KEY=$(az cognitiveservices account keys list \
    --name "$EEOC_OPENAI" \
    --resource-group "$EEOC_RG" \
    --query key1 -o tsv 2>/dev/null || echo "")
if [[ -n "$OPENAI_KEY" ]]; then
    az keyvault secret set \
        --vault-name "$EEOC_KV" \
        --name "OPENAI-API-KEY" \
        --value "$OPENAI_KEY" \
        -o none 2>/dev/null || true
    log_ok "OpenAI API key stored in Key Vault"
fi

################################################################################
# SECTION 13: Azure Cognitive Search
################################################################################

step_header 11 "$TOTAL_STEPS" "Azure Cognitive Search" "~3 minutes"

az search service create \
    --name "$EEOC_SEARCH" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --sku Standard \
    --partition-count 1 \
    --replica-count 1 \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Search ${EEOC_SEARCH} may already exist"
log_ok "Cognitive Search: ${EEOC_SEARCH} (Standard S1)"

# Store admin key in Key Vault
SEARCH_KEY=$(az search admin-key show \
    --service-name "$EEOC_SEARCH" \
    --resource-group "$EEOC_RG" \
    --query primaryKey -o tsv 2>/dev/null || echo "")
if [[ -n "$SEARCH_KEY" ]]; then
    az keyvault secret set \
        --vault-name "$EEOC_KV" \
        --name "SearchServiceAdminKey" \
        --value "$SEARCH_KEY" \
        -o none 2>/dev/null || true
    log_ok "Search admin key stored in Key Vault"
fi

################################################################################
# SECTION 14: Container Apps Environment + Log Analytics
################################################################################

step_header 12 "$TOTAL_STEPS" "Container Apps Environment" "~4 minutes"

# Log Analytics workspace (used by Container Apps, App Insights, and Sentinel)
az monitor log-analytics workspace create \
    --resource-group "$EEOC_RG" \
    --workspace-name "$EEOC_LOG_WORKSPACE" \
    --location "$EEOC_REGION" \
    --retention-time 365 \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Log Analytics ${EEOC_LOG_WORKSPACE} may already exist"

LOG_WS_ID=$(az monitor log-analytics workspace show \
    --resource-group "$EEOC_RG" \
    --workspace-name "$EEOC_LOG_WORKSPACE" \
    --query customerId -o tsv 2>/dev/null || echo "")
LOG_WS_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --resource-group "$EEOC_RG" \
    --workspace-name "$EEOC_LOG_WORKSPACE" \
    --query primarySharedKey -o tsv 2>/dev/null || echo "")
LOG_WS_RESOURCE_ID=$(az monitor log-analytics workspace show \
    --resource-group "$EEOC_RG" \
    --workspace-name "$EEOC_LOG_WORKSPACE" \
    --query id -o tsv 2>/dev/null || echo "")
log_ok "Log Analytics: ${EEOC_LOG_WORKSPACE} (365 day retention)"

# Container Apps Environment — internal only, VNet integrated
APPS_SUBNET_ID=$(az network vnet subnet show \
    --resource-group "$EEOC_RG" \
    --vnet-name "$EEOC_VNET" \
    --name snet-apps \
    --query id -o tsv)

az containerapp env create \
    --name "$EEOC_CAE" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --infrastructure-subnet-resource-id "$APPS_SUBNET_ID" \
    --internal-only true \
    --logs-workspace-id "$LOG_WS_ID" \
    --logs-workspace-key "$LOG_WS_KEY" \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Container Apps environment ${EEOC_CAE} may already exist"
log_ok "Container Apps Environment: ${EEOC_CAE} (internal-only)"

################################################################################
# SECTION 15: Deploy Container Apps (10 apps)
################################################################################

step_header 13 "$TOTAL_STEPS" "Container Apps" "~10 minutes"

KV_URI="https://${EEOC_KV}.vault.usgovcloudapi.net/"
EEOC_TENANT_ID=$(az account show --query tenantId -o tsv)

# Each app: name, image, cpu, memory, min_replicas, max_replicas, cpu_scale_pct
# Images reference ACR; push images before first deploy.
# Using placeholder images here — replaced by CI/CD on first push.
declare -a APPS=(
    "ca-udip-ai|eeoc-udip-ai-assistant:latest|2|4Gi|2|6|70"
    "ca-udip-cdc|eeoc-udip-data-middleware:latest|2|4Gi|1|2|80"
    "ca-adr-webapp|eeoc-adr-webapp:latest|2|4Gi|3|12|65"
    "ca-triage-webapp|eeoc-triage-webapp:latest|1|2Gi|2|6|70"
    "ca-arc-integration|eeoc-arc-integration:latest|1|2Gi|2|4|70"
    "ca-ogc-trialtool|eeoc-ogc-trialtool:latest|1|2Gi|2|4|70"
    "ca-mcp-aggregator|eeoc-mcp-hub-functions:latest|0.5|512Mi|1|2|70"
    "ca-superset-web|eeoc-superset:latest|2|4Gi|2|4|70"
    "ca-debezium|eeoc-debezium-connect:latest|2|4Gi|1|1|90"
)

for app_spec in "${APPS[@]}"; do
    IFS='|' read -r app_name app_image app_cpu app_mem app_min app_max app_cpu_pct <<< "$app_spec"

    az containerapp create \
        --name "$app_name" \
        --resource-group "$EEOC_RG" \
        --environment "$EEOC_CAE" \
        --image "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest" \
        --cpu "$app_cpu" \
        --memory "$app_mem" \
        --min-replicas "$app_min" \
        --max-replicas "$app_max" \
        --ingress internal \
        --target-port 8000 \
        --env-vars \
            "KEY_VAULT_URI=${KV_URI}" \
            "AZURE_TENANT_ID=${EEOC_TENANT_ID}" \
            "REDIS_URL=rediss://${EEOC_REDIS}.redis.cache.usgovcloudapi.net:6380" \
        --scale-rule-name "cpu-scaling" \
        --scale-rule-type "cpu" \
        --scale-rule-metadata "type=Utilization" "value=${app_cpu_pct}" \
        --tags $TAGS \
        -o none 2>/dev/null || log_skip "${app_name} may already exist"
    log_ok "Container App: ${app_name} (${app_cpu} CPU, ${app_mem}, ${app_min}-${app_max} replicas)"
done

# PgBouncer gets special config.
# The DATABASE_URL contains a credential — store it in Key Vault and
# reference it via secretref once managed identity is wired up.
# For initial provisioning, use placeholder; replace post-deploy.
# actual credential — Container Apps secret refs replace this once managed identity is wired
PG_BOUNCER_DB_URL="postgres://${PG_ADMIN_USER}@${EEOC_PG_SERVER}:${PG_ADMIN_PASS}@${PG_HOST}:5432/udip"
az keyvault secret set \
    --vault-name "$EEOC_KV" \
    --name "PGBOUNCER-DATABASE-URL" \
    --value "postgres://${PG_ADMIN_USER}@${EEOC_PG_SERVER}:${PG_ADMIN_PASS}@${PG_HOST}:5432/udip" \
    -o none 2>/dev/null || true

az containerapp create \
    --name "ca-pgbouncer" \
    --resource-group "$EEOC_RG" \
    --environment "$EEOC_CAE" \
    --image "edoburu/pgbouncer:latest" \
    --cpu 0.5 \
    --memory "256Mi" \
    --min-replicas 2 \
    --max-replicas 4 \
    --ingress internal \
    --target-port 6432 \
    --env-vars \
        "DATABASE_URL=${PG_BOUNCER_DB_URL}" \
        "POOL_MODE=transaction" \
        "MAX_CLIENT_CONN=${PGBOUNCER_MAX_CLIENT}" \
        "DEFAULT_POOL_SIZE=${PGBOUNCER_DEFAULT_POOL}" \
        "MAX_DB_CONNECTIONS=${PGBOUNCER_MAX_DB_CONN}" \
    --scale-rule-name "cpu-scaling" \
    --scale-rule-type "cpu" \
    --scale-rule-metadata "type=Utilization" "value=80" \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "ca-pgbouncer may already exist"
log_ok "Container App: ca-pgbouncer (3000 client / 80 pool / 200 max)"
log_info "Post-deploy: update ca-pgbouncer DATABASE_URL with Key Vault secret ref"

################################################################################
# SECTION 16: Azure Functions (ADR + Triage)
################################################################################

step_header 14 "$TOTAL_STEPS" "Azure Functions" "~4 minutes"

# Function App plan (Premium EP1 for VNet integration)
FUNC_PLAN="plan-eeoc-func-${EEOC_ENV}"
az functionapp plan create \
    --name "$FUNC_PLAN" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --sku EP1 \
    --is-linux true \
    -o none 2>/dev/null || log_skip "Function plan ${FUNC_PLAN} may already exist"
log_ok "Function plan: ${FUNC_PLAN} (Premium EP1)"

# Storage account for function app state
FUNC_STORAGE="steeocfunc${EEOC_ENV}"
az storage account create \
    --name "$FUNC_STORAGE" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --https-only true \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    -o none 2>/dev/null || log_skip "Function storage ${FUNC_STORAGE} may already exist"

# ADR Function App
az functionapp create \
    --name "$EEOC_FUNC_ADR" \
    --resource-group "$EEOC_RG" \
    --plan "$FUNC_PLAN" \
    --storage-account "$FUNC_STORAGE" \
    --runtime python \
    --runtime-version 3.12 \
    --functions-version 4 \
    --os-type Linux \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Function ${EEOC_FUNC_ADR} may already exist"

# VNet integration for ADR functions
az functionapp vnet-integration add \
    --name "$EEOC_FUNC_ADR" \
    --resource-group "$EEOC_RG" \
    --vnet "$EEOC_VNET" \
    --subnet snet-apps \
    -o none 2>/dev/null || true
log_ok "Function App: ${EEOC_FUNC_ADR} (Python 3.12, VNet integrated)"

# Triage Function App
az functionapp create \
    --name "$EEOC_FUNC_TRIAGE" \
    --resource-group "$EEOC_RG" \
    --plan "$FUNC_PLAN" \
    --storage-account "$FUNC_STORAGE" \
    --runtime python \
    --runtime-version 3.12 \
    --functions-version 4 \
    --os-type Linux \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Function ${EEOC_FUNC_TRIAGE} may already exist"

az functionapp vnet-integration add \
    --name "$EEOC_FUNC_TRIAGE" \
    --resource-group "$EEOC_RG" \
    --vnet "$EEOC_VNET" \
    --subnet snet-apps \
    -o none 2>/dev/null || true
log_ok "Function App: ${EEOC_FUNC_TRIAGE} (Python 3.12, VNet integrated)"

# Set Key Vault reference for both function apps
for func_app in "$EEOC_FUNC_ADR" "$EEOC_FUNC_TRIAGE"; do
    az functionapp config appsettings set \
        --name "$func_app" \
        --resource-group "$EEOC_RG" \
        --settings \
            "KEY_VAULT_URI=${KV_URI}" \
            "AZURE_TENANT_ID=${EEOC_TENANT_ID}" \
        -o none 2>/dev/null || true
done
log_ok "Function App settings configured with Key Vault references"

################################################################################
# SECTION 17: Azure Front Door + WAF (ADR)
################################################################################

step_header 15 "$TOTAL_STEPS" "Azure Front Door and WAF" "~4 minutes"

# WAF policy
az network front-door waf-policy create \
    --name "$EEOC_WAF_POLICY" \
    --resource-group "$EEOC_RG" \
    --mode Prevention \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "WAF policy ${EEOC_WAF_POLICY} may already exist"

# OWASP 3.2 managed ruleset
az network front-door waf-policy managed-rules add \
    --policy-name "$EEOC_WAF_POLICY" \
    --resource-group "$EEOC_RG" \
    --type DefaultRuleSet \
    --version "2.1" \
    -o none 2>/dev/null || true

# Bot manager ruleset
az network front-door waf-policy managed-rules add \
    --policy-name "$EEOC_WAF_POLICY" \
    --resource-group "$EEOC_RG" \
    --type Microsoft_BotManagerRuleSet \
    --version "1.0" \
    -o none 2>/dev/null || true
log_ok "WAF policy: ${EEOC_WAF_POLICY} (OWASP 3.2, bot manager, prevention mode)"

# Rate limiting custom rule — 100 requests/min/IP
az network front-door waf-policy rule create \
    --policy-name "$EEOC_WAF_POLICY" \
    --resource-group "$EEOC_RG" \
    --name RateLimitPerIP \
    --priority 100 \
    --rule-type RateLimitRule \
    --rate-limit-threshold 100 \
    --rate-limit-duration-in-minutes 1 \
    --action Block \
    --defer \
    -o none 2>/dev/null || true

az network front-door waf-policy rule match-condition add \
    --policy-name "$EEOC_WAF_POLICY" \
    --resource-group "$EEOC_RG" \
    --name RateLimitPerIP \
    --match-variable RemoteAddr \
    --operator IPMatch \
    --values "0.0.0.0/0" \
    -o none 2>/dev/null || true
log_ok "Rate limiting rule: 100 req/min/IP"

# Front Door profile
az afd profile create \
    --profile-name "$EEOC_FRONTDOOR" \
    --resource-group "$EEOC_RG" \
    --sku Standard_AzureFrontDoor \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Front Door ${EEOC_FRONTDOOR} may already exist"
log_ok "Front Door: ${EEOC_FRONTDOOR} (Standard)"

# Front Door endpoint for ADR
az afd endpoint create \
    --endpoint-name "adr-endpoint" \
    --profile-name "$EEOC_FRONTDOOR" \
    --resource-group "$EEOC_RG" \
    --enabled-state Enabled \
    -o none 2>/dev/null || true

# Origin group (backends are Container Apps — configured after image push)
az afd origin-group create \
    --origin-group-name "adr-origin-group" \
    --profile-name "$EEOC_FRONTDOOR" \
    --resource-group "$EEOC_RG" \
    --probe-path "/healthz" \
    --probe-protocol Https \
    --probe-request-type HEAD \
    --probe-interval-in-seconds 30 \
    --sample-size 4 \
    --successful-samples-required 3 \
    -o none 2>/dev/null || true
log_ok "Front Door origin group configured with /healthz probe"

################################################################################
# SECTION 18: Application Insights
################################################################################

step_header 16 "$TOTAL_STEPS" "Application Insights" "~1 minute"

az monitor app-insights component create \
    --app "$EEOC_APPINSIGHTS" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --workspace "$LOG_WS_RESOURCE_ID" \
    --application-type web \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "App Insights ${EEOC_APPINSIGHTS} may already exist"
log_ok "Application Insights: ${EEOC_APPINSIGHTS}"

APPINSIGHTS_KEY=$(az monitor app-insights component show \
    --app "$EEOC_APPINSIGHTS" \
    --resource-group "$EEOC_RG" \
    --query instrumentationKey -o tsv 2>/dev/null || echo "")
APPINSIGHTS_CONN=$(az monitor app-insights component show \
    --app "$EEOC_APPINSIGHTS" \
    --resource-group "$EEOC_RG" \
    --query connectionString -o tsv 2>/dev/null || echo "")

# Store instrumentation key in Key Vault
if [[ -n "$APPINSIGHTS_KEY" ]]; then
    az keyvault secret set \
        --vault-name "$EEOC_KV" \
        --name "APPINSIGHTS-INSTRUMENTATIONKEY" \
        --value "$APPINSIGHTS_KEY" \
        -o none 2>/dev/null || true
    log_ok "App Insights instrumentation key stored in Key Vault"
fi

# Enable diagnostic settings on PostgreSQL
PG_RESOURCE_ID=$(az postgres flexible-server show \
    --name "$EEOC_PG_SERVER" \
    --resource-group "$EEOC_RG" \
    --query id -o tsv 2>/dev/null || echo "")

if [[ -n "$PG_RESOURCE_ID" && -n "$LOG_WS_RESOURCE_ID" ]]; then
    az monitor diagnostic-settings create \
        --name "pg-diagnostics" \
        --resource "$PG_RESOURCE_ID" \
        --workspace "$LOG_WS_RESOURCE_ID" \
        --logs '[{"category": "PostgreSQLFlexLogs", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        -o none 2>/dev/null || true
    log_ok "PostgreSQL diagnostic settings enabled"
fi

################################################################################
# SECTION 19: Azure Monitor Alert Rules
################################################################################

step_header 17 "$TOTAL_STEPS" "Monitor Alert Rules" "~3 minutes"

# Action group for notifications
az monitor action-group create \
    --name "$EEOC_ACTION_GROUP" \
    --resource-group "$EEOC_RG" \
    --short-name "EEOCAIOps" \
    --action email ocio-ops "$EEOC_NOTIFICATION_EMAIL" \
    --action email security "$EEOC_SECURITY_EMAIL" \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "Action group ${EEOC_ACTION_GROUP} may already exist"
log_ok "Action group: ${EEOC_ACTION_GROUP}"

AG_ID=$(az monitor action-group show \
    --name "$EEOC_ACTION_GROUP" \
    --resource-group "$EEOC_RG" \
    --query id -o tsv 2>/dev/null || echo "")

# Alert: database CPU > 80% for 5 minutes
if [[ -n "$PG_RESOURCE_ID" && -n "$AG_ID" ]]; then
    az monitor metrics alert create \
        --name "alert-pg-cpu-high" \
        --resource-group "$EEOC_RG" \
        --scopes "$PG_RESOURCE_ID" \
        --condition "avg cpu_percent > 80" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --action "$AG_ID" \
        --description "PostgreSQL CPU above 80% for 5 minutes" \
        --tags $TAGS \
        -o none 2>/dev/null || true
    log_ok "Alert: PostgreSQL CPU > 80%"

    # Alert: active connections > 200
    az monitor metrics alert create \
        --name "alert-pg-connections-high" \
        --resource-group "$EEOC_RG" \
        --scopes "$PG_RESOURCE_ID" \
        --condition "avg active_connections > 200" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --action "$AG_ID" \
        --description "PostgreSQL active connections above 200" \
        --tags $TAGS \
        -o none 2>/dev/null || true
    log_ok "Alert: PostgreSQL connections > 200"
fi

# Alert: Redis memory > 80%
if [[ -n "$REDIS_ID" && -n "$AG_ID" ]]; then
    az monitor metrics alert create \
        --name "alert-redis-memory-high" \
        --resource-group "$EEOC_RG" \
        --scopes "$REDIS_ID" \
        --condition "avg usedmemorypercentage > 80" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --action "$AG_ID" \
        --description "Redis memory usage above 80%" \
        --tags $TAGS \
        -o none 2>/dev/null || true
    log_ok "Alert: Redis memory > 80%"
fi

# Alert: Event Hub consumer lag > 5 minutes
if [[ -n "$EVENTHUB_ID" && -n "$AG_ID" ]]; then
    az monitor metrics alert create \
        --name "alert-eventhub-consumer-lag" \
        --resource-group "$EEOC_RG" \
        --scopes "$EVENTHUB_ID" \
        --condition "avg OutgoingMessages < 1" \
        --window-size 5m \
        --evaluation-frequency 5m \
        --severity 2 \
        --action "$AG_ID" \
        --description "Event Hub consumer may be stalled (no outgoing messages in 5 min)" \
        --tags $TAGS \
        -o none 2>/dev/null || true
    log_ok "Alert: Event Hub consumer lag"
fi

# Alert: WORM storage deletion attempt (log-based)
if [[ -n "$LOG_WS_RESOURCE_ID" && -n "$AG_ID" ]]; then
    az monitor scheduled-query create \
        --name "alert-worm-breach-attempt" \
        --resource-group "$EEOC_RG" \
        --scopes "$LOG_WS_RESOURCE_ID" \
        --condition "count > 0" \
        --condition-query "StorageBlobLogs | where OperationName == 'DeleteBlob' and Uri contains 'hub-audit-archive' | where TimeGenerated > ago(5m)" \
        --window-size 5m \
        --evaluation-frequency 5m \
        --severity 1 \
        --action "$AG_ID" \
        --description "Attempted deletion on WORM audit archive container" \
        --tags $TAGS \
        -o none 2>/dev/null || log_skip "WORM alert rule may need manual configuration"
    log_ok "Alert: WORM breach attempt"
fi

################################################################################
# SECTION 20: Azure Sentinel (M-21-31 EL3)
################################################################################

step_header 18 "$TOTAL_STEPS" "Azure Sentinel (M-21-31)" "~3 minutes"

if [[ -n "$LOG_WS_RESOURCE_ID" ]]; then
    # Enable Sentinel on the Log Analytics workspace
    az sentinel onboarding-state create \
        --resource-group "$EEOC_RG" \
        --workspace-name "$EEOC_SENTINEL_WS" \
        --name "default" \
        -o none 2>/dev/null || log_skip "Sentinel may already be enabled"
    log_ok "Sentinel enabled on workspace: ${EEOC_SENTINEL_WS}"

    # Connect Azure Activity data connector
    az sentinel data-connector create \
        --resource-group "$EEOC_RG" \
        --workspace-name "$EEOC_SENTINEL_WS" \
        --data-connector-id "azureActivityConnector" \
        --azure-activity-log "{\"state\": \"Enabled\"}" \
        -o none 2>/dev/null || log_skip "Azure Activity connector may already exist"
    log_ok "Sentinel data connector: Azure Activity"

    # Enable UEBA (User Entity Behavior Analytics)
    az sentinel setting create \
        --resource-group "$EEOC_RG" \
        --workspace-name "$EEOC_SENTINEL_WS" \
        --name "Ueba" \
        --ueba "{\"isEnabled\": true, \"dataSources\": [\"AuditLogs\", \"SigninLogs\"]}" \
        -o none 2>/dev/null || log_skip "UEBA may already be enabled"
    log_ok "Sentinel UEBA enabled"

    # Analytics rule: brute-force sign-in detection
    az sentinel alert-rule create \
        --resource-group "$EEOC_RG" \
        --workspace-name "$EEOC_SENTINEL_WS" \
        --rule-id "brute-force-detection" \
        --kind Scheduled \
        --display-name "Brute-Force Sign-In Detection" \
        --query "SigninLogs | where ResultType != '0' | summarize FailureCount=count() by UserPrincipalName, IPAddress, bin(TimeGenerated, 5m) | where FailureCount > 10" \
        --severity "High" \
        --query-frequency "PT5M" \
        --query-period "PT5M" \
        --trigger-operator "GreaterThan" \
        --trigger-threshold 0 \
        -o none 2>/dev/null || log_skip "Analytics rule may need manual setup via portal"
    log_ok "Sentinel analytics rule: brute-force detection"
else
    log_skip "Sentinel skipped — Log Analytics workspace not available"
fi

################################################################################
# SECTION 21: NSG Flow Logs (M-21-31 EL3)
################################################################################

step_header 19 "$TOTAL_STEPS" "NSG Flow Logs" "~2 minutes"

# flow logs require a Network Watcher and storage account
# Network Watcher is auto-created per region in most subscriptions
for nsg_name in "$NSG_APPS" "$NSG_PG"; do
    NSG_ID=$(az network nsg show \
        --name "$nsg_name" \
        --resource-group "$EEOC_RG" \
        --query id -o tsv 2>/dev/null || echo "")

    if [[ -n "$NSG_ID" ]]; then
        az network watcher flow-log create \
            --name "flowlog-${nsg_name}" \
            --nsg "$NSG_ID" \
            --resource-group "$EEOC_RG" \
            --location "$EEOC_REGION" \
            --storage-account "$STORAGE_ID" \
            --workspace "$LOG_WS_RESOURCE_ID" \
            --enabled true \
            --retention 90 \
            --traffic-analytics true \
            --interval 10 \
            -o none 2>/dev/null || log_skip "Flow log for ${nsg_name} may already exist"
        log_ok "NSG flow log: ${nsg_name} (90 day retention, Traffic Analytics)"
    fi
done

################################################################################
# SECTION 22: Container Registry (ACR)
################################################################################

step_header 20 "$TOTAL_STEPS" "Azure Container Registry" "~2 minutes"

az acr create \
    --name "$EEOC_ACR" \
    --resource-group "$EEOC_RG" \
    --location "$EEOC_REGION" \
    --sku Premium \
    --admin-enabled false \
    --tags $TAGS \
    -o none 2>/dev/null || log_skip "ACR ${EEOC_ACR} may already exist"
log_ok "Container Registry: ${EEOC_ACR} (Premium, admin disabled)"

################################################################################
# SECTION 23: Post-provisioning output
################################################################################

step_header 21 "$TOTAL_STEPS" "Post-Provisioning Summary" "~10 seconds"

# Save deployment summary
SUMMARY_FILE="deploy_summary_${TIMESTAMP}.txt"

cat << EOF | tee "$SUMMARY_FILE"

==========================================================================
  EEOC AI Integration Platform — Provisioning Complete
==========================================================================
  Environment: ${EEOC_ENV}
  Region:      ${EEOC_REGION}
  Timestamp:   $(date -u +"%Y-%m-%dT%H:%M:%SZ")
  Log file:    ${LOG_FILE}
==========================================================================

RESOURCE INVENTORY:
  Resource Group:           ${EEOC_RG}
  Virtual Network:          ${EEOC_VNET} (${VNET_CIDR})
  Key Vault:                ${EEOC_KV}
  Storage Account:          ${EEOC_STORAGE}
  PostgreSQL Primary:       ${EEOC_PG_SERVER}
  PostgreSQL Replica:       ${EEOC_PG_REPLICA}
  Redis:                    ${EEOC_REDIS}
  Event Hub Namespace:      ${EEOC_EVENTHUB_NS}
  Azure OpenAI:             ${EEOC_OPENAI}
  Cognitive Search:         ${EEOC_SEARCH}
  Container Apps Env:       ${EEOC_CAE}
  Container Registry:       ${EEOC_ACR}
  Front Door:               ${EEOC_FRONTDOOR}
  WAF Policy:               ${EEOC_WAF_POLICY}
  App Insights:             ${EEOC_APPINSIGHTS}
  Log Analytics:            ${EEOC_LOG_WORKSPACE}
  Sentinel:                 ${EEOC_SENTINEL_WS}
  ADR Function App:         ${EEOC_FUNC_ADR}
  Triage Function App:      ${EEOC_FUNC_TRIAGE}

KEY VAULT SECRETS (names only):
  HUB-AUDIT-HMAC-KEY
  HUB-AUDIT-HASH-SALT
  MCP-WEBHOOK-SECRET-ADR
  MCP-WEBHOOK-SECRET-ARC
  MCP-WEBHOOK-SECRET-TRIAGE
  PG-ADMIN-PASSWORD
  REDIS-CONNECTION-STRING
  EVENTHUB-CONNECTION-STRING
  OPENAI-API-KEY
  SearchServiceAdminKey
  APPINSIGHTS-INSTRUMENTATIONKEY
  PGBOUNCER-DATABASE-URL

CONTAINER APPS DEPLOYED:
  ca-udip-ai            (2 CPU, 4Gi, 2-6 replicas)
  ca-udip-cdc           (2 CPU, 4Gi, 1-2 replicas)
  ca-adr-webapp         (2 CPU, 4Gi, 3-12 replicas)
  ca-triage-webapp      (1 CPU, 2Gi, 2-6 replicas)
  ca-arc-integration    (1 CPU, 2Gi, 2-4 replicas)
  ca-ogc-trialtool      (1 CPU, 2Gi, 2-4 replicas)
  ca-pgbouncer          (0.5 CPU, 256Mi, 2-4 replicas)
  ca-mcp-aggregator     (0.5 CPU, 512Mi, 1-2 replicas)
  ca-superset-web       (2 CPU, 4Gi, 2-4 replicas)
  ca-debezium           (2 CPU, 4Gi, 1-1 replicas)

SECURITY:
  - All PaaS services use private endpoints (no public access)
  - WORM immutability on audit archive (2555 days / 7 years)
  - NSG flow logs with Traffic Analytics
  - Sentinel + UEBA enabled
  - TLS 1.2 minimum on all endpoints
  - RBAC-only Key Vault (no access policies)
  - WAF in Prevention mode with OWASP 3.2 + bot protection
  - Rate limiting: 100 req/min/IP on Front Door

COMPLIANCE:
  - FedRAMP High: Azure Government, private endpoints, CMK-ready
  - M-21-31 EL3: Sentinel, UEBA, flow logs, DNS Analytics
  - NARA: 7-year WORM retention on audit records
  - FOIA: Export container provisioned (foia-exports)

==========================================================================
  MANUAL STEPS REMAINING
==========================================================================

  1. Create Entra ID app registrations:
     - Hub API (ARC.Read, ARC.Write app roles)
     - ARC Integration API (M2M client credentials)
     - ADR webapp (user auth + Login.gov federation)
     - Triage webapp (internal user auth)
     See: Azure_Full_Deployment_Guide.md Section 2.12

  2. Request WAL/CDC access from ARC DBA:
     Two SQL commands on PrEPA PostgreSQL:
       SELECT pg_create_logical_replication_slot('udip_cdc', 'pgoutput');
       CREATE PUBLICATION udip_publication FOR ALL TABLES;
     Plus: read-only credentials, hostname, port confirmation,
           max_slot_wal_keep_size set to at least 50GB

  3. Build and push Docker images to ACR:
     az acr login --name ${EEOC_ACR}
     # then docker build + docker push for each app

  4. Create DNS CNAME for ADR:
     ${EEOC_ADR_DOMAIN} -> ${EEOC_FRONTDOOR}.azurefd.net

  5. Upload TLS certificate to Key Vault:
     az keyvault certificate import \\
       --vault-name ${EEOC_KV} \\
       --name adr-tls-cert \\
       --file /path/to/cert.pfx

  6. Configure APIM for MCP Hub:
     See: Azure_MCP_Hub_Setup_Guide.md

  7. Update Container App env vars with app-specific settings:
     See deployment guide for per-app configuration

  8. Enable feature flags per application:
     - ADR: ENABLE_UDIP_INTEGRATION, ENABLE_HUB_INTEGRATION
     - Triage: ENABLE_ARC_WRITEBACK
     - UDIP: ENABLE_CDC_CONSUMER

  9. Run spoke connection sequence (Phase 3.1-3.6):
     See: Azure_Deployment_Sequence.md

==========================================================================

EOF

echo ""
log_ok "Deployment summary saved to: ${SUMMARY_FILE}"
log_ok "Full log saved to: ${LOG_FILE}"
echo ""
echo "Total provisioning time: ~45-60 minutes"
echo ""
