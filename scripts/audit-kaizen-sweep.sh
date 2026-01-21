#!/usr/bin/env bash
# Audit kaizen-sweep workflow deployments across the org
#
# Usage:
#   ./scripts/audit-kaizen-sweep.sh [--json] [--fix]
#
# Options:
#   --json    Output results as JSON (for programmatic consumption)
#   --fix     Show commands to fix non-compliant repos
#
# Examples:
#   ./scripts/audit-kaizen-sweep.sh              # Standard audit report
#   ./scripts/audit-kaizen-sweep.sh --json       # JSON output for automation
#   ./scripts/audit-kaizen-sweep.sh --fix        # Include remediation commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ORG="innago-property-management"
WORKFLOW_TEMPLATE="$REPO_ROOT/.github/workflows/kaizen-sweep-caller.yml"
WORKFLOW_PATH=".github/workflows/kaizen-sweep.yml"

# Expected values from template
EXPECTED_REF="@main"
EXPECTED_PERMISSIONS=(
    "contents: write"
    "pull-requests: write"
    "issues: read"
    "id-token: write"
)

# Parse arguments
JSON_OUTPUT=false
SHOW_FIX=false

for arg in "$@"; do
    case $arg in
        --json) JSON_OUTPUT=true ;;
        --fix) SHOW_FIX=true ;;
        --help|-h)
            echo "Usage: $0 [--json] [--fix]"
            echo ""
            echo "Audit kaizen-sweep workflow deployments across the org."
            echo ""
            echo "Options:"
            echo "  --json    Output results as JSON"
            echo "  --fix     Show commands to fix non-compliant repos"
            exit 0
            ;;
    esac
done

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Results tracking
declare -a COMPLIANT_REPOS=()
declare -a DRIFT_REPOS=()
declare -a MISSING_REPOS=()
declare -A DRIFT_DETAILS=()

log() {
    if ! $JSON_OUTPUT; then
        echo -e "$@"
    fi
}

# Get repos with kaizen-enabled topic
log "Fetching repos with kaizen-enabled topic..."
REPOS=$(gh repo list "$ORG" --topic kaizen-enabled --json name --jq '.[].name' 2>/dev/null || echo "")

if [[ -z "$REPOS" ]]; then
    log "${YELLOW}No repos found with kaizen-enabled topic${NC}"
    if $JSON_OUTPUT; then
        echo '{"compliant":[],"drift":[],"missing":[],"summary":{"total":0,"compliant":0,"drift":0,"missing":0}}'
    fi
    exit 0
fi

REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
log "Found $REPO_COUNT repos with kaizen-enabled topic"
log ""

# Audit each repo
for REPO in $REPOS; do
    log -n "Checking $REPO... "

    # Fetch workflow file content
    WORKFLOW_CONTENT=$(gh api "repos/$ORG/$REPO/contents/$WORKFLOW_PATH" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [[ -z "$WORKFLOW_CONTENT" ]]; then
        log "${RED}MISSING${NC}"
        MISSING_REPOS+=("$REPO")
        DRIFT_DETAILS["$REPO"]="Workflow file not found at $WORKFLOW_PATH"
        continue
    fi

    # Check if this is the source repo (contains the reusable workflow, not a caller)
    if echo "$WORKFLOW_CONTENT" | grep -q "workflow_call:"; then
        log "${GREEN}SOURCE REPO (reusable workflow)${NC}"
        COMPLIANT_REPOS+=("$REPO")
        continue
    fi

    # Check for issues
    ISSUES=()

    # Check ref (should be @main, not @v2 or SHA)
    if ! echo "$WORKFLOW_CONTENT" | grep -q "Oui-DELIVER/.github/workflows/kaizen-sweep.yml@main"; then
        ACTUAL_REF=$(echo "$WORKFLOW_CONTENT" | grep -o "Oui-DELIVER/.github/workflows/kaizen-sweep.yml@[^[:space:]]*" | sed 's/.*@//' || echo "unknown")
        ISSUES+=("uses: @$ACTUAL_REF (expected: @main)")
    fi

    # Check permissions
    for PERM in "${EXPECTED_PERMISSIONS[@]}"; do
        PERM_KEY=$(echo "$PERM" | cut -d: -f1)
        PERM_VALUE=$(echo "$PERM" | cut -d: -f2 | tr -d ' ')

        if ! echo "$WORKFLOW_CONTENT" | grep -qE "^[[:space:]]*${PERM_KEY}:[[:space:]]*${PERM_VALUE}"; then
            # Check if permission exists with wrong value
            ACTUAL_VALUE=$(echo "$WORKFLOW_CONTENT" | grep -E "^[[:space:]]*${PERM_KEY}:" | sed "s/.*${PERM_KEY}:[[:space:]]*//" | tr -d ' ' || echo "missing")
            if [[ "$ACTUAL_VALUE" == "missing" ]] || [[ -z "$ACTUAL_VALUE" ]]; then
                ISSUES+=("permissions.$PERM_KEY: missing (expected: $PERM_VALUE)")
            else
                ISSUES+=("permissions.$PERM_KEY: $ACTUAL_VALUE (expected: $PERM_VALUE)")
            fi
        fi
    done

    # Check workflow name
    if ! echo "$WORKFLOW_CONTENT" | grep -q "^name: Kaizen Sweep"; then
        ACTUAL_NAME=$(echo "$WORKFLOW_CONTENT" | grep "^name:" | sed 's/name:[[:space:]]*//' || echo "unknown")
        ISSUES+=("name: '$ACTUAL_NAME' (expected: 'Kaizen Sweep')")
    fi

    # Check secrets configuration
    if ! echo "$WORKFLOW_CONTENT" | grep -q "anthropicKey:"; then
        ISSUES+=("secrets.anthropicKey: missing")
    fi
    if ! echo "$WORKFLOW_CONTENT" | grep -q "githubToken:"; then
        ISSUES+=("secrets.githubToken: missing")
    fi

    # Report results
    if [[ ${#ISSUES[@]} -eq 0 ]]; then
        log "${GREEN}COMPLIANT${NC}"
        COMPLIANT_REPOS+=("$REPO")
    else
        log "${YELLOW}DRIFT DETECTED${NC}"
        DRIFT_REPOS+=("$REPO")
        DRIFT_DETAILS["$REPO"]=$(IFS=';'; echo "${ISSUES[*]}")

        if ! $JSON_OUTPUT; then
            for ISSUE in "${ISSUES[@]}"; do
                log "   - $ISSUE"
            done
        fi
    fi
done

log ""

# Summary
TOTAL=${#COMPLIANT_REPOS[@]}+${#DRIFT_REPOS[@]}+${#MISSING_REPOS[@]}
TOTAL=$((${#COMPLIANT_REPOS[@]} + ${#DRIFT_REPOS[@]} + ${#MISSING_REPOS[@]}))

if $JSON_OUTPUT; then
    # Build JSON output
    COMPLIANT_JSON=$(printf '%s\n' "${COMPLIANT_REPOS[@]}" | jq -R . | jq -s .)
    DRIFT_JSON="["
    FIRST=true
    for REPO in "${DRIFT_REPOS[@]}"; do
        if ! $FIRST; then DRIFT_JSON+=","; fi
        FIRST=false
        ISSUES_STR="${DRIFT_DETAILS[$REPO]}"
        ISSUES_ARRAY=$(echo "$ISSUES_STR" | tr ';' '\n' | jq -R . | jq -s .)
        DRIFT_JSON+="{\"repo\":\"$REPO\",\"issues\":$ISSUES_ARRAY}"
    done
    DRIFT_JSON+="]"

    MISSING_JSON="["
    FIRST=true
    for REPO in "${MISSING_REPOS[@]}"; do
        if ! $FIRST; then MISSING_JSON+=","; fi
        FIRST=false
        MISSING_JSON+="{\"repo\":\"$REPO\",\"issues\":[\"${DRIFT_DETAILS[$REPO]}\"]}"
    done
    MISSING_JSON+="]"

    cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "org": "$ORG",
  "compliant": $COMPLIANT_JSON,
  "drift": $DRIFT_JSON,
  "missing": $MISSING_JSON,
  "summary": {
    "total": $TOTAL,
    "compliant": ${#COMPLIANT_REPOS[@]},
    "drift": ${#DRIFT_REPOS[@]},
    "missing": ${#MISSING_REPOS[@]}
  }
}
EOF
else
    log "================================"
    log "Kaizen Sweep Audit - $(date +%Y-%m-%d)"
    log "================================"
    log ""

    if [[ ${#COMPLIANT_REPOS[@]} -gt 0 ]]; then
        log "${GREEN}Compliant (${#COMPLIANT_REPOS[@]}):${NC}"
        for REPO in "${COMPLIANT_REPOS[@]}"; do
            log "  $REPO"
        done
        log ""
    fi

    if [[ ${#DRIFT_REPOS[@]} -gt 0 ]]; then
        log "${YELLOW}Drift Detected (${#DRIFT_REPOS[@]}):${NC}"
        for REPO in "${DRIFT_REPOS[@]}"; do
            log "  $REPO"
            ISSUES_STR="${DRIFT_DETAILS[$REPO]}"
            IFS=';' read -ra ISSUES <<< "$ISSUES_STR"
            for ISSUE in "${ISSUES[@]}"; do
                log "    - $ISSUE"
            done
        done
        log ""
    fi

    if [[ ${#MISSING_REPOS[@]} -gt 0 ]]; then
        log "${RED}Missing Workflow (${#MISSING_REPOS[@]}):${NC}"
        for REPO in "${MISSING_REPOS[@]}"; do
            log "  $REPO - has kaizen-enabled topic but no workflow file"
        done
        log ""
    fi

    log "Summary: $TOTAL repos | ${GREEN}${#COMPLIANT_REPOS[@]} compliant${NC} | ${YELLOW}${#DRIFT_REPOS[@]} drift${NC} | ${RED}${#MISSING_REPOS[@]} missing${NC}"

    if $SHOW_FIX && [[ ${#DRIFT_REPOS[@]} -gt 0 || ${#MISSING_REPOS[@]} -gt 0 ]]; then
        log ""
        log "================================"
        log "Remediation Commands"
        log "================================"

        for REPO in "${DRIFT_REPOS[@]}" "${MISSING_REPOS[@]}"; do
            log ""
            log "# Fix $REPO:"
            log "./scripts/deploy-kaizen-sweep.sh $REPO --pr"
        done
    fi
fi

# Exit with appropriate code
if [[ ${#DRIFT_REPOS[@]} -gt 0 || ${#MISSING_REPOS[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
