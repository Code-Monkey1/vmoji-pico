#!/usr/bin/env python3
"""Fail if a Markdown doc links to a repo file that does not exist.

Checks relative links and images in README.md, AGENTS.md and docs/**/*.md, so moving or
deleting a file cannot silently leave a dead link. Anchors into Markdown files
(file.md#some-heading) must match a heading, using GitHub's slug rules. External URLs
are not fetched.

Usage: scripts/check-doc-links.py [-h|--help]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# [text](target) and ![alt](target); target ends at whitespace or ')'.
LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
FENCE = re.compile(r"^(```|~~~)")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")


def slug(heading: str) -> str:
    """GitHub's anchor for a heading: lowercase, punctuation dropped (but - and _ kept),
    spaces to hyphens."""
    text = re.sub(r"[`*]", "", heading).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(doc: Path) -> set[str]:
    found = set()
    in_fence = False
    for line in doc.read_text(encoding="utf-8").splitlines():
        if FENCE.match(line.strip()):
            in_fence = not in_fence
        elif not in_fence and (match := HEADING.match(line)):
            found.add(slug(match.group(1)))
    return found


def doc_files() -> list[Path]:
    files = [ROOT / "README.md", ROOT / "AGENTS.md"]
    files += sorted((ROOT / "docs").rglob("*.md"))
    return [f for f in files if f.exists()]


def broken_links(doc: Path) -> list[tuple[int, str]]:
    broken = []
    in_fence = False
    for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
        if FENCE.match(line.strip()):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for target in LINK.findall(line):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target):
                continue  # URL or mailto:
            path, _, anchor = target.partition("#")
            resolved = doc if not path else doc.parent / path
            if not resolved.exists():
                broken.append((number, target))
            elif anchor and resolved.suffix == ".md" and anchor not in anchors(resolved):
                broken.append((number, target + "  (no such heading)"))
    return broken


def main() -> int:
    if any(arg in ("-h", "--help") for arg in sys.argv[1:]):
        print(__doc__.strip())
        return 0
    failures = 0
    for doc in doc_files():
        for number, target in broken_links(doc):
            print(f"{doc.relative_to(ROOT)}:{number}: broken link -> {target}")
            failures += 1
    if failures:
        print(f"{failures} broken link(s).")
        return 1
    print(f"Doc links ok ({len(doc_files())} files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
