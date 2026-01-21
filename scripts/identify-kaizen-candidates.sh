#!/usr/bin/env bash
# Identify repos that are candidates for kaizen-sweep enablement
#
# Usage:
#   ./scripts/identify-kaizen-candidates.sh [--days N] [--json] [--lang LANG]
#
# Options:
#   --days N    Look back N days for activity (default: 30)
#   --json      Output results as JSON
#   --lang LANG Filter by primary language (e.g., "C#", "TypeScript")
#   --all       Include repos with no recent activity
#
# Examples:
#   ./scripts/identify-kaizen-candidates.sh                    # Active repos, last 30 days
#   ./scripts/identify-kaizen-candidates.sh --days 7           # Active in last week
#   ./scripts/identify-kaizen-candidates.sh --lang "C#"        # Only C# repos
#   ./scripts/identify-kaizen-candidates.sh --json             # JSON output

set -euo pipefail

ORG="innago-property-management"

# Parse arguments
DAYS=30
JSON_OUTPUT=false
LANG_FILTER=""
INCLUDE_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            DAYS="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --lang)
            LANG_FILTER="$2"
            shift 2
            ;;
        --all)
            INCLUDE_ALL=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--days N] [--json] [--lang LANG] [--all]"
            echo ""
            echo "Identify repos that are candidates for kaizen-sweep enablement."
            echo ""
            echo "Options:"
            echo "  --days N    Look back N days for activity (default: 30)"
            echo "  --json      Output results as JSON"
            echo "  --lang LANG Filter by primary language"
            echo "  --all       Include repos with no recent activity"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Calculate cutoff date
CUTOFF_DATE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "-${DAYS} days" +%Y-%m-%d)

log() {
    if ! $JSON_OUTPUT; then
        echo -e "$@"
    fi
}

log "Fetching repos from $ORG..."
log ""

# Fetch all repos with relevant metadata
REPOS_JSON=$(gh repo list "$ORG" --limit 200 --json name,pushedAt,primaryLanguage,repositoryTopics,isArchived,description)

# Build jq filter
JQ_FILTER='
    .[] |
    select(.isArchived == false) |
    select(.primaryLanguage.name != null)
'

# Add activity filter unless --all
if ! $INCLUDE_ALL; then
    JQ_FILTER="$JQ_FILTER | select(.pushedAt >= \"$CUTOFF_DATE\")"
fi

# Add language filter if specified
if [[ -n "$LANG_FILTER" ]]; then
    JQ_FILTER="$JQ_FILTER | select(.primaryLanguage.name == \"$LANG_FILTER\")"
fi

# Exclude already enabled repos
JQ_FILTER="$JQ_FILTER | select(((.repositoryTopics // []) | map(.name) | any(. == \"kaizen-enabled\")) | not)"

# Transform to useful output
JQ_TRANSFORM='
{
    name: .name,
    lastPush: .pushedAt[0:10],
    language: .primaryLanguage.name,
    description: (.description // "")[0:50],
    topics: ((.repositoryTopics // []) | map(.name) | join(", "))
}
'

# Get candidates
CANDIDATES=$(echo "$REPOS_JSON" | jq -r "[$JQ_FILTER | $JQ_TRANSFORM] | sort_by(.lastPush) | reverse")
CANDIDATE_COUNT=$(echo "$CANDIDATES" | jq 'length')

# Get currently enabled for context
ENABLED=$(echo "$REPOS_JSON" | jq -r '[.[] | select((.repositoryTopics // []) | map(.name) | any(. == "kaizen-enabled")) | .name]')
ENABLED_COUNT=$(echo "$ENABLED" | jq 'length')

if $JSON_OUTPUT; then
    jq -n \
        --arg cutoff "$CUTOFF_DATE" \
        --arg lang "${LANG_FILTER:-all}" \
        --argjson candidates "$CANDIDATES" \
        --argjson enabled "$ENABLED" \
        '{
            filter: {
                cutoffDate: $cutoff,
                language: $lang
            },
            enabled: $enabled,
            candidates: $candidates,
            summary: {
                enabled: ($enabled | length),
                candidates: ($candidates | length)
            }
        }'
else
    # Colors
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    log "========================================"
    log "Kaizen Sweep Candidate Analysis"
    log "========================================"
    log ""
    log "Filter: Active since $CUTOFF_DATE${LANG_FILTER:+ | Language: $LANG_FILTER}"
    log ""

    log "${GREEN}Currently Enabled ($ENABLED_COUNT):${NC}"
    echo "$ENABLED" | jq -r '.[] | "  ✅ \(.)"'
    log ""

    log "${YELLOW}Candidates ($CANDIDATE_COUNT):${NC}"
    log ""

    if [[ "$CANDIDATE_COUNT" -eq 0 ]]; then
        log "  No candidates found matching criteria."
    else
        # Group by language for easier review
        LANGUAGES=$(echo "$CANDIDATES" | jq -r '[.[].language] | unique | .[]')

        for LANG in $LANGUAGES; do
            LANG_REPOS=$(echo "$CANDIDATES" | jq -r "[.[] | select(.language == \"$LANG\")]")
            LANG_COUNT=$(echo "$LANG_REPOS" | jq 'length')

            log "${CYAN}$LANG ($LANG_COUNT):${NC}"
            echo "$LANG_REPOS" | jq -r '.[] | "  \(.name) | \(.lastPush) | \(.description)"'
            log ""
        done
    fi

    log "========================================"
    log "Summary: ${GREEN}$ENABLED_COUNT enabled${NC} | ${YELLOW}$CANDIDATE_COUNT candidates${NC}"
    log ""
    log "To enable a repo:"
    log "  ./scripts/deploy-kaizen-sweep.sh <repo-name> --pr"
fi
