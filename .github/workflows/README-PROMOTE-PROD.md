# promote-prod

Promotes a service to production by writing its image tag into
`value-overrides-prod-eks.yaml` in the ArgoCD repo, behind a GitHub Environment
approval, and recording the release as a GitHub Deployment.

It replaces the manual edit of `value-overrides-prod-eks.yaml`. Nothing else about
the pipeline changes: `build-publish` still handles dev, QA and stage through the
`update-argocd` action.

## Why it exists

Production releases were hand-edited commits to `argocd-shared`, which meant no
author, no approval and no record. That last part is what makes DORA metrics
impossible to calculate — deployment frequency and lead time both need a dated,
queryable production release event.

This workflow makes that step reviewable and attributable: a named person starts
it, a code owner approves it, and the change lands as a pull request rather than a
hand edit.

It does **not** record the deployment. Production is a pull-model reconcile, so the
deployment event is emitted by ArgoCD at sync time into the event store — see the
metrics and release model, section 5.1. This workflow produces the merge that
ArgoCD then reconciles, and nothing more.

The `reason` input captures, at the moment of the click, whether a release is
planned work, a rollback or a hotfix. Rollback is one of the three change-failure
conditions and is free to capture here; change failure rate itself is derived from
incident attribution, not from this field alone.

## One-time setup per service

1. **Create the environment.** In the service repo, Settings → Environments → New
   environment, named `production`. Under *Deployment branches and tags* choose
   **Selected branches and tags** and add the single pattern `main`.

   Required reviewers are **not** available on GitHub Team for private repos (the
   API returns "Please ensure the billing plan supports the required reviewers
   protection rule"), so the release approval does not live here — it lives in the
   ArgoCD repo, see below.
2. **Add the caller workflow.** Drop the file below into the service repo as
   `.github/workflows/promote-prod.yaml`, setting `folderName` to the service's
   `helm-values` folder. Set `updateMigrationTag: false` if the service has no
   `migrationJob.image.tag` in its values file.

   ```yaml
   name: promote-prod

   on:
     workflow_dispatch:
       inputs:
         version:
           description: "Version to promote. Leave blank to promote whatever is in stage."
           required: false
           type: string
           default: ''
         reason:
           description: "Why this is going out"
           required: true
           type: choice
           options:
             - planned
             - rollback
             - hotfix
           default: planned
         dryRun:
           description: "Validate and show the diff without pushing"
           required: false
           type: boolean
           default: false

   permissions:
     contents: read

   jobs:
     promote:
       uses: innago-property-management/Oui-DELIVER/.github/workflows/promote-prod.yml@main
       permissions:
         contents: read
       with:
         folderName: help
         version: ${{ inputs.version }}
         reason: ${{ inputs.reason }}
         dryRun: ${{ inputs.dryRun }}
         updateMigrationTag: true
       secrets:
         githubToken: ${{ secrets.ORG_NUGET_PUSH }}
   ```
3. **Check the token.** `githubToken` needs write access to `argocd-shared` and
   `read:packages` on GHCR. `ORG_NUGET_PUSH` already has both.

## Releasing

Actions → promote-prod → Run workflow. Leave *version* blank to promote whatever is
currently in stage, which is the normal case. Pick a `reason`. The run pauses for
approval, then writes the tag and pushes `automated/prod-<service>-<version>` to the
ArgoCD repo, where `auto-pr` raises the pull request and `auto-merge` merges it.

Rolling back is the same workflow with an older version and `reason: rollback`.
There is no separate rollback path.

## Dry run

Tick *dryRun* to exercise the whole path without consequences. It resolves and
validates the version, makes the edit in a throwaway checkout, prints the diff to
the job summary, and then stops: nothing is pushed to the ArgoCD repo and no
deployment record is created. Use it the first time a service is wired up, to
confirm the values file is shaped the way the workflow expects.

## What it refuses to do

| Situation | Behaviour |
|---|---|
| No `value-overrides-prod-eks.yaml` for the service | Fails — the service does not deploy to prod-eks |
| Production is already on that version | Fails — nothing to promote |
| Version is older than production, `reason` is not `rollback` | Fails — asks you to re-run as a rollback |
| Image tag is not in GHCR | Fails before touching the ArgoCD repo |
| `updateMigrationTag: true` but no `migrationJob.image.tag` | Fails, telling you to set it false |
| The `&tag` YAML anchor is lost during the edit | Fails rather than push a broken values file |
| `folderName` is not a plain service name | Fails — see the security note |
| `dryRun` is set | Validates and prints the diff, then stops before pushing |

That last one guards a real hazard. Every prod values file declares its tag as an
anchor (`tag: &tag 21.4.1`) referenced further down the file. The current `yq`
preserves it on scalar assignment — verified against merlin's stage file, which
still carries its anchor after automated commits — but a `yq` upgrade that changed
this would silently break every production values file in the org. The check costs
nothing and fails loudly instead.

## Why there are no deployment records here

An earlier version of this workflow created a GitHub Deployment on the service
repo. That has been removed.

The Deployments API records deployments *initiated from a workflow*. Production
here is a pull-model reconcile: this workflow writes an image tag, ArgoCD notices
and applies it. Recording a deployment at push time would announce something that
had not happened yet — and under the code-owner gate it would mark a promotion
successful that a reviewer might still reject.

Deployment events come from ArgoCD's notification hook into
`innago-engineering-metrics`, at sync time, carrying what actually landed.

The `production` environment on the service repo is still required, but only for
its **deployment-branch policy**: restricting it to `main` is what stops a
promotion being dispatched from a branch carrying a tampered `folderName`. It
records nothing. Do not delete it as dead configuration.

## Security note

`folderName` decides which service's values file gets written, but the environment
approval that gates the run belongs to the *calling* repo. Left unchecked, a repo
could pass a folder name that resolves into another service's directory and promote
that service on an approval that was never meant for it. The workflow therefore
requires `folderName` to match `^[a-z0-9][a-z0-9-]*$`, which rejects path separators
and traversal components. All 199 existing `helm-values` folders satisfy it.

Releases are gated in three independent places, none of which needs Enterprise Cloud:

1. **CODEOWNERS in the ArgoCD repo — the release approval.** `.github/CODEOWNERS`
   already requires a code owner on `helm-values/**/value-overrides-prod-eks.yaml`.
   This workflow pushes a `promote/` branch, *not* `automated/`, precisely so that
   `auto-merge` does not pick it up: that job merges `^automated/.*` using an app
   that is a ruleset bypass actor, which would skip the code owner review entirely.
   Every production promotion therefore waits for a human named in CODEOWNERS.
2. **Deployment branches on the environment — the integrity gate.** Restricting the
   `production` environment to `main` means the only caller definition that can
   reach production is the reviewed one. Without it, someone could dispatch from a
   branch where `folderName` pointed at a different service.
3. **The `folderName` pattern check — the blast-radius gate.** `folderName` decides
   which service's values file is written, so it is restricted to
   `^[a-z0-9][a-z0-9-]*$` to reject path separators and traversal components.

Keep `workflow_dispatch` permissions on service repos tight; write access is what
lets someone start a promotion, even though they cannot complete one alone.
