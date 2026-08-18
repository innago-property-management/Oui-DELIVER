# publish-react-lib

Builds, tests and publishes React libraries to GitHub Packages. It is the React
counterpart of [`publish-angular-lib.yml`](publish-angular-lib.yml) and follows the
same release convention: **a version bump in a library's `package.json` is what
triggers a publish.**

The difference is discovery. Angular libraries are enumerated through
`angular.json` and built with `ng build`, publishing from `dist/<project>`. React
libraries have no workspace manifest, so this workflow discovers them by folder
position and drives them entirely through their own npm scripts. That makes it
framework-agnostic in practice — anything that builds and tests with plain npm
scripts works, React or otherwise.

## Usage

```yaml
jobs:
  build-and-test:
    if: github.event_name == 'pull_request'
    uses: innago-property-management/Oui-DELIVER/.github/workflows/publish-react-lib.yml@main
    permissions:
      contents: read
      packages: read
    secrets:
      npm_token: ${{ secrets.YOUR_PACKAGES_TOKEN }}
    with:
      workspace_path: 'innago-react-workspace'
      skip_publish: true

  build-and-publish:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    uses: innago-property-management/Oui-DELIVER/.github/workflows/publish-react-lib.yml@main
    permissions:
      contents: read
      packages: write
    secrets:
      npm_token: ${{ secrets.YOUR_PACKAGES_TOKEN }}
    with:
      workspace_path: 'innago-react-workspace'
      skip_publish: false
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `node_version` | no | `18` | Node.js version |
| `workspace_path` | no | `innago-react-workspace` | Directory whose **immediate** subfolders are libraries |
| `skip_publish` | no | `false` | Build and test only — use for PR validation |
| `libraries` | no | `''` | Space- or comma-separated folder names to force, bypassing change detection |

## Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `npm_token` | yes | Token with `packages:write` for publishing to GitHub Packages |

## Outputs

The composite action exposes `published`, `processed`, `count_published` and
`count_processed`, which the workflow renders into the job summary.

## The library contract

A library is any directory **directly** under `workspace_path` containing a
`package.json`. Nothing is registered anywhere — drop the folder in and the next
merge picks it up.

```jsonc
{
  "name": "@innago-property-management/<your-lib>",
  "version": "1.0.0",
  "files": ["dist", "README.md"],
  "publishConfig": { "registry": "https://npm.pkg.github.com/" },
  "scripts": {
    "build": "…",     // required
    "test": "…",      // required in order to publish
    "verify": "…",    // optional, runs first
    "typecheck": "…"  // optional, runs before build
  }
}
```

Per library, in order:

1. **Install** — `npm ci` when a `package-lock.json` is committed, otherwise
   `npm install` with a warning.
2. **`verify`**, then **`typecheck`** — skipped silently when not defined. Useful
   for codegen drift checks and lint gates.
3. **`build`** — required. A library without it fails.
4. **`test`** — required to publish. Matching `publish-angular-lib`, a library
   with no test script cannot ship; in `skip_publish` mode it only warns.
5. **`npm publish`** from the **package root**, so `files` and `exports` decide
   what ships. There is no `dist/`-relative publish step like ng-packagr's.

## How change detection works

On a merge to `main`, HEAD is the merge commit, so the action diffs against its
first parent:

- A true merge commit has 2 parents, so `HEAD^1` is the previous tip of `main`
  and `HEAD^1..HEAD` is exactly what the PR introduced.
- A squash or rebase merge has 1 parent, where `HEAD~1` is equivalent.

It then matches `^<workspace_path>/[^/]+/package\.json$` — exactly one level deep,
so nested packages are ignored — and for each match compares `.version` between
the base ref and HEAD. Unchanged versions are skipped with a log line. Changing
code without bumping the version therefore builds and tests but publishes nothing.

`fetch-depth: 0` is required and the workflow sets it.

## Re-publishing manually

Because detection is diff-based, re-running the workflow on an unchanged commit
finds nothing to do. Pass `libraries` to bypass detection:

```yaml
with:
  libraries: in-icon
  skip_publish: false
```

Forced runs skip the version-changed check but still respect the
already-published guard: the action calls `npm view <name>@<version>` first and
skips with a warning if that exact version exists, so a re-run is safe rather
than a hard failure.

## Failure behaviour

Each library is independent. A failure is logged with `::error::`, the loop
continues to the next library, and the step exits non-zero at the end with a
count. One broken library does not prevent the others from publishing.
