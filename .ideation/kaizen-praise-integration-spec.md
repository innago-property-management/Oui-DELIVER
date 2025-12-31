# Kaizen-Praise Integration Specification

**Author:** Claude Sonnet 4.5
**Status:** Design Draft
**Last Updated:** December 22, 2024
**Phase:** 2 (Future Enhancement)

---

## Executive Summary

This document specifies the integration between the **kaizen-review system** (which posts improvement suggestions on merged PRs) and the **praise-opportunity system** (which surfaces recognition opportunities to team leads).

**Purpose:** Automatically detect when engineers accept and implement kaizen code improvement suggestions, then surface these as high-value recognition opportunities to their team leads.

**Architecture:** Hybrid approach using Argo Events for event detection and GitHub Actions for classification and execution.

---

## Problem Statement

When engineers accept and implement kaizen suggestions, they demonstrate:
- **Growth mindset** - Openness to improvement feedback
- **Craftsmanship** - Caring about code quality beyond functional requirements
- **Responsiveness** - Acting on feedback promptly

These behaviors are praiseworthy but often go unrecognized because they're subtle and happen asynchronously.

---

## Solution Overview

Detect when engineers accept kaizen suggestions through multiple signal types, calculate confidence scores, and surface high-confidence acceptances as praise opportunities to team leads.

### Design Principles

1. **Signal clarity over volume** - Only surface genuine acceptance, not coincidental changes
2. **Avoid false positives** - Better to miss some acceptances than create noise with false matches
3. **Preserve engineer autonomy** - Accepting kaizen should feel like a choice, not an obligation
4. **Respect timing** - Surface praise when the behavior is fresh (within days, not weeks)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         GitHub Events                             │
│  (pull_request, issue_comment, pull_request_review_comment)      │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                      Argo Events Sensor                           │
│  - Filters for kaizen-related events                              │
│  - Routes to classification workflow                              │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                   GitHub Actions Workflow                         │
│  - Kaizen Acceptance Classifier                                   │
│  - Matches events to previous kaizen suggestions                  │
│  - Calculates confidence score                                    │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ├────────── Confidence < 0.8 → Drop
                         │
                         ├────────── Confidence >= 0.8
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                  Praise Opportunity Storage                       │
│  - S3 + Iceberg (as per praise-opportunity design)                │
│  - Signal type: "kaizen_acceptance"                               │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Teams Notification                             │
│  - To engineer's lead                                             │
│  - Includes: suggestion, implementation, time elapsed             │
└──────────────────────────────────────────────────────────────────┘
```

---

## Kaizen Acceptance Signals

### Signal 1: New PR References Kaizen Comment

**Trigger:** Pull request opened/merged with description or commit message referencing kaizen comment

**Detection Pattern:**
```yaml
Event: pull_request (opened or closed with merged=true)
Filters:
  - PR body contains: "[kaizen]" OR "kaizen" OR "from review: <kaizen_pr_number>"
  - OR Commit messages contain: "[kaizen]" OR "addresses kaizen from #<pr_number>"
```

**Confidence Scoring:**
- **High (0.9)**: PR explicitly references kaizen comment ID or PR number
- **Medium (0.7)**: PR or commit message contains "[kaizen]" prefix
- **Low (0.5)**: PR contains "kaizen" but no explicit reference

---

### Signal 2: Follow-up Commit in Same PR

**Trigger:** New commit pushed to PR after kaizen comment posted

**Detection Pattern:**
```yaml
Event: push
Filters:
  - Branch matches open PR
  - Commit timestamp > kaizen comment timestamp on that PR
  - Commit message contains: "[kaizen]" OR "kaizen" OR matches suggestion pattern
```

**Confidence Scoring:**
- **High (0.95)**: Commit message explicitly says "[kaizen]" + describes same change as suggestion
- **Medium (0.6)**: Commit changes overlap with kaizen suggestion (file/line proximity)
- **Low (0.3)**: Commit in same PR after kaizen comment, but no explicit reference

**Example Scenario:**
```
PR #123 opened
  ├─ Kaizen bot posts comment: "Extract retry constants (lines 45-52)"
  ├─ Engineer pushes new commit: "[kaizen] Extract RETRY_DELAY constants"
  └─ Signal detected: kaizen_acceptance (confidence: 0.95)
```

---

### Signal 3: Comment Reaction (Thumbs Up on Kaizen Comment)

**Trigger:** Engineer reacts with 👍 to kaizen comment

**Confidence Scoring:**
- **Low (0.4)**: Reaction alone (acknowledgment, not necessarily implementation)
- **Medium (0.7)**: Reaction + subsequent commit in same PR
- **High (0.9)**: Reaction + new PR explicitly implementing suggestion

**Why Low Confidence Alone:**
- 👍 may mean "I see this" not "I'll implement this"
- Don't want to praise for intent without follow-through
- Use as qualifier for other signals

---

### Signal 4: Engineer Comment Acknowledging Intent

**Trigger:** Engineer replies to kaizen comment indicating they'll implement it

**Confidence Scoring:**
- **Low (0.3)**: Acknowledgment only ("good idea, will consider")
- **Medium (0.6)**: Commitment + timeline ("I'll do this in next PR")
- **High (0.95)**: Completion claim ("fixed in #456" + verified PR exists)

**NLP Pattern Matching:**
```python
ACKNOWLEDGMENT_PATTERNS = [r'\b(good|great|right|agree|yes|ok|sure)\b']
COMMITMENT_PATTERNS = [r"\b(i'll|will|going to|plan to|next pr)\b"]
COMPLETION_PATTERNS = [r'\b(done|fixed|implemented|completed)\b', r'\bin #\d+\b']
```

---

## Signal Aggregation & Confidence Calculation

### Aggregation Rules

| Signal Combination | Final Confidence | Action |
|--------------------|------------------|--------|
| New PR + explicit reference | 0.95 | Real-time notification |
| Follow-up commit + [kaizen] prefix | 0.95 | Real-time notification |
| Reaction + commit in same PR | 0.7 | Daily digest |
| Comment commitment + later PR | 0.8 | Real-time notification |
| Reaction only | 0.4 | No notification |
| Comment acknowledgment only | 0.3 | No notification |

### Confidence Threshold for Praise Surfacing

- **High threshold (0.8+)**: Surface immediately as real-time praise opportunity
- **Medium threshold (0.6-0.79)**: Include in daily digest
- **Low threshold (<0.6)**: Store for analytics, don't surface to leads

**Rationale:**
- Leads have limited attention; only surface high-signal opportunities
- False positives erode trust in the system
- Engineers shouldn't feel surveilled for every minor action

### Time Decay Factor

Older acceptances are less praiseworthy (feedback loops work best when timely).

```python
def apply_time_decay(confidence: float, days_elapsed: int) -> float:
    """Apply exponential decay to confidence based on time since suggestion."""
    HALF_LIFE_DAYS = 14  # Confidence halves every 2 weeks
    decay_factor = 0.5 ** (days_elapsed / HALF_LIFE_DAYS)
    return confidence * decay_factor

# Example:
# Day 1: 0.9 confidence -> 0.9 * 0.95 = 0.855 (still high)
# Day 7: 0.9 confidence -> 0.9 * 0.76 = 0.684 (medium)
# Day 14: 0.9 confidence -> 0.9 * 0.5 = 0.45 (low, don't surface)
```

---

## Implementation Architecture

### Argo Events Configuration

**EventSource: GitHub Kaizen Events**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: github-kaizen-events
  namespace: praise-system
spec:
  github:
    kaizen-acceptance-events:
      owner: "innago-property-management"
      repository: "*"  # Org-wide
      webhook:
        endpoint: /github/kaizen
        port: "12001"
      events:
        - pull_request
        - push
        - issue_comment
        - pull_request_review_comment
```

**Sensor: Kaizen Acceptance Classifier**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: kaizen-acceptance-classifier
  namespace: praise-system
spec:
  triggers:
    - template:
        name: classify-kaizen-acceptance
        github:
          eventType: kaizen-acceptance-event
          # Dispatch to GitHub Actions workflow
```

**Why GitHub Actions?**
- Native GitHub API access for fetching kaizen comments
- Easier to test/iterate than Argo sensor logic
- Can leverage Claude Code Action for semantic analysis

---

### GitHub Actions Workflow

**Workflow: `.github/workflows/kaizen-acceptance-classifier.yml`**

```yaml
name: Kaizen Acceptance Classifier

on:
  repository_dispatch:
    types: [kaizen-acceptance-event]

permissions:
  contents: read
  pull-requests: read
  issues: read

jobs:
  classify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install PyGithub anthropic pydantic

      - name: Run classification logic
        id: classify
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          EVENT_PAYLOAD: ${{ toJson(github.event.client_payload) }}
        run: python .github/scripts/classify_kaizen_acceptance.py

      - name: Post to Praise System
        if: steps.classify.outputs.confidence >= 0.8
        env:
          PRAISE_API_URL: ${{ secrets.PRAISE_API_URL }}
          PRAISE_API_KEY: ${{ secrets.PRAISE_API_KEY }}
        run: |
          curl -X POST "$PRAISE_API_URL/opportunities" \
            -H "x-api-key: $PRAISE_API_KEY" \
            -H "Content-Type: application/json" \
            -d @${{ steps.classify.outputs.praise_payload_file }}
```

---

## Praise Opportunity Payload

### Signal Type: `kaizen_acceptance`

```json
{
  "id": "kaizen-123-987654",
  "timestamp": "2024-12-22T15:30:00Z",
  "engineer": "engineer_a",
  "engineer_team": "Platform",
  "lead": "lead_x",
  "repo": "payment-service",
  "pr_number": 123,
  "event_type": "kaizen_acceptance",
  "signals": [{
    "type": "kaizen_acceptance",
    "detail": "Implemented kaizen suggestion: Extract retry constants (12.5 hours after suggestion)",
    "strength": "high",
    "target_engineer": "engineer_a"
  }],
  "raw_event": {
    "suggestion": {
      "comment_id": 987654,
      "improvement": "Extract retry delay constants...",
      "suggested_at": "2024-12-22T03:00:00Z"
    },
    "signals": [{
      "type": "follow_up_commit_explicit",
      "confidence": 0.95,
      "evidence": {
        "commit_sha": "abc123",
        "commit_message": "[kaizen] Extract RETRY_DELAY_MS constants",
        "hours_after_suggestion": 12.5
      }
    }],
    "final_confidence": 0.88
  }
}
```

---

## False Positive Avoidance

### Common Scenarios

| Scenario | Risk | Mitigation |
|----------|------|------------|
| Engineer makes similar change coincidentally | Medium | Require explicit reference or [kaizen] marker |
| Engineer was already planning the change | Medium | Time decay reduces stale suggestions |
| Copy-paste from another PR | Low | Check contextual appropriateness |
| Automated refactoring tool | Low | Verify human-authored commit messages |

### Confidence Calibration

Track dismiss rate to tune thresholds:

```sql
SELECT
    signal_type,
    COUNT(*) as surfaced,
    COUNT_IF(lead_action = 'dismissed') as dismissed,
    ROUND(dismissed / surfaced * 100, 1) as dismiss_rate_pct
FROM praise_opportunities
WHERE event_type = 'kaizen_acceptance'
GROUP BY signal_type;
```

**Threshold adjustment:**
- If dismiss rate >30%, increase confidence threshold
- If dismiss rate <10%, consider lowering threshold

---

## Example Scenarios

### Scenario 1: HIGH CONFIDENCE (0.91)

**Timeline:**
1. PR #123 opened by `engineer_a`
2. Kaizen bot posts comment: "[kaizen] Extract retry constants (lines 45-52)"
3. 8 hours later: `engineer_a` pushes commit: "[kaizen] Extract RETRY_DELAY_MS constants"

**Detection:**
- Signal: `follow_up_commit_explicit`
- Raw confidence: 0.95
- Time elapsed: 8 hours
- Time decay factor: 0.96
- Final confidence: 0.95 × 0.96 = 0.91 (HIGH)

**Outcome:** Real-time notification to lead

---

### Scenario 2: MEDIUM CONFIDENCE (0.525)

**Timeline:**
1. PR #123 merged with kaizen comment
2. 3 days later: `engineer_a` opens PR #456 titled "Refactor retry logic"
3. PR description: "Improves retry handling as suggested in review"

**Detection:**
- Signal: `new_pr_implicit_reference`
- Raw confidence: 0.7
- Time elapsed: 72 hours
- Time decay factor: 0.75
- Final confidence: 0.7 × 0.75 = 0.525 (BELOW THRESHOLD)

**Outcome:** Not surfaced, stored for analytics

---

### Scenario 3: FALSE POSITIVE AVOIDED

**Timeline:**
1. PR #123 with kaizen comment: "Extract constants"
2. PR #456 by different engineer extracts constants in unrelated file

**Detection:**
- No "[kaizen]" prefix detected
- No explicit #123 reference
- Confidence: 0 (no signals)

**Outcome:** System correctly ignores coincidental change

---

## Success Criteria

### Technical Success

| Metric | Target | Measurement |
|--------|--------|-------------|
| False positive rate | <20% | % of surfaced opportunities dismissed by leads |
| Detection coverage | >60% | % of actual kaizen acceptances detected |
| Latency | <10 minutes | Time from acceptance event to notification |
| Uptime | >99.5% | Argo Events + GitHub Actions availability |

### Behavioral Impact

| Metric | Target | Measurement |
|--------|--------|-------------|
| Kaizen acceptance rate | +10% | % of kaizen suggestions implemented |
| Time to acceptance | -20% | Median hours from suggestion to implementation |
| Engineer sentiment | Neutral/Positive | Pulse survey on code quality recognition |

### Lead Engagement

| Metric | Target | Measurement |
|--------|--------|-------------|
| Lead action rate | >50% | % of notifications that get praised or dismissed |
| Praise delivery rate | >70% | % of notifications marked "praised" vs "dismissed" |
| Time to response | <24 hours | Median time from notification to lead action |

---

## Implementation Phases

### Phase 1: MVP (Current - Kaizen Review Only)
- ✅ Kaizen-review skill created
- ✅ GitHub Actions workflows created
- ✅ Comment-only implementation (no automatic commits)
- ✅ "Silence is success" pattern implemented

### Phase 2: Praise Integration (Future - 2-3 months)
- [ ] Deploy Argo Events EventSource & Sensor
- [ ] Create GitHub Actions classifier workflow
- [ ] Implement 4 signal detection types
- [ ] Basic confidence scoring & time decay
- [ ] POST to Praise API

### Phase 3: Enhanced Classification (Future - 4-6 months)
- [ ] Claude-based semantic matching for implicit acceptance
- [ ] Historical pattern analysis (engineer receptivity)
- [ ] Multi-PR tracking
- [ ] Lead feedback integration
- [ ] A/B testing confidence thresholds

### Phase 4: Gamification (Future - 7+ months)
- [ ] Kaizen acceptance leaderboard (opt-in)
- [ ] "Kaizen champion" badges
- [ ] Team-level dashboards

---

## Open Questions

### Q1: Kaizen Bot Identity
**Decision needed:** What is the exact GitHub username for kaizen bot?
- `github-actions[bot]`?
- Custom bot account?

### Q2: Cross-Repo Tracking
**Question:** Should we detect when kaizen in repo A is implemented in repo B?
**Recommendation:** Start single-repo, add cross-repo in Phase 3

### Q3: Comment Format Standardization
**Question:** Should kaizen comments follow structured format for easier parsing?
**Recommendation:** Start freeform, add optional structured format in Phase 3

### Q4: Notification Routing
**Question:** Should ALL acceptances (≥0.8) go real-time, or some to daily digest?
**Recommendation:** 0.9+ real-time, 0.8-0.89 daily digest

### Q5: Engineer Opt-Out
**Question:** Should engineers be able to opt out of tracking?
**Recommendation:** No opt-out for Phase 2, add in Phase 3 if requested

---

## Related Systems

### Kaizen-Review System
- **Location:** `.ideation/kaizen-review-prompt.md`
- **Purpose:** Post improvement suggestions on merged PRs
- **Integration point:** Kaizen comments are source signals for this system

### Kaizen-Sweep System
- **Location:** `.ideation/kaizen-sweep-prompt.md`
- **Purpose:** Scheduled maintainability reviews of legacy code
- **Integration point:** Similar acceptance detection logic applies

### Praise-Opportunity System
- **Location:** `.ideation/praise-opportunity-system-design.md`
- **Purpose:** Surface recognition opportunities to team leads
- **Integration point:** Kaizen acceptance is one signal type among many

---

## References

- [Argo Events Documentation](https://argoproj.github.io/argo-events/)
- [GitHub Webhooks Reference](https://docs.github.com/webhooks)
- [PyGithub Library](https://pygithub.readthedocs.io/)
- [Anthropic Claude API](https://docs.anthropic.com/)

---

**Status:** This is a Phase 2 design document. Phase 1 (kaizen-review only) is implemented and ready for deployment.
