# Claude Code Review Workflow

Automatically review pull requests for code quality, security, and best practices using Claude AI with intelligent feedback and structured prompts for fixes.

## Overview

This reusable GitHub Actions workflow performs comprehensive code reviews on pull requests, identifying:

- 🚨 **Security Vulnerabilities**: SQL injection, XSS, auth bypasses, hardcoded secrets
- 🐛 **Bugs**: Logic errors, null references, incorrect conditions
- ⚠️ **Warnings**: Potential issues, missing validations, performance concerns
- 🔧 **Suggestions**: Best practices, code quality improvements
- ✅ **Positive Patterns**: Well-implemented code worth praising

## Key Innovation: AI-to-AI Handoff

Claude's reviews include a **"Prompt for AI Agents"** section with structured, copy-paste-ready prompts that another AI can use to implement the suggested fixes automatically.

**Example Flow:**
```
PR Opened
    ↓
Claude Reviews → Finds 3 issues
    ↓
Generates Structured Prompt
    ↓
Developer Copies Prompt → Pastes into local Claude Code
    ↓
Local Claude Implements Fixes
    ↓
PR Updated → Claude Re-reviews → Approves
```

## Quick Start

### 1. Set Up Required Secrets

Add these secrets to your repository (Settings → Secrets and variables → Actions):

| Secret Name | Description | Where to Get It |
|------------|-------------|-----------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | OAuth token for Claude Code | [Setup Guide](https://docs.anthropic.com/claude/docs/claude-code-oauth) |

> **Note**: `GITHUB_TOKEN` is automatically provided by GitHub Actions

### 2. Create Workflow File

Create `.github/workflows/claude-code-review.yml` in your repository:

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]

jobs:
  claude-review:
    name: AI Code Review
    # Skip draft PRs
    if: github.event.pull_request.draft == false
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    with:
      repository: ${{ github.repository }}
      pr_number: ${{ github.event.pull_request.number }}
      base_branch: ${{ github.event.pull_request.base.ref }}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Grant Workflow Permissions

Ensure your workflow has the necessary permissions:

1. Go to **Settings → Actions → General → Workflow permissions**
2. Select **"Read and write permissions"**
3. Check **"Allow GitHub Actions to create and approve pull requests"**

### 4. Test It Out

Open a pull request and watch Claude review it! Within a few minutes, you'll see a comprehensive review comment with findings.

## How It Works

### Review Process

1. **PR Trigger**: Workflow starts when PR is opened, updated, or reopened
2. **Context Gathering**: Claude fetches PR details, diff, and previous review state
3. **File Filtering**: Excludes test files, generated files, and focuses on critical code
4. **Code Analysis**: Examines changes for bugs, security issues, quality concerns
5. **Review Generation**: Creates human-readable summary + structured prompts
6. **Review Submission**: Posts review with approve/comment/request-changes

### Review State Machine

Claude manages review state intelligently:

```
PR Created/Updated
    ↓
[Review] → Analyze changes
    ↓
    ├─→ [No Issues] → --approve
    ├─→ [Minor Issues] → --comment (suggestions)
    └─→ [Major Issues] → --request-changes

PR Updated (after --request-changes)
    ↓
[Re-review] → Check if issues addressed
    ↓
    ├─→ [Issues Fixed] → --approve (clears "changes requested")
    ├─→ [Issues Persist] → --comment (reminder)
    └─→ [New Issues] → --request-changes
```

**Critical Behavior**: If Claude previously requested changes and those issues are fixed, it **MUST** approve to clear the "changes requested" status.

### File Filtering Strategy

To manage token usage efficiently, Claude uses a tiered approach:

#### Always Excluded (Summarized Only):
- Test files: `*.test.ts`, `*.spec.cs`, `**/Tests/**`
- Generated files: `*.g.cs`, `*.generated.cs`, `**/obj/**`, `**/bin/**`
- Lock files: `package-lock.json`, `yarn.lock`, `*.lock`
- Large data files: JSON/XML files >1000 lines

#### Prioritized (Reviewed First):
- Controllers, services, API endpoints
- Authentication/authorization code
- Database migrations
- Configuration files (appsettings.json, *.config)
- Public API surfaces (interfaces, DTOs)

#### Tiered Review:

| PR Size | Strategy |
|---------|----------|
| <50 files | Review all non-excluded files |
| 50-100 files | Detailed review of critical files, summarize others |
| >100 files | Review top 20 critical files, high-level summary of rest |

## Understanding Reviews

Claude's reviews have two main sections:

### 1. Human-Readable Summary (Always Present)

```markdown
## 📋 Code Review Summary

**PR:** #456 - Add user profile caching
**Author:** @alice
**Files Changed:** 3 (+127/-45)

### Overall Assessment
[What this PR does and overall quality]

### ✅ What's Good
- [Positive feedback on well-implemented patterns]
- [Security improvements, best practices]

### 🔍 Findings

#### 🚨 Security Issues (1)
- **JWT secret in code** - Critical security vulnerability

#### 🐛 Bugs (0)
[No bugs found]

#### ⚠️ Warnings (2)
- **Missing null check** - Could cause NullReferenceException
- **No expiration validation** - Tokens could be used indefinitely

#### 🔧 Suggestions (1)
- **Extract constants** - Magic numbers should be named constants

### 📊 Review Statistics
- **Critical Issues:** 1 (blocking)
- **Non-Critical Issues:** 3 (suggestions)
- **Files Reviewed:** 3
- **Files Skipped:** 2 (test files)

### 🎯 Recommendation
🚫 **Request Changes** - Critical issues must be addressed before merge
```

### 2. Prompt for AI Agents (Conditional)

Included **only when** issues are found:

```markdown
---

## Prompt for AI Agents

Please address the following code review comments:

### Overall Context
- Repository conventions from CLAUDE.md (if present)
- Related patterns or dependencies
- Testing requirements

### Item 1: Remove Hardcoded JWT Secret
<location>`src/Services/AuthService.cs:45`</location>

<code_context>
 public class AuthService
 {
+    private const string SECRET = "my-super-secret-key-12345";
+
     public string GenerateToken(User user)
     {
         var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SECRET));
     }
 }
</code_context>

<issue_to_address>
**🚨 security:** JWT secret hardcoded in source

The JWT secret is hardcoded in source code, which is a critical security
vulnerability. Secrets must never be committed to source control.

Impact: Anyone with repo access can forge authentication tokens.

```suggestion
public class AuthService
{
    private readonly string _jwtSecret;

    public AuthService(IConfiguration configuration)
    {
        _jwtSecret = configuration["JwtSettings:SecretKey"]
            ?? throw new InvalidOperationException("JWT secret not configured");
    }

    public string GenerateToken(User user)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_jwtSecret));
        // ...
    }
}
```

- Move secret to appsettings.json
- Never commit actual secrets - use fnox or env vars
- Update appsettings.Development.json
</issue_to_address>
```

## Using the Structured Prompts

When Claude finds issues:

1. **Review the findings** in the human-readable summary
2. **Copy the "Prompt for AI Agents" section** entirely
3. **Open a local Claude Code session** (or paste into your preferred AI assistant)
4. **Paste the prompt**
5. **Let the AI implement the fixes**
6. **Push the changes**
7. **Claude will re-review and approve if issues are resolved**

The structured format provides everything needed:
- Exact file paths and line numbers
- Current code context
- Detailed explanation of the issue
- Suggested fix with complete code
- Implementation notes

## Configuration Options

### Basic Configuration

The minimal setup shown above works for most repositories and provides:
- Comprehensive code review on all PRs
- Automatic file filtering
- Repository convention awareness (CLAUDE.md)
- Intelligent review state management

### Advanced Configuration

#### Review Focus

Target specific aspects of code quality:

```yaml
jobs:
  security-review:
    name: Security-Focused Review
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    with:
      repository: ${{ github.repository }}
      pr_number: ${{ github.event.pull_request.number }}
      review_focus: 'security'  # Options: comprehensive, security, performance, style
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

#### File Pattern Filter

Review only specific files:

```yaml
jobs:
  typescript-review:
    name: TypeScript Code Review
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    with:
      repository: ${{ github.repository }}
      pr_number: ${{ github.event.pull_request.number }}
      file_pattern: 'src/**/*.{ts,tsx}'  # Only review TypeScript files
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

#### Repository-Specific Context

Add custom guidelines:

```yaml
jobs:
  claude-review:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    with:
      repository: ${{ github.repository }}
      pr_number: ${{ github.event.pull_request.number }}
      additional_context: |
        ## Security Requirements
        - This is a payment processing service
        - All card data must use PCI-compliant handling
        - No payment info in logs
        - Require 2FA for admin operations

        ## Database Changes
        - All migrations must be reversible
        - Include rollback scripts
        - Test on staging first
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

#### Conditional Reviews

Review only specific conditions:

```yaml
jobs:
  claude-review:
    # Only review external contributor PRs
    if: github.event.pull_request.author_association == 'FIRST_TIME_CONTRIBUTOR'
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    # ... rest of config
```

```yaml
jobs:
  claude-review:
    # Skip for dependabot PRs
    if: github.event.pull_request.user.login != 'dependabot[bot]'
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    # ... rest of config
```

## Severity Guide

Claude uses emoji indicators for issue severity:

| Emoji | Severity | Meaning | Blocking? |
|-------|----------|---------|-----------|
| 🚨 | security | Security vulnerability | ✅ Yes |
| 🐛 | bug | Incorrect behavior | ✅ Yes |
| ⚠️ | warning | Potential issue | ⚠️ Should fix |
| 🔧 | suggestion | Nice to have | ❌ No |
| ✨ | feature | Additional functionality | ❌ No |
| 📝 | docs | Documentation needed | ❌ No |
| 🧪 | test | Test coverage needed | ❌ No |
| ✅ | positive | Good pattern (praise) | N/A |

**Review Actions by Severity:**
- 🚨 Security or 🐛 Bug found → **Request Changes**
- Only ⚠️ Warnings → **Comment** or **Request Changes** (judgment call)
- Only 🔧 Suggestions → **Comment**
- No issues → **Approve**

## Example Reviews

### Example 1: Approve (No Issues)

```markdown
## 📋 Code Review Summary

**PR:** #456 - Add Redis caching
**Author:** @alice
**Files Changed:** 3 (+127/-45)

### Overall Assessment
This PR adds Redis caching to user profile lookups, significantly improving
API response times. Implementation follows repository patterns and includes
proper error handling.

### ✅ What's Good
- Excellent cache key strategy (user ID + timestamp)
- Proper fallback to database on cache miss
- Cache invalidation on profile updates
- Good test coverage (95% on new code)
- Clear logging of cache hits/misses

### 🔍 Findings
No issues found. This is clean, well-implemented code.

### 📊 Review Statistics
- **Critical Issues:** 0
- **Non-Critical Issues:** 0
- **Files Reviewed:** 3

### 🎯 Recommendation
✅ **Approved** - Ready to merge

Great work on this feature! The caching implementation is solid.

---

🤖 Automated review by Claude Code Reviewer
```

### Example 2: Request Changes (Critical Issues)

```markdown
## 📋 Code Review Summary

**PR:** #457 - Fix authentication bug
**Author:** @bob
**Files Changed:** 5 (+89/-23)

### Overall Assessment
This PR addresses token expiration but introduces a security vulnerability
and has a logic bug that would break refresh token flow.

### ✅ What's Good
- Good test coverage for happy path
- Clear commit messages

### 🔍 Findings

#### 🚨 Security Issues (1)
- **JWT secret in code** (AuthService.cs:45) - Hardcoded secret key

#### 🐛 Bugs (1)
- **Null reference exception** (TokenService.cs:78) - Missing null check

#### ⚠️ Warnings (1)
- **Missing expiration check** (TokenService.cs:92) - Refresh token not validated

### 📊 Review Statistics
- **Critical Issues:** 2 (blocking)
- **Non-Critical Issues:** 1
- **Files Reviewed:** 5

### 🎯 Recommendation
🚫 **Request Changes** - Critical issues must be addressed

---

## Prompt for AI Agents

[Structured prompts for each issue...]

---

🤖 Automated review by Claude Code Reviewer
```

### Example 3: Approve (Issues Fixed)

```markdown
## 📋 Code Review Summary

**PR:** #457 - Fix authentication bug (Updated)
**Author:** @bob
**Files Changed:** 5 (+95/-23)

### Overall Assessment
All issues from previous review have been addressed. Security vulnerability
is fixed, null checks in place, and token expiration properly validated.

### ✅ What's Good
- JWT secret now uses configuration
- Comprehensive null checking added
- Token expiration validation implemented
- Integration tests for error cases
- Good use of UTC timestamps

### 🔍 Findings
No new issues. Previous concerns resolved.

### 📊 Review Statistics
- **Critical Issues:** 0 (previously 2, now fixed ✅)

### 🎯 Recommendation
✅ **Approved** - All previous issues resolved

✅ **Previous Issues Resolved:** The security vulnerability, null reference
bug, and missing expiration check from the last review have all been
properly addressed.

Excellent work addressing the feedback!

---

🤖 Automated review by Claude Code Reviewer
```

## Troubleshooting

### Review Doesn't Run

**Check:**
1. Workflow file exists in `.github/workflows/`
2. Workflow triggers on correct events (opened, synchronize)
3. `CLAUDE_CODE_OAUTH_TOKEN` secret is set
4. Workflow permissions allow PR writes

**View logs:**
- Actions tab → Select workflow run → View detailed logs

### Review Never Completes

**Possible causes:**
- Very large PR (>100 files) - Consider splitting
- Token limit exceeded - Check logs for errors
- API timeout - Retry or reduce PR size

**Solutions:**
- Use `file_pattern` to focus review
- Split large PRs into smaller ones
- Check Anthropic API status

### Claude Always Approves/Never Approves

**Check:**
1. Review the skill configuration
2. Verify repository conventions (CLAUDE.md)
3. Check if `additional_context` is too restrictive
4. Review logs for error messages

**Adjust:**
- Update `review_focus` parameter
- Modify skill in Oui-DELIVER repository
- Add specific guidelines in `additional_context`

### "Changes Requested" Not Clearing

**Ensure:**
- Claude has permission to approve PRs
- Workflow runs on PR updates (synchronize event)
- Claude checks previous review state

**Verify in logs:**
- "Check previous review state" step shows correct detection
- Review action uses `--approve` when issues fixed

### Structured Output Format Issues

**Validate:**
1. Using latest version of workflow (`@main`)
2. claude-code-reviewer skill is current
3. Entire "Prompt for AI Agents" section is copied

**Report:**
- Open issue in Oui-DELIVER if format consistently broken

### High API Costs

**Reduce usage:**
1. Use `file_pattern` to limit scope
2. Add `if` conditions for specific PRs
3. Skip draft PRs (shown in examples)
4. Skip dependabot PRs
5. Set Anthropic API usage alerts

**Monitor:**
- Check Anthropic Console regularly
- Track costs by repository

## Best Practices

### For Developers

✅ **Do:**
- Review Claude's findings carefully
- Use structured prompts to implement fixes
- Push fixes and let Claude re-review
- Provide context in PR descriptions
- Split large PRs for better reviews

❌ **Don't:**
- Ignore security/bug findings
- Merge without addressing critical issues
- Create massive PRs (>100 files)
- Dismiss all suggestions without consideration

### For Repository Maintainers

✅ **Do:**
- Create `CLAUDE.md` with repository conventions
- Use `additional_context` for specific guidelines
- Monitor review quality and iterate
- Set up cost alerts
- Use conditional reviews for appropriate PRs

❌ **Don't:**
- Auto-merge based solely on Claude approval
- Skip human review entirely
- Ignore API cost accumulation
- Use for every tiny PR (add conditions)

## Repository Conventions

Claude checks for a `CLAUDE.md` file in your repository root. If present, it will:

1. Apply defined coding standards
2. Flag violations as issues
3. Reference conventions in review comments
4. Include conventions in structured output

**Example CLAUDE.md:**
```markdown
## Coding Standards

- All if statements must use braces
- Use LoggerMessage source generator for logging
- One class per file
- No secrets in code (use fnox)
- All database operations must have timeouts
```

Claude will then flag violations like:
```markdown
**⚠️ warning:** Missing braces on if statement

Per CLAUDE.md conventions, all if statements must use braces even
for single-line bodies.
```

## Integration with Other Workflows

### Combine with Deployment Risk Assessment

```yaml
jobs:
  code-review:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-review.yml@main
    # ... config

  deployment-risk:
    needs: code-review
    if: success()
    uses: innago-property-management/Oui-DELIVER/.github/workflows/deployment-risk-assessment.yml@main
    # ... config
```

### Require Review Before Merge

In branch protection rules:
1. Require status check: "AI Code Review"
2. Require review approval before merge

This ensures Claude has reviewed every PR before merging.

## Learn More

- [Claude Code Mention Handler](./README-CLAUDE-CODE-MENTION.md)
- [Claude Code Documentation](https://docs.anthropic.com/claude/docs/claude-code)
- [Anthropic API Reference](https://docs.anthropic.com/claude/reference)
- [Main Oui-DELIVER README](../../CLAUDE.md)

## Support

- **Issues**: [Oui-DELIVER Issues](https://github.com/innago-property-management/Oui-DELIVER/issues)
- **Questions**: Mention @claude in an issue (see [mention handler](./README-CLAUDE-CODE-MENTION.md))
- **Platform Team**: Contact for infrastructure or OAuth support
