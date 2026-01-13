# Deployment Risk Assessment Workflow

Automatically assess deployment risk for pull requests using Claude AI and comprehensive analysis of code changes, deployment history, and production health.

## Overview

This reusable GitHub Actions workflow analyzes pull requests and provides risk assessments with actionable recommendations. It helps teams make informed deployment decisions by evaluating:

- 📝 **Code Changes**: File counts, critical path modifications, API changes
- 📊 **Deployment History**: Frequency, success rate, recent issues
- 🔍 **Production Health**: Active anomalies, observability status
- 🎯 **Risk Scoring**: 0-10 scale with clear deployment recommendations

## Quick Start

### 1. Set Up Required Secrets

Add these secrets to your repository (Settings → Secrets and variables → Actions):

| Secret Name | Description | Where to Get It |
|------------|-------------|-----------------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key for Claude | [console.anthropic.com](https://console.anthropic.com) |
| `DEPLOYMENT_RISK_MCP_URL` | MCP server endpoint URL | Contact your platform team |
| `DEPLOYMENT_RISK_API_KEY` | API key for the MCP server | Contact your platform team |

> **Note**: `GITHUB_TOKEN` is automatically provided by GitHub Actions

### 2. Create Workflow File

Create `.github/workflows/deployment-risk-assessment.yml` in your repository:

```yaml
name: Deployment Risk Assessment

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  assess-risk:
    name: Assess Deployment Risk
    uses: innago-property-management/Oui-DELIVER/.github/workflows/deployment-risk-assessment.yml@main
    with:
      pr_number: ${{ github.event.pull_request.number }}
      base_branch: ${{ github.event.pull_request.base.ref }}
    secrets:
      ANTHROPIC_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      DEPLOYMENT_RISK_MCP_URL: ${{ secrets.DEPLOYMENT_RISK_MCP_URL }}
      TOKEN: ${{ secrets.GITHUB_TOKEN }}
      DEPLOYMENT_RISK_WAF_KEY: ${{ secrets.DEPLOYMENT_RISK_API_KEY }}
```

### 3. Grant Workflow Permissions

Ensure your workflow has the necessary permissions:

1. Go to **Settings → Actions → General → Workflow permissions**
2. Select **"Read and write permissions"**
3. Check **"Allow GitHub Actions to create and approve pull requests"**

### 4. Test It Out

Open a pull request and watch the workflow run! Within a few minutes, you'll see a comprehensive risk assessment posted as a comment.

## Configuration Options

### Basic Configuration

The minimal configuration shown above works for most repositories. The workflow will automatically:
- Analyze all changed files in the PR
- Compare against the base branch
- Query deployment history and production health
- Post a formatted risk assessment comment

### Advanced Configuration

#### Add Repository-Specific Context

Customize the assessment with context specific to your repository:

```yaml
jobs:
  assess-risk:
    name: Assess Deployment Risk
    uses: innago-property-management/Oui-DELIVER/.github/workflows/deployment-risk-assessment.yml@main
    with:
      pr_number: ${{ github.event.pull_request.number }}
      base_branch: ${{ github.event.pull_request.base.ref }}
      additional_context: |
        ## Repository-Specific Guidelines
        - This is a healthcare application - focus on HIPAA compliance
        - Check for proper error handling in patient data operations
        - Verify all database migrations are reversible
        - Ensure audit logging is present for sensitive operations
    secrets:
      ANTHROPIC_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      DEPLOYMENT_RISK_MCP_URL: ${{ secrets.DEPLOYMENT_RISK_MCP_URL }}
      TOKEN: ${{ secrets.GITHUB_TOKEN }}
      DEPLOYMENT_RISK_WAF_KEY: ${{ secrets.DEPLOYMENT_RISK_API_KEY }}
```

#### Custom Base Branch

For repositories that don't use `main`:

```yaml
with:
  pr_number: ${{ github.event.pull_request.number }}
  base_branch: develop  # or 'master', 'trunk', etc.
```

## Understanding the Risk Assessment

### Risk Scores (0-10 Scale)

| Score | Category | Deployment Strategy |
|-------|----------|-------------------|
| 0-3 | 🟢 **LOW** | Standard deployment process |
| 4-6 | 🟡 **MEDIUM** | Extended canary period, 1 approval required |
| 7-8 | 🟠 **HIGH** | Gradual rollout, 2 approvals, on-call engineer notified |
| 9-10 | 🔴 **CRITICAL** | Defer to off-hours, 3 approvals, incident commander on standby |

### Risk Factors Analyzed

The assessment considers multiple factors:

**Code Analysis**
- Number of files changed (more files = higher risk)
- Changes to critical paths (services, controllers, middleware, config files)
- Public API modifications (breaking changes detection)
- Database migration impacts

**Deployment History**
- Deployment frequency (infrequent deploys = higher risk)
- Recent deployment failures
- Time since last successful deployment

**Production Health**
- Active anomalies or production issues
- Observability status (metrics, logs, traces)
- Recent incident history

**Service Criticality**
- High-impact services (payment, authentication, fraud detection)
- Downstream dependencies
- User-facing vs. internal services

### Sample Assessment Output

When the workflow runs, you'll see a comment like this:

```markdown
## 🎯 Deployment Risk Assessment

**Risk Score**: 7/10 (🟠 HIGH)

### 📊 Risk Analysis
- **Files Changed**: 15 files (⚠️ Above threshold)
- **Critical Paths**: Modified `services/PaymentService.cs` and `middleware/AuthMiddleware.cs`
- **Active Anomalies**: 2 ongoing issues in production
- **Deployment Frequency**: Last deploy 9 days ago (⚠️ Infrequent)

### ⚠️ Risk Factors
1. Changes to payment processing logic
2. Two active P2 incidents in production
3. Infrequent deployment cadence suggests complex changes
4. Modifications to authentication middleware

### ✅ Deployment Recommendations
- **Approvals Required**: 2 technical leads
- **Deployment Window**: Extended canary (30 minutes)
- **Monitoring**: Have on-call engineer available
- **Rollback Plan**: Verified and tested
- **Stakeholder Notification**: Alert #payments-team before deploy

### 📝 File Analysis
**High Risk Files**:
- `Services/PaymentService.cs` - Core payment processing
- `Middleware/AuthMiddleware.cs` - Authentication layer

**Medium Risk Files**:
- `Controllers/PaymentController.cs`
- `Models/PaymentRequest.cs`

**Low Risk Files**:
- `Tests/*.cs` (13 files)

### 🔍 Observability Status
✅ Metrics configured
✅ Error logging present
✅ Distributed tracing enabled
⚠️ Load testing recommended for payment changes
```

## How It Works

The workflow follows this execution flow:

1. **Trigger**: Runs when a PR is opened, updated, or reopened
2. **Setup**: Loads Claude AI skill and PR context
3. **Assessment**: Calls remote MCP server to analyze:
   - Git diff and file changes
   - Deployment history from monitoring systems
   - Production health metrics
   - Observability configuration
4. **Risk Calculation**: Computes risk score based on multiple factors
5. **Comment**: Posts formatted assessment to the PR

The entire process typically completes in 30-90 seconds.

## Troubleshooting

### "ANTHROPIC_API_KEY not found" Error

**Cause**: The Anthropic API key secret is not configured or has the wrong name.

**Solution**:
1. Verify the secret exists: Settings → Secrets and variables → Actions
2. Ensure the secret name is exactly `ANTHROPIC_API_KEY` (case-sensitive)
3. If using organization secrets, ensure they're enabled for your repository
4. For public repositories, organization secrets must be explicitly allowed

### "Permission denied" Error

**Cause**: Workflow doesn't have permission to write PR comments.

**Solution**:
1. Go to Settings → Actions → General → Workflow permissions
2. Select "Read and write permissions"
3. Enable "Allow GitHub Actions to create and approve pull requests"

### Assessment Times Out

**Cause**: Large repository or slow network connection to MCP server.

**Solution**:
1. Check MCP server status with your platform team
2. For very large PRs (>100 files), consider breaking into smaller PRs
3. Verify network connectivity to the MCP endpoint

### No Comment Posted

**Cause**: Workflow completed but comment wasn't created.

**Solution**:
1. Check workflow logs for errors
2. Verify `GITHUB_TOKEN` permissions
3. Ensure PR is not from a fork (security limitation)
4. Check if rate limits were hit

### Incorrect Risk Score

**Cause**: Assessment may need repository-specific tuning.

**Solution**:
1. Use `additional_context` to provide domain-specific guidance
2. Contact platform team to adjust risk scoring for your service type
3. Review the detailed risk factors in the assessment

## Advanced Usage

### For Organizations

If you're using this across multiple repositories:

1. **Set organization-level secrets** for shared credentials
2. **Create a template repository** with pre-configured workflow
3. **Enable secrets for public repositories** if needed (Settings → Secrets → Public repositories)
4. **Document your risk score thresholds** for your deployment process

### For Different Repository Types

The workflow adapts to different types of repositories:

**Microservices**: Focuses on API compatibility and downstream impacts

**Libraries**: Emphasizes public API changes and semantic versioning

**Frontend Applications**: Considers user-facing changes and browser compatibility

**Infrastructure**: Highlights configuration changes and rollback procedures

## Architecture

This workflow uses a two-tier architecture:

- **GitHub Actions** (this workflow): Orchestrates the assessment
- **Remote MCP Server**: Performs analysis with access to deployment data

For detailed architecture information, see [README-DEPLOYMENT-RISK-ARCHITECTURE.md](./README-DEPLOYMENT-RISK-ARCHITECTURE.md).

## Support and Contribution

### Getting Help

- **Issues**: [Report bugs or request features](https://github.com/innago-property-management/Oui-DELIVER/issues)
- **Discussions**: [Ask questions](https://github.com/innago-property-management/Oui-DELIVER/discussions)
- **Internal**: Reach out to the platform team on Slack

### Contributing

We welcome contributions! This is an open-source project designed to be adapted by other organizations.

To contribute:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request with a clear description

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for detailed guidelines.

## License

This workflow is part of the Oui-DELIVER project and is available under the [MIT License](../../LICENSE).

## Related Resources

- [Anthropic Claude Code Action](https://github.com/anthropics/claude-code-action)
- [MCP (Model Context Protocol)](https://modelcontextprotocol.io)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

**Questions?** Open an issue or contact the platform team!
