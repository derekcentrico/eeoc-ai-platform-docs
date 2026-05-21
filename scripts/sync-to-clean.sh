#!/usr/bin/env bash
set -euo pipefail

# sync-to-clean.sh — Export a working EEOC repo to its agency-facing clean copy.
#
# Copies the latest file state (no git history) from a working repo into
# its corresponding clean repo, stripping all AI tooling artifacts, dev
# workspace files, and development metadata.  Agency-owned CI workflows
# (Black Duck, etc.) in the clean repo are preserved and never overwritten.
#
# Pre-flight runs the repo's own local-ci.sh (the same gates used in
# development) before any files are copied.  If local-ci.sh fails, the
# script aborts — only verified code reaches the agency repo.
#
# Usage:
#   bash sync-to-clean.sh <working-repo-dir> <clean-repo-dir> [--skip-ci]
#
# Examples:
#   bash sync-to-clean.sh \
#       ~/ai-platform/workspace/eeoc-workspace/eeoc-ofs-adr \
#       ~/ai-platform/workspace/eeoc-agency-export/ADR_PORTAL
#
#   bash sync-to-clean.sh ../eeoc-ofs-adr ../../eeoc-agency-export/ADR_PORTAL --skip-ci
#
# After the script finishes, manually review, commit, and push from the
# agency export directory:
#   cd ~/ai-platform/workspace/eeoc-agency-export/ADR_PORTAL
#   git diff            # review every change
#   git add -A && git commit -m "Update to latest"
#   git push origin main

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Patterns that indicate AI authorship — checked BEFORE sync.
# These cannot be mechanically stripped and must be fixed in the
# working repo before export.
PREFLIGHT_AI_PATTERNS=(
    "Co-Authored-By"
    "Claude Desktop"
    "Claude Code"
    "508 skill"
    "platform skill"
    "skill-compliant"
    "per the skill"
    "required by the skill"
)

# Patterns checked AFTER sync on the clean copy.  Includes everything
# the post-sync scrub should have removed (.claude/, CLAUDE.md, etc.)
# plus the preflight patterns as a safety net.
POSTSYNC_AI_PATTERNS=(
    "anthropic"
    "Co-Authored-By"
    "Claude Desktop"
    "Claude Code"
    "508 skill"
    "platform skill"
    "skill-compliant"
    "\.claude/"
    "CLAUDE\.md"
)

EXCLUDE_PATHS=(
    ".git"
    ".claude"
    ".hypothesis"
    ".mypy_cache"
    ".pytest_cache"
    ".ruff_cache"
    ".coverage"
    ".venv"
    "venv"
    "__pycache__"
    "build"
    "dist"
    "debug"
    "misc"
    "*.pyc"
    "*.pyo"
    "*.whl"
    ".env"
    ".env.*"
    ".secrets.baseline"
    ".post-impl-verified"
    "*.egg-info"
)

# Agency-owned files in the clean repo that must never be overwritten.
AGENCY_PRESERVED_FILES=(
    ".github/workflows/blackduck-workflow.yml"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}PASS${NC}  $1"; }
fail()  { echo -e "  ${RED}FAIL${NC}  $1"; }
warn()  { echo -e "  ${YELLOW}WARN${NC}  $1"; }
info()  { echo -e "  ----  $1"; }

die() { echo -e "\n${RED}ABORTED:${NC} $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

if [ $# -lt 2 ]; then
    echo "Usage: $0 <working-repo-dir> <clean-repo-dir> [--skip-ci]"
    exit 1
fi

WORKING="$(cd "$1" && pwd)"
CLEAN="$(cd "$2" && pwd)"
SKIP_CI=false
[ "${3:-}" = "--skip-ci" ] && SKIP_CI=true

[ -d "$WORKING/.git" ] || die "Working directory is not a git repo: $WORKING"
[ -d "$CLEAN/.git" ]   || die "Clean directory is not a git repo: $CLEAN"

REPO_NAME="$(basename "$WORKING")"
echo "============================================================"
echo "  sync-to-clean: $REPO_NAME"
echo "  working: $WORKING"
echo "  clean:   $CLEAN"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Gate 1: local-ci.sh — run the repo's own verification pipeline
# ---------------------------------------------------------------------------

echo "Gate 1: Local CI verification"

if [ "$SKIP_CI" = true ]; then
    warn "Local CI skipped (--skip-ci flag)"
elif [ -f "$WORKING/scripts/local-ci.sh" ]; then
    info "Running: bash scripts/local-ci.sh --fast"
    if (cd "$WORKING" && bash scripts/local-ci.sh --fast); then
        pass "local-ci.sh passed"
    else
        fail "local-ci.sh failed — fix findings before export"
        die "Local CI gate failed"
    fi
else
    warn "No scripts/local-ci.sh found — running fallback checks"

    # Fallback: ruff + gitleaks if local-ci.sh is absent
    if command -v ruff &>/dev/null; then
        SRC_DIRS=$(find "$WORKING" -maxdepth 2 -name '*.py' -not -path '*/.git/*' \
            -not -path '*/.venv/*' -not -path '*/__pycache__/*' \
            -printf '%h\n' | sort -u | head -5)
        if [ -n "$SRC_DIRS" ]; then
            (cd "$WORKING" && ruff check $SRC_DIRS 2>/dev/null) \
                && pass "Ruff lint passed" \
                || { fail "Ruff lint failed"; die "Lint gate failed"; }
        fi
    fi

    if command -v gitleaks &>/dev/null; then
        if gitleaks detect --source "$WORKING" --no-git --redact --quiet 2>/dev/null; then
            pass "Gitleaks: no secrets detected"
        else
            fail "Gitleaks: potential secrets found"
            die "Security gate failed"
        fi
    else
        warn "Gitleaks not installed — skipping"
    fi
fi

# ---------------------------------------------------------------------------
# Gate 2: AI tooling artifact check
# ---------------------------------------------------------------------------

echo ""
echo "Gate 2: AI tooling artifact check"
AI_FAILURES=0

for pattern in "${PREFLIGHT_AI_PATTERNS[@]}"; do
    hits=$(grep -ril \
        -E "$pattern" "$WORKING" 2>/dev/null \
        | grep -v '.git/' | grep -v '__pycache__' | grep -v '.venv/' \
        | grep -v 'node_modules/' | grep -v '.hypothesis/' \
        | grep -v '\.png$\|\.jpg$\|\.ico$\|\.gif$\|\.woff' \
        | grep -v '\.gitignore$' \
        | grep -v '\.pre-commit-config\.yaml$' \
        | grep -v 'CLAUDE\.md$' \
        | grep -v '\.claude/' || true)
    if [ -n "$hits" ]; then
        count=$(echo "$hits" | wc -l)
        warn "AI pattern \"$pattern\" found in $count file(s):"
        echo "$hits" | head -5 | sed 's/^/         /'
        AI_FAILURES=$((AI_FAILURES + 1))
    fi
done

if [ "$AI_FAILURES" -gt 0 ]; then
    fail "AI artifacts: $AI_FAILURES patterns found — scrub before export"
    die "AI artifact gate failed"
else
    pass "AI artifacts: no development tooling references in source"
fi

# ---------------------------------------------------------------------------
# All gates passed — begin sync
# ---------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "  All gates passed — syncing files"
echo "============================================================"
echo ""

# Back up agency-preserved files from clean repo
BACKUP_DIR=$(mktemp -d)
for preserved in "${AGENCY_PRESERVED_FILES[@]}"; do
    if [ -f "$CLEAN/$preserved" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$preserved")"
        cp "$CLEAN/$preserved" "$BACKUP_DIR/$preserved"
        info "Preserved agency file: $preserved"
    fi
done

info "Clean repo .git/ is untouched (files-only sync)"

# Build rsync exclude list
RSYNC_EXCLUDES=()
for exc in "${EXCLUDE_PATHS[@]}"; do
    RSYNC_EXCLUDES+=(--exclude="$exc")
done

# Sync: delete anything in clean that's not in working (except .git and
# agency-preserved files), then copy everything from working.
rsync -a --delete \
    --exclude=".git" \
    "${RSYNC_EXCLUDES[@]}" \
    "$WORKING/" "$CLEAN/"

info "File sync complete"

# Remove build artifacts that rsync --delete skips (excluded paths
# already present in the clean repo from prior syncs)
find "$CLEAN" -not -path '*/.git/*' -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -type d -name '.mypy_cache' -exec rm -rf {} + 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -type d -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -type d -name '.ruff_cache' -exec rm -rf {} + 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -type d -name '.hypothesis' -exec rm -rf {} + 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -name '.coverage' -delete 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -name '.post-impl-verified' -delete 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -name '.secrets.baseline' -delete 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -type d -name '*.egg-info' -exec rm -rf {} + 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -type d -name 'build' -exec rm -rf {} + 2>/dev/null || true
find "$CLEAN" -not -path '*/.git/*' -type d -name 'dist' -exec rm -rf {} + 2>/dev/null || true
info "Cleaned build artifacts from clean repo"

# Restore agency-preserved files
for preserved in "${AGENCY_PRESERVED_FILES[@]}"; do
    if [ -f "$BACKUP_DIR/$preserved" ]; then
        mkdir -p "$CLEAN/$(dirname "$preserved")"
        cp "$BACKUP_DIR/$preserved" "$CLEAN/$preserved"
        info "Restored agency file: $preserved"
    fi
done
rm -rf "$BACKUP_DIR"

# ---------------------------------------------------------------------------
# Post-sync scrub
# ---------------------------------------------------------------------------

echo ""
echo "Post-sync scrub"

# Remove .claude/ references from .gitignore
if [ -f "$CLEAN/.gitignore" ]; then
    sed -i '/^# Claude Code$/d; /^\.claude\/$/d; /^\.claude$/d' "$CLEAN/.gitignore"
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$CLEAN/.gitignore"
    info "Stripped .claude/ from .gitignore"
fi

# Remove local claude hooks from .pre-commit-config.yaml (keep gitleaks + ruff)
if [ -f "$CLEAN/.pre-commit-config.yaml" ]; then
    python3 -c "
import yaml

with open('$CLEAN/.pre-commit-config.yaml') as f:
    data = yaml.safe_load(f)

if data and 'repos' in data:
    cleaned = [r for r in data['repos'] if r.get('repo') != 'local']
    data['repos'] = cleaned

with open('$CLEAN/.pre-commit-config.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)
" 2>/dev/null && info "Stripped local hooks from .pre-commit-config.yaml" \
    || { fail "Could not parse .pre-commit-config.yaml — PyYAML may not be installed"; die "Pre-commit scrub failed (local hooks may survive)"; }
fi

# Remove any CLAUDE.md files
rm -f "$CLEAN/CLAUDE.md" "$CLEAN/.claude" 2>/dev/null
find "$CLEAN" -name 'CLAUDE.md' -not -path '*/.git/*' -delete 2>/dev/null
find "$CLEAN" -type d -name '.claude' -not -path '*/.git/*' -exec rm -rf {} + 2>/dev/null
info "Removed any CLAUDE.md files and .claude/ directories"

# ---------------------------------------------------------------------------
# Post-sync verification — scan the CLEAN copy for any remaining artifacts
# ---------------------------------------------------------------------------

echo ""
echo "Post-sync verification"
POSTSYNC_HITS=0

for pattern in "${POSTSYNC_AI_PATTERNS[@]}"; do
    hits=$(grep -ril \
        -E "$pattern" "$CLEAN" 2>/dev/null \
        | grep -v '.git/' \
        | grep -v 'THIRD_PARTY_LICENSES' \
        | grep -v '\.png$\|\.jpg$\|\.ico$\|\.gif$\|\.woff\|\.ttf\|\.eot' || true)
    if [ -n "$hits" ]; then
        count=$(echo "$hits" | wc -l)
        warn "Post-sync: \"$pattern\" still present in $count file(s):"
        echo "$hits" | head -5 | sed 's/^/         /'
        POSTSYNC_HITS=$((POSTSYNC_HITS + 1))
    fi
done

if [ "$POSTSYNC_HITS" -gt 0 ]; then
    fail "Post-sync: $POSTSYNC_HITS AI patterns remain — manual scrub needed"
    die "Post-sync verification failed"
else
    pass "Post-sync: clean repo has no AI tooling references"
fi

# ---------------------------------------------------------------------------
# Summary — manual commit and push required
# ---------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "  sync-to-clean complete: $REPO_NAME"
echo "============================================================"
echo ""

cd "$CLEAN"
CHANGED=$(git status --short | wc -l)

if [ "$CHANGED" -eq 0 ]; then
    info "No changes — clean repo is already current"
else
    info "$CHANGED file(s) changed in clean repo"
    echo ""
    git status --short 2>/dev/null | head -20 || true
    [ "$CHANGED" -gt 20 ] && echo "  ... and $((CHANGED - 20)) more"
    echo ""
    echo "  Next steps (manual):"
    echo "    cd $CLEAN"
    echo "    git diff                    # review every change"
    echo "    git add -A"
    echo "    git commit -m 'Update to latest'"
    echo "    git push origin main        # after visual confirmation"
fi
