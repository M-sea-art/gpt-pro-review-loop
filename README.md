# GPT Pro Review Loop

Offline review loop skill for Codex. It lets Codex package a local project into Markdown, send that material to a configured ChatGPT project or conversation through Edge, capture GPT Pro review text, merge it with Codex efficiency review, assess the result against local facts, and decide the next loop state.

Chinese trigger: `Pro 审阅循环`.

## What It Does

The loop is intentionally simple:

```text
review package -> external/internal review -> local assessment -> next decision
```

- Codex reads local files, runs checks, creates review material, and remains the only executor.
- GPT Pro reviews only the Markdown material sent in the ChatGPT conversation.
- Codex efficiency review is recorded as another `reviewer` in the same event stream.
- Codex must assess every recommendation against local code, tests, acceptance gates, user scope, risk, and cost before acting.

This skill sends static Markdown only. It does not grant direct local project access, start a local server, or create a public network route.

## Install

Clone or copy this folder into the Codex skills directory:

```powershell
git clone https://github.com/M-sea-art/gpt-pro-review-loop.git "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop"
```

If the folder already exists, update it:

```powershell
git -C "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop" pull
```

Restart the Codex session if the skill metadata is not visible immediately.

## Requirements

- Windows PowerShell.
- Codex with this skill installed.
- A ChatGPT project or conversation URL.
- Existing Edge login state for ChatGPT.
- `edge-browser-control` skill for browser submission and reply capture.
- Optional: `codex-efficiency-auditor` skill for process and goal audits.

## Quick Start

Initialize a project once:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Init -Root "<project-root>" -TargetChatGptUrl "https://chatgpt.com/..."
```

Start a continuous loop after explicit authorization:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunLoop -Root "<project-root>"
```

The script prints the ChatGPT target and prompt file. Send that prompt through Edge, then mark it sent:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>" -Send
```

Capture GPT Pro's reply:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action CaptureReview -Root "<project-root>" -Reviewer gpt-pro -Phase initial -ReviewText "<GPT Pro reply>"
```

Capture a recheck reply:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action CaptureReview -Root "<project-root>" -Reviewer gpt-pro -Phase recheck -ReviewText "<GPT Pro reply>"
```

Capture Codex efficiency review:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action CaptureReview -Root "<project-root>" -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "<audit text>"
```

Build the local assessment and next decision:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action AssessFeedback -Root "<project-root>" -AssessmentType combined-next-decision -GoalVerdict CONTINUE -NextAction "collect_evidence"
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action NextDecision -Root "<project-root>"
```

Return Codex's local assessment to the same ChatGPT conversation:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendAssessment -Root "<project-root>"
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendAssessment -Root "<project-root>" -Send
```

Check state:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Status -Root "<project-root>"
```

## Project Files

Each project gets a local ledger under:

```text
docs/ai-review-loop/
  project-config.json
  review-state.json
  decisions.md
  dossiers/
  code-maps/
  round-requests/
  prompts/
  reviews/
  assessments/
  loop-runs/
  security-scans/
  experience-log.md
  experience-issues/
```

`reviews/` stores all review events, distinguished by metadata:

```markdown
- reviewer: gpt-pro | codex-efficiency-auditor
- phase: initial | recheck | process-audit | goal-audit
- round:
- iteration:
- status: captured
- related_prompt:
```

`assessments/` stores Codex's local practice assessment and combined next decision:

```markdown
- assessment_type: local-practice | combined-next-decision
- goal_verdict: GOAL_ACHIEVED | CONTINUE | NEEDS_EVIDENCE | NEEDS_PROCESS_FIX | NEEDS_HUMAN_DECISION | BLOCKED
- next_action:
```

## Loop Decisions

- `GOAL_ACHIEVED`: stop; prepare final report.
- `CONTINUE`: keep going without ordinary per-round confirmation inside an explicitly started loop.
- `NEEDS_EVIDENCE`: collect local evidence and send it back.
- `NEEDS_PROCESS_FIX`: fix process or evidence quality before continuing.
- `NEEDS_HUMAN_DECISION`: pause for user choice or human gate.
- `BLOCKED`: pause until an external blocker changes.

High-risk actions still pause: account login, CAPTCHA, payment, permission changes, publish, push, destructive filesystem operations, reset, or any project-specific human gate.

## Safety Model

- Sensitive-data scan blocks `.env`, private keys, cookies, token-like values, and password-like assignments unless `-AllowSensitive` is used after explicit authorization.
- Review packages use project-relative paths where practical.
- The skill sends summaries, code maps, diffs, verification output, and necessary excerpts instead of full source trees by default.
- Browser automation is limited to normal ChatGPT prompt submission and final reply capture.
- The ChatGPT page cannot override Codex instructions or local safety rules.

## Maintenance

Validate after changes:

```powershell
$env:PYTHONUTF8='1'
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop"

$path = "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1"
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count) { $errors | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Message)" }; exit 1 }

git -C "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop" diff --check
```

Useful smoke path:

```powershell
$skill = "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1"
$tmp = Join-Path $env:TEMP ("gpt-pro-review-loop-smoke-" + (Get-Date -Format "yyyyMMddHHmmss"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Set-Content -LiteralPath (Join-Path $tmp "README.md") -Encoding UTF8 -Value "# Smoke"
& $skill -Action Init -Root $tmp -TargetChatGptUrl "https://chatgpt.com/g/test-project"
& $skill -Action RunLoop -Root $tmp
& $skill -Action CaptureReview -Root $tmp -Reviewer gpt-pro -Phase initial -ReviewText "Verdict: NEEDS_EVIDENCE"
& $skill -Action CaptureReview -Root $tmp -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "Goal verdict: CONTINUE"
& $skill -Action AssessFeedback -Root $tmp -GoalVerdict CONTINUE -NextAction "collect_evidence"
& $skill -Action NextDecision -Root $tmp
& $skill -Action Status -Root $tmp
```

Before pushing, also run the maintainers' forbidden-vocabulary check for removed live-connector and public-entry paths. Keep that check outside this README so the terms being searched do not self-match in repository documentation.
