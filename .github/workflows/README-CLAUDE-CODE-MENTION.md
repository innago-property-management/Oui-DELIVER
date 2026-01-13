# Claude Code Mention Handler Workflow

Respond to @claude mentions in GitHub issues and pull requests with intelligent, contextual assistance powered by Claude AI.

## Overview

This reusable GitHub Actions workflow enables interactive assistance by responding when developers mention @claude in issues or PR comments. Claude can:

- 🤔 **Answer Questions**: Explain code, architecture, and implementation details
- 🐛 **Analyze Bugs**: Investigate issues and suggest fixes
- 💡 **Provide Guidance**: Recommend approaches for implementing features
- 📝 **Review Code**: Offer feedback on specific code snippets
- 🤖 **Generate Prompts**: Create structured prompts for AI-assisted implementation

## Key Innovation: AI-to-AI Handoff

Claude's responses include a **"Prompt for AI Agents"** section when code changes are needed. This structured output can be copy-pasted into another Claude Code session or AI assistant to implement the suggested changes automatically.

**Example Flow:**
```
Developer: "@claude how should I add logging to the payment service?"
    ↓
Claude: [Explains approach + generates structured prompt]
    ↓
Developer: [Copies structured prompt to local Claude Code session]
    ↓
Local Claude: [Implements the logging changes]
```

## Quick Start

### 1. Set Up Required Secrets

Add these secrets to your repository (Settings → Secrets and variables → Actions):

| Secret Name | Description | Where to Get It |
|------------|-------------|-----------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | OAuth token for Claude Code | [Setup Guide](https://docs.anthropic.com/claude/docs/claude-code-oauth) |

> **Note**: `GITHUB_TOKEN` is automatically provided by GitHub Actions

### 2. Create Workflow File

Create `.github/workflows/claude-code-mention.yml` in your repository:

```yaml
name: Claude Code Mention Handler

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  pull_request_review:
    types: [submitted]
  issues:
    types: [opened, assigned]

jobs:
  claude-mention-response:
    # Only run if @claude is mentioned
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@claude')) ||
      (github.event_name == 'issues' && (contains(github.event.issue.body, '@claude') || contains(github.event.issue.title, '@claude')))
    name: Respond to @claude Mention
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-mention.yml@main
    with:
      repository: ${{ github.repository }}
      event_type: ${{ github.event_name }}
      comment_body: ${{ github.event.comment.body || github.event.review.body || github.event.issue.body }}
      pr_number: ${{ github.event.pull_request.number || github.event.issue.pull_request.number }}
      issue_number: ${{ github.event.issue.number }}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Grant Workflow Permissions

Ensure your workflow has the necessary permissions:

1. Go to **Settings → Actions → General → Workflow permissions**
2. Select **"Read and write permissions"**
3. Check **"Allow GitHub Actions to create and approve pull requests"**

### 4. Try It Out

Mention @claude in an issue or PR comment:

```markdown
@claude what does the ProcessPayment method do?
```

Within a minute or two, Claude will respond with a helpful explanation!

## How to Use

### Asking Questions

Simple questions get straightforward answers:

```markdown
@claude where is the authentication logic?
```

```markdown
@claude what files handle user registration?
```

```markdown
@claude explain how the payment flow works
```

### Requesting Bug Analysis

Claude can investigate bugs and suggest fixes:

```markdown
@claude the auth token keeps expiring too quickly, can you help fix this?
```

Claude will:
1. Examine the relevant code
2. Identify the root cause
3. Provide a human-readable explanation
4. Generate a structured "Prompt for AI Agents" section with the fix

### Getting Implementation Guidance

Ask for help implementing features:

```markdown
@claude how should I add logging to the payment service?
```

```markdown
@claude what's the best way to implement caching for user profiles?
```

Claude will:
1. Explain the recommended approach
2. Reference repository conventions (CLAUDE.md)
3. Generate structured implementation prompts

### Code Review Requests

Get feedback on specific code:

```markdown
@claude can you review the changes in PaymentService.cs?
```

```markdown
@claude does this implementation follow our security standards?
```

## Understanding Responses

Claude's responses have two parts:

### 1. Human-Readable Response (Always Present)

Natural, conversational explanation that:
- Answers your question
- Provides context and reasoning
- Links to relevant code or documentation
- Explains trade-offs and recommendations

**Example:**
```markdown
The auth token expiration is set to 5 minutes in `appsettings.json:15-20`,
which is too short for normal user sessions. Standard practice for access
tokens is 60-120 minutes.

[Continues with explanation...]
```

### 2. Prompt for AI Agents (Conditional)

Structured, machine-consumable format included **only when** there are code changes to make:

```markdown
---

## Prompt for AI Agents

Please address the following items:

### Overall Context
- This repository uses ASP.NET Core authentication
- Configuration follows pattern in appsettings.json

### Item 1: Increase Token Expiration Time
<location>`appsettings.json:15-20`</location>

<code_context>
"JwtSettings": {
  "ExpirationMinutes": 5
}
</code_context>

<issue_to_address>
**🐛 bug:** Token expiration too short

[Detailed explanation...]

```suggestion
"JwtSettings": {
  "ExpirationMinutes": 60
}
```
</issue_to_address>
```

### Using the "Prompt for AI Agents" Section

When Claude includes this section:

1. **Copy the entire section** (from "## Prompt for AI Agents" to the end)
2. **Open a local Claude Code session** (or other AI assistant)
3. **Paste the prompt**
4. **Let the AI implement the changes**

The structured format includes:
- `<location>` - Exact file paths and line numbers
- `<code_context>` - Existing code for reference
- `<issue_to_address>` - What needs to change and why
- `suggestion` blocks - The actual code to implement

## Configuration Options

### Basic Configuration

The minimal configuration shown above works for most repositories. The workflow will automatically:
- Detect @claude mentions across issues and PRs
- Gather context from the repository
- Use repository conventions (CLAUDE.md) if present
- Post responses as comments

### Advanced Configuration

#### Add Repository-Specific Context

Customize Claude's behavior with additional context:

```yaml
jobs:
  claude-mention-response:
    if: contains(github.event.comment.body, '@claude')
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-mention.yml@main
    with:
      repository: ${{ github.repository }}
      event_type: ${{ github.event_name }}
      comment_body: ${{ github.event.comment.body }}
      pr_number: ${{ github.event.pull_request.number }}
      issue_number: ${{ github.event.issue.number }}
      additional_context: |
        ## Repository-Specific Guidelines
        - This is a financial application - prioritize security
        - All database changes require migration scripts
        - Payment-related code requires security team review
        - Use fnox for secret management (never hardcode)
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

#### Filter by User or Label

Only respond to certain users or labeled issues:

```yaml
jobs:
  claude-mention-response:
    # Only respond on issues labeled "help-wanted"
    if: |
      contains(github.event.comment.body, '@claude') &&
      contains(github.event.issue.labels.*.name, 'help-wanted')
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-mention.yml@main
    # ... rest of config
```

```yaml
jobs:
  claude-mention-response:
    # Only respond to team members
    if: |
      contains(github.event.comment.body, '@claude') &&
      (github.event.sender.login == 'alice' || github.event.sender.login == 'bob')
    uses: innago-property-management/Oui-DELIVER/.github/workflows/claude-code-mention.yml@main
    # ... rest of config
```

## Severity Indicators

When Claude identifies issues, it uses emoji indicators:

| Emoji | Severity | Meaning |
|-------|----------|---------|
| 🚨 | security | Must fix - security vulnerability |
| 🐛 | bug | Must fix - incorrect behavior |
| ⚠️ | warning | Should fix - potential issue |
| 🔧 | suggestion | Nice to have - improvement |
| ✨ | feature | Additional functionality to add |
| 📝 | docs | Documentation needed |
| 🧪 | test | Test coverage needed |

## Examples

### Example 1: Simple Question

**User:**
```markdown
@claude what does the ProcessPayment method do?
```

**Claude:**
```markdown
The `ProcessPayment` method (in `src/PaymentService.cs:45-78`) handles payment
processing for tenant rent payments. Here's what it does:

1. Validates the payment amount and account
2. Calls the payment gateway API (Stripe)
3. Records the transaction in the database
4. Sends confirmation email to the tenant
5. Returns a PaymentResult with status and transaction ID

The method uses the `IPaymentGateway` interface, so the actual gateway
implementation can be swapped (currently uses StripeGateway).
```

*(No "Prompt for AI Agents" section - this is informational)*

### Example 2: Bug Fix Request

**User:**
```markdown
@claude the auth token keeps expiring too quickly, can you help fix this?
```

**Claude:**
```markdown
I found the issue! The token expiration is set to 5 minutes in `appsettings.json`,
which is too short for normal user sessions. This should typically be 60-120
minutes for access tokens.

---

## Prompt for AI Agents

Please address the following items:

### Overall Context
- This repository uses ASP.NET Core authentication with JWT tokens
- Configuration follows the pattern in appsettings.json

### Item 1: Increase Token Expiration Time
<location>`appsettings.json:15-20`</location>

<code_context>
"JwtSettings": {
  "SecretKey": "...",
  "Issuer": "InnagoAuth",
  "Audience": "InnagoApp",
  "ExpirationMinutes": 5
}
</code_context>

<issue_to_address>
**🐛 bug:** Token expiration too short (5 minutes)

The current 5-minute expiration causes frequent logouts and poor user experience.
Standard practice for access tokens is 60-120 minutes.

```suggestion
"JwtSettings": {
  "SecretKey": "...",
  "Issuer": "InnagoAuth",
  "Audience": "InnagoApp",
  "ExpirationMinutes": 60
}
```

Consider also implementing refresh tokens if not already present for better
security with longer sessions.
</issue_to_address>
```

## Troubleshooting

### Claude Doesn't Respond

**Check that:**
1. The workflow file is present in `.github/workflows/`
2. The `if` condition properly detects @claude mentions
3. `CLAUDE_CODE_OAUTH_TOKEN` secret is set correctly
4. Workflow permissions allow commenting

**View logs:**
- Go to Actions tab → Select the workflow run → View logs

### Response is Not Helpful

**Try:**
1. Be more specific in your request
2. Reference specific files or code sections
3. Provide more context about the problem
4. Ask follow-up questions to clarify

**Example improvements:**
- ❌ "@claude fix this"
- ✅ "@claude the payment processing in PaymentService.cs fails for amounts over $1000"

### "Prompt for AI Agents" Format is Broken

**Ensure:**
1. You're using the latest version of the workflow (`@main`)
2. Copy the entire section including the `---` separator
3. The claude-mention-responder skill is up to date

**Report issues:**
If the format is consistently broken, open an issue in the Oui-DELIVER repository.

### Rate Limiting or Costs

**Manage usage:**
1. Limit mentions to specific users or labels (see configuration)
2. Set spending limits in Anthropic Console
3. Monitor API usage regularly

## Best Practices

### For Users

✅ **Do:**
- Be specific about what you need
- Reference files, functions, or line numbers
- Ask follow-up questions if needed
- Use the structured output for implementation

❌ **Don't:**
- Spam @claude mentions
- Ask vague questions without context
- Expect Claude to make direct code changes (it's advisory only)

### For Repository Maintainers

✅ **Do:**
- Create a `CLAUDE.md` file with repository conventions
- Use `additional_context` for repo-specific guidelines
- Monitor Claude's responses for quality
- Iterate on the skill configuration

❌ **Don't:**
- Allow unlimited access (consider user/label filters)
- Ignore cost monitoring
- Skip permission configuration

## Learn More

- [Claude Code Documentation](https://docs.anthropic.com/claude/docs/claude-code)
- [Anthropic API Reference](https://docs.anthropic.com/claude/reference)
- [Main Oui-DELIVER README](../../CLAUDE.md)
- [Claude Code Review Workflow](./README-CLAUDE-CODE-REVIEW.md)

## Support

- **Issues**: [Oui-DELIVER Issues](https://github.com/innago-property-management/Oui-DELIVER/issues)
- **Questions**: Mention @claude in an issue or PR (dogfooding!)
- **Platform Team**: Contact for MCP or infrastructure support
