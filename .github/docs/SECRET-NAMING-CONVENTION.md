# Secret Naming Convention

## Standard: SCREAMING_SNAKE_CASE

All secrets in Oui-DELIVER workflows should use SCREAMING_SNAKE_CASE to match GitHub's built-in conventions.

## Migration Guide

| Current Name | Standard Name | Status |
|--------------|---------------|--------|
| `githubToken` | `GITHUB_TOKEN` | Migrate |
| `cosignKey` | `COSIGN_KEY` | Migrate |
| `cosignPassword` | `COSIGN_PASSWORD` | Migrate |
| `anthropicKey` | `ANTHROPIC_API_KEY` | Migrate |
| `npm_token` | `NPM_TOKEN` | Migrate |

## Rationale

- Matches GitHub's built-in secrets (`GITHUB_TOKEN`, `GITHUB_REPOSITORY`)
- Clearly distinguishes secrets from local variables
- Language-agnostic (works across shell, YAML, etc.)

## Transition Strategy

1. Add new SCREAMING_SNAKE_CASE secrets as aliases
2. Update workflows to prefer new names with fallback
3. Deprecate old names after 90 days
4. Remove old secret references

## Example Fallback Pattern

```yaml
env:
  API_KEY: ${{ secrets.ANTHROPIC_API_KEY || secrets.anthropicKey }}
```
