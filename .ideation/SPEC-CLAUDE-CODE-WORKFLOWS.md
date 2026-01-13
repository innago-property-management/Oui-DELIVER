# Specification: Claude Code Mention & Review Workflows

**Created:** 2025-12-31
**Status:** Design Phase
**Author:** Claude Code (Spec-Driven Development)

## Executive Summary

This specification defines the architecture, design decisions, and implementation approach for two new Claude-powered GitHub Actions workflows:

1. **claude-code-mention.yml** - Interactive @claude mentions in issues/PRs
2. **claude-code-review.yml** - Automated PR code reviews

Both workflows implement a novel "dual output" pattern that creates an AI-to-AI handoff: a reviewing Claude identifies issues and generates structured prompts that an implementing Claude can consume to fix them automatically.

## Background & Context

### Existing Infrastructure

The Oui-DELIVER repository already contains:
- **deployment-risk-assessment.yml** - Risk assessment using Claude + MCP server
- **kaizen-code-review.yml** - Incremental code quality improvements
- **Skill system** - Markdown-based system prompts in `.github/skills/`
- **Sparse checkout pattern** - Skills loaded from Oui-DELIVER into consuming repos

### Key Innovation: AI-to-AI Handoff

The draft workflows introduce a "Prompt for AI Agents" section that:
- Provides structured, machine-consumable output alongside human-readable summaries
- Uses XML-style tags (`<location>`, `<code_context>`, `<issue_to_address>`)
- Enables another Claude Code session to consume the output and implement fixes
- Creates a feedback loop: review → fix → validate

### Research Findings

After analyzing existing workflows and the claude-code-action patterns:

1. **Skill extraction is beneficial** - Separating skills from workflows improves:
   - Reusability across multiple workflows
   - Versioning and maintenance
   - Testing and iteration
   - Documentation clarity

2. **OAuth vs API Key** - The draft workflows use `claude_code_oauth_token`:
   - This is the **modern, preferred approach** for claude-code-action@v1
   - Provides better GitHub integration (more permissions, better rate limits)
   - Deployment-risk uses `anthropic_api_key` (older pattern, still valid)
   - **Recommendation:** Use OAuth for new workflows

3. **Permissions model** - Different workflows need different permissions:
   - Mention workflow: Needs write access (comments, possibly edits)
   - Review workflow: Needs write access + ability to approve/request changes

4. **Token limits** - Large PRs can hit token limits:
   - Claude 3.5 Sonnet: ~200K tokens input
   - Need strategies: file filtering, chunking, or early termination

5. **Structured output format** - The XML-style format is appropriate:
   - Clear boundaries (location, context, issue)
   - Easy to parse by both humans and AI
   - Already proven in existing AI tool outputs (Anthropic's MCP, OpenAI's function calling)

## Design Decisions

### Decision 1: Extract Skills to Separate Files

**Decision:** Extract the inline prompts from both workflows into dedicated skill files.

**Rationale:**
- Consistency with existing deployment-risk and kaizen patterns
- Enables skill versioning independent of workflow logic
- Improves readability (workflows show orchestration, skills show intelligence)
- Allows testing skills independently via Claude Code CLI
- Makes skills reusable across multiple trigger patterns

**Implementation:**
- Create `.github/skills/claude-mention-responder/SKILL.md`
- Create `.github/skills/claude-code-reviewer/SKILL.md`
- Use sparse checkout pattern in workflows (like deployment-risk)

### Decision 2: Use OAuth Authentication

**Decision:** Use `claude_code_oauth_token` instead of `anthropic_api_key`.

**Rationale:**
- OAuth is the modern, recommended approach for claude-code-action@v1
- Provides better GitHub integration capabilities
- Simplifies permission management (token inherits repo access)
- Future-proofs workflows as Anthropic migrates to OAuth-first

**Trade-offs:**
- Requires users to set up OAuth app (more initial setup)
- Deployment-risk uses API key (inconsistency), but that's acceptable
- **Migration path:** Document both approaches, recommend OAuth for new workflows

### Decision 3: Structured Output Format - Refined XML-Style

**Decision:** Keep the XML-style format but refine it for consistency.

**Refined Format:**
```markdown
## Prompt for AI Agents

Please address the following items:

### Overall Context
[Cross-cutting concerns, architectural notes, conventions to follow]

### Item 1: {Brief Title}
<location>path/to/file.ext:LINE_START-LINE_END</location>

<code_context>
[Existing code with diff markers (+/-) or description of context]
</code_context>

<issue_to_address>
**{EMOJI} {severity}:** {Brief title}

{Detailed explanation of WHY this matters}

```suggestion
{The code to implement or change}
```

{Additional implementation notes if needed}
</issue_to_address>

### Item 2: {Brief Title}
...
```

**Rationale:**
- XML-style tags are familiar and parse-friendly
- Severity emojis provide quick visual scanning
- `suggestion` code blocks are GitHub-native (will render as suggestions in some UIs)
- Combines structured (for machines) with readable (for humans)

**Alternatives Considered:**
- JSON format: Too verbose, harder for humans to read
- YAML format: Indentation-sensitive, error-prone in markdown
- Pure markdown: Harder to parse reliably

### Decision 4: Permissions Strategy

**Permissions for claude-code-mention.yml:**
```yaml
permissions:
  contents: read          # Read repo files
  pull-requests: write    # Comment on PRs
  issues: write           # Comment on issues
  id-token: write         # OIDC for OAuth
```

**Permissions for claude-code-review.yml:**
```yaml
permissions:
  contents: read          # Read repo files
  pull-requests: write    # Comment, approve, request changes
  issues: read            # Read linked issues
  id-token: write         # OIDC for OAuth
```

**Rationale:**
- Minimal necessary permissions (principle of least privilege)
- `id-token: write` required for OAuth flow
- Review workflow needs `pull-requests: write` for `gh pr review --approve/--request-changes`
- Mention workflow might need broader permissions if user asks for edits (future enhancement)

### Decision 5: Token Management Strategy

**Problem:** Large PRs (>100 files, >50K lines changed) can exceed token limits.

**Solution - Multi-Tiered Approach:**

**Tier 1: File Filtering (Preventive)**
- Exclude test files from detailed review (summarize instead)
- Exclude generated files (package-lock.json, *.generated.cs)
- Exclude large binary diffs
- Focus on source code files

**Tier 2: Chunking (Adaptive)**
- If filtered files still exceed ~150K tokens (leaving buffer):
  - Break into chunks by directory or file type
  - Process each chunk independently
  - Aggregate results

**Tier 3: Early Termination (Fallback)**
- If single file exceeds token limit:
  - Summarize file instead of full diff
  - Post warning: "File too large for detailed review"
  - Link to GitHub's diff view

**Tier 4: Progressive Review (Future)**
- Review critical files first (controllers, services)
- Post initial results
- Continue with remaining files in follow-up comment

**Implementation in Skills:**
- Mention workflow: Simpler logic (user-directed, smaller scope)
- Review workflow: Full tiered approach with file filtering

### Decision 6: Integration with Existing Workflows

**Goal:** Harmonize with deployment-risk and kaizen workflows.

**Approach:**

1. **Consistent Skill Structure**
   - Use same markdown structure as deployment-risk and kaizen
   - Sections: Role, Context, Process, Output Format, Error Handling, Examples

2. **Consistent Naming Conventions**
   - Skills: `{purpose}-{role}/SKILL.md` pattern
   - Workflows: `{purpose}-{reusable-suffix}.yml` for reusable workflows

3. **Secret Naming Strategy**
   - OAuth token: `CLAUDE_CODE_OAUTH_TOKEN` (organization secret)
   - GitHub token: `GITHUB_TOKEN` (automatic)
   - Anthropic API key: `ANTHROPIC_API_KEY` (fallback, organization secret)

4. **Documentation Pattern**
   - Create `README-CLAUDE-CODE-MENTION.md`
   - Create `README-CLAUDE-CODE-REVIEW.md`
   - Update main `CLAUDE.md` with new workflows

### Decision 7: Review Workflow Logic - Approval State Machine

**Problem:** The review workflow needs to handle state transitions properly.

**State Machine:**
```
PR Created/Updated
  ↓
[Review] → Analyze changes
  ↓
  ├─→ [No Issues Found] → --approve (clear previous reviews if any)
  ├─→ [Non-blocking Issues] → --comment (suggestions only)
  └─→ [Blocking Issues] → --request-changes (must fix)

PR Updated (after --request-changes)
  ↓
[Re-review] → Check if issues addressed
  ↓
  ├─→ [Issues Fixed] → --approve (clear requested changes status)
  ├─→ [Issues Persist] → --comment (remind about outstanding issues)
  └─→ [New Issues] → --request-changes (new concerns)
```

**Key Behavior:**
- **CRITICAL:** If previously requested changes and issues are now fixed → MUST approve to clear status
- Use `gh pr list --search "is:open review:changes_requested"` to detect previous state
- Include "Previous Review Status" section in skill

### Decision 8: Dual Output Format - Human + AI Sections

**Format for Both Workflows:**

**Human-Readable Section** (always present):
- Conversational, natural language
- Answers the user's question or summarizes findings
- Uses markdown formatting for clarity
- Includes context and reasoning

**Prompt for AI Agents Section** (conditional):
- Only included if there are actionable changes to make
- Structured format (XML-style tags)
- Copy-paste ready for Claude Code CLI or another session
- Includes enough context for an agent with no prior knowledge

**When to Include AI Section:**
- Mention workflow: When response includes code changes, fixes, or implementations
- Review workflow: When review finds issues (blocking or non-blocking)

**When to Omit AI Section:**
- Pure discussion/questions (mention workflow)
- PR approved with no suggestions (review workflow)
- Informational responses without code changes

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub (Event Triggers)                                      │
├─────────────────────────────────────────────────────────────┤
│ • issue_comment (contains @claude)                          │
│ • pull_request (opened, synchronize)                        │
│ • pull_request_review_comment (contains @claude)            │
│ • pull_request_review (contains @claude)                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ GitHub Actions Workflows                                     │
├─────────────────────────────────────────────────────────────┤
│ • claude-code-mention.yml (Reusable)                        │
│ • claude-code-review.yml (Reusable)                         │
│                                                              │
│ Responsibilities:                                            │
│ • Load skill from .github/skills/                           │
│ • Configure claude-code-action with OAuth                   │
│ • Pass PR/issue context to Claude                           │
│ • Handle workflow-level errors                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ claude-code-action (Anthropic)                              │
├─────────────────────────────────────────────────────────────┤
│ • Authenticates with Anthropic API (OAuth)                  │
│ • Provides Claude with GitHub context                       │
│ • Manages tool execution (gh CLI, git, etc.)                │
│ • Handles conversation turns (if multi-turn enabled)        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Claude 3.5 Sonnet (Anthropic API)                           │
├─────────────────────────────────────────────────────────────┤
│ • Executes skill instructions                                │
│ • Uses gh CLI tools to read PR diffs, issue context         │
│ • Analyzes code and generates responses                     │
│ • Posts comments via gh CLI                                 │
│ • Generates structured "Prompt for AI Agents" output        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ GitHub (Outputs)                                             │
├─────────────────────────────────────────────────────────────┤
│ • PR/Issue comments (markdown)                              │
│ • PR reviews (approve/comment/request-changes)              │
│ • Structured prompts for follow-up AI sessions              │
└─────────────────────────────────────────────────────────────┘
```

### File Structure

```
Oui-DELIVER/
├── .github/
│   ├── workflows/
│   │   ├── claude-code-mention.yml           # Reusable workflow
│   │   ├── claude-code-review.yml            # Reusable workflow
│   │   ├── claude-code-mention-internal.yml  # Internal trigger
│   │   ├── claude-code-review-internal.yml   # Internal trigger
│   │   ├── README-CLAUDE-CODE-MENTION.md     # Usage docs
│   │   └── README-CLAUDE-CODE-REVIEW.md      # Usage docs
│   │
│   └── skills/
│       ├── claude-mention-responder/
│       │   └── SKILL.md                       # Mention handler skill
│       │
│       └── claude-code-reviewer/
│           └── SKILL.md                       # Review workflow skill
│
├── CLAUDE.md                                   # Updated with new workflows
└── .ideation/
    ├── claude-code-mention.yml                # Original draft (archive)
    ├── claude-code-review.yml                 # Original draft (archive)
    └── SPEC-CLAUDE-CODE-WORKFLOWS.md          # This document
```

### Data Flow

**Mention Workflow:**
```
1. User posts comment with "@claude please fix the auth bug"
2. GitHub triggers: issue_comment[created] event
3. Workflow starts:
   a. Checkout repo
   b. Sparse checkout Oui-DELIVER skills
   c. Load claude-mention-responder skill
   d. Pass event context to claude-code-action
4. Claude executes:
   a. Uses gh CLI to read issue/PR context
   b. Uses Read/Grep tools to examine code
   c. Analyzes the request
   d. Generates human-readable response
   e. If actionable → Generates "Prompt for AI Agents" section
   f. Uses gh CLI to post comment
5. Output: Comment posted to issue/PR
```

**Review Workflow:**
```
1. PR opened or updated
2. GitHub triggers: pull_request[opened, synchronize] event
3. Workflow starts:
   a. Checkout repo (with full history for diff)
   b. Sparse checkout Oui-DELIVER skills
   c. Load claude-code-reviewer skill
   d. Pass PR context to claude-code-action
4. Claude executes:
   a. Uses gh pr diff to get changes
   b. Uses gh pr list to check previous review state
   c. Applies file filtering (exclude tests, generated files)
   d. Analyzes changes against code quality standards
   e. Checks if previous review issues are resolved
   f. Generates human-readable summary
   g. Generates structured "Prompt for AI Agents" section
   h. Uses gh pr review to post review
5. Output: PR review posted (approve/comment/request-changes)
```

## Skill Definitions

### Skill 1: claude-mention-responder

**Purpose:** Respond helpfully to @claude mentions in issues and PR comments.

**Key Responsibilities:**
1. Understand the user's request in context
2. Gather necessary information (code, issues, PRs)
3. Provide clear, actionable responses
4. Generate structured output for follow-up automation

**Constraints:**
- Must determine when to provide "Prompt for AI Agents" section
- Should reference repository's CLAUDE.md for conventions
- Must handle vague requests gracefully (ask clarifying questions)
- Should not make changes directly (mention = advisory, not executive)

**Output Format:**
- Human-readable response (always)
- Prompt for AI Agents section (when applicable)
- Use severity emojis consistently

**Tools Available:**
- `gh pr view`, `gh pr diff`, `gh pr list`
- `gh issue view`, `gh issue list`
- `gh search` (code, issues, PRs)
- Read, Grep, Glob tools (via claude-code-action)
- Bash tool (limited to gh commands)

### Skill 2: claude-code-reviewer

**Purpose:** Review PR changes and provide structured feedback with dual output.

**Key Responsibilities:**
1. Analyze PR diff comprehensively
2. Identify code quality issues, bugs, security concerns
3. Recognize what was done well (positive feedback)
4. Generate structured prompts for automated fixes
5. Manage review state machine (approve/comment/request-changes)

**Constraints:**
- Must handle large PRs gracefully (file filtering, chunking)
- Must check previous review state before approving/requesting changes
- Should focus on substantive issues (not style nitpicks)
- Must include enough context in structured output for automated fixes

**Output Format:**
- Human-readable summary (always)
- Detailed findings by severity
- Structured "Prompt for AI Agents" section (when issues found)
- Use severity emojis consistently

**Review State Management:**
- Check if previous review requested changes
- If issues fixed → Approve to clear status
- If new issues → Request changes or comment based on severity
- If no issues → Approve (or comment with positive feedback)

**Tools Available:**
- `gh pr view`, `gh pr diff`, `gh pr list`
- `gh pr review` (approve, comment, request-changes)
- `gh issue view`, `gh issue list`
- `gh search` (code, issues, PRs)
- Read, Grep, Glob tools (via claude-code-action)
- Bash tool (limited to gh commands)

## Workflow Specifications

### Workflow 1: claude-code-mention.yml

**Type:** Reusable workflow (workflow_call)

**Triggers (in consuming repos):**
```yaml
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request_review:
    types: [submitted]
```

**Filter Condition:**
```yaml
if: |
  (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
  (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
  (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@claude')) ||
  (github.event_name == 'issues' && (contains(github.event.issue.body, '@claude') || contains(github.event.issue.title, '@claude')))
```

**Inputs:**
```yaml
inputs:
  repository:
    required: false
    type: string
    default: ${{ github.repository }}
    description: 'Repository in owner/name format'

  event_type:
    required: true
    type: string
    description: 'Type of event (issue_comment, pr_review_comment, etc.)'

  comment_body:
    required: true
    type: string
    description: 'Body of the comment containing @claude mention'

  pr_number:
    required: false
    type: number
    description: 'PR number if event is PR-related'

  issue_number:
    required: false
    type: number
    description: 'Issue number if event is issue-related'
```

**Secrets:**
```yaml
secrets:
  CLAUDE_CODE_OAUTH_TOKEN:
    required: true
    description: 'OAuth token for Claude Code authentication'

  GITHUB_TOKEN:
    required: true
    description: 'GitHub token for API access'
```

**Permissions:**
```yaml
permissions:
  contents: read
  pull-requests: write
  issues: write
  id-token: write
```

**Steps:**
1. Checkout repository (shallow, fetch-depth: 1)
2. Sparse checkout Oui-DELIVER skill
3. Load claude-mention-responder skill
4. Run claude-code-action with skill and context
5. (Claude handles posting response via gh CLI)

**Error Handling:**
- Skill loading failure → Post generic error comment
- Claude API failure → Post error with retry suggestion
- Timeout (10 minutes) → Post timeout comment

### Workflow 2: claude-code-review.yml

**Type:** Reusable workflow (workflow_call)

**Triggers (in consuming repos):**
```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
```

**Inputs:**
```yaml
inputs:
  repository:
    required: false
    type: string
    default: ${{ github.repository }}
    description: 'Repository in owner/name format'

  pr_number:
    required: true
    type: number
    description: 'Pull request number to review'

  base_branch:
    required: false
    type: string
    default: 'main'
    description: 'Base branch for comparison'

  review_focus:
    required: false
    type: string
    default: 'comprehensive'
    description: 'Review focus: comprehensive, security, performance, or style'

  file_pattern:
    required: false
    type: string
    default: '**/*'
    description: 'Glob pattern for files to review (e.g., "src/**/*.ts")'
```

**Secrets:**
```yaml
secrets:
  CLAUDE_CODE_OAUTH_TOKEN:
    required: true
    description: 'OAuth token for Claude Code authentication'

  GITHUB_TOKEN:
    required: true
    description: 'GitHub token for API access'
```

**Permissions:**
```yaml
permissions:
  contents: read
  pull-requests: write
  issues: read
  id-token: write
```

**Steps:**
1. Checkout repository (full history, fetch-depth: 0)
2. Sparse checkout Oui-DELIVER skill
3. Load claude-code-reviewer skill
4. Append review_focus to skill if specified
5. Run claude-code-action with skill and PR context
6. (Claude handles posting review via gh pr review)

**Error Handling:**
- Skill loading failure → Post comment with error
- Claude API failure → Post comment suggesting manual review
- Token limit exceeded → Post partial results + warning
- Timeout (15 minutes) → Post timeout comment

## Documentation Approach

### Document 1: README-CLAUDE-CODE-MENTION.md

**Sections:**
1. **Overview** - What the workflow does, when to use it
2. **Quick Start** - Minimal setup steps
3. **How to Use** - Examples of @claude mentions
4. **Configuration** - Workflow inputs, secrets required
5. **Understanding Responses** - Human vs AI sections
6. **AI-to-AI Handoff** - How to use "Prompt for AI Agents" output
7. **Troubleshooting** - Common issues and solutions
8. **Advanced Usage** - Custom skills, filtering, etc.
9. **Examples** - Real-world scenarios

**Target Audience:**
- Developers using the workflow in their repos
- Users mentioning @claude in issues/PRs
- Engineers setting up the workflow for the first time

### Document 2: README-CLAUDE-CODE-REVIEW.md

**Sections:**
1. **Overview** - Automated PR review capabilities
2. **Quick Start** - Minimal setup steps
3. **How It Works** - Review process, approval logic
4. **Configuration** - Workflow inputs, review focus options
5. **Understanding Reviews** - Human summary vs structured output
6. **Implementing Fixes** - Using "Prompt for AI Agents" output
7. **Review State Machine** - Approval/request-changes logic
8. **Token Management** - How large PRs are handled
9. **Customization** - Review focus, file patterns, exclusions
10. **Troubleshooting** - Common issues and solutions
11. **Examples** - Sample reviews for different PR types

**Target Audience:**
- Developers whose PRs will be reviewed
- Repository maintainers setting up automated reviews
- Engineers customizing review behavior

### Document 3: CLAUDE.md Updates

**New Section: "Claude Code Workflows"**
```markdown
## Claude Code Workflows

### 3. @claude Mention Handler

**Purpose**: Respond to @claude mentions in issues and PRs

**What Claude Does**:
- Answers questions about code and architecture
- Provides implementation guidance
- Analyzes bugs and suggests fixes
- Generates structured prompts for automated fixes

**Trigger**: @claude mention in issue/PR comment

**Learn More**: [.github/workflows/README-CLAUDE-CODE-MENTION.md]

### 4. Automated Code Review

**Purpose**: Automatically review PRs for code quality, security, and best practices

**What Claude Does**:
- Reviews all changed files in PR
- Identifies bugs, security issues, and quality concerns
- Recognizes well-implemented patterns
- Generates structured prompts for automated fixes
- Manages review state (approve/request-changes)

**Trigger**: PR opened, updated, or reopened

**Learn More**: [.github/workflows/README-CLAUDE-CODE-REVIEW.md]
```

## Implementation Tasks

### Phase 1: Skill Extraction (Foundational)
1. Create `.github/skills/claude-mention-responder/SKILL.md`
   - Extract from draft workflow
   - Add structured output format specification
   - Add examples of good responses
   - Add error handling guidelines
2. Create `.github/skills/claude-code-reviewer/SKILL.md`
   - Extract from draft workflow
   - Add review state machine logic
   - Add file filtering strategy
   - Add token management guidelines
   - Add examples of reviews

### Phase 2: Workflow Implementation (Core)
3. Implement `claude-code-mention.yml` reusable workflow
   - Define workflow_call inputs/secrets
   - Add sparse checkout step
   - Configure claude-code-action with OAuth
   - Add error handling
4. Implement `claude-code-review.yml` reusable workflow
   - Define workflow_call inputs/secrets
   - Add full-depth checkout (for git diff)
   - Configure claude-code-action with OAuth
   - Add error handling
5. Create internal trigger workflows
   - `claude-code-mention-internal.yml` (for Oui-DELIVER repo)
   - `claude-code-review-internal.yml` (for Oui-DELIVER repo)

### Phase 3: Documentation (Essential)
6. Write `README-CLAUDE-CODE-MENTION.md`
   - Quick start guide
   - Usage examples
   - AI-to-AI handoff explanation
   - Troubleshooting
7. Write `README-CLAUDE-CODE-REVIEW.md`
   - Quick start guide
   - Review state machine explanation
   - Implementing fixes from structured output
   - Troubleshooting
8. Update `CLAUDE.md`
   - Add new workflows to "Our Claude-Powered Workflows" section
   - Update architecture diagrams if needed

### Phase 4: Testing & Validation (Critical)
9. Test mention workflow
   - Create test issue with @claude mention
   - Verify response quality
   - Verify structured output format
   - Test error cases (API failure, timeout)
10. Test review workflow
    - Create test PR with known issues
    - Verify review quality
    - Verify structured output format
    - Verify approval/request-changes logic
    - Test large PR handling
11. Test AI-to-AI handoff
    - Use structured output from review in a new Claude Code session
    - Verify fixes are implemented correctly
    - Document the handoff process

### Phase 5: Rollout (Gradual)
12. Deploy to Oui-DELIVER (internal testing)
13. Document in main README.md
14. Announce to team (internal)
15. Monitor first week of usage
16. Iterate based on feedback
17. Open for external use (public repos)

## Success Metrics

### Quantitative Metrics
- **Mention Response Rate**: % of @claude mentions that receive valid responses (target: >95%)
- **Review Coverage**: % of PRs reviewed within 5 minutes (target: >90%)
- **Structured Output Quality**: % of reviews with parseable structured output (target: >95%)
- **False Positive Rate**: % of reviews with incorrect/irrelevant suggestions (target: <10%)
- **Token Limit Hits**: % of PRs that hit token limits (target: <5%)

### Qualitative Metrics
- **Response Relevance**: Are @claude responses helpful and on-topic?
- **Review Value**: Do reviews identify real issues vs noise?
- **AI-to-AI Handoff Success**: Can implementing Claude successfully use the structured output?
- **Developer Satisfaction**: Do developers find the workflows useful?

### Monitoring Approach
- GitHub Actions logs for failure rates
- Manual review of first 50 mentions/reviews
- Team feedback (Slack, retros)
- Cost tracking (Anthropic API usage)

## Open Questions & Future Enhancements

### Open Questions (Require Decisions Before Implementation)
1. **Q: Should review workflow auto-approve low-risk PRs?**
   - Consideration: Fast-track trivial PRs (README updates, typo fixes)
   - Risk: Over-automation could reduce human oversight
   - **Recommendation:** Start with --comment only, add auto-approve in Phase 2 with opt-in flag

2. **Q: How to handle concurrent reviews (multiple PRs updating simultaneously)?**
   - Consideration: GitHub Actions concurrency limits
   - **Recommendation:** Use concurrency groups by PR number

3. **Q: Should mention workflow allow direct edits (not just suggestions)?**
   - Consideration: "@claude fix this" could commit directly
   - Risk: Security implications, need careful permission management
   - **Recommendation:** Start with advisory-only, add edit capability in Phase 2

### Future Enhancements
1. **Multi-turn conversations**
   - Allow follow-up @claude mentions to continue context
   - Requires conversation state management

2. **Custom review profiles**
   - Per-repo or per-team review policies
   - Example: "security-focused" vs "performance-focused"

3. **Integration with CI/CD**
   - Block merges if critical issues found
   - Require issue resolution before merge

4. **Learning from feedback**
   - Track when developers accept vs reject suggestions
   - Improve review quality over time

5. **Batch review for large PRs**
   - Progressive review: critical files first, then rest
   - Post multiple comments instead of single large comment

6. **Integration with issue tracking**
   - Auto-create issues for non-blocking suggestions
   - Link PR reviews to related issues

## Risk Analysis & Mitigation

### Risk 1: High API Costs
**Impact:** Moderate | **Likelihood:** Moderate

**Mitigation:**
- Set per-repo or org-wide rate limits
- Implement file filtering to reduce token usage
- Monitor costs via Anthropic Console
- Add budget alerts

### Risk 2: Poor Review Quality (False Positives/Negatives)
**Impact:** High | **Likelihood:** Moderate

**Mitigation:**
- Start with --comment mode (non-blocking)
- Iterate on skills based on feedback
- Manual review of first 50 reviews
- Add "Report Issue" link in review comments

### Risk 3: Token Limit Exceeded on Large PRs
**Impact:** Moderate | **Likelihood:** Low

**Mitigation:**
- Implement tiered token management strategy
- File filtering (exclude tests, generated files)
- Chunking for very large PRs
- Early termination with partial results

### Risk 4: OAuth Setup Complexity
**Impact:** Moderate | **Likelihood:** Low

**Mitigation:**
- Document OAuth setup thoroughly
- Provide fallback to API key authentication
- Create video walkthrough
- Offer setup assistance

### Risk 5: Security - Leaking Sensitive Information
**Impact:** High | **Likelihood:** Low

**Mitigation:**
- Review workflow permissions carefully
- Limit tool access to gh CLI commands only
- No write access to files via Claude
- Test with sensitive repos before public rollout

### Risk 6: Developer Confusion (AI-to-AI Handoff)
**Impact:** Moderate | **Likelihood:** Moderate

**Mitigation:**
- Clear documentation with examples
- Video demo of handoff process
- Add "How to use this output" section to reviews
- Provide example commands

## Conclusion

This specification provides a comprehensive design for two Claude-powered workflows that introduce a novel AI-to-AI handoff pattern. By extracting skills, using OAuth authentication, and implementing structured output formats, these workflows will:

1. Enable interactive @claude mentions for ad-hoc assistance
2. Automate PR code reviews with actionable feedback
3. Create a feedback loop where reviewing Claude generates prompts for implementing Claude
4. Maintain consistency with existing Oui-DELIVER workflows

The implementation is broken into 5 phases with clear tasks, success metrics, and risk mitigation strategies. The next step is to begin Phase 1 (Skill Extraction) followed by incremental implementation and testing.

---

**Next Steps:**
1. Review this specification with team
2. Approve design decisions
3. Begin implementation (Phase 1: Skill Extraction)
4. Iterate based on testing and feedback
