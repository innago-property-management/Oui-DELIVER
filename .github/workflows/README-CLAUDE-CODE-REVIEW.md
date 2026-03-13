# Claude Code Review Workflow

Reusable GitHub Actions workflow that performs comprehensive PR code reviews using Claude AI, with formal GitHub review submissions (APPROVE / REQUEST_CHANGES / COMMENT) and structured agent fix prompts.

## Quick Start

### 1. Set Up Secrets

| Secret | Description |
|--------|-------------|
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude |

> `GITHUB_TOKEN` is provided automatically. The workflow uses OIDC to authenticate with the Claude GitHub App.

### 2. Create Caller Workflow

Create `.github/workflows/claude-code-review.yml` in your repository:

```yaml
name: PR Code Review

on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]

# REQUIRED: The reusable workflow needs these permissions.
# id-token: write is needed for Claude Code Action's OIDC authentication.
permissions:
  contents: read
  pull-requests: write
  actions: read
  id-token: write

jobs:
  review:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    with:
      allow_approve: true
      additional_context: |
        This is a [language] project. Focus on [specific concerns].
    secrets:
      anthropicKey: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 3. Grant Repository Permissions

In your repo: **Settings > Actions > General > Workflow permissions**:
- Select **"Read and write permissions"**
- Check **"Allow GitHub Actions to create and approve pull requests"**

## Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `allow_approve` | boolean | `false` | Allow APPROVE verdicts. When false, APPROVE downgrades to COMMENT with "Recommendation: approve" |
| `additional_context` | string | `""` | Repo-specific review guidance appended to the prompt |

## Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `anthropicKey` | Yes | Anthropic API key |

## How It Works

### Architecture

```
Consuming Repo                          Oui-DELIVER (this repo)
┌──────────────────────┐               ┌──────────────────────────┐
│ claude-code-review.yml│──workflow_call──>│ claude-code-review.yml   │
│ (thin caller)        │               │ (reusable workflow)      │
│ - permissions        │               │ - Claude Code Action     │
│ - inputs/secrets     │               │ - Review prompt          │
└──────────────────────┘               │ - gh api for reviews     │
                                       └──────────────────────────┘
```

### Review Process

1. PR opened/updated triggers caller workflow
2. Caller invokes reusable workflow with inputs and secrets
3. Claude fetches PR diff and metadata via `gh pr diff` / `gh pr view`
4. Analyzes code quality, security, performance, testing, documentation
5. Chooses verdict: APPROVE, REQUEST_CHANGES, or COMMENT
6. Submits **one batched review** via `gh api` with inline comments
7. If REQUEST_CHANGES, includes an **agent fix prompt** for AI-to-AI handoff

### Why `gh api` Instead of Claude Code Action's Built-in Review?

The Claude Code Action [deliberately blocks](https://github.com/anthropics/claude-code-action/blob/main/docs/capabilities-and-limitations.md) PR approvals:

> *"Provides inline comment tool without exposing full PR review capabilities, so that Claude can't accidentally approve a PR"*
> — `src/mcp/github-inline-comment-server.ts`

We bypass this by granting `--allowedTools "Bash(gh api repos/*:*)"` which lets Claude call the GitHub REST API directly to submit formal reviews.

### Agent Fix Prompt (AI-to-AI Handoff)

When Claude requests changes, the review body includes a collapsible block:

```markdown
<details>
<summary>Agent fix prompt</summary>

Address the following review findings on PR #123
in repo org/repo, branch feature/foo:

[SECURITY] src/auth.ts line 45 — Move JWT secret to environment variable
[BUG] src/api.ts line 78 — Add null check before accessing user.profile
...

Run tests after all fixes. Push to the same branch.
</details>
```

Copy this into a local Claude Code session to auto-fix the issues.

## Important: Caller Permissions

**The caller workflow MUST declare permissions.** For reusable workflows (`workflow_call`), the OIDC token and GitHub token permissions are determined by the **caller**, not the reusable workflow. The reusable workflow's `permissions` block only sets the maximum.

```yaml
# REQUIRED in the caller — without this, OIDC auth fails
permissions:
  contents: read
  pull-requests: write
  actions: read
  id-token: write    # Required for Claude Code Action OIDC authentication
```

Without `id-token: write` in the caller, you'll see:
```
Could not fetch an OIDC token. Did you remember to add `id-token: write`
to your workflow permissions?
```

## Important: Reusable Workflow Updates and `@main`

Callers reference the reusable workflow via `@main`:
```yaml
uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
```

**Be aware:** GitHub Actions detects when a reusable workflow has changed between the time a PR was opened and when the workflow runs. In some configurations, the Claude Code Action may refuse to run if the underlying workflow changed after the PR was created. This means:

- Pushing changes to `claude-code-review.yml` in Oui-DELIVER can break in-flight review runs across all consuming repos
- Affected PRs need a re-push (or manual re-run) to pick up the new workflow version
- Consider using a **tagged ref** (`@v2`) instead of `@main` for stability, and update callers explicitly when ready

For breaking changes to the reusable workflow, coordinate updates:
1. Merge the workflow change to Oui-DELIVER
2. Re-run or re-push affected PRs in consuming repos

## Verdict Logic

| Condition | Verdict |
|-----------|---------|
| Security vulnerabilities, broken logic, missing error handling, absent tests, deprecated APIs | REQUEST_CHANGES |
| Code is correct, only minor style nits | APPROVE (or COMMENT if `allow_approve: false`) |
| Advisory observations, no blocking issues | COMMENT |

## Customization Examples

### Language-Specific Context

```yaml
additional_context: |
  This is an Elixir/OTP project. Focus on:
  - GenServer correctness and supervision tree design
  - Pattern matching exhaustiveness
  - Proper use of with/case/cond
  - Telemetry event naming conventions
```

### Security-Sensitive Service

```yaml
additional_context: |
  This is a payment processing service (PCI scope).
  - Flag any logging of card data or PII
  - All external calls must have timeouts
  - Database operations require explicit transactions
  - No secrets in code (use fnox or env vars)
```

### Skip Certain PRs

```yaml
jobs:
  review:
    if: github.event.pull_request.user.login != 'dependabot[bot]'
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    # ...
```

## Troubleshooting

### OIDC Token Error
**Error:** `Could not fetch an OIDC token`
**Fix:** Add `id-token: write` to the **caller** workflow's permissions block (not just the reusable).

### Review Doesn't Post
**Check:** Does the caller have `pull-requests: write` permission? Is `ANTHROPIC_API_KEY` secret set?

### Review Runs But Can't Approve
**Check:** Is `allow_approve: true` set in the caller's inputs? Is "Allow GitHub Actions to create and approve pull requests" enabled in repo settings?

### Workflow Refuses to Run After Oui-DELIVER Update
**Cause:** Claude Code Action detected the reusable workflow changed.
**Fix:** Re-push to the PR branch or manually re-run the workflow.

## Learn More

- [Claude Code Action](https://github.com/anthropics/claude-code-action)
- [Claude Code Action FAQ](https://github.com/anthropics/claude-code-action/blob/main/docs/faq.md)
- [Capabilities & Limitations](https://github.com/anthropics/claude-code-action/blob/main/docs/capabilities-and-limitations.md)
