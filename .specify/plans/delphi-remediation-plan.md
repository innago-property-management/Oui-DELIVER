# Oui-DELIVER Delphi Remediation Plan

**Generated**: 2026-01-13
**Panel**: Operational, Kantian, Buddhist, Marxist
**Average Score**: 2.1/5

---

## Executive Summary

A Delphi panel review identified 11 critical issues across security, reliability, universalizability, and developer experience. This plan addresses them in priority order.

---

## Phase 0: P0 Critical - Security & Reliability

### 1.1 Bash Scripts Missing `set -e`

**Problem**: Failures in bash scripts are silently ignored.

**Files**:
- `/Volumes/Repos/Oui-DELIVER/prevent-commits-to-default-branch.sh`
- `/Volumes/Repos/Oui-DELIVER/.ideation/deploy-kaizen-to-merlin-repos.sh`

**Fix**: Add `set -euo pipefail` after shebang.

**Complexity**: S

---

### 1.2 NuGet Uses `--store-password-in-clear-text`

**Problem**: Credentials stored in cleartext on disk.

**Files**:
- `.github/actions/build-dotnet/action.yaml` (line 56)
- `.github/actions/check-licenses-action/action.yaml` (line 39)
- `.github/workflows/merge-checks.yml` (lines 87, 164)

**Fix**: Remove `--username`, `--password`, `--store-password-in-clear-text` flags. Use environment variable `NuGetPackageSourceCredentials_github` instead (already set).

**Complexity**: M

---

### 1.3 Cosign Signing Can Be Silently Skipped

**Problem**: No verification that signing succeeded.

**File**: `.github/actions/build-publish-sign-docker/action.yaml` (lines 139-166)

**Fix**: Add `set -euo pipefail` and verification step:
```bash
cosign verify --key env://COSIGN_KEY "$IMAGE@$DIGEST" || {
  echo "::error::Signature verification failed!"
  exit 1
}
```

**Complexity**: M

---

### 1.4 No Verification Docker Push Succeeded

**Problem**: Signing attempts even if push failed.

**File**: `.github/actions/build-publish-sign-docker/action.yaml`

**Fix**: Add verification step before signing:
```bash
docker manifest inspect "$IMAGE@$DIGEST" > /dev/null || {
  echo "::error::Image not found in registry after push!"
  exit 1
}
```

**Complexity**: S (depends on 1.3 - same file)

---

## Phase 1: P1 High - Resilience & Coupling

### 2.1 MCP Health Checks Have No Retry Logic

**Problem**: Single failure blocks all PRs.

**File**: `.github/workflows/deployment-risk-assessment.yml` (lines 61-78)

**Fix**: Add retry loop with exponential backoff:
```bash
MAX_RETRIES=3
for attempt in $(seq 1 $MAX_RETRIES); do
  HTTP_CODE=$(curl -s -o /tmp/response.txt -w "%{http_code}" \
    --connect-timeout 10 --max-time 30 \
    --header "x-api-key: $API_KEY" "$ENDPOINT") || HTTP_CODE=000
  [ "$HTTP_CODE" -eq 200 ] && exit 0
  sleep $((2 ** attempt))
done
exit 1
```

**Complexity**: M

---

### 2.2 All Workflows Use `@main`

**Problem**: Breaking changes propagate instantly to all consumers.

**Scope**: 39 instances across 15+ workflow files.

**Fix**:
1. Create release workflow (`.github/workflows/release.yml`)
2. Tag current state as `v2.0.0`
3. Replace all `@main` with `@v2`

**Complexity**: L

---

### 2.3 ArgoCD YAML Updates Not Validated

**Problem**: yq silently succeeds even if path doesn't exist.

**File**: `.github/actions/update-argocd/action.yaml` (lines 59-69)

**Fix**: Add validation before and after yq:
```bash
OLD_TAG=$(yq '.image.tag' "$FILE")
yq --inplace ".image.tag=\"${tag}\"" "$FILE"
NEW_TAG=$(yq '.image.tag' "$FILE")
[ "$OLD_TAG" != "$NEW_TAG" ] || {
  echo "::error::YAML path not found or unchanged"
  exit 1
}
```

**Complexity**: M

---

## Phase 2: P2 Medium - Universalizability & Experience

### 3.1 Hardcoded Organization Name

**Problem**: `innago-property-management` hardcoded 77+ times.

**Fix**: Parameterize with input defaulting to `${{ github.repository_owner }}`.

**Files**: All workflow and action files with NuGet/GitHub references.

**Complexity**: M

---

### 3.2 Secret Naming Inconsistent

**Problem**: Mix of camelCase (`githubToken`), SCREAMING_SNAKE_CASE (`GITHUB_TOKEN`), snake_case (`npm_token`).

**Fix**: Standardize to SCREAMING_SNAKE_CASE (matches GitHub convention).

**Migration**:
- `githubToken` → `GITHUB_TOKEN`
- `cosignKey` → `COSIGN_KEY`
- `anthropicKey` → `ANTHROPIC_API_KEY`

**Complexity**: M

---

### 3.3 No Workflow Observability

**Problem**: Failures take 10+ minutes to notice.

**Fix**: Add job summaries and optional Slack notifications.

**Complexity**: M

---

### 3.4 Kaizen System Is Opt-Out

**Problem**: Repos are swept by default.

**Fix**: Require `kaizen-enabled` topic for opt-in.

**File**: `.github/kaizen-sweep/config.yml`

**Complexity**: S

---

## Dependency Graph

```
P0 (parallel, no deps)
├── 1.1 Bash set -e
├── 1.2 NuGet credentials
├── 1.3 Cosign verification ──┐
└── 1.4 Docker push verify ───┘ (same file)

P1 (after P0 stable)
├── 2.1 MCP retry
├── 2.2 Version pinning
└── 2.3 ArgoCD validation

P2 (after P1)
├── 3.1 Org parameterization
├── 3.2 Secret naming
├── 3.3 Observability
└── 3.4 Kaizen opt-in
```

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Docker push failure rate | <0.5% |
| NuGet push failure rate | <0.5% |
| Cosign success rate | 100% |
| MCP health check pass rate | >99% |

---

## Panel Validation

| Persona | Validated | Notes |
|---------|-----------|-------|
| Operational | ✓ | "Will surface hidden failures - monitor 48h post-deploy" |
| Kantian | ✓ | "Adopt SCREAMING_SNAKE_CASE uniformly" |
| Buddhist | Pending | Coupling concerns require version pinning |
| Marxist | Pending | Kaizen opt-in addresses labor concerns |
