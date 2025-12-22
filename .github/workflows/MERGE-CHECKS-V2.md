# Merge Checks Node v2 - Migration Guide

## What's New in v2?

v2 modernizes the merge checks workflow with better tools based on 2025 best practices research.

### Key Improvements

| Category | v1 Tool | v2 Tool | Why? |
|----------|---------|---------|------|
| **Outdated Check** | `npm outdated` | `npm-check-updates` | Active maintenance (Dec 2024), rich filtering, ignore patterns |
| **Security Audit** | `npm audit` | `audit-ci` | CI-native design, allowlists, severity thresholds, JSON config |
| **Actions** | v5.0.0 | v6.1.0 | Latest versions pinned by immutable commit hash |

### Research Sources

- [npm-check-updates](https://www.npmjs.com/package/npm-check-updates) - 611 dependents, published 12 days ago
- [audit-ci](https://www.npmjs.com/package/audit-ci) - 196k weekly downloads, JSON config with schema
- [Research findings](https://github.com/raineorshine/npm-check-updates) - Active GitHub maintenance

## Migration Path

### Option 1: Simple Migration (No Config Changes)

Replace workflow reference:
```yaml
jobs:
  merge-checks:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/merge-checks-node-v2.yml@main
    with:
      allowed_licenses_path: ".github/allowed-licenses.json"
      ignored_packages_path: ".github/ignored-packages.json"
    secrets:
      githubToken: ${{ secrets.GITHUB_TOKEN }}
```

This works immediately with default settings:
- Outdated check targets "latest" versions
- Audit fails on "moderate" severity or higher
- No packages ignored

### Option 2: Configure Ignored Packages

Ignore intentional major version pins:
```yaml
jobs:
  merge-checks:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/merge-checks-node-v2.yml@main
    with:
      allowed_licenses_path: ".github/allowed-licenses.json"
      ignored_packages_path: ".github/ignored-packages.json"

      # NEW v2 parameters
      ignored_outdated_packages: "@types/node,vitest,zod"
      outdated_target: "latest"  # Check all updates, but ignore packages above
    secrets:
      githubToken: ${{ secrets.GITHUB_TOKEN }}
```

### Option 3: Advanced Configuration with audit-ci

For complex allowlists, create `.github/audit-ci.jsonc`:

```jsonc
{
  "$schema": "https://github.com/IBM/audit-ci/raw/main/docs/schema.json",
  "moderate": true,
  "high": true,
  "critical": true,
  "allowlist": [
    // Allowlist specific advisory
    "GHSA-42xw-2xvc-qx8m",

    // Allowlist advisory only for specific dependency path
    "GHSA-rp65-9cf3-cjxr|react-scripts>@svgr/webpack>@svgr/plugin-svgo>svgo>css-select>nth-check",

    // Allowlist all advisories in transitive deps of react-scripts
    "*|react-scripts>*"
  ],
  "package-manager": "npm"
}
```

Then reference it:
```yaml
jobs:
  merge-checks:
    uses: innago-property-management/Oui-DELIVER/.github/workflows/merge-checks-node-v2.yml@main
    with:
      allowed_licenses_path: ".github/allowed-licenses.json"
      ignored_packages_path: ".github/ignored-packages.json"

      # Use custom audit config
      audit_config_path: ".github/audit-ci.jsonc"
    secrets:
      githubToken: ${{ secrets.GITHUB_TOKEN }}
```

## Configuration Parameters

### New v2 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ignored_outdated_packages` | string | `""` | Comma-separated **package names** to ignore (e.g., `"@types/node,vitest,zod"`). Note: Use package names only, NOT version patterns. |
| `outdated_target` | string | `"latest"` | Update level: `latest`, `minor`, `patch`, `@next`, `@beta` |
| `audit_config_path` | string | `""` | Path to audit-ci.jsonc config file (optional) |
| `audit_level` | string | `"moderate"` | Minimum severity to fail: `moderate`, `high`, `critical` |

### Existing v1 Parameters (Unchanged)

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `allowed_licenses_path` | string | Yes | Path to allowed licenses JSON file |
| `ignored_packages_path` | string | Yes | Path to ignored packages JSON file |

## Common Use Cases

### Use Case 1: Pin to Node 20 LTS

Your project targets Node 20 but @types/node v25 is available. Ignore @types/node completely:

```yaml
with:
  ignored_outdated_packages: "@types/node"
  outdated_target: "latest"
```

### Use Case 2: Conservative Updates (Only Patch/Minor)

Only check for patch and minor updates, ignore major version bumps:

```yaml
with:
  ignored_outdated_packages: ""  # Check all packages
  outdated_target: "minor"       # But only fail on minor/patch
```

### Use Case 3: Allowlist Known Vulnerability

You've assessed a vulnerability and want to temporarily allow it:

Create `.github/audit-ci.jsonc`:
```jsonc
{
  "$schema": "https://github.com/IBM/audit-ci/raw/main/docs/schema.json",
  "moderate": true,
  "allowlist": [
    "GHSA-xxxx-yyyy-zzzz"  // Specific advisory ID
  ]
}
```

```yaml
with:
  audit_config_path: ".github/audit-ci.jsonc"
```

### Use Case 4: Strict Security (Critical Only)

Only fail on critical vulnerabilities:

```yaml
with:
  audit_level: "critical"
```

## Troubleshooting

### "npm-check-updates not found"

The workflow uses `npx --yes npm-check-updates` which auto-installs. If this fails, check:
- npm registry access
- Corporate proxy settings
- Node.js version (requires 18.18.0+)

### "audit-ci config file not found"

Ensure `audit_config_path` points to a file that exists:
```bash
ls -la .github/audit-ci.jsonc
```

### "Outdated check fails on pinned major versions"

Add packages to `ignored_outdated_packages` (package names only, no version patterns):
```yaml
ignored_outdated_packages: "@types/node,eslint"
```

Or use `outdated_target: "minor"` to ignore all major updates across all packages.

## Rollback to v1

If you encounter issues, revert to v1:
```yaml
uses: innago-property-management/Oui-DELIVER/.github/workflows/merge-checks-node.yml@main
```

Then file an issue with:
- Error message
- Workflow run URL
- package.json (sanitized)

## Future Enhancements

Planned for v3:
- **Socket.dev integration** - Detect malware, install scripts, typosquatting (beyond CVEs)
- **Knip integration** - Unused dependency detection
- **Configurable reporters** - JSON, SARIF, GitHub Security
- **Monorepo support** - Workspace-aware checking

## Questions?

File an issue in the Oui-DELIVER repository with:
- `[merge-checks-v2]` prefix
- Your use case
- Current behavior vs expected behavior
