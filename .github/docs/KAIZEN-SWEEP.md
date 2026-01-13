# Kaizen Sweep - Automated Codebase Improvement

Kaizen Sweep is a scheduled workflow that proactively finds and fixes small improvements across repositories.

## Architecture (3 Files)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Oui-DELIVER                               │
│                   (Central Workflow Repo)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────┐    ┌───────────────────────────┐  │
│  │ kaizen-sweep-dispatcher  │    │ kaizen-sweep.yml          │  │
│  │                          │    │ (Reusable Workflow)       │  │
│  │ • Runs hourly on cron    │    │                           │  │
│  │ • Picks repos from       │    │ • Claude Code Action      │  │
│  │   config.yml             │    │ • Finds ONE small fix     │  │
│  │ • Triggers workflow IN   │    │ • Creates branch + PR     │  │
│  │   each target repo       │    │                           │  │
│  └────────────┬─────────────┘    └───────────────────────────┘  │
│               │                              ▲                   │
│               │                              │ workflow_call     │
└───────────────┼──────────────────────────────┼───────────────────┘
                │                              │
                │ gh workflow run              │
                ▼                              │
┌─────────────────────────────────────────────────────────────────┐
│                      Target Repository                           │
│               (e.g., Innago.Property, Merlin.API)                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ kaizen-sweep.yml  (copied from kaizen-sweep-caller.yml)  │   │
│  │                                                          │   │
│  │ on: workflow_dispatch                                    │   │
│  │ jobs:                                                    │   │
│  │   uses: Oui-DELIVER/.../kaizen-sweep.yml@main           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Result: Branch + PR created HERE, not in Oui-DELIVER           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## The Flow

```
1. SCHEDULE (Hourly)
   ┌─────────────────┐
   │  Dispatcher     │ ─── Reads config.yml ─── Which repos? What hour?
   └────────┬────────┘
            │
            ▼
2. DISPATCH (Per Repo)
   ┌─────────────────┐
   │  gh workflow    │ ─── Triggers kaizen-sweep.yml IN target repo
   │  run --repo X   │
   └────────┬────────┘
            │
            ▼
3. EXECUTE (In Target Repo Context)
   ┌─────────────────┐
   │  Claude Code    │ ─── Scans codebase
   │  Action         │ ─── Finds improvement
   └────────┬────────┘     (magic strings, dead code, etc.)
            │
            ▼
4. CREATE PR (In Target Repo)
   ┌─────────────────┐
   │  git branch     │ ─── kaizen-sweep/fix-description
   │  git push       │ ─── Push to TARGET repo
   │  gh pr create   │ ─── PR in TARGET repo
   └─────────────────┘
```

## What Claude Looks For

| Pattern | Action |
|---------|--------|
| Magic strings | Extract to constants |
| Dead code | Remove unused functions |
| Inconsistencies | Standardize patterns |
| Debug statements | Remove console.log/WriteLine |
| Typos | Fix spelling in messages |
| Null checks | Simplify redundant checks |

## Key Design Principle

**The workflow runs IN the target repo** - this ensures:
- Branches are created in the right place
- PRs appear in the right repo
- No cross-contamination between repositories

## Enabling Kaizen Sweep in a Repository

1. Copy `kaizen-sweep-caller.yml` to your repo as `.github/workflows/kaizen-sweep.yml`
2. Ensure `ANTHROPIC_API_KEY` secret exists in your repo
3. Add your repo to `.github/kaizen-sweep/config.yml` in Oui-DELIVER

## Files

| File | Location | Purpose |
|------|----------|---------|
| `kaizen-sweep-dispatcher.yml` | Oui-DELIVER | Hourly scheduler |
| `kaizen-sweep.yml` | Oui-DELIVER | Reusable workflow (workflow_call) |
| `kaizen-sweep-caller.yml` | Oui-DELIVER | Template for target repos |
| `config.yml` | Oui-DELIVER/.github/kaizen-sweep/ | Repo schedule config |
| `SKILL.md` | Oui-DELIVER/.github/skills/kaizen-sweep/ | Claude's instructions |
