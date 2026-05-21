#!/usr/bin/env bash
set -euo pipefail

# init-clean-repo.sh — Set up a new agency export directory for a working repo.
#
# Creates the clean repo directory, initializes git, seeds it with the
# Black Duck CI workflow, and runs the first sync-to-clean pass.
# The operator then reviews, commits, and pushes manually.
#
# Usage:
#   bash init-clean-repo.sh <working-repo-dir> <clean-repo-dir> [agency-remote-url]
#
# Examples:
#   bash init-clean-repo.sh \
#       ~/ai-platform/workspace/eeoc-workspace/eeoc-ofs-triage \
#       ~/ai-platform/workspace/eeoc-agency-export/OFS_TRIAGE \
#       https://github.com/EEOC/OFS_TRIAGE.git
#
#   bash init-clean-repo.sh ../eeoc-ofs-triage ../../eeoc-agency-export/OFS_TRIAGE
#
# After init completes:
#   cd ~/ai-platform/workspace/eeoc-agency-export/OFS_TRIAGE
#   git diff --cached      # review staged files
#   git commit -m "Initial import"
#   git remote add origin <url>    # if not set during init
#   git push -u origin main

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "  ----  $1"; }
pass()  { echo -e "  ${GREEN}PASS${NC}  $1"; }
warn()  { echo -e "  ${YELLOW}WARN${NC}  $1"; }
die()   { echo -e "\n${RED}ABORTED:${NC} $1" >&2; exit 1; }

if [ $# -lt 2 ]; then
    echo "Usage: $0 <working-repo-dir> <clean-repo-dir> [agency-remote-url]"
    exit 1
fi

WORKING="$(cd "$1" && pwd)"
CLEAN_PATH="$2"
REMOTE_URL="${3:-}"

[ -d "$WORKING/.git" ] || die "Working directory is not a git repo: $WORKING"

if [ -d "$CLEAN_PATH" ]; then
    die "Clean directory already exists: $CLEAN_PATH  (use sync-to-clean.sh for updates)"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_NAME="$(basename "$WORKING")"

echo "============================================================"
echo "  init-clean-repo: $REPO_NAME"
echo "  working: $WORKING"
echo "  clean:   $CLEAN_PATH"
echo "  remote:  ${REMOTE_URL:-<not set — add manually>}"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# Step 1: Create directory and initialize git
# -----------------------------------------------------------------------

mkdir -p "$CLEAN_PATH"
CLEAN="$(cd "$CLEAN_PATH" && pwd)"

cd "$CLEAN"
git init --initial-branch=main
info "Initialized git repo at $CLEAN"

# -----------------------------------------------------------------------
# Step 2: Set remote if provided
# -----------------------------------------------------------------------

if [ -n "$REMOTE_URL" ] && [ "$REMOTE_URL" != "pending" ]; then
    git remote add origin "$REMOTE_URL"
    info "Remote set: $REMOTE_URL"
else
    warn "No remote set — add one before pushing:"
    echo "         git remote add origin <url>"
fi

# -----------------------------------------------------------------------
# Step 3: Seed with Black Duck CI workflow
# -----------------------------------------------------------------------

mkdir -p "$CLEAN/.github/workflows"

cat > "$CLEAN/.github/workflows/blackduck-workflow.yml" <<'BDWF'
name: CI-BlackDuck-SCA-Basic
on:
  push:
    branches: [main, master, develop, stage, release]
  pull_request:
    branches: [main, master, develop, stage, release]
  workflow_dispatch:

jobs:
  build:
    runs-on: [azure-linux-runner]
    steps:
    - name: Checkout Source
      uses: actions/checkout@v6
    - name: Black Duck SCA Scan
      id: black-duck-sca-scan
      uses: blackduck-inc/black-duck-security-scan@v2

      env:
        DETECT_PROJECT_NAME: ${{ github.event.repository.name }}
        DETECT_PROJECT_VERSION_NAME: ${{ github.event_name != 'pull_request' && github.ref_name || github.event.pull_request.base.ref }}

      with:
        blackducksca_url: ${{ vars.BLACKDUCKSCA_URL }}
        blackducksca_token: ${{ secrets.BLACKDUCKSCA_TOKEN }}
        blackducksca_prcomment_enabled: true
        blackducksca_fixpr_enabled: true
        blackducksca_externalIssues_create: true
        github_token: ${{ secrets.GITHUB_TOKEN }}
        blackducksca_reports_sarif_create: true
        blackducksca_upload_sarif_report: true
        include_diagnostics: false
BDWF

info "Seeded Black Duck CI workflow"

# -----------------------------------------------------------------------
# Step 4: Create a seed commit so sync-to-clean has a base
# -----------------------------------------------------------------------

cat > "$CLEAN/README.md" <<README
# $(basename "$CLEAN")

EEOC application repository.
README

git add -A
git commit -m "Initialize repository with Black Duck CI workflow"
info "Created seed commit"

# -----------------------------------------------------------------------
# Step 5: Run sync-to-clean for the initial file population
# -----------------------------------------------------------------------

echo ""
info "Running initial sync..."
echo ""

if [ -f "$SCRIPT_DIR/sync-to-clean.sh" ]; then
    bash "$SCRIPT_DIR/sync-to-clean.sh" "$WORKING" "$CLEAN" --skip-ci
else
    die "sync-to-clean.sh not found at $SCRIPT_DIR — cannot populate files"
fi

echo ""
echo "============================================================"
echo "  init-clean-repo complete: $(basename "$CLEAN")"
echo "============================================================"
echo ""
echo "  Next steps (manual):"
echo "    cd $CLEAN"
echo "    git diff            # review all synced files"
echo "    git add -A"
echo "    git commit -m 'Initial import from source repository'"
if [ -n "$REMOTE_URL" ] && [ "$REMOTE_URL" != "pending" ]; then
    echo "    git push -u origin main"
else
    echo "    git remote add origin <agency-repo-url>"
    echo "    git push -u origin main"
fi
