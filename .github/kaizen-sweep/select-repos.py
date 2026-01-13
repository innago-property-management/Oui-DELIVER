#!/usr/bin/env python3
"""
Select repositories for Kaizen Sweep based on hour-of-week.

Usage:
    python select-repos.py [--hour HOUR] [--config CONFIG] [--json]

Arguments:
    --hour HOUR     Hour of week (0-167). If not provided, calculates from current time.
    --config CONFIG Path to config file. Default: config.yml in same directory.
    --json          Output as JSON instead of space-separated list.

Output:
    Space-separated list of repo objects with name and optional overrides,
    or JSON array if --json flag is provided.
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml


def get_hour_of_week(dt: datetime = None) -> int:
    """Calculate hour of week (0-167) from datetime."""
    if dt is None:
        dt = datetime.now(timezone.utc)
    # weekday() returns 0=Monday, 6=Sunday
    day_index = dt.weekday()
    hour_of_day = dt.hour
    return (day_index * 24) + hour_of_day


def load_config(config_path: Path) -> dict:
    """Load and parse config YAML."""
    with open(config_path) as f:
        return yaml.safe_load(f)


def is_active_time(hour_of_week: int, settings: dict) -> bool:
    """Check if current hour is within active sweep window."""
    active_hours = settings.get("active_hours")
    active_days = settings.get("active_days")

    day_index = hour_of_week // 24
    hour_of_day = hour_of_week % 24

    if active_days is not None and day_index not in active_days:
        return False

    if active_hours is not None and hour_of_day not in active_hours:
        return False

    return True


def select_repos(config: dict, hour_of_week: int) -> list[dict]:
    """Select repos to sweep for this hour."""
    settings = config.get("settings", {})
    active_repos = config.get("active_repos", [])
    overrides = config.get("overrides") or {}

    if not active_repos:
        return []

    # Check if we're in active time window
    if not is_active_time(hour_of_week, settings):
        return []

    # Calculate which repos to select
    repos_per_hour = settings.get("repos_per_hour", 1)
    total_repos = len(active_repos)

    # Calculate "active hour index" - hours within the active window
    # This ensures we cycle through repos during active hours only
    active_hours = settings.get("active_hours") or list(range(24))
    active_days = settings.get("active_days") or list(range(7))

    day_index = hour_of_week // 24
    hour_of_day = hour_of_week % 24

    # Calculate position within active window
    day_position = active_days.index(day_index) if day_index in active_days else 0
    hour_position = active_hours.index(hour_of_day) if hour_of_day in active_hours else 0
    active_hour_index = (day_position * len(active_hours)) + hour_position

    # Select repos using modulo arithmetic
    selected = []
    start_index = (active_hour_index * repos_per_hour) % total_repos

    for i in range(repos_per_hour):
        repo_index = (start_index + i) % total_repos
        repo = active_repos[repo_index].copy()

        # Apply any overrides
        repo_name = repo.get("name")
        if repo_name in overrides:
            repo.update(overrides[repo_name])

        selected.append(repo)

    return selected


def main():
    parser = argparse.ArgumentParser(description="Select repos for Kaizen Sweep")
    parser.add_argument("--hour", type=int, help="Hour of week (0-167)")
    parser.add_argument("--config", type=str, help="Path to config file")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--debug", action="store_true", help="Print debug info")
    args = parser.parse_args()

    # Determine config path
    if args.config:
        config_path = Path(args.config)
    else:
        config_path = Path(__file__).parent / "config.yml"

    if not config_path.exists():
        print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    # Load config
    config = load_config(config_path)

    # Get hour of week
    hour_of_week = args.hour if args.hour is not None else get_hour_of_week()

    # Validate hour range
    if hour_of_week < 0 or hour_of_week > 167:
        print(f"Error: Hour of week must be between 0 and 167, got {hour_of_week}", file=sys.stderr)
        sys.exit(1)

    if args.debug:
        day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        day_index = hour_of_week // 24
        hour_of_day = hour_of_week % 24
        print(f"Hour of week: {hour_of_week} ({day_names[day_index]} {hour_of_day:02d}:00 UTC)", file=sys.stderr)

    # Select repos
    selected = select_repos(config, hour_of_week)

    if args.debug:
        print(f"Selected {len(selected)} repos", file=sys.stderr)

    # Output
    if args.json:
        print(json.dumps(selected))
    else:
        # Output space-separated repo names for shell consumption
        names = [repo["name"] for repo in selected]
        print(" ".join(names))


if __name__ == "__main__":
    main()
