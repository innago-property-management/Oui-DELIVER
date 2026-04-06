# Stacked .NET Architecture — Build & Publish Workflow

**Date:** 2026-04-06
**Status:** Draft
**Workflow:** `build-publish-dotnet-stacked.yml`

## Problem

Innago .NET services are evolving from "one running service per repo" to a **stacked architecture** pattern where a single repo produces multiple deployable images (e.g., InternalService, PrivateService, migrations, adapter layers). The existing `build-publish.yml` workflow hardcodes a maximum of two Docker images (main + migrations) via the composite action's built-in migrations support.

## Solution

A new reusable workflow that uses **convention-driven discovery** of named Dockerfiles at the repo root to build, publish, sign, and deploy N images from a single repo.

## Convention

### Named Dockerfiles at Repo Root

```
Dockerfile.{PascalCaseName}
```

Each file is discovered and produces an image named `{serviceName}-{kebab-cased-name}`.

### Example: tenant-ledger

```
Dockerfile.PrivateService                    → tenant-ledger-private-service
Dockerfile.InternalService                   → tenant-ledger-internal-service
Dockerfile.PersistenceMigrations             → tenant-ledger-persistence-migrations
Dockerfile.MerlinFataMorganaInvoiceMockery   → tenant-ledger-merlin-fata-morgana-invoice-mockery
```

### Layer Roles

| Role | Convention | Docker Image | ArgoCD Behavior |
|------|-----------|-------------|-----------------|
| **Persistence** | `*Migrations` suffix | Migrations image | `migrationJob.image.tag` in PrivateService's ArgoCD folder |
| **PrivateService** | `Dockerfile.PrivateService` | Own image | Own ArgoCD folder + receives migration tag |
| **InternalService** | `Dockerfile.InternalService` | Own image | Own ArgoCD folder |
| **Adapter/Orchestrator** | Any other `Dockerfile.*` | Own image | Own ArgoCD folder |

### ArgoCD Folder Convention

Each non-migration service gets its own folder in `argocd-shared`:

```
helm-values/
  tenant-ledger-private-service/
    value-overrides-dev.yaml       # image.tag + migrationJob.image.tag
    value-overrides-qa.yaml
    value-overrides-stage.yaml
  tenant-ledger-internal-service/
    value-overrides-dev.yaml       # image.tag only
    ...
```

Migrations pair with PrivateService via the webapp Helm chart's `migrationJob` convention — they run as a Kubernetes pre-deploy hook in the same Helm release.

## Workflow Architecture

```
version ──┐
detect  ──┤
discover ─┤
           ├── build-test (dotnet build + test, NuGet push, SBOM — runs once)
           │
           ├── publish-images (matrix × N, needs: build-test)
           │     └── build-publish-sign-docker composite action per image
           │
           ├── update-argocd (matrix × services, needs: publish-images)
           │     └── update-argocd action per folder (serial to avoid git conflicts)
           │
           ├── summary (always, job summary with image table)
           │
           └── generate_provenance (if SLSA enabled)
```

### Key Design Decisions

1. **Single `serviceName` input** — no image lists, no Dockerfile paths. Convention handles naming.

2. **Discovery, not declaration** — workflow scans `Dockerfile.*` at root. Adding a new layer = adding a Dockerfile. No workflow changes needed.

3. **`*Migrations` suffix is the only special case** — these images don't get their own ArgoCD folder; they update `migrationJob.image.tag` in PrivateService's folder.

4. **Migrations always pair with PrivateService** — this is the stacked architecture convention. PrivateService depends on Persistence, so it owns the migration pre-deploy hook.

5. **`max-parallel: 1` for ArgoCD updates** — prevents git conflicts when multiple matrix legs push branches to argocd-shared simultaneously.

6. **Composite action unchanged** — `build-publish-sign-docker` stays as the atomic unit for one image. The stacked workflow just calls it N times without using the built-in migrations support.

## Changes to Existing Actions

### `update-argocd/action.yaml`

Added `updateMigrationTag` input (default: `'true'`). When `'false'`, skips `migrationJob.image.tag` update and verification. Backward compatible — all existing callers get the default behavior.

### `detect-build-type/action.yml`

Extended `has_docker` detection to also find `Dockerfile.*` files (stacked repos have no root `Dockerfile`). Updated sparse checkout to include `Dockerfile.*`.

## Caller Example

```yaml
# tenant-ledger-service/.github/workflows/build-publish.yaml
name: build-publish

on:
  push:
    branches: [main]
    tags: ['*']
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/build-publish-dotnet-stacked.yml@main
    secrets:
      githubToken: ${{ secrets.ORG_NUGET_PUSH }}
      cosignKey: ${{ secrets.COSIGN_KEY }}
      cosignPassword: ${{ secrets.COSIGN_PASSWORD }}
    permissions:
      attestations: write
      packages: write
      pull-requests: write
      id-token: write
      contents: write
      actions: read
    with:
      serviceName: tenant-ledger
      argoCdRepoName: "${{ github.repository_owner }}/argocd-shared"
      slsa: true
```

## Migration Path

1. Create named `Dockerfile.*` files at repo root (can coexist with existing root `Dockerfile`)
2. Switch caller workflow from `build-publish.yml` to `build-publish-dotnet-stacked.yml`
3. Create ArgoCD folders for each service layer in `argocd-shared`
4. Remove old root `Dockerfile` once stacked Dockerfiles are verified

## Future Considerations

- If a non-PrivateService layer ever needs migrations, the pairing convention can be extended with an explicit input or naming convention (e.g., `Dockerfile.{Target}Migrations`)
- The `detect-build-type` action's `skip_tests` optimization works correctly for stacked repos that also produce NuGet packages; for stacked repos without packages, the optimization will need the migration detection to also consider `Dockerfile.*`
