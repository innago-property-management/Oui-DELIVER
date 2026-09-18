#!/usr/bin/env python3
"""Evaluate a pull request against the delivery-metadata rules.

Model v2 section 13.1. Two properties matter more than the checking itself:

  * It NEVER blocks a merge (13.1, 14.9). The surface is a check run with a
    NEUTRAL conclusion — visible in the checks box, no notification, no thread.
  * It PROPOSES rather than demands. Most of this is derivable: a PR touching
    only tests, config or docs is almost certainly release-note:none, and a
    branch or commit body carrying an issue reference already names the issue.

It escalates to a single sticky comment only once the PR has an approval and
metadata is still missing, and is silent on drafts. One comment, edited in
place — never one per push.

Reads a PR context JSON on stdin, writes a verdict JSON to stdout.
"""
import json
import re
import sys

NOTE_PREFIX = "release-note:"
VALID_NOTES = {"release-note:external", "release-note:internal-only", "release-note:none"}

# Paths that cannot change what a customer sees.
NON_CUSTOMER_FACING = re.compile(
    r"(^|/)("
    r"tests?|test|spec|specs|__tests__|e2e|"
    r"docs?|documentation|"
    r"\.github|\.vscode|\.idea"
    r")(/|$)"
    r"|\.(md|txt|ya?ml|json|toml|ini|cfg|editorconfig|gitignore|lock)$"
    r"|(^|/)(Dockerfile|Makefile|\.env\.example)$",
    re.IGNORECASE,
)
# High confidence anywhere: an explicit #1234 or issue-1234.
ISSUE_REF = re.compile(r"(?:^|[^\w])#(\d{1,6})\b|(?:issue[-_/]?)(\d{1,6})", re.IGNORECASE)

# Branch names here often carry a bare number — fix/1086-sidebar. Requiring a
# leading intent word keeps version strings (1.8.18) and sequence suffixes
# (feat-dev-1301) out: proposing the WRONG issue would manufacture false
# traceability, which is worse than proposing nothing.
BRANCH_REF = re.compile(r"(?:^|[-_/])(?:issue|gh|fix|feat|bug|hotfix)[-_/#]*(\d{2,6})(?:[-_/]|$)",
                        re.IGNORECASE)


def issue_refs(branch, *texts):
    found = []
    for t in texts:
        for m in ISSUE_REF.finditer(t or ""):
            n = m.group(1) or m.group(2)
            if n and int(n) > 0:
                found.append(int(n))
    for m in ISSUE_REF.finditer(branch or ""):
        n = m.group(1) or m.group(2)
        if n and int(n) > 0:
            found.append(int(n))
    for m in BRANCH_REF.finditer(branch or ""):
        found.append(int(m.group(1)))
    return sorted(set(found))


def evaluate(ctx):
    labels = set(ctx.get("labels") or [])
    files = ctx.get("files") or []
    closes = ctx.get("closes_issues") or []

    has_note = bool(labels & VALID_NOTES)
    has_link = bool(closes)

    proposals = []

    if not has_note:
        if files and all(NON_CUSTOMER_FACING.search(f) for f in files):
            proposals.append({
                "id": "propose-release-note-none",
                "label": "release-note:none",
                "why": "every changed path is a test, config or documentation file",
            })

    if not has_link:
        refs = issue_refs(ctx.get("branch"), ctx.get("title"), ctx.get("body"),
                          *(ctx.get("commit_messages") or []))
        if refs:
            proposals.append({
                "id": "propose-issue-link",
                "issue": refs[0],
                "why": f"the branch, title or a commit body references #{refs[0]}",
            })

    missing = []
    if not has_note:
        missing.append("a release-note label")
    if not has_link:
        missing.append("a linked issue")

    # Escalate only once someone has approved and it is still missing. Before
    # that the neutral check is the whole of the ask.
    escalate = bool(missing) and ctx.get("approved") and not ctx.get("is_draft")

    return {
        "ok": not missing,
        "missing": missing,
        "proposals": proposals,
        "escalate": escalate,
        "is_draft": bool(ctx.get("is_draft")),
        # Neutral, always. This check has no failure state by design.
        "conclusion": "neutral",
        "summary": ("All delivery metadata present." if not missing
                    else "Missing " + " and ".join(missing) + "."),
    }


if __name__ == "__main__":
    print(json.dumps(evaluate(json.load(sys.stdin)), indent=2, sort_keys=True))
