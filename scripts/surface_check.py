#!/usr/bin/env python3
"""Repository surface checks for the productized pro-loop skill.

This intentionally checks the public shape, not runtime behavior.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


PUBLIC_COMMANDS = {"local", "pro", "required-pro", "testline", "status", "audit", "gain", "debt", "help", "off"}
REQUIRED_PHRASES = {
    "README.md": [
        "Default path: local review first",
        "GPT Pro is a manual add-on",
        "Thin Command Surface",
    ],
    "SKILL.md": [
        "New projects default to `pro_review_mode=disabled`",
        "GPT Pro is a manual add-on",
        "If a new project has no ChatGPT target URL, continue the local loop",
    ],
    "AGENTS.md": [
        "Default Behavior",
        "Thin Command Surface",
        "should_send_to_gpt=false means continue local action",
    ],
}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(path: Path) -> str:
    if not path.exists():
        fail(f"Missing required surface file: {path}")
    return path.read_text(encoding="utf-8")


def check_required_phrases(root: Path) -> None:
    for rel, phrases in REQUIRED_PHRASES.items():
        text = read(root / rel)
        for phrase in phrases:
            if phrase not in text:
                fail(f"{rel} is missing required phrase: {phrase}")


def check_thin_command_surface(root: Path) -> None:
    text = read(root / "scripts" / "pro_loop.ps1")
    match = re.search(r"ValidateSet\(([^)]*)\)", text, re.S)
    if not match:
        fail("scripts/pro_loop.ps1 must declare a ValidateSet command surface")
    commands = set(re.findall(r'"([^"]+)"', match.group(1)))
    missing = PUBLIC_COMMANDS - commands
    extra = commands - PUBLIC_COMMANDS
    if missing or extra:
        fail(f"Unexpected pro_loop command surface. missing={sorted(missing)} extra={sorted(extra)}")


def check_readme_quickstart(root: Path) -> None:
    text = read(root / "README.md")
    if "## 90-Second Path" not in text:
        fail("README is missing 90-Second Path")
    quick_section = text.split("## 90-Second Path", 1)[1].split("##", 1)[0]
    code_blocks = re.findall(r"```powershell\n(.*?)```", quick_section, re.S)
    quick = "\n".join(code_blocks)
    if "-TargetChatGptUrl" in quick:
        fail("README 90-Second Path must not require a ChatGPT URL")
    if "-ProReviewMode optional" in quick:
        fail("README 90-Second Path must not default to optional Pro mode")


def check_removed_connector_terms(root: Path) -> None:
    parts = [
        ("Dev", "Space"),
        ("cloud", "flared"),
        ("try", "cloudflare"),
        ("quick", " tunnel"),
        ("Start", "Session"),
        ("Stop", "Session"),
        ("Preflight", "Connector"),
        ("docs/ai", "-bridge"),
    ]
    excluded = {
        "scripts/surface_check.py",
        ".github/workflows/test.yml",
        "tests/gpt_pro_review_loop.Tests.ps1",
        "testResults.xml",
    }
    terms = ["".join(p) for p in parts]
    for path in root.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        rel = path.relative_to(root).as_posix()
        if rel in excluded:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for term in terms:
            if term in text:
                fail(f"Removed connector term found in {rel}: {term}")


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    check_required_phrases(root)
    check_thin_command_surface(root)
    check_readme_quickstart(root)
    check_removed_connector_terms(root)
    print("Surface check passed!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
