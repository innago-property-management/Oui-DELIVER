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

This workflow produces one. The `reason` input also captures, at the moment of the
click, whether a release is planned work, a rollback or a hotfix. That is the input
to change fail rate and deployment rework rate, and it cannot be reliably inferred
after the fact.

## One-time setup per service

1. **Create the environment.** In the service repo, Settings → Environments → New
   environment, named `production`. Add the people or team who may approve a
   release under *Required reviewers*. This is the actual gate — see the security
   note below.
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
     deployments: write

   jobs:
     promote:
       uses: innago-property-management/Oui-DELIVER/.github/workflows/promote-prod.yml@main
       permissions:
         contents: read
         deployments: write
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

## Deployment records

The promote job creates a GitHub Deployment on the **service** repo with this payload:

```json
{
  "source": "promote-prod",
  "service": "merlin",
  "version": "21.4.2",
  "previousVersion": "21.4.1",
  "reason": "planned"
}
```

and closes it `success` or `failure`. The metrics job reads these, filtering on
`payload.source == "promote-prod"`.

Note that declaring `environment:` on a job makes GitHub create its own deployment
record too. That record has an empty payload, so the `source` filter excludes it —
do not remove that filter or every release will be counted twice.

## Security note

`folderName` decides which service's values file gets written, but the environment
approval that gates the run belongs to the *calling* repo. Left unchecked, a repo
could pass a folder name that resolves into another service's directory and promote
that service on an approval that was never meant for it. The workflow therefore
requires `folderName` to match `^[a-z0-9][a-z0-9-]*$`, which rejects path separators
and traversal components. All 199 existing `helm-values` folders satisfy it.

`auto-merge` in the ArgoCD repo merges any branch matching `^automated/.*` without
human review. This workflow deliberately uses that prefix, because the environment
approval has already happened by then and a second gate would only slow releases
down. The consequence is that the environment's *Required reviewers* list is the
only thing standing between a dispatch and a production release. Keep it populated,
and keep `workflow_dispatch` permissions on service repos tight.
