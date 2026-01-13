# Claude AI Integration Guide

This repository contains reusable GitHub Actions workflows that leverage Claude AI through the [Anthropic Claude Code Action](https://github.com/anthropics/claude-code-action).

## What is Claude Code Action?

The Claude Code Action is an official GitHub Action from Anthropic that enables Claude AI to:
- 📖 **Read** repository files and understand code context
- ✍️ **Write** code changes directly to branches
- 💬 **Comment** on pull requests with detailed analysis
- 🔧 **Execute** tools and workflows through MCP (Model Context Protocol)
- 🤖 **Respond** to @mentions in issues and pull requests

## Our Claude-Powered Workflows

### 1. Deployment Risk Assessment

**Purpose**: Automatically assess deployment risk for pull requests

**What Claude Does**:
- Analyzes git diffs and identifies critical changes
- Queries deployment history via MCP tools
- Evaluates production health metrics
- Calculates risk scores based on multiple factors
- Posts comprehensive risk assessment as PR comments

**Key Features**:
- Uses MCP to connect to remote risk assessment server
- Custom skill defines risk scoring methodology
- Provides actionable deployment recommendations
- Considers code changes, deployment history, and production health

**Learn More**: [.github/workflows/README-DEPLOYMENT-RISK.md](.github/workflows/README-DEPLOYMENT-RISK.md)

### 2. @claude Mention Handler

**Purpose**: Respond to @claude mentions in GitHub issues and pull requests

**What Claude Does**:
- Answers questions about code, architecture, and implementation
- Analyzes bugs and suggests fixes
- Provides implementation guidance for features
- Reviews specific code snippets
- Generates structured "Prompt for AI Agents" for automated implementation

**Key Features**:
- Interactive assistance via @claude mentions
- Context-aware responses using repository code and conventions
- Dual output: human-readable + machine-consumable structured prompts
- AI-to-AI handoff pattern for automated fixes
- Advisory mode (suggests but doesn't change code directly)

**Learn More**: [.github/workflows/README-CLAUDE-CODE-MENTION.md](.github/workflows/README-CLAUDE-CODE-MENTION.md)

### 3. Automated Code Review

**Purpose**: Automatically review pull requests for code quality, security, and best practices

**What Claude Does**:
- Reviews all changed files in PRs
- Identifies bugs, security vulnerabilities, and quality issues
- Recognizes well-implemented patterns (positive feedback)
- Generates structured "Prompt for AI Agents" for automated fixes
- Manages review state (approve/comment/request-changes)
- Clears "changes requested" status when issues are resolved

**Key Features**:
- Comprehensive analysis: security, bugs, performance, quality
- Intelligent file filtering for large PRs
- Review state machine (tracks previous reviews)
- Dual output: human-readable summary + structured prompts
- AI-to-AI handoff pattern for implementing fixes
- Severity indicators (🚨 security, 🐛 bug, ⚠️ warning, 🔧 suggestion)

**Learn More**: [.github/workflows/README-CLAUDE-CODE-REVIEW.md](.github/workflows/README-CLAUDE-CODE-REVIEW.md)

### 4. Auto PR (Future Enhancement)

**Purpose**: Automatically create pull requests for routine updates

**Potential Use Cases**:
- Dependency updates with changelog analysis
- Documentation generation from code changes
- Automated refactoring suggestions
- Configuration synchronization across services

## How We Use Claude

### Skills System

We define **skills** (system prompts) that give Claude specific expertise for each workflow. Skills are markdown files that define:

- **Role**: What persona Claude should adopt
- **Context**: Domain knowledge and constraints
- **Process**: Step-by-step instructions
- **Output Format**: Structure of responses
- **Tools**: MCP tools available for use

Example skill location: `.github/skills/deployment-risk-workflow-client/SKILL.md`

### MCP (Model Context Protocol) Integration

Claude connects to **remote MCP servers** that provide:

- Custom tools for domain-specific operations
- Access to internal APIs and data sources
- Stateful operations (start assessment → poll → get result)
- Secure credential management in Kubernetes

**Benefits of MCP**:
- No credentials exposed in GitHub Actions
- Reusable tools across multiple workflows
- Separation of orchestration (Claude) from execution (MCP server)
- Easy to extend with new capabilities

### Workflow Pattern

Our Claude-powered workflows follow this pattern:

```yaml
- name: Load skill
  id: skill
  run: |
    SKILL_CONTENT=$(cat .github/skills/my-skill/SKILL.md)
    echo "skill_content<<EOF" >> $GITHUB_OUTPUT
    echo "$SKILL_CONTENT" >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT

- name: Run Claude
  uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    claude_args: |
      --system-prompt "${{ steps.skill.outputs.skill_content }}"
      --mcp-config '{"mcpServers":{...}}'
    prompt: |
      [Task-specific instructions with GitHub context]
```

## Creating New Claude Workflows

### Step 1: Define Your Skill

Create a skill file at `.github/skills/your-skill-name/SKILL.md`:

```markdown
# Role: [Your Role Name]

You are a [describe expertise and purpose].

## Context
[Domain knowledge, constraints, limitations]

## Available Tools
- `tool_name`: [description]

## Process
1. [Step-by-step instructions]
2. [Each step should be clear and actionable]
3. [Include error handling steps]

## Output Format
[Define expected output structure]

## Examples
[Show examples of good outputs]

## Error Handling
[How to handle common failures]
```

### Step 2: Create the Workflow

Create a workflow file at `.github/workflows/your-workflow.yml`:

```yaml
name: Your Workflow Name

on:
  workflow_call:
    inputs:
      # Define inputs
    secrets:
      ANTHROPIC_KEY:
        required: true
      # Other required secrets

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  your-job:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Load skill
        id: skill
        run: |
          SKILL_CONTENT=$(cat .github/skills/your-skill-name/SKILL.md)
          echo "skill_content<<EOF" >> $GITHUB_OUTPUT
          echo "$SKILL_CONTENT" >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT

      - name: Run Claude
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          claude_args: |
            --system-prompt "${{ steps.skill.outputs.skill_content }}"
          prompt: |
            [Your task description with context]
```

### Step 3: Test and Iterate

1. Create a test PR or issue
2. Trigger the workflow
3. Review Claude's output
4. Refine the skill based on results
5. Iterate until behavior is consistent

### Step 4: Document

Add documentation:
- Update `README.md` with the new workflow
- Create a `README-YOUR-WORKFLOW.md` in `.github/workflows/`
- Add examples of usage
- Document required secrets and permissions

## Best Practices

### Skill Design

✅ **DO**:
- Be specific about the task and expected output
- Provide clear step-by-step instructions
- Include examples of good and bad outputs
- Define error handling procedures
- Use markdown formatting for readability

❌ **DON'T**:
- Make skills too general or vague
- Omit important context or constraints
- Assume Claude knows your internal systems
- Skip error handling instructions
- Use overly complex language

### Prompt Engineering

✅ **DO**:
- Include relevant GitHub context (`${{ github.repository }}`, etc.)
- Break complex tasks into clear steps
- Specify output format explicitly
- Test prompts iteratively
- Use the `prompt` field for task-specific instructions

❌ **DON'T**:
- Put all logic in the prompt (use skills for reusable logic)
- Assume Claude has access to information not provided
- Use ambiguous language
- Skip validation steps

### MCP Integration

✅ **DO**:
- Use MCP for operations requiring credentials or internal access
- Implement polling for long-running operations
- Return structured data from MCP tools
- Version your MCP server APIs
- Document MCP tool interfaces clearly

❌ **DON'T**:
- Expose credentials in GitHub Actions
- Make synchronous calls for long operations
- Return unstructured text from MCP tools
- Change tool interfaces without versioning
- Assume network reliability

### Security

✅ **DO**:
- Store all credentials as GitHub secrets
- Use organization secrets for shared credentials
- Limit workflow permissions to minimum required
- Validate inputs before processing
- Sanitize logs of sensitive data

❌ **DON'T**:
- Put credentials in workflow files
- Grant excessive permissions
- Log sensitive data
- Trust user input without validation
- Expose internal URLs publicly

### Testing

✅ **DO**:
- Test workflows on draft PRs first
- Use test repositories for development
- Validate all error paths
- Monitor API usage and rate limits
- Review Claude's outputs manually at first

❌ **DON'T**:
- Test directly on production workflows
- Assume Claude will always succeed
- Ignore rate limit warnings
- Auto-merge Claude's changes without review
- Skip validation of outputs

## Common Patterns

### Pattern 1: Asynchronous Operations

For long-running tasks, use polling:

```markdown
## Process
1. Call `start_operation` and receive operation_id
2. Poll `get_operation_status` every 10 seconds
3. Maximum 5 minutes timeout (30 attempts)
4. When status is "completed", retrieve results
5. If timeout, post comment explaining delay
```

### Pattern 2: Multi-Step Analysis

For complex analysis, break into phases:

```markdown
## Process

### Phase 1: Data Collection
1. Gather git diff
2. Query deployment history
3. Check production metrics

### Phase 2: Analysis
1. Calculate risk factors
2. Identify critical changes
3. Determine recommendations

### Phase 3: Reporting
1. Format results as markdown
2. Include visualizations
3. Post to PR
```

### Pattern 3: Conditional Logic

Handle different scenarios:

```markdown
## Process
1. Analyze PR size
2. IF files < 5:
   - Use basic assessment
3. ELSE IF files < 20:
   - Use detailed assessment
4. ELSE:
   - Use comprehensive assessment with breakdown
5. Post appropriate comment
```

## Debugging Claude Workflows

### Common Issues

**Issue**: Claude doesn't follow instructions

**Solutions**:
- Make instructions more explicit
- Add examples of correct behavior
- Break complex tasks into smaller steps
- Check if context is too large (token limits)

**Issue**: Claude times out

**Solutions**:
- Implement polling for long operations
- Use MCP server for heavy processing
- Break into smaller subtasks
- Increase timeout limits if needed

**Issue**: Claude's output is inconsistent

**Solutions**:
- Add more constraints to the skill
- Provide output templates
- Use schema validation
- Include examples of correct format

**Issue**: Rate limits hit

**Solutions**:
- Add delays between API calls
- Cache intermediate results
- Use conditional execution
- Monitor usage patterns

### Debugging Steps

1. **Check workflow logs**: Review the full execution trace
2. **Validate secrets**: Ensure all required secrets are set
3. **Test skills locally**: Use Claude Code CLI to test skills
4. **Simplify**: Remove complexity until it works, then add back
5. **Review context**: Check what information Claude actually receives

### Getting Help

- **Claude Code Action Issues**: https://github.com/anthropics/claude-code-action/issues
- **Anthropic Discord**: Join for community support
- **Internal**: Contact the platform team
- **Documentation**: https://docs.anthropic.com

## Performance Considerations

### Token Usage

- Skills and prompts consume tokens
- Large git diffs increase token usage
- Multiple tool calls add up
- Monitor usage in Anthropic Console

**Optimization Tips**:
- Keep skills concise
- Summarize large diffs
- Limit context to relevant files
- Cache expensive operations

### Execution Time

- GitHub Actions has timeout limits (typically 6 hours, configurable)
- Claude API calls have their own timeouts
- MCP operations can be slow
- Network latency matters

**Optimization Tips**:
- Use asynchronous patterns
- Implement early termination
- Offload heavy work to MCP servers
- Add progress indicators

### Cost Management

- Each Claude API call costs money
- More tokens = higher cost
- Multiple retries add up
- Monitor costs in Anthropic Console

**Optimization Tips**:
- Use appropriate model (Claude 3.5 Sonnet is recommended)
- Cache results when possible
- Limit max_turns in claude_args
- Set budgets and alerts

## Future Enhancements

We're exploring:

- **Auto-Documentation**: Generate docs from code changes
- **Code Review Assistant**: Automated code review comments
- **Changelog Generation**: Semantic changelog from commits
- **Test Generation**: Auto-generate test cases
- **Refactoring Suggestions**: Identify improvement opportunities
- **Security Scanning**: AI-powered security analysis
- **Performance Analysis**: Identify optimization opportunities

## Resources

### Official Documentation
- [Claude Code Action](https://github.com/anthropics/claude-code-action)
- [Model Context Protocol](https://modelcontextprotocol.io)
- [Anthropic API Docs](https://docs.anthropic.com)
- [GitHub Actions](https://docs.github.com/en/actions)

### Community
- [Anthropic Discord](https://discord.gg/anthropic)
- [MCP GitHub Discussions](https://github.com/modelcontextprotocol/modelcontextprotocol/discussions)

### Internal Resources
- [Deployment Risk Assessment README](.github/workflows/README-DEPLOYMENT-RISK.md)
- [Architecture Documentation](.github/workflows/README-DEPLOYMENT-RISK-ARCHITECTURE.md)
- [Contributing Guide](CONTRIBUTING.md)

---

**Ready to build with Claude?** Start by exploring our [Deployment Risk Assessment workflow](.github/workflows/README-DEPLOYMENT-RISK.md) as a reference implementation!
