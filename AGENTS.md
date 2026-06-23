# GPT Pro Review Loop Agent Rule

This repository provides a local-first Codex review loop.

## Core Ladder

1. Identify the project goal contract.
2. Run the local loop first.
3. Bind claims to local evidence.
4. Invite GPT Pro only when the user explicitly asks or a required external gate exists.
5. Treat GPT Pro as advisory input, not the final judge.
6. Route every recommendation through local assessment, efficiency audit, project-total guard, and Done Gate.
7. Do not claim project-total completion until evidence gates and Human Gate boundaries allow it.

## Default Behavior

- New projects default to `pro_review_mode=disabled`.
- Missing ChatGPT URL is not a blocker for local review.
- `should_send_to_gpt=false` means continue local action, not completion.
- Exact invariant: should_send_to_gpt=false means continue local action.
- Subgoal success is not project-total completion.
- `testline_95_auto` is candidate/test-line only and requires isolated Git branch, worktree, or disposable line.

## Thin Command Surface

Prefer the thin wrapper for ordinary use:

```powershell
scripts/pro_loop.ps1 -Command local -Root "<project-root>"
scripts/pro_loop.ps1 -Command status -Root "<project-root>"
scripts/pro_loop.ps1 -Command pro -Root "<project-root>" -TargetChatGptUrl "https://chatgpt.com/..."
scripts/pro_loop.ps1 -Command testline -Root "<project-root>" -ConfirmTestlineIsolation
scripts/pro_loop.ps1 -Command gain -Root "<project-root>"
scripts/pro_loop.ps1 -Command debt -Root "<project-root>"
```

Use `scripts/gpt_pro_review_loop.ps1` directly for advanced maintenance and debugging.

## Safety Boundary

Never restore direct local file access for GPT Pro, local connector bridges, public tunnel handoffs, or automatic publish/push/merge/deploy behavior. Human Gate, credentials, permissions, destructive operations, and protected project scope still pause.
