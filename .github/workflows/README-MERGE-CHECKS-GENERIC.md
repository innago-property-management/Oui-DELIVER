# merge-checks-generic

A reusable workflow for repositories that don't fit Python, Node, Angular, or .NET patterns. Ideal for:
- Shell script collections
- Configuration repositories
- Documentation repos
- Infrastructure-as-code (Terraform, Helm, etc.)
- Mixed-language repos

## Jobs

| Job | Description | Always Runs |
|-----|-------------|-------------|
| `sast` | Static analysis with Semgrep (all languages) | ✅ |
| `secrets` | Secret detection with GitLeaks | ✅ |
| `shellcheck` | Shell script linting | Configurable |

## Usage

### Basic (all defaults)

```yaml
name: merge-checks

on:
  pull_request:
    branches: [main]

jobs:
  merge-checks:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/merge-checks-generic.yml@main
```

### With ShellCheck for scripts/ directory

```yaml
jobs:
  merge-checks:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/merge-checks-generic.yml@main
    with:
      shellcheck_scandir: "./scripts"
      shellcheck_severity: "warning"
```

### Disable ShellCheck (config-only repo)

```yaml
jobs:
  merge-checks:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/merge-checks-generic.yml@main
    with:
      shellcheck_enabled: false
```

## Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `shellcheck_enabled` | boolean | `true` | Enable ShellCheck job |
| `shellcheck_scandir` | string | `.` | Directory to scan for shell scripts |
| `shellcheck_severity` | string | `warning` | Minimum severity: error, warning, info, style |

## Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `githubToken` | No | GitHub token for API access (optional) |
