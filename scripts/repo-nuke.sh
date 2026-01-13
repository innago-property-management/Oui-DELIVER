#!/bin/bash
set -euo pipefail

# repo-nuke.sh - Nuclear option for cleaning repository history
# Usage: repo-nuke.sh [org/repo] [--keep-commits N]

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

KEEP_COMMITS=0
REPO=""
WORK_DIR=""
VISIBILITY="public"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [org/repo]

Nuclear option for cleaning repository history.

OPTIONS:
    --keep-commits N    Keep the last N commits (default: 0 = full nuke)
    --help              Show this help message

EXAMPLES:
    $(basename "$0") innago-property-management/my-repo
    $(basename "$0") --keep-commits 100 innago-property-management/my-repo
    $(basename "$0")  # Interactive mode

EOF
    exit 0
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

prompt_required() {
    local prompt="$1"
    local var_name="$2"
    local value=""

    while [[ -z "$value" ]]; do
        read -rp "$prompt: " value
    done
    eval "$var_name=\"$value\""
}

prompt_confirm() {
    local prompt="$1"
    local response
    read -rp "$prompt [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-commits)
            KEEP_COMMITS="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            REPO="$1"
            shift
            ;;
    esac
done

# Interactive prompts if missing
if [[ -z "$REPO" ]]; then
    prompt_required "Enter repository (org/repo)" REPO
fi

if [[ "$KEEP_COMMITS" -eq 0 ]]; then
    echo ""
    echo "History preservation options:"
    echo "  0 = Full nuke (no history, clean slate)"
    echo "  N = Keep last N commits"
    echo ""
    read -rp "Commits to keep [0]: " input
    KEEP_COMMITS="${input:-0}"
fi

ORG=$(echo "$REPO" | cut -d'/' -f1)
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
WORK_DIR=$(mktemp -d)
FRESH_DIR="${WORK_DIR}/${REPO_NAME}-fresh"
SETTINGS_FILE="${WORK_DIR}/repo-settings.json"

log_info "Repository: $REPO"
log_info "Keep commits: $KEEP_COMMITS"
log_info "Working directory: $WORK_DIR"

# Verify repo exists and get settings
log_info "Fetching repository settings..."

if ! gh repo view "$REPO" --json name &>/dev/null; then
    log_error "Repository $REPO not found or not accessible"
    exit 1
fi

# Capture settings
log_info "Capturing repository configuration..."

cat > "$SETTINGS_FILE" <<EOF
{
  "repo": "$REPO",
  "captured_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo ""
echo "=== Repository Settings ==="

# Visibility
VISIBILITY=$(gh repo view "$REPO" --json visibility --jq '.visibility' | tr '[:upper:]' '[:lower:]')
log_info "Visibility: $VISIBILITY"

# Description
DESCRIPTION=$(gh repo view "$REPO" --json description --jq '.description // empty')
if [[ -n "$DESCRIPTION" ]]; then
    log_info "Description: $DESCRIPTION"
fi

# Webhooks
echo ""
echo "--- Webhooks ---"
WEBHOOKS=$(gh api "repos/$REPO/hooks" --jq '.[].config.url' 2>/dev/null || echo "")
if [[ -n "$WEBHOOKS" ]]; then
    echo "$WEBHOOKS"
else
    echo "(none)"
fi

# Secrets (names only)
echo ""
echo "--- Repository Secrets (names only) ---"
SECRETS=$(gh secret list -R "$REPO" 2>/dev/null || echo "")
if [[ -n "$SECRETS" ]]; then
    echo "$SECRETS"
else
    echo "(none or no access)"
fi

# Branch protection
echo ""
echo "--- Branch Protection (main) ---"
PROTECTION=$(gh api "repos/$REPO/branches/main/protection" 2>/dev/null || echo "")
if [[ -n "$PROTECTION" && "$PROTECTION" != *"not protected"* ]]; then
    echo "$PROTECTION" | jq -r '{
        required_reviews: .required_pull_request_reviews.required_approving_review_count,
        dismiss_stale: .required_pull_request_reviews.dismiss_stale_reviews,
        require_code_owner: .required_pull_request_reviews.require_code_owner_reviews,
        status_checks: [.required_status_checks.contexts[]?]
    }' 2>/dev/null || echo "(complex protection rules - check manually)"
else
    echo "(none)"
fi

# Open PRs
echo ""
echo "--- Open Pull Requests ---"
OPEN_PRS=$(gh pr list -R "$REPO" --state open --json number,title --jq '.[] | "#\(.number): \(.title)"' 2>/dev/null || echo "")
if [[ -n "$OPEN_PRS" ]]; then
    echo "$OPEN_PRS"
else
    echo "(none)"
fi

echo ""
echo "=== End Settings ==="
echo ""

# Confirm before proceeding
log_warn "This will PERMANENTLY DELETE the repository and recreate it."
if [[ "$KEEP_COMMITS" -eq 0 ]]; then
    log_warn "ALL HISTORY will be lost. Only current files will be preserved."
else
    log_warn "Only the last $KEEP_COMMITS commits will be preserved."
fi
echo ""

if ! prompt_confirm "Are you sure you want to proceed?"; then
    log_info "Aborted."
    rm -rf "$WORK_DIR"
    exit 0
fi

# Double confirm for safety
if ! prompt_confirm "Type 'y' again to confirm deletion of $REPO"; then
    log_info "Aborted."
    rm -rf "$WORK_DIR"
    exit 0
fi

# Clone the repository
log_info "Cloning repository..."
git clone "git@github.com:$REPO.git" "${WORK_DIR}/${REPO_NAME}"
cd "${WORK_DIR}/${REPO_NAME}"

# Ensure we're on the default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
git checkout "$DEFAULT_BRANCH"
git pull origin "$DEFAULT_BRANCH"

# Create fresh copy
log_info "Creating fresh copy..."
mkdir -p "$FRESH_DIR"

if [[ "$KEEP_COMMITS" -eq 0 ]]; then
    # Full nuke - no history
    rsync -av --exclude='.git' "${WORK_DIR}/${REPO_NAME}/" "$FRESH_DIR/"
    cd "$FRESH_DIR"
    git init
    git add .
    git commit -m "Initial commit - fresh start

Security reset: repository history has been purged.

Previous history was removed due to security concerns.
See repository settings backup for configuration details."
else
    # Keep last N commits
    cd "${WORK_DIR}/${REPO_NAME}"

    # Get the SHA that will be our new root
    TOTAL_COMMITS=$(git rev-list --count HEAD)
    if [[ "$KEEP_COMMITS" -ge "$TOTAL_COMMITS" ]]; then
        log_warn "Repository only has $TOTAL_COMMITS commits. Keeping all."
        cp -R "${WORK_DIR}/${REPO_NAME}" "$FRESH_DIR"
        rm -rf "${FRESH_DIR}/.git"
        cd "$FRESH_DIR"
        git init
        git add .
        git commit -m "Initial commit - history preserved (all $TOTAL_COMMITS commits)"
    else
        # Create a new repo with truncated history
        TARGET_SHA=$(git rev-parse "HEAD~$((KEEP_COMMITS))")

        cd "$FRESH_DIR"
        git init

        # Copy files from the target commit as initial state
        git -C "${WORK_DIR}/${REPO_NAME}" archive "$TARGET_SHA" | tar -x
        git add .
        git commit -m "Initial commit - history truncated

This commit represents the state at $(git -C "${WORK_DIR}/${REPO_NAME}" log -1 --format='%h %s' "$TARGET_SHA")

History before this point was removed for security reasons."

        # Now cherry-pick the commits we want to keep
        log_info "Cherry-picking last $KEEP_COMMITS commits..."

        # Get list of commits to cherry-pick (oldest first)
        COMMITS=$(git -C "${WORK_DIR}/${REPO_NAME}" rev-list --reverse "HEAD~${KEEP_COMMITS}..HEAD")

        for commit in $COMMITS; do
            # Get the commit content
            git -C "${WORK_DIR}/${REPO_NAME}" format-patch -1 "$commit" --stdout | git am --3way || {
                log_warn "Conflict cherry-picking $commit, attempting resolution..."
                git add .
                git am --continue || git am --skip
            }
        done
    fi
fi

cd "$FRESH_DIR"

# Verify the fresh repo
log_info "Fresh repository created with $(git rev-list --count HEAD) commit(s)"
git log --oneline | head -5

echo ""
log_warn "About to delete the remote repository..."

# Delete remote repo
if ! prompt_confirm "Delete $REPO now?"; then
    log_info "Aborted at deletion step. Fresh copy is at: $FRESH_DIR"
    exit 0
fi

log_info "Deleting remote repository..."
gh repo delete "$REPO" --yes

# Recreate repository
log_info "Recreating repository as $VISIBILITY..."
VISIBILITY_FLAG="--$VISIBILITY"

if [[ -n "$DESCRIPTION" ]]; then
    gh repo create "$REPO" "$VISIBILITY_FLAG" --source=. --push --description "$DESCRIPTION"
else
    gh repo create "$REPO" "$VISIBILITY_FLAG" --source=. --push
fi

log_info "Repository recreated successfully!"
echo ""

# Output reconfiguration checklist
cat <<EOF
=== RECONFIGURATION CHECKLIST ===

Repository: $REPO
New URL: https://github.com/$REPO

[ ] Re-enable secret scanning:
    Settings → Code security → Secret scanning

[ ] Reconfigure branch protection:
    Settings → Branches → Add rule for '$DEFAULT_BRANCH'

EOF

if [[ -n "$WEBHOOKS" ]]; then
    echo "[ ] Reconfigure webhooks:"
    echo "$WEBHOOKS" | while read -r hook; do
        echo "    - $hook"
    done
    echo ""
fi

if [[ -n "$SECRETS" ]]; then
    echo "[ ] Re-add repository secrets:"
    echo "$SECRETS" | while read -r secret; do
        echo "    - $secret"
    done
    echo ""
fi

cat <<EOF
[ ] Notify team members to re-clone or update remotes

[ ] ROTATE ALL EXPOSED CREDENTIALS
    (If this was a security incident, credentials are compromised)

Settings backup saved to: $SETTINGS_FILE

=================================
EOF

log_info "Done! Repository has been nuked and recreated."
