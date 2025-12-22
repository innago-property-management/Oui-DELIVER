# Praise Opportunity Surfacing System

## Design Document

**Author:** Chris Anderson  
**Status:** Draft  
**Last Updated:** December 2024

---

## Overview

This system automatically identifies praiseworthy engineering behaviors from GitHub activity and surfaces them to team leads, enabling timely, specific affirmation of team members.

### Problem Statement

Leaders know they should recognize good work, but:

- They're not present for every contribution
- Praiseworthy behaviors often go unnoticed in the noise of daily commits
- Generic recognition ("good job this sprint") lacks the specificity that makes affirmation meaningful

### Solution

Capture GitHub events, classify them for praise-worthy signals, store in low-cost Iceberg tables, and notify leads with actionable prompts they can personalize.

### Design Principles

1. **The system surfaces opportunities — humans deliver praise.** Automation identifies; leads personalize.
2. **Specificity over volume.** One high-quality signal beats five weak ones.
3. **Low operational cost.** Write-once, read-rarely pattern favors S3 + Iceberg over traditional warehousing.

---

## Architecture

```
┌─────────────────┐
│  GitHub Events  │
│  (webhooks)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Argo Events    │
│  (ingestion)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Enrichment     │
│  Lambda/Container│
│  (classification)│
└────────┬────────┘
         │
         ├──────────────────────┐
         ▼                      ▼
┌─────────────────┐    ┌─────────────────┐
│  S3 Bucket      │    │  Teams Webhook  │
│  (Iceberg)      │    │  (notifications)│
└────────┬────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐
│  Snowflake      │
│  (external tbl) │
│  (analytics)    │
└─────────────────┘
```

---

## GitHub Events

### Events to Capture

| Event | Webhook Type | Primary Use |
|-------|--------------|-------------|
| PR merged | `pull_request.closed` (merged=true) | Most praise signals |
| Review submitted | `pull_request_review` | Reviewer recognition |
| Review comment | `pull_request_review_comment` | Substantive feedback |
| Check run completed | `check_run.completed` | CI health patterns |
| Push | `push` | Co-author detection |

### Webhook Configuration

```yaml
# Argo Events EventSource
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: github-praise-events
spec:
  github:
    praise-webhook:
      owner: "innago"
      repository: "*"  # Org-wide
      webhook:
        endpoint: /github/praise
        port: "12000"
        method: POST
      events:
        - pull_request
        - pull_request_review
        - pull_request_review_comment
        - push
        - check_run
      apiToken:
        name: github-token
        key: token
      webhookSecret:
        name: github-webhook-secret
        key: secret
```

---

## Praise Signal Classification

### Signal Types

| Signal | Trigger | Strength Criteria |
|--------|---------|-------------------|
| `complexity_reduction` | Lines deleted > lines added | High: >200 deleted; Medium: >50 |
| `test_coverage` | Coverage delta positive | High: >5%; Medium: >2% |
| `cross_team_contribution` | Author team ≠ repo owner team | Medium (always) |
| `quality_review` | Review with comments, fast turnaround | High: <4h + >2 comments |
| `mentorship` | Co-authored commits | Medium (always) |
| `documentation` | Docs added alongside code | Medium: >100 words |
| `first_contribution` | First PR to repo | High (always) |
| `sustained_consistency` | N consecutive clean PRs | High: 10+; Medium: 5+ |

### Classification Logic

```python
from dataclasses import dataclass
from typing import Optional
from enum import Enum

class SignalStrength(Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"

@dataclass
class PraiseSignal:
    type: str
    detail: str
    strength: SignalStrength
    target_engineer: Optional[str] = None  # If different from PR author

@dataclass
class PraiseOpportunity:
    id: str
    timestamp: str
    engineer: str
    engineer_team: str
    lead: str
    repo: str
    pr_number: int
    event_type: str
    signals: list[PraiseSignal]
    raw_event: dict

def classify_pr_merged(event: dict) -> Optional[PraiseOpportunity]:
    """Classify a merged PR for praise signals."""
    signals = []
    
    lines_added = event.get("additions", 0)
    lines_deleted = event.get("deletions", 0)
    
    # Complexity reduction
    if lines_deleted > lines_added and lines_deleted > 50:
        strength = SignalStrength.HIGH if lines_deleted > 200 else SignalStrength.MEDIUM
        signals.append(PraiseSignal(
            type="complexity_reduction",
            detail=f"Deleted {lines_deleted} lines while adding {lines_added}",
            strength=strength
        ))
    
    # Test coverage improvement
    coverage_delta = get_coverage_delta(event)
    if coverage_delta and coverage_delta > 2:
        strength = SignalStrength.HIGH if coverage_delta > 5 else SignalStrength.MEDIUM
        signals.append(PraiseSignal(
            type="test_coverage",
            detail=f"Coverage increased by {coverage_delta:.1f}%",
            strength=strength
        ))
    
    # Cross-team contribution
    author_team = lookup_team(event["user"]["login"])
    repo_team = lookup_repo_owner_team(event["repository"]["full_name"])
    if author_team and repo_team and author_team != repo_team:
        signals.append(PraiseSignal(
            type="cross_team_contribution",
            detail=f"{author_team} engineer contributing to {repo_team} codebase",
            strength=SignalStrength.MEDIUM
        ))
    
    # First contribution to repo
    if is_first_contribution(event["user"]["login"], event["repository"]["full_name"]):
        signals.append(PraiseSignal(
            type="first_contribution",
            detail=f"First contribution to {event['repository']['name']}",
            strength=SignalStrength.HIGH
        ))
    
    # Quality reviews (praise the reviewers, not author)
    for review in get_reviews(event["number"]):
        turnaround = calculate_turnaround_hours(event["created_at"], review["submitted_at"])
        comment_count = review.get("comment_count", 0)
        
        if turnaround < 4 and comment_count > 2:
            signals.append(PraiseSignal(
                type="quality_review",
                detail=f"Thorough review ({comment_count} comments) in {turnaround:.1f} hours",
                strength=SignalStrength.HIGH,
                target_engineer=review["user"]["login"]
            ))
    
    # Co-authored commits (mentorship signal)
    coauthors = extract_coauthors(event)
    if coauthors:
        for coauthor in coauthors:
            signals.append(PraiseSignal(
                type="mentorship",
                detail=f"Paired with {coauthor} on this work",
                strength=SignalStrength.MEDIUM,
                target_engineer=coauthor
            ))
    
    if not signals:
        return None
    
    author = event["user"]["login"]
    return PraiseOpportunity(
        id=generate_id(),
        timestamp=event["merged_at"],
        engineer=author,
        engineer_team=author_team,
        lead=lookup_lead(author),
        repo=event["repository"]["name"],
        pr_number=event["number"],
        event_type="pr.merged",
        signals=signals,
        raw_event=event
    )

def extract_coauthors(event: dict) -> list[str]:
    """Extract co-authors from commit trailers."""
    coauthors = []
    for commit in event.get("commits", []):
        message = commit.get("message", "")
        for line in message.split("\n"):
            if line.lower().startswith("co-authored-by:"):
                # Extract email/name from trailer
                coauthors.append(parse_coauthor(line))
    return coauthors
```

### Future Enhancement: Claude Classification

For subjective signals that heuristics can't capture:

```python
CLAUDE_CLASSIFICATION_PROMPT = """
Review this PR for praiseworthy behaviors beyond what metrics can capture:

Title: {title}
Description: {body}
Files changed: {files}
Commit messages: {commits}

Look for:
- Exceptionally clear PR description
- Commit messages that tell a coherent story
- Proactive documentation
- Evidence of careful design thinking
- Going above and beyond the requirements

If you identify a praiseworthy behavior, respond with:
{{"signal": "<brief description>", "strength": "high|medium", "reasoning": "<why this matters>"}}

If nothing stands out, respond with:
{{"signal": null}}
"""

async def claude_classify(event: dict) -> Optional[PraiseSignal]:
    """Use Claude for subjective signal detection."""
    response = await anthropic.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=200,
        messages=[{
            "role": "user",
            "content": CLAUDE_CLASSIFICATION_PROMPT.format(
                title=event["title"],
                body=event["body"],
                files=event["changed_files"],
                commits=format_commits(event)
            )
        }]
    )
    
    result = json.loads(response.content[0].text)
    if result.get("signal"):
        return PraiseSignal(
            type="claude_detected",
            detail=result["signal"],
            strength=SignalStrength(result["strength"])
        )
    return None
```

---

## Storage Layer

### Why Iceberg on S3

- **Write-once, read-rarely pattern**: Events written once, queried 3-5 times
- **Cost optimization**: S3 storage costs << Snowflake compute for ingestion
- **Schema evolution**: Iceberg handles schema changes gracefully
- **Time travel**: Debug and audit historical classifications

### S3 Bucket Structure

```
s3://innago-praise-events/
├── opportunities/
│   ├── engineer_team=AI-BI-Marketing/
│   │   └── dt=2024-12-19/
│   │       └── data-00001.parquet
│   ├── engineer_team=DevKit/
│   │   └── dt=2024-12-19/
│   │       └── data-00001.parquet
│   └── ...
├── raw_events/
│   └── dt=2024-12-19/
│       └── github-events-00001.json
└── metadata/
    └── opportunities/
        └── v1.metadata.json
```

### Iceberg Table Schema

```sql
CREATE TABLE praise_opportunities (
    -- Identity
    id STRING NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    
    -- People
    engineer STRING NOT NULL,
    engineer_team STRING,
    lead STRING,
    
    -- Context
    repo STRING NOT NULL,
    pr_number INT,
    event_type STRING NOT NULL,
    
    -- Signals (nested structure)
    signals ARRAY<STRUCT<
        type STRING,
        detail STRING,
        strength STRING,
        target_engineer STRING
    >> NOT NULL,
    
    -- Lead response tracking
    notification_sent BOOLEAN DEFAULT FALSE,
    notification_sent_at TIMESTAMP,
    lead_action STRING,  -- 'praised', 'dismissed', 'pending', NULL
    lead_action_at TIMESTAMP,
    
    -- Debugging
    raw_event VARIANT
)
PARTITIONED BY (DATE(timestamp), engineer_team)
LOCATION 's3://innago-praise-events/opportunities/'
TBLPROPERTIES (
    'table_type' = 'ICEBERG',
    'format-version' = '2'
);
```

### Snowflake External Table Setup

```sql
-- 1. Create catalog integration
CREATE OR REPLACE CATALOG INTEGRATION praise_catalog
    CATALOG_SOURCE = OBJECT_STORE
    TABLE_FORMAT = ICEBERG
    ENABLED = TRUE;

-- 2. Create external volume
CREATE OR REPLACE EXTERNAL VOLUME praise_volume
    STORAGE_LOCATIONS = (
        (
            NAME = 'praise-s3-location'
            STORAGE_PROVIDER = 'S3'
            STORAGE_BASE_URL = 's3://innago-praise-events/'
            STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::ACCOUNT_ID:role/SnowflakePraiseRole'
            STORAGE_AWS_EXTERNAL_ID = 'innago_praise_external_id'
        )
    );

-- 3. Create Iceberg table reference
CREATE OR REPLACE ICEBERG TABLE praise_db.public.praise_opportunities
    EXTERNAL_VOLUME = 'praise_volume'
    CATALOG = 'praise_catalog'
    CATALOG_TABLE_NAME = 'opportunities';

-- 4. Grant access
GRANT SELECT ON TABLE praise_db.public.praise_opportunities TO ROLE analytics_role;
GRANT SELECT ON TABLE praise_db.public.praise_opportunities TO ROLE lead_role;
```

### IAM Role Configuration

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::innago-praise-events",
                "arn:aws:s3:::innago-praise-events/*"
            ]
        }
    ]
}
```

Trust policy for Snowflake:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::SNOWFLAKE_ACCOUNT:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "innago_praise_external_id"
                }
            }
        }
    ]
}
```

---

## Notification Layer

### Teams Adaptive Card

```python
import requests
from typing import Optional

TEAMS_WEBHOOK_URL = "https://outlook.office.com/webhook/..."

def send_praise_notification(opportunity: PraiseOpportunity) -> bool:
    """Send Teams notification to lead."""
    
    # Filter to high/medium signals only
    notable_signals = [s for s in opportunity.signals if s.strength != SignalStrength.LOW]
    if not notable_signals:
        return False
    
    # Pick the strongest signal for the headline
    top_signal = max(notable_signals, key=lambda s: 0 if s.strength == SignalStrength.MEDIUM else 1)
    
    # Build signal list for card
    signal_text = "\n".join([f"• {s.detail}" for s in notable_signals[:3]])
    
    card = {
        "type": "message",
        "attachments": [{
            "contentType": "application/vnd.microsoft.card.adaptive",
            "content": {
                "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                "type": "AdaptiveCard",
                "version": "1.4",
                "body": [
                    {
                        "type": "TextBlock",
                        "size": "medium",
                        "weight": "bolder",
                        "text": f"🌟 Praise opportunity: {opportunity.engineer}",
                        "wrap": True
                    },
                    {
                        "type": "TextBlock",
                        "text": signal_text,
                        "wrap": True
                    },
                    {
                        "type": "ColumnSet",
                        "columns": [
                            {
                                "type": "Column",
                                "items": [{
                                    "type": "TextBlock",
                                    "text": f"📁 {opportunity.repo}",
                                    "size": "small",
                                    "isSubtle": True
                                }]
                            },
                            {
                                "type": "Column",
                                "items": [{
                                    "type": "TextBlock",
                                    "text": f"PR #{opportunity.pr_number}",
                                    "size": "small",
                                    "isSubtle": True
                                }]
                            }
                        ]
                    }
                ],
                "actions": [
                    {
                        "type": "Action.OpenUrl",
                        "title": "View PR",
                        "url": f"https://github.com/innago/{opportunity.repo}/pull/{opportunity.pr_number}"
                    },
                    {
                        "type": "Action.Http",
                        "title": "✓ I praised them",
                        "method": "POST",
                        "url": "https://api.innago.com/praise/action",
                        "body": f'{{"id": "{opportunity.id}", "action": "praised"}}'
                    },
                    {
                        "type": "Action.Http",
                        "title": "Dismiss",
                        "method": "POST",
                        "url": "https://api.innago.com/praise/action",
                        "body": f'{{"id": "{opportunity.id}", "action": "dismissed"}}'
                    }
                ]
            }
        }]
    }
    
    response = requests.post(TEAMS_WEBHOOK_URL, json=card, timeout=10)
    return response.status_code == 200
```

### Notification Modes

| Mode | Frequency | Use Case |
|------|-----------|----------|
| Real-time | On event | High-signal opportunities (first contribution, major refactor) |
| Daily digest | 9 AM local | Batch of medium-signal opportunities |
| Weekly summary | Monday AM | Trends, engineers without recent recognition |

### Digest Template

```python
def build_weekly_digest(lead: str, opportunities: list[PraiseOpportunity]) -> dict:
    """Build weekly digest for a lead."""
    
    by_engineer = defaultdict(list)
    for opp in opportunities:
        by_engineer[opp.engineer].append(opp)
    
    sections = []
    for engineer, opps in sorted(by_engineer.items(), key=lambda x: -len(x[1])):
        signals = [s.detail for o in opps for s in o.signals][:3]
        sections.append({
            "type": "Container",
            "items": [
                {
                    "type": "TextBlock",
                    "text": f"**{engineer}** ({len(opps)} opportunities)",
                    "wrap": True
                },
                {
                    "type": "TextBlock",
                    "text": "\n".join([f"• {s}" for s in signals]),
                    "size": "small",
                    "wrap": True
                }
            ]
        })
    
    return {
        "type": "AdaptiveCard",
        "body": [
            {
                "type": "TextBlock",
                "size": "large",
                "weight": "bolder",
                "text": f"Weekly Praise Summary"
            },
            {
                "type": "TextBlock",
                "text": f"{len(opportunities)} opportunities across {len(by_engineer)} engineers",
                "isSubtle": True
            },
            *sections
        ]
    }
```

---

## Analytics Queries

### Lead Effectiveness

```sql
-- Praise rate by lead (are they acting on opportunities?)
SELECT 
    lead,
    COUNT(*) as opportunities,
    COUNT_IF(lead_action = 'praised') as praised,
    COUNT_IF(lead_action = 'dismissed') as dismissed,
    COUNT_IF(lead_action IS NULL) as pending,
    ROUND(praised / NULLIF(opportunities, 0) * 100, 1) as praise_rate_pct,
    AVG(DATEDIFF('hour', notification_sent_at, lead_action_at)) as avg_response_hours
FROM praise_opportunities
WHERE timestamp > DATEADD(month, -1, CURRENT_TIMESTAMP)
    AND notification_sent = TRUE
GROUP BY lead
ORDER BY opportunities DESC;
```

### Signal Effectiveness

```sql
-- Which signals lead to actual praise vs dismissal?
SELECT 
    s.value:type::STRING as signal_type,
    COUNT(*) as occurrences,
    COUNT_IF(p.lead_action = 'praised') as led_to_praise,
    COUNT_IF(p.lead_action = 'dismissed') as dismissed,
    ROUND(led_to_praise / NULLIF(occurrences, 0) * 100, 1) as praise_rate_pct
FROM praise_opportunities p,
    LATERAL FLATTEN(input => p.signals) s
WHERE p.timestamp > DATEADD(month, -3, CURRENT_TIMESTAMP)
    AND p.lead_action IS NOT NULL
GROUP BY signal_type
ORDER BY occurrences DESC;
```

### Recognition Coverage

```sql
-- Engineers who aren't getting surfaced (may need different signals)
WITH engineer_opportunities AS (
    SELECT 
        engineer,
        engineer_team,
        COUNT(*) as opportunities_90d,
        COUNT_IF(lead_action = 'praised') as praised_90d
    FROM praise_opportunities
    WHERE timestamp > DATEADD(day, -90, CURRENT_TIMESTAMP)
    GROUP BY engineer, engineer_team
)
SELECT 
    e.name as engineer,
    e.team,
    COALESCE(eo.opportunities_90d, 0) as opportunities,
    COALESCE(eo.praised_90d, 0) as praised
FROM employees e
LEFT JOIN engineer_opportunities eo ON e.github_username = eo.engineer
WHERE e.role = 'engineer'
ORDER BY opportunities ASC, praised ASC;
```

### Team Trends

```sql
-- Team-level recognition trends over time
SELECT 
    DATE_TRUNC('week', timestamp) as week,
    engineer_team,
    COUNT(*) as opportunities,
    COUNT_IF(lead_action = 'praised') as praised,
    COUNT(DISTINCT engineer) as unique_engineers
FROM praise_opportunities
WHERE timestamp > DATEADD(month, -6, CURRENT_TIMESTAMP)
GROUP BY week, engineer_team
ORDER BY week DESC, engineer_team;
```

---

## Operational Considerations

### Noise Control

| Problem | Mitigation |
|---------|------------|
| Too many notifications | Aggregate to daily digest; raise signal thresholds |
| Same engineer surfaced repeatedly | Rate limit per engineer per week |
| Low-value signals | Track dismiss rate; deprecate signals with >70% dismiss |
| Leads ignoring notifications | Escalate to skip-level or remove from routing |

### Configuration Tuning

```yaml
# config/praise-thresholds.yaml
signals:
  complexity_reduction:
    min_lines_deleted: 50
    high_threshold: 200
    
  test_coverage:
    min_delta_pct: 2.0
    high_threshold_pct: 5.0
    
  quality_review:
    max_turnaround_hours: 4
    min_comments: 2

notifications:
  realtime:
    min_strength: high
    
  digest:
    min_strength: medium
    send_time: "09:00"
    timezone: "America/New_York"
    
  weekly:
    send_day: monday
    send_time: "09:00"

rate_limits:
  per_engineer_per_week: 3
  per_lead_per_day: 10
```

### Monitoring

```sql
-- Alert if no opportunities generated in 24h (system health check)
SELECT 
    CASE 
        WHEN MAX(timestamp) < DATEADD(hour, -24, CURRENT_TIMESTAMP) 
        THEN 'ALERT: No praise opportunities in 24h'
        ELSE 'OK'
    END as status,
    MAX(timestamp) as last_opportunity
FROM praise_opportunities;
```

---

## Implementation Phases

### Phase 1: MVP (Week 1-2)

- [ ] GitHub webhook ingestion via Argo Events
- [ ] Basic classification (complexity_reduction, test_coverage)
- [ ] S3 + Iceberg storage
- [ ] Teams notification (real-time only)
- [ ] Manual Snowflake queries

### Phase 2: Full Classification (Week 3-4)

- [ ] All signal types implemented
- [ ] Lead lookup from HR system
- [ ] Daily digest mode
- [ ] Lead action tracking (praised/dismissed)

### Phase 3: Analytics (Week 5-6)

- [ ] Snowflake external table setup
- [ ] Dashboard for recognition coverage
- [ ] Signal effectiveness tracking
- [ ] Threshold tuning based on dismiss rates

### Phase 4: Enhancement (Ongoing)

- [ ] Claude classification for subjective signals
- [ ] Weekly summary reports
- [ ] Slack integration (in addition to Teams)
- [ ] Manager skip-level visibility

---

## Open Questions

1. **Lead assignment**: How do we map engineers to leads? HR system API, static config, or GitHub CODEOWNERS?

2. **Cross-team praise**: When an engineer contributes to another team's repo, does their lead get notified, the repo owner's lead, or both?

3. **Contractor/vendor handling**: Should Taazaa engineers be included in the same praise flow?

4. **Privacy**: Are engineers notified that their activity is being analyzed? Opt-out mechanism?

5. **Gaming prevention**: Could engineers artificially trigger signals? Does it matter if the underlying behavior is still good?

---

## Measurement & Experimentation

### Hypothesis

Engineers who receive specific, timely affirmation will exhibit increased frequency of the praised behaviors compared to engineers who do not receive affirmation for equivalent behaviors.

### Study Design

#### Randomized Controlled Experiment

When a praise opportunity is generated, randomly assign to one of two groups:

| Group | Treatment | Purpose |
|-------|-----------|---------|
| **Treatment** | Lead notified as normal | Measure effect of praise system |
| **Control** | Notification suppressed | Baseline behavior trajectory |

Assignment ratio: 70/30 (treatment/control) to maximize system value while maintaining statistical power.

```python
import random

def should_notify(opportunity: PraiseOpportunity) -> tuple[bool, str]:
    """Randomly assign to treatment or control group."""
    
    # Consistent assignment per engineer+signal to avoid mixed signals
    assignment_key = f"{opportunity.engineer}:{opportunity.signals[0].type}"
    random.seed(hash(assignment_key))
    
    if random.random() < 0.70:
        return True, "treatment"
    else:
        return False, "control"
```

#### Extended Schema for Experimentation

```sql
ALTER TABLE praise_opportunities ADD COLUMN experiment_group STRING;  -- 'treatment', 'control'
ALTER TABLE praise_opportunities ADD COLUMN experiment_id STRING;     -- Links related observations
```

### Metrics Framework

#### Primary Metrics (Behavior Change)

For each signal type, measure behavior frequency in windows before and after the praise event:

| Window | Definition |
|--------|------------|
| Pre-period | 90 days before first praise opportunity |
| Post-period | 90 days after praise delivered (treatment) or suppressed (control) |

```sql
-- Behavior change by experiment group
WITH experiment_cohorts AS (
    SELECT 
        engineer,
        experiment_group,
        s.value:type::STRING as signal_type,
        MIN(timestamp) as cohort_entry_date
    FROM praise_opportunities p,
        LATERAL FLATTEN(input => p.signals) s
    WHERE experiment_group IS NOT NULL
    GROUP BY engineer, experiment_group, signal_type
),

pre_period_behavior AS (
    SELECT 
        ec.engineer,
        ec.experiment_group,
        ec.signal_type,
        COUNT(*) as behavior_count,
        'pre' as period
    FROM experiment_cohorts ec
    JOIN pr_metrics pm 
        ON ec.engineer = pm.author
        AND pm.merged_at BETWEEN 
            DATEADD(day, -90, ec.cohort_entry_date) 
            AND ec.cohort_entry_date
    WHERE pm.signal_type = ec.signal_type
    GROUP BY ec.engineer, ec.experiment_group, ec.signal_type
),

post_period_behavior AS (
    SELECT 
        ec.engineer,
        ec.experiment_group,
        ec.signal_type,
        COUNT(*) as behavior_count,
        'post' as period
    FROM experiment_cohorts ec
    JOIN pr_metrics pm 
        ON ec.engineer = pm.author
        AND pm.merged_at BETWEEN 
            ec.cohort_entry_date 
            AND DATEADD(day, 90, ec.cohort_entry_date)
    WHERE pm.signal_type = ec.signal_type
    GROUP BY ec.engineer, ec.experiment_group, ec.signal_type
)

SELECT 
    experiment_group,
    signal_type,
    AVG(post.behavior_count - pre.behavior_count) as avg_behavior_change,
    STDDEV(post.behavior_count - pre.behavior_count) as stddev_change,
    COUNT(DISTINCT pre.engineer) as sample_size
FROM pre_period_behavior pre
JOIN post_period_behavior post 
    ON pre.engineer = post.engineer 
    AND pre.signal_type = post.signal_type
GROUP BY experiment_group, signal_type
ORDER BY signal_type, experiment_group;
```

#### Secondary Metrics (Broader Impact)

Beyond the specific praised behavior, measure spillover effects:

| Metric | Hypothesis | Measurement |
|--------|------------|-------------|
| **PR velocity** | Praised engineers ship faster | PRs per month, pre vs post |
| **Review participation** | Affirmation increases engagement | Reviews given per month |
| **Cross-team activity** | Feeling valued increases collaboration | PRs to non-home repos |
| **Retention signal** | Valued engineers stay longer | Time to next commit after praise |

```sql
-- Spillover effects: overall engagement change
SELECT 
    experiment_group,
    AVG(post_prs_per_month - pre_prs_per_month) as velocity_change,
    AVG(post_reviews_per_month - pre_reviews_per_month) as review_engagement_change,
    AVG(post_cross_team_prs - pre_cross_team_prs) as collaboration_change
FROM engineer_experiment_summary
GROUP BY experiment_group;
```

#### Control Metrics (Validity Checks)

Ensure groups are comparable and experiment is valid:

| Check | Purpose | Alert Threshold |
|-------|---------|-----------------|
| Group balance | Random assignment worked | >5% difference in baseline metrics |
| Contamination | Treatment didn't leak to control | Control engineers report receiving praise |
| Attrition | Engineers didn't leave mid-experiment | >10% attrition difference between groups |

### Analysis Plan

#### Statistical Approach

1. **Difference-in-differences**: Compare (post - pre) between treatment and control
2. **Per-signal analysis**: Some behaviors may be more reinforceable than others
3. **Effect size**: Cohen's d to assess practical significance, not just statistical

```python
from scipy import stats
import numpy as np

def analyze_treatment_effect(treatment_changes: list[float], control_changes: list[float]) -> dict:
    """Analyze whether treatment group shows significant behavior increase."""
    
    # T-test for difference in means
    t_stat, p_value = stats.ttest_ind(treatment_changes, control_changes)
    
    # Effect size (Cohen's d)
    pooled_std = np.sqrt(
        ((len(treatment_changes) - 1) * np.std(treatment_changes)**2 + 
         (len(control_changes) - 1) * np.std(control_changes)**2) /
        (len(treatment_changes) + len(control_changes) - 2)
    )
    cohens_d = (np.mean(treatment_changes) - np.mean(control_changes)) / pooled_std
    
    return {
        "treatment_mean_change": np.mean(treatment_changes),
        "control_mean_change": np.mean(control_changes),
        "difference": np.mean(treatment_changes) - np.mean(control_changes),
        "t_statistic": t_stat,
        "p_value": p_value,
        "cohens_d": cohens_d,
        "effect_interpretation": interpret_cohens_d(cohens_d),
        "sample_size_treatment": len(treatment_changes),
        "sample_size_control": len(control_changes)
    }

def interpret_cohens_d(d: float) -> str:
    """Interpret effect size."""
    d = abs(d)
    if d < 0.2:
        return "negligible"
    elif d < 0.5:
        return "small"
    elif d < 0.8:
        return "medium"
    else:
        return "large"
```

#### Minimum Detectable Effect

With 44 engineers, 70/30 split, 90-day observation windows:

- Treatment: ~31 engineers
- Control: ~13 engineers

Power analysis for detecting a 20% behavior increase:

```python
from statsmodels.stats.power import TTestIndPower

power_analysis = TTestIndPower()
required_n = power_analysis.solve_power(
    effect_size=0.5,  # Medium effect
    power=0.8,
    alpha=0.05,
    ratio=31/13  # Treatment/control ratio
)
# Result: Need ~25 per group for medium effect detection
# With 31 treatment, 13 control, can detect large effects reliably
```

**Implication**: With current team size, focus on detecting large effects. For subtle effects, extend observation period or wait for Taazaa expansion.

### Confound Mitigation

| Confound | Risk | Mitigation |
|----------|------|------------|
| **Selection bias** | Leads praise engineers already improving | Random assignment eliminates; control group establishes baseline |
| **Hawthorne effect** | Knowing you're observed changes behavior | Neither group knows about experiment; observation is passive |
| **Regression to mean** | Extreme performers regress naturally | Compare to control group, not to prior self |
| **Seasonality** | Behavior varies by sprint, quarter | Use concurrent control, not historical baseline |
| **Lead quality variation** | Some leads praise better than others | Stratified randomization by lead |

#### Stratified Randomization

To ensure balance across leads:

```python
def stratified_assignment(opportunity: PraiseOpportunity, lead_assignments: dict) -> str:
    """Assign to group while maintaining balance within each lead's reports."""
    
    lead = opportunity.lead
    engineer = opportunity.engineer
    
    if lead not in lead_assignments:
        lead_assignments[lead] = {"treatment": [], "control": []}
    
    # Assign to underrepresented group for this lead
    t_count = len(lead_assignments[lead]["treatment"])
    c_count = len(lead_assignments[lead]["control"])
    
    if t_count / max(t_count + c_count, 1) < 0.70:
        group = "treatment"
    else:
        group = "control"
    
    lead_assignments[lead][group].append(engineer)
    return group
```

### Reporting

#### Weekly Experiment Health Check

```sql
-- Ensure experiment is running correctly
SELECT 
    experiment_group,
    COUNT(*) as opportunities,
    COUNT(DISTINCT engineer) as unique_engineers,
    COUNT_IF(notification_sent) as notifications_sent,
    AVG(CASE WHEN lead_action = 'praised' THEN 1 ELSE 0 END) as praise_rate
FROM praise_opportunities
WHERE timestamp > DATEADD(day, -7, CURRENT_TIMESTAMP)
    AND experiment_group IS NOT NULL
GROUP BY experiment_group;
```

#### Monthly Results Summary

```sql
-- Core experiment results
WITH results AS (
    SELECT 
        experiment_group,
        signal_type,
        engineer,
        pre_behavior_count,
        post_behavior_count,
        post_behavior_count - pre_behavior_count as change
    FROM experiment_behavior_summary
)

SELECT 
    signal_type,
    
    -- Treatment group
    AVG(CASE WHEN experiment_group = 'treatment' THEN change END) as treatment_avg_change,
    STDDEV(CASE WHEN experiment_group = 'treatment' THEN change END) as treatment_stddev,
    COUNT(CASE WHEN experiment_group = 'treatment' THEN 1 END) as treatment_n,
    
    -- Control group  
    AVG(CASE WHEN experiment_group = 'control' THEN change END) as control_avg_change,
    STDDEV(CASE WHEN experiment_group = 'control' THEN change END) as control_stddev,
    COUNT(CASE WHEN experiment_group = 'control' THEN 1 END) as control_n,
    
    -- Effect
    AVG(CASE WHEN experiment_group = 'treatment' THEN change END) - 
    AVG(CASE WHEN experiment_group = 'control' THEN change END) as treatment_effect

FROM results
GROUP BY signal_type
ORDER BY treatment_effect DESC;
```

### Ethical Considerations

1. **No harm to control group**: Control engineers aren't *losing* recognition they would have received — leads weren't systematically surfacing these opportunities before the system existed.

2. **Transparency option**: After experiment concludes, inform all engineers about the study and share aggregate results.

3. **Sunset control**: After sufficient data collected (6-12 months), convert all to treatment — don't maintain control indefinitely.

4. **Individual opt-out**: If an engineer requests to know their status or opts out, honor immediately and exclude from analysis.

### Success Criteria

| Outcome | Threshold | Interpretation |
|---------|-----------|----------------|
| **Strong positive** | Treatment effect >20%, p<0.05, Cohen's d >0.5 | System demonstrably drives behavior change |
| **Moderate positive** | Treatment effect >10%, p<0.10 | Suggestive evidence; extend study or increase sample |
| **Null result** | No significant difference | Praise may not reinforce, or signals need refinement |
| **Negative result** | Control outperforms treatment | System may be creating perverse incentives; investigate |

### Timeline

| Month | Activity |
|-------|----------|
| 1 | Instrument experiment assignment; begin data collection |
| 2-3 | Accumulate baseline observations |
| 4-6 | First analysis window; preliminary results |
| 7-12 | Extended observation; final analysis |
| 12+ | Publish findings; convert control to treatment |

---

## Measurement & Experimentation

### Hypothesis

Engineers who receive specific, timely affirmation will exhibit increased frequency of the praised behaviors compared to engineers who do not receive affirmation for equivalent behaviors.

### Study Design

#### Randomized Controlled Experiment

When a praise opportunity is generated, randomly assign to one of two groups:

| Group | Treatment | Purpose |
|-------|-----------|---------|
| Treatment | Lead notified normally | Measure effect of praise |
| Control | Notification suppressed | Baseline behavior trajectory |

Assignment ratio: 70/30 treatment/control (ethical balance — most engineers still get recognized while maintaining statistical power).

```python
import random
from datetime import datetime

def should_notify(opportunity: PraiseOpportunity) -> tuple[bool, str]:
    """Randomly assign to treatment or control group."""
    
    # Consistent assignment per engineer+signal to avoid contamination
    # Same engineer+signal always gets same assignment
    seed = hash(f"{opportunity.engineer}:{opportunity.signals[0].type}")
    random.seed(seed)
    
    if random.random() < 0.70:
        return True, "treatment"
    else:
        return False, "control"
```

#### Observational Cohorts (Non-randomized)

If randomization isn't acceptable, compare natural cohorts:

| Cohort | Definition | Expected N |
|--------|------------|------------|
| Praised | Surfaced → Lead acted → Praise delivered | ~40% of surfaced |
| Dismissed | Surfaced → Lead dismissed | ~30% of surfaced |
| Unsurfaced | Behavior occurred but below threshold | ~50% of all PRs |
| No behavior | Engineer didn't exhibit signal behavior | Remainder |

**Caution**: Observational design has confounds (leads may praise engineers already trending up). Use propensity score matching or difference-in-differences to mitigate.

### Metrics

#### Primary Outcome: Behavior Frequency

For each signal type, measure occurrences per engineer per 30-day period.

```sql
CREATE OR REPLACE VIEW engineer_behavior_timeseries AS
SELECT 
    author as engineer,
    signal_type,
    DATE_TRUNC('month', merged_at) as month,
    COUNT(*) as behavior_count
FROM pr_signals
GROUP BY engineer, signal_type, month;
```

#### Secondary Outcomes

| Metric | Source | Rationale |
|--------|--------|-----------|
| PR volume | GitHub | Does praise increase overall output? |
| Review participation | GitHub | Does praise spillover to other behaviors? |
| Cross-team contributions | GitHub | Does praise encourage collaboration? |
| Retention | HR system | Long-term effect on attrition |
| Engagement survey scores | HR system | Self-reported feeling of being valued |

### Analysis Queries

#### Pre/Post Comparison (Within-Subject)

```sql
WITH praise_events AS (
    SELECT 
        engineer,
        s.value:type::STRING as signal_type,
        MIN(timestamp) as first_praise_date,
        experiment_group
    FROM praise_opportunities p,
        LATERAL FLATTEN(input => p.signals) s
    WHERE lead_action = 'praised'
       OR experiment_group = 'control'  -- Include suppressed for comparison
    GROUP BY engineer, signal_type, experiment_group
),

behavior_windows AS (
    SELECT 
        pe.engineer,
        pe.signal_type,
        pe.experiment_group,
        pe.first_praise_date,
        
        -- 90 days before
        SUM(CASE 
            WHEN ps.merged_at BETWEEN DATEADD(day, -90, pe.first_praise_date) 
                                  AND pe.first_praise_date 
            THEN 1 ELSE 0 
        END) as behavior_before,
        
        -- 90 days after
        SUM(CASE 
            WHEN ps.merged_at BETWEEN pe.first_praise_date 
                                  AND DATEADD(day, 90, pe.first_praise_date) 
            THEN 1 ELSE 0 
        END) as behavior_after
        
    FROM praise_events pe
    LEFT JOIN pr_signals ps 
        ON pe.engineer = ps.author 
        AND pe.signal_type = ps.signal_type
    GROUP BY pe.engineer, pe.signal_type, pe.experiment_group, pe.first_praise_date
)

SELECT 
    experiment_group,
    signal_type,
    COUNT(DISTINCT engineer) as n_engineers,
    AVG(behavior_before) as avg_before,
    AVG(behavior_after) as avg_after,
    AVG(behavior_after - behavior_before) as avg_change,
    AVG((behavior_after - behavior_before) / NULLIF(behavior_before, 0)) as avg_pct_change
FROM behavior_windows
GROUP BY experiment_group, signal_type
ORDER BY signal_type, experiment_group;
```

#### Treatment Effect Estimation

```sql
-- Difference-in-differences estimator
WITH behavior_panel AS (
    SELECT 
        pe.engineer,
        pe.signal_type,
        pe.experiment_group,
        
        -- Pre-period behavior rate (per 30 days)
        SUM(CASE WHEN ps.merged_at < pe.first_praise_date THEN 1 ELSE 0 END) 
            / GREATEST(DATEDIFF(day, DATEADD(day, -90, pe.first_praise_date), pe.first_praise_date) / 30.0, 1) 
            as pre_rate,
        
        -- Post-period behavior rate (per 30 days)
        SUM(CASE WHEN ps.merged_at >= pe.first_praise_date THEN 1 ELSE 0 END) 
            / GREATEST(DATEDIFF(day, pe.first_praise_date, DATEADD(day, 90, pe.first_praise_date)) / 30.0, 1) 
            as post_rate
            
    FROM praise_events pe
    LEFT JOIN pr_signals ps 
        ON pe.engineer = ps.author 
        AND pe.signal_type = ps.signal_type
        AND ps.merged_at BETWEEN DATEADD(day, -90, pe.first_praise_date) 
                             AND DATEADD(day, 90, pe.first_praise_date)
    GROUP BY pe.engineer, pe.signal_type, pe.experiment_group, pe.first_praise_date
)

SELECT 
    signal_type,
    
    -- Treatment group change
    AVG(CASE WHEN experiment_group = 'treatment' THEN post_rate - pre_rate END) as treatment_change,
    
    -- Control group change  
    AVG(CASE WHEN experiment_group = 'control' THEN post_rate - pre_rate END) as control_change,
    
    -- Difference-in-differences (causal estimate)
    AVG(CASE WHEN experiment_group = 'treatment' THEN post_rate - pre_rate END) -
    AVG(CASE WHEN experiment_group = 'control' THEN post_rate - pre_rate END) as treatment_effect,
    
    -- Sample sizes
    COUNT(DISTINCT CASE WHEN experiment_group = 'treatment' THEN engineer END) as n_treatment,
    COUNT(DISTINCT CASE WHEN experiment_group = 'control' THEN engineer END) as n_control
    
FROM behavior_panel
GROUP BY signal_type
ORDER BY treatment_effect DESC;
```

### Statistical Considerations

#### Power Analysis

With 44 engineers:

| Effect Size | Required N per group | Detectable with 44? |
|-------------|---------------------|---------------------|
| Large (d=0.8) | ~26 per group | Yes (marginal) |
| Medium (d=0.5) | ~64 per group | No |
| Small (d=0.2) | ~394 per group | No |

**Implication**: With 44 engineers, you can detect large effects only. Consider:

- Pooling across signal types for more power
- Running experiment over longer period to accumulate more observations
- Treating each praise event (not engineer) as unit of analysis

#### Multiple Comparisons

Testing multiple signal types inflates false positive risk. Apply Bonferroni correction:

```sql
-- Adjusted significance threshold
-- If testing 5 signal types at α=0.05
-- Adjusted α = 0.05 / 5 = 0.01
```

Or use False Discovery Rate (FDR) correction for exploratory analysis.

### Schema Additions

```sql
-- Add experiment tracking to praise_opportunities table
ALTER TABLE praise_opportunities ADD COLUMN experiment_group STRING;  -- 'treatment', 'control'
ALTER TABLE praise_opportunities ADD COLUMN experiment_assigned_at TIMESTAMP;

-- Create summary table for behavior tracking
CREATE TABLE pr_signals (
    id STRING,
    merged_at TIMESTAMP,
    author STRING,
    repo STRING,
    pr_number INT,
    signal_type STRING,  -- matches praise signal types
    signal_detail STRING,
    
    -- Denormalized for query performance
    lines_added INT,
    lines_deleted INT,
    coverage_delta FLOAT,
    review_turnaround_hours FLOAT,
    review_comment_count INT
)
PARTITIONED BY (DATE(merged_at), signal_type);
```

### Reporting

#### Monthly Experiment Report

```sql
-- Executive summary for monthly review
SELECT 
    DATE_TRUNC('month', first_praise_date) as month,
    experiment_group,
    COUNT(DISTINCT engineer) as engineers,
    AVG(behavior_after - behavior_before) as avg_behavior_change,
    STDDEV(behavior_after - behavior_before) as stddev_change
FROM behavior_windows
GROUP BY month, experiment_group
ORDER BY month DESC, experiment_group;
```

#### Visualization Requirements

1. **Time series**: Behavior frequency over time, treatment vs control
2. **Before/after scatter**: Each engineer as a point, pre vs post behavior
3. **Effect size forest plot**: Treatment effect by signal type with confidence intervals
4. **Lead effectiveness**: Correlation between lead praise rate and team behavior change

### Ethical Considerations

| Concern | Mitigation |
|---------|------------|
| Withholding recognition | Control group isn't *denied* praise — system simply doesn't prompt leads. Organic recognition still occurs. |
| Surveillance perception | Communicate that system surfaces positive behaviors only. No punitive tracking. |
| Gaming incentives | Monitor for artificial signal inflation. If behaviors are genuinely good, gaming is acceptable. |
| Consent | Consider opt-out mechanism for engineers uncomfortable with tracking. |

### Timeline

| Phase | Duration | Activities |
|-------|----------|------------|
| Baseline | 8 weeks | Collect behavior data without intervention |
| Experiment | 12 weeks | Randomized notification with tracking |
| Analysis | 2 weeks | Statistical analysis, report generation |
| Decision | 1 week | Continue, modify, or expand based on results |

### Success Criteria

| Outcome | Threshold for Success |
|---------|----------------------|
| Treatment effect | >15% increase in praised behavior frequency |
| Statistical significance | p < 0.05 (adjusted for multiple comparisons) |
| Lead engagement | >50% of notifications result in action |
| Engineer sentiment | No negative feedback in pulse surveys |

### Potential Publications

If results are significant:

1. **Internal case study**: Share with Taazaa, investor network
2. **Anthropic partnership**: Claude-assisted recognition system
3. **Snowflake partnership**: Iceberg + behavioral analytics case study
4. **Academic/practitioner**: HBR follow-up to Mercurio's affirmation research

---

## Appendix: Related Work

- [The Power of Affirmation at Work](https://hbr.org/2025/12/the-power-of-affirmation-at-work) - Zach Mercurio, HBR
- Snyder & Fromkin - Uniqueness theory
- Christina Maslach - Individuation and burnout prevention
