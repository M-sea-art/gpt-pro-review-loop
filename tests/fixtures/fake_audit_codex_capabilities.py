#!/usr/bin/env python3
"""Deterministic capability-scan fixture for public CI.

The production loop can call the real codex-efficiency-auditor script. Tests use
this fixture through GPT_PRO_REVIEW_LOOP_AUDITOR_SCRIPT so GitHub-hosted runners
do not need the user's local Codex skill directory.
"""

import argparse
import json


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--context", default="")
    args = parser.parse_args()

    context = args.context or ""
    lower = context.lower()
    if any(token in lower for token in ("game", "godot", "phaser", "three", "webgl", "sprite", "playtest")):
        best = [
            {
                "name": "game-studio",
                "status": "installed-not-exposed",
                "directly_usable": "not-until-exposed",
                "install_or_enable_needed": "maybe-expose-or-enable",
                "authorization_needed": "human-gate-before-write-or-external-action",
                "mention": "@game-studio",
                "child_mentions": [
                    "$game-studio:game-playtest",
                    "$game-studio:game-studio",
                    "$game-studio:web-game-foundations",
                ],
            },
            {
                "name": "codegraph",
                "status": "available-in-session",
                "directly_usable": "yes",
                "install_or_enable_needed": "no",
                "authorization_needed": "no-for-read-only",
                "mention": "codegraph",
                "child_mentions": [],
            },
        ]
    else:
        best = [
            {
                "name": "codegraph",
                "status": "available-in-session",
                "directly_usable": "yes",
                "install_or_enable_needed": "no",
                "authorization_needed": "no-for-read-only",
                "mention": "codegraph",
                "child_mentions": [],
            },
            {
                "name": "github",
                "status": "installed-not-exposed",
                "directly_usable": "not-until-exposed",
                "install_or_enable_needed": "maybe-expose-or-enable",
                "authorization_needed": "human-gate-before-write-or-external-action",
                "mention": "@github",
                "child_mentions": ["$github:github"],
            },
        ]

    payload = {
        "scan_basis": "fixture",
        "context": context,
        "best_capabilities": best,
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
