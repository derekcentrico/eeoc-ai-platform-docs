#!/usr/bin/env bash
set -euo pipefail

# sync-all-clean.sh — Run sync-to-clean.sh against every mapped repo pair.
#
# Reads clean-repo-map.conf and syncs each working repo to its clean
# counterpart.  Skips entries marked "pending" (no agency repo yet) and
# entries whose clean directory does not exist (run init-clean-repo.sh first).
#
# Never commits or pushes.  After this script finishes, review each clean
# repo individually and commit/push manually.
#
# Usage:
#   bash sync-all-clean.sh                    # full CI gates on each repo
#   bash sync-all-clean.sh --skip-ci          # skip local-ci (faster)
#   bash sync-all-clean.sh --only eeoc-ofs-adr  # sync a single repo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAP_FILE="$SCRIPT_DIR/clean-repo-map.conf"
WORKING_BASE="${WORKING_BASE:-$(cd "$SCRIPT_DIR/../../" && pwd)}"
CLEAN_BASE="${CLEAN_BASE:-$(cd "$SCRIPT_DIR/../../../eeoc-agency-export" 2>/dev/null && pwd || echo "")}"

SKIP_CI=""
ONLY_REPO=""

for arg in "$@"; do
    case "$arg" in
        --skip-ci)  SKIP_CI="--skip-ci" ;;
        --only)     shift; ONLY_REPO="$1" 2>/dev/null || true ;;
        *)          [ -z "$ONLY_REPO" ] || true; ONLY_REPO="$arg" ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

[ -f "$MAP_FILE" ] || { echo "Map file not found: $MAP_FILE"; exit 1; }
[ -n "$CLEAN_BASE" ] || { echo "Clean repo base not found. Set CLEAN_BASE or ensure eeoc-agency-export/ exists."; exit 1; }

echo "============================================================"
echo "  sync-all-clean"
echo "  working base: $WORKING_BASE"
echo "  clean base:   $CLEAN_BASE"
echo "============================================================"
echo ""

TOTAL=0
SYNCED=0
SKIPPED=0
FAILED=0
RESULTS=""

while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    working_name=$(echo "$line" | awk '{print $1}')
    clean_name=$(echo "$line" | awk '{print $2}')
    remote=$(echo "$line" | awk '{print $3}')

    # Filter to single repo if --only was used
    if [ -n "$ONLY_REPO" ] && [ "$working_name" != "$ONLY_REPO" ]; then
        continue
    fi

    TOTAL=$((TOTAL + 1))
    working_dir="$WORKING_BASE/$working_name"
    clean_dir="$CLEAN_BASE/$clean_name"

    echo "--- $working_name → $clean_name ---"

    # Skip if working repo missing
    if [ ! -d "$working_dir/.git" ]; then
        echo -e "  ${YELLOW}SKIP${NC}  Working repo not found: $working_dir"
        SKIPPED=$((SKIPPED + 1))
        RESULTS="$RESULTS\n  SKIP  $working_name (working dir missing)"
        echo ""
        continue
    fi

    # Skip if clean repo not initialized
    if [ ! -d "$clean_dir/.git" ]; then
        echo -e "  ${YELLOW}SKIP${NC}  Clean repo not initialized: $clean_dir"
        echo "         Run: bash init-clean-repo.sh $working_dir $clean_dir $remote"
        SKIPPED=$((SKIPPED + 1))
        RESULTS="$RESULTS\n  SKIP  $working_name (clean dir not initialized)"
        echo ""
        continue
    fi

    # Run sync
    if bash "$SCRIPT_DIR/sync-to-clean.sh" "$working_dir" "$clean_dir" $SKIP_CI; then
        SYNCED=$((SYNCED + 1))
        RESULTS="$RESULTS\n  ${GREEN}OK${NC}    $working_name → $clean_name"
    else
        FAILED=$((FAILED + 1))
        RESULTS="$RESULTS\n  ${RED}FAIL${NC}  $working_name → $clean_name"
    fi
    echo ""

done < "$MAP_FILE"

echo "============================================================"
echo "  sync-all-clean results"
echo "============================================================"
echo -e "$RESULTS"
echo ""
echo "  Total: $TOTAL  Synced: $SYNCED  Skipped: $SKIPPED  Failed: $FAILED"
echo ""

if [ "$SYNCED" -gt 0 ]; then
    echo "  Review each synced repo before committing:"
    echo "    cd $CLEAN_BASE/<repo>"
    echo "    git diff && git add -A && git commit -m 'Update to latest'"
fi

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
