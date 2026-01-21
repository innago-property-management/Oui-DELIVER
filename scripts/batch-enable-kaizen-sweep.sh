#!/usr/bin/env bash
# Batch enable kaizen-sweep for multiple repos
#
# Usage:
#   ./scripts/batch-enable-kaizen-sweep.sh [--days N] [--lang LANG] [--dry-run]
#   ./scripts/batch-enable-kaizen-sweep.sh --repos "repo1 repo2 repo3"
#
# Options:
#   --days N      Filter candidates by activity (default: 30)
#   --lang LANG   Filter by primary language
#   --repos LIST  Explicit list of repos (space-separated, quoted)
#   --dry-run     Show what would be enabled without creating PRs
#   --direct      Push directly instead of creating PRs (for repos without protection)
#
# Output:
#   Creates PRs for each repo and outputs URLs for human review
#
# Examples:
#   ./scripts/batch-enable-kaizen-sweep.sh --days 30           # All active repos
#   ./scripts/batch-enable-kaizen-sweep.sh --lang "C#"         # Only C# repos
#   ./scripts/batch-enable-kaizen-sweep.sh --dry-run           # Preview only
#   ./scripts/batch-enable-kaizen-sweep.sh --repos "merlin property"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDENTIFY_SCRIPT="$SCRIPT_DIR/identify-kaizen-candidates.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-kaizen-sweep.sh"

# Parse arguments
DAYS=30
LANG_FILTER=""
EXPLICIT_REPOS=""
DRY_RUN=false
DIRECT_PUSH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            DAYS="$2"
            shift 2
            ;;
        --lang)
            LANG_FILTER="$2"
            shift 2
            ;;
        --repos)
            EXPLICIT_REPOS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --direct)
            DIRECT_PUSH=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--days N] [--lang LANG] [--repos LIST] [--dry-run] [--direct]"
            echo ""
            echo "Batch enable kaizen-sweep for multiple repos."
            echo ""
            echo "Options:"
            echo "  --days N      Filter candidates by activity (default: 30)"
            echo "  --lang LANG   Filter by primary language"
            echo "  --repos LIST  Explicit list of repos (space-separated, quoted)"
            echo "  --dry-run     Show what would be enabled without creating PRs"
            echo "  --direct      Push directly instead of creating PRs"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get list of repos to enable
if [[ -n "$EXPLICIT_REPOS" ]]; then
    REPOS=($EXPLICIT_REPOS)
    echo -e "${CYAN}Using explicit repo list: ${#REPOS[@]} repos${NC}"
else
    echo -e "${CYAN}Finding candidates (--days $DAYS${LANG_FILTER:+ --lang $LANG_FILTER})...${NC}"

    IDENTIFY_ARGS="--days $DAYS --json"
    [[ -n "$LANG_FILTER" ]] && IDENTIFY_ARGS="$IDENTIFY_ARGS --lang $LANG_FILTER"

    CANDIDATES_JSON=$("$IDENTIFY_SCRIPT" $IDENTIFY_ARGS)
    REPOS=($(echo "$CANDIDATES_JSON" | jq -r '.candidates[].name'))

    echo -e "Found ${GREEN}${#REPOS[@]}${NC} candidates"
fi

if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No repos to enable.${NC}"
    exit 0
fi

echo ""
echo "========================================"
echo "Repos to enable:"
echo "========================================"
for REPO in "${REPOS[@]}"; do
    echo "  - $REPO"
done
echo ""

if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN - No changes will be made${NC}"
    echo ""
    echo "Would run for each repo:"
    if $DIRECT_PUSH; then
        echo "  $DEPLOY_SCRIPT <repo>"
    else
        echo "  $DEPLOY_SCRIPT <repo> --pr"
    fi
    exit 0
fi

# Confirm
echo -e "${YELLOW}This will create ${#REPOS[@]} PRs (or direct pushes).${NC}"
read -p "Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Track results
declare -a SUCCESS_REPOS=()
declare -a FAILED_REPOS=()
declare -a PR_URLS=()

echo ""
echo "========================================"
echo "Enabling repos..."
echo "========================================"
echo ""

for REPO in "${REPOS[@]}"; do
    echo -e "${CYAN}[$((${#SUCCESS_REPOS[@]} + ${#FAILED_REPOS[@]} + 1))/${#REPOS[@]}]${NC} Enabling $REPO..."

    DEPLOY_ARGS="$REPO"
    if ! $DIRECT_PUSH; then
        DEPLOY_ARGS="$DEPLOY_ARGS --pr"
    fi

    # Capture output to extract PR URL
    if OUTPUT=$("$DEPLOY_SCRIPT" $DEPLOY_ARGS 2>&1); then
        SUCCESS_REPOS+=("$REPO")

        # Extract PR URL if present
        PR_URL=$(echo "$OUTPUT" | grep -o "https://github.com/[^[:space:]]*pull/[0-9]*" || echo "")
        if [[ -n "$PR_URL" ]]; then
            PR_URLS+=("$PR_URL")
            echo -e "  ${GREEN}✓${NC} PR created: $PR_URL"
        else
            echo -e "  ${GREEN}✓${NC} Enabled (direct push or already existed)"
        fi
    else
        FAILED_REPOS+=("$REPO")
        echo -e "  ${RED}✗${NC} Failed"
        echo "$OUTPUT" | head -5 | sed 's/^/    /'
    fi

    # Brief pause to avoid rate limits
    sleep 1
done

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo ""
echo -e "${GREEN}Successful: ${#SUCCESS_REPOS[@]}${NC}"
echo -e "${RED}Failed: ${#FAILED_REPOS[@]}${NC}"

if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
    echo ""
    echo "Failed repos:"
    for REPO in "${FAILED_REPOS[@]}"; do
        echo "  - $REPO"
    done
fi

if [[ ${#PR_URLS[@]} -gt 0 ]]; then
    echo ""
    echo "========================================"
    echo "PRs Requiring Review"
    echo "========================================"
    echo ""
    for URL in "${PR_URLS[@]}"; do
        echo "$URL"
    done

    echo ""
    echo "========================================"
    echo "Quick Actions"
    echo "========================================"
    echo ""
    echo "# Open all PRs in browser:"
    echo "for url in \\"
    for URL in "${PR_URLS[@]}"; do
        echo "  \"$URL\" \\"
    done
    echo "; do open \"\$url\"; sleep 0.5; done"

    echo ""
    echo "# Or copy this for bulk operations:"
    echo "${PR_URLS[*]}"
fi
