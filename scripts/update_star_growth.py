#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Update the README star growth section from GitHub star counts.

The script:
- fetches the current star count from the GitHub repository API, or accepts
  a manual --stars override for local testing
- upserts today's entry into docs/star-history.json
- rewrites the STAR_GROWTH marker block in README.mbt.md
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


START_MARKER = "<!-- STAR_GROWTH:START -->"
END_MARKER = "<!-- STAR_GROWTH:END -->"


@dataclass
class StarPoint:
    date: str
    stars: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--readme", default="README.mbt.md")
    parser.add_argument("--history", default="docs/star-history.json")
    parser.add_argument("--repo", default=None)
    parser.add_argument("--stars", type=int, default=None)
    parser.add_argument("--limit", type=int, default=14)
    return parser.parse_args()


def resolve_repo_slug(project_root: Path, explicit: str | None) -> str:
    if explicit:
        return explicit
    env_repo = os.getenv("GITHUB_REPOSITORY")
    if env_repo:
        return env_repo
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "github"],
            cwd=project_root,
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("Failed to resolve repository slug from git remote") from exc
    remote = result.stdout.strip()
    ssh_match = re.match(r"git@github\.com:([^/]+/[^/]+?)(?:\.git)?$", remote)
    https_match = re.match(
        r"https://github\.com/([^/]+/[^/]+?)(?:\.git)?$",
        remote,
    )
    match = ssh_match or https_match
    if not match:
        raise RuntimeError(f"Unsupported GitHub remote format: {remote}")
    return match.group(1)


def fetch_star_count(repo_slug: str) -> int:
    url = f"https://api.github.com/repos/{repo_slug}"
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "moonclaw-star-growth-updater",
    }
    token = os.getenv("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    stars = payload.get("stargazers_count")
    if not isinstance(stars, int):
        raise RuntimeError("GitHub API response did not include stargazers_count")
    return stars


def load_history(history_path: Path) -> list[StarPoint]:
    if not history_path.exists():
        return []
    with open(history_path, "r", encoding="utf-8") as handle:
        raw = json.load(handle)
    points: list[StarPoint] = []
    for entry in raw:
        date = entry.get("date")
        stars = entry.get("stars")
        if isinstance(date, str) and isinstance(stars, int):
            points.append(StarPoint(date=date, stars=stars))
    points.sort(key=lambda point: point.date)
    return points


def save_history(history_path: Path, history: list[StarPoint]) -> None:
    payload = [{"date": point.date, "stars": point.stars} for point in history]
    with open(history_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def upsert_today(history: list[StarPoint], today: str, stars: int) -> list[StarPoint]:
    updated = list(history)
    if updated and updated[-1].date == today:
        updated[-1] = StarPoint(date=today, stars=stars)
        return updated
    for index, point in enumerate(updated):
        if point.date == today:
            updated[index] = StarPoint(date=today, stars=stars)
            updated.sort(key=lambda item: item.date)
            return updated
    updated.append(StarPoint(date=today, stars=stars))
    updated.sort(key=lambda item: item.date)
    return updated


def render_section(history: list[StarPoint], limit: int, today: str) -> str:
    recent = history[-limit:]
    lines = [
        START_MARKER,
        f"_Last updated: {today}_",
        "",
        "| Date | Stars | Delta |",
        "| --- | ---: | ---: |",
    ]
    for index, point in enumerate(recent):
        if index == 0:
            delta = "—"
        else:
            previous = recent[index - 1]
            difference = point.stars - previous.stars
            delta = f"{difference:+d}"
        lines.append(f"| {point.date} | {point.stars} | {delta} |")
    lines.append(END_MARKER)
    return "\n".join(lines)


def rewrite_readme(readme_path: Path, section: str) -> None:
    content = readme_path.read_text(encoding="utf-8")
    pattern = re.compile(
        rf"{re.escape(START_MARKER)}.*?{re.escape(END_MARKER)}",
        re.DOTALL,
    )
    if pattern.search(content):
        updated = pattern.sub(section, content)
    else:
        stripped = content.rstrip()
        updated = f"{stripped}\n\n## Star Growth\n\n{section}\n"
    readme_path.write_text(updated, encoding="utf-8")


def main() -> int:
    args = parse_args()
    project_root = Path(__file__).resolve().parent.parent
    readme_path = project_root / args.readme
    history_path = project_root / args.history
    repo_slug = resolve_repo_slug(project_root, args.repo)
    stars = args.stars if args.stars is not None else fetch_star_count(repo_slug)
    today = datetime.now(timezone.utc).date().isoformat()
    history = load_history(history_path)
    updated_history = upsert_today(history, today, stars)
    save_history(history_path, updated_history)
    section = render_section(updated_history, args.limit, today)
    rewrite_readme(readme_path, section)
    print(f"Updated star growth for {repo_slug}: {stars} stars on {today}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
