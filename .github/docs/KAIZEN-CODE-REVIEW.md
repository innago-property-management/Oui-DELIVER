# Kaizen Code Review - Per-PR Analysis

Kaizen Code Review is a reactive workflow that reviews pull requests when engineers push code.

## Kaizen Sweep vs Kaizen Code Review

| Kaizen Sweep | Kaizen Code Review |
|--------------|-------------------|
| Proactive - runs on schedule | Reactive - runs on PR events |
| Creates PRs with fixes | Comments on existing PRs |
| Finds tech debt across codebase | Reviews what engineer changed |
| One small fix at a time | Comprehensive review of PR |

## The Flow

```
1. ENGINEER PUSHES
   ┌─────────────────┐
   │  git push       │ ─── Opens or updates PR
   └────────┬────────┘
            │
            ▼
2. TRIGGER
   ┌─────────────────┐
   │  pull_request:  │ ─── on: [opened, synchronize]
   │  types: [...]   │
   └────────┬────────┘
            │
            ▼
3. CLAUDE REVIEWS
   ┌─────────────────┐
   │  Claude Code    │ ─── Reads the diff
   │  Action         │ ─── Analyzes changes
   └────────┬────────┘
            │
            ▼
4. POSTS COMMENT
   ┌─────────────────┐
   │  PR Comment     │ ─── Findings + suggestions
   │                 │ ─── Approval or request changes
   └─────────────────┘
```

## What It Reviews

### Security
- SQL injection, XSS, command injection
- Hardcoded secrets or credentials
- Authentication/authorization issues

### Bugs
- Null reference risks
- Off-by-one errors
- Race conditions

### Performance
- N+1 queries
- Unnecessary allocations
- Missing async/await

### Code Quality
- Naming conventions
- Dead code introduced
- Missing error handling

### Positive Feedback
- Well-implemented patterns
- Good test coverage
- Clean abstractions

## Output Format

```markdown
## Kaizen Code Review

### Issues Found

**Security** - SQL injection risk in UserService.cs:45
   ```csharp
   // Before
   var query = $"SELECT * FROM users WHERE id = {userId}";

   // Suggested
   var query = "SELECT * FROM users WHERE id = @userId";
   ```

**Bug** - Potential null reference in OrderHandler.cs:112

### What's Done Well

- Good use of dependency injection in PaymentProcessor
- Comprehensive error handling in ApiController

### Verdict: REQUEST_CHANGES
```

## Severity Indicators

| Icon | Meaning |
|------|---------|
| :rotating_light: | Security issue - must fix |
| :bug: | Bug - likely to cause problems |
| :warning: | Warning - should address |
| :wrench: | Suggestion - nice to have |
| :white_check_mark: | Positive feedback |

## Files

| File | Location | Purpose |
|------|----------|---------|
| `kaizen-code-review.yml` | Oui-DELIVER | Reusable workflow |
| `kaizen-code-review-internal.yml` | Oui-DELIVER | Runs on merged PRs |
| `SKILL.md` | Oui-DELIVER/.github/skills/kaizen-review-workflow-client/ | Claude's review instructions |

## Enabling in a Repository

The code review workflow can be called from any repository:

```yaml
name: Kaizen Code Review

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/kaizen-code-review.yml@main
    with:
      pr_number: ${{ github.event.pull_request.number }}
      repository: ${{ github.repository }}
    secrets:
      anthropicKey: ${{ secrets.ANTHROPIC_API_KEY }}
      githubToken: ${{ secrets.GITHUB_TOKEN }}
```
