#!/usr/bin/env python3
"""Small repository-local skill metadata validator for CI.

The Codex desktop environment also provides a system quick_validate.py. This
fallback keeps the public repository CI self-contained.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        fail("SKILL.md must start with YAML frontmatter")
    end = text.find("\n---", 4)
    if end == -1:
        fail("SKILL.md frontmatter is not closed")
    data: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        if ":" not in line:
            fail(f"Invalid frontmatter line: {line}")
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"')
    return data


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    skill_path = root / "SKILL.md"
    if not skill_path.exists():
        fail("Missing SKILL.md")
    frontmatter = parse_frontmatter(skill_path.read_text(encoding="utf-8"))
    name = frontmatter.get("name", "")
    description = frontmatter.get("description", "")
    if not re.fullmatch(r"[a-z0-9-]{1,63}", name):
        fail("name must be 1-63 lowercase letters, digits, or hyphens")
    if not description:
        fail("description is required")
    print("Skill is valid!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
