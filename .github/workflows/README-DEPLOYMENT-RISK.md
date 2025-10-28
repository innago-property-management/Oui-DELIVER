# Deployment Risk Assessment - Architecture

## Overview

This deployment risk assessment system uses a **two-tier architecture** to separate orchestration concerns from assessment logic:

```
┌─────────────────────────────────────────┐
│  GitHub Actions (Any Repo)             │
│  - Thin workflow-client skill          │
│  - Submit, Poll, Interpret, Report     │
└──────────────┬──────────────────────────┘
               │ HTTPS/SSE
               │ mcp-remote
               ▼
┌─────────────────────────────────────────┐
│  Remote MCP Server (K8s Cluster)       │
│  - Full deployment-risk-assessor skill │
│  - Git analysis, Keptn, Observability  │
│  - Kicks off Argo Workflows            │
└──────────────┬──────────────────────────┘
               │
               ├──► Thanos Query (metrics)
               ├──► Kubernetes API (resources)
               └──► Argo Workflows (git ops)
```

## Components

### 1. Workflow Client Skill (In Each Repo)

**Location**: `.github/skills/deployment-risk-workflow-client/SKILL.md`

**Responsibilities:**
- Submit risk assessment request to remote MCP server
- Poll for completion (max 5 minutes)
- Interpret and format results
- Post PR comment with risk assessment

**Does NOT contain:**
- Risk scoring logic
- Git diff analysis
- Keptn metrics queries
- Observability validation

### 2. Remote MCP Server (Deployed in K8s)

**Will be located at**: `https://deployment-risk-mcp.innago.com/mcp` (or similar)

**Responsibilities:**
- Embeds the full `deployment-risk-assessor` skill
- Executes all risk assessment logic
- Manages git operations (clone, diff analysis)
- Queries Thanos for Keptn metrics and anomalies
- Queries Kubernetes API for observability resources
- Returns comprehensive risk assessment

**Benefits of K8s Deployment:**
- **No credential exposure** - ServiceAccount handles auth
- **Direct network access** - No WAF bypass needed
- **kubectl access** - Can validate K8s resources
- **Reusable** - Multiple repos use same endpoint
- **Scalable** - Can trigger Argo Workflows for long-running tasks

### 3. GitHub Actions Workflow

**Location**: `.github/workflows/deployment-risk-assessment.yml`

**Key Features:**
- Minimal dependencies (just Node.js)
- Uses `mcp-remote` to connect to remote MCP server via SSE
- Passes PR context to Claude Code Action
- No secrets for Thanos/Kubernetes (handled by remote server)

## MCP Tools

### `start_risk_assessment`

**Purpose**: Initiate a deployment risk assessment

**Input**:
```json
{
  "repository": "innago-property-management/service-name",
  "pr_number": 123,
  "base_branch": "main",
  "head_branch": "feature-branch",
  "pr_title": "Add new feature",
  "pr_author": "username"
}
```

**Output**:
```json
{
  "assessment_id": "uuid",
  "status": "started"
}
```

### `get_risk_assessment`

**Purpose**: Retrieve status and results of an assessment

**Input**:
```json
{
  "assessment_id": "uuid"
}
```

**Output** (when complete):
```json
{
  "assessment_id": "uuid",
  "status": "completed",
  "result": {
    "risk_score": 7,
    "risk_category": "HIGH",
    "risk_factors": [...],
    "git_analysis": {...},
    "deployment_history": {...},
    "observability": {...},
    "active_anomalies": 2,
    "recommendations": {...}
  }
}
```

## Risk Scoring Algorithm

The remote MCP server calculates risk scores (0-10) based on:

### Factors (0-10 scale):
- **File count**: 0-3 points (thresholds: 5/10/20 files)
- **Critical path changes**: 0-3 points (services, controllers, middleware, config)
- **PublicAPI changes**: +3 points (breaking changes detected)
- **Active anomalies**: +3 points (production issues)
- **Low deployment frequency**: +1 point (>7 days between deploys)
- **Critical service**: +1 point (fraud, identity, payment services)

### Categories:
- **LOW (0-3)**: Standard deployment
- **MEDIUM (4-6)**: Extended canary, 1 approval
- **HIGH (7-8)**: Gradual rollout, 2 approvals, on-call engineer
- **CRITICAL (9-10)**: Defer to off-hours, 3 approvals, incident commander

## Configuration

### GitHub Secrets Required

1. **`ANTHROPIC_API_KEY`** - Claude API key for GitHub Actions
2. **`DEPLOYMENT_RISK_MCP_URL`** - Remote MCP server endpoint (e.g., `https://deployment-risk-mcp.innago.com/mcp`)
3. **`GITHUB_TOKEN`** - Automatically provided by GitHub Actions

### No Longer Required (handled by K8s deployment):
- ~~`THANOS_USER`~~ - Server has direct access
- ~~`THANOS_PASS`~~ - Server has direct access
- ~~User-Agent whitelist~~ - Internal network traffic

## Workflow Execution Flow

1. **Trigger**: PR opened/updated
2. **Load Skill**: Read thin workflow-client skill from `.github/skills/`
3. **Start Assessment**: Claude calls `start_risk_assessment` MCP tool
4. **Remote Processing** (in K8s):
   - Git clone and diff analysis
   - Keptn metrics query (Thanos)
   - Observability validation (kubectl)
   - Anomaly detection (Thanos)
   - Risk score calculation
5. **Poll for Result**: Claude calls `get_risk_assessment` every 10s
6. **Format Comment**: Claude formats risk assessment as markdown
7. **Post PR Comment**: Claude posts comment via GitHub API

## Deployment Steps

### For Each Repository Using This System:

1. Copy `.github/skills/deployment-risk-workflow-client/` to repo
2. Copy `.github/workflows/deployment-risk-assessment.yml` to repo
3. Configure GitHub secrets:
   - `ANTHROPIC_API_KEY`
   - `DEPLOYMENT_RISK_MCP_URL`
4. Test on a pull request

### For Platform Team (One-Time Setup):

1. Build and deploy MCP server to K8s with:
   - Full `deployment-risk-assessor` skill embedded
   - ServiceAccount with RBAC for K8s read access
   - Internal network access to Thanos
   - Ingress with TLS
2. Configure Argo Workflows (if using async pattern)
3. Provide MCP endpoint URL to consuming repos

## Future Enhancements

### Option 1: Synchronous (Current Design)
- MCP server executes all operations synchronously
- Returns result within ~30-60 seconds
- Good for: Fast assessments, simple git operations

### Option 2: Asynchronous with Argo Workflows
- MCP server triggers Argo Workflow
- Workflow executes assessment in separate pods
- MCP server polls for result
- Good for: Complex analysis, large repos, timeout-prone operations

## Advantages of This Architecture

1. **Separation of Concerns**:
   - Repos contain orchestration logic only
   - Assessment logic centralized in MCP server
   - Easy to update assessment algorithm without touching repos

2. **Security**:
   - No credentials in GitHub Actions
   - ServiceAccount-based auth in K8s
   - No WAF bypass tricks needed

3. **Maintainability**:
   - Update MCP server once, affects all repos
   - Thin skill in repos is stable (rarely changes)
   - Clear separation between "what" (orchestration) and "how" (assessment)

4. **Scalability**:
   - MCP server can scale horizontally in K8s
   - Can add caching layer for frequently-assessed PRs
   - Can migrate to Argo Workflows if needed

5. **Reusability**:
   - Multiple repos use same MCP endpoint
   - Consistent risk assessment across organization
   - Single source of truth for risk scoring logic
