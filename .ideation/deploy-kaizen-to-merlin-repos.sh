#!/bin/bash
# Deploy Kaizen Code Review Workflows to Merlin Repositories
# This script commits and pushes the kaizen workflow files to all merlin repos

set -e  # Exit on error

REPOS=(
  "merlin"
  "merlin-main-job"
  "merlin-creditreporting-job"
  "merlin-quickbook-job"
  "merlin-invoicejob"
  "merlin-latefeejob"
  "merlin-schedulejob"
)

COMMIT_MESSAGE="$(cat <<'EOF'
Add Kaizen code review workflow

Enables automatic code quality suggestions on merged PRs using Claude AI.

**What this does:**
- Triggers on PR merge (closed + merged=true)
- Analyzes PR diff for improvement opportunities
- Posts optional suggestions following "Boy Scout Rule"
- Focuses on: extract method, extract constant, simplify control flow,
  improve naming, remove dead code, add guards

**Key features:**
- "Silence is success" - only comments when improvements found
- ONE improvement per file (prevents overwhelming PRs)
- Advisor not enforcer - all suggestions are optional
- Quality bar: low-risk + obviously beneficial + minimal disruption

**Workflow details:**
- Calls reusable workflow from Oui-DELIVER repository
- Uses organization secrets: ANTHROPIC_API_KEY, GITHUB_TOKEN
- Can be manually triggered via workflow_dispatch for testing

**Testing:**
Use workflow_dispatch to test on recent merged PRs before relying on
automatic triggers.

**More info:**
See Oui-DELIVER repository for full kaizen system documentation.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"

echo "========================================="
echo "Kaizen Workflow Deployment Script"
echo "========================================="
echo ""
echo "This script will:"
echo "  1. Check out each merlin repository"
echo "  2. Create a feature branch (feat/kaizen-workflow)"
echo "  3. Commit the kaizen workflow file"
echo "  4. Push to GitHub"
echo "  5. Provide PR creation commands"
echo ""
echo "Repositories to deploy:"
for repo in "${REPOS[@]}"; do
  echo "  - $repo"
done
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

cd /Volumes/Repos

for repo in "${REPOS[@]}"; do
  echo ""
  echo "========================================="
  echo "Processing: $repo"
  echo "========================================="

  if [ ! -d "$repo" ]; then
    echo "❌ Repository not found: $repo"
    continue
  fi

  cd "$repo"

  # Check if workflow file exists
  if [ ! -f ".github/workflows/kaizen-code-review.yml" ]; then
    echo "❌ Workflow file not found in $repo"
    cd /Volumes/Repos
    continue
  fi

  # Fetch latest
  echo "📥 Fetching latest changes..."
  git fetch origin 2>&1 | head -5

  # Determine main branch name
  MAIN_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
  if [ -z "$MAIN_BRANCH" ]; then
    MAIN_BRANCH="main"
  fi
  echo "   Main branch: $MAIN_BRANCH"

  # Check out main and pull latest
  echo "🔄 Checking out $MAIN_BRANCH..."
  git checkout "$MAIN_BRANCH" 2>&1 | head -3
  git pull origin "$MAIN_BRANCH" 2>&1 | head -5

  # Create feature branch
  BRANCH_NAME="feat/kaizen-workflow"
  echo "🌱 Creating branch: $BRANCH_NAME"

  # Delete local branch if it exists
  git branch -D "$BRANCH_NAME" 2>/dev/null || true

  git checkout -b "$BRANCH_NAME"

  # Stage workflow file
  echo "📝 Staging kaizen workflow file..."
  git add .github/workflows/kaizen-code-review.yml

  # Commit
  echo "💾 Committing..."
  git commit -m "$COMMIT_MESSAGE"

  # Push
  echo "🚀 Pushing to GitHub..."
  git push -u origin "$BRANCH_NAME" --force

  # Store PR creation command
  echo ""
  echo "✅ Successfully deployed to $repo"
  echo "   Branch: $BRANCH_NAME"
  echo "   Create PR:"
  echo "   gh pr create --repo innago-property-management/$repo --base $MAIN_BRANCH --head $BRANCH_NAME --title \"Add Kaizen code review workflow\" --body \"Enables automatic code quality suggestions on merged PRs. See commit message for details.\""
  echo ""

  cd /Volumes/Repos
done

echo ""
echo "========================================="
echo "✅ Deployment Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Review the pushed branches on GitHub"
echo "  2. Create PRs using the commands above (or via GitHub UI)"
echo "  3. Merge PRs to enable kaizen on each repository"
echo "  4. Test using workflow_dispatch on a recent merged PR"
echo ""
echo "Note: The Oui-DELIVER kaizen system must be merged to main first"
echo "      for the reusable workflow to be available."
echo ""
