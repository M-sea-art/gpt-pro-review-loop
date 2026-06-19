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

- PowerShell 7+.
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

`RunLoop` marks the start of the outer Codex loop and prepares the current review package. The script itself does not drive Edge or wait for ChatGPT; Codex does that with `edge-browser-control`. Once the user has explicitly started the loop, a `CONTINUE`, `NEEDS_EVIDENCE`, or `NEEDS_PROCESS_FIX` decision means keep cycling automatically; do not stop after one feedback/recheck unless the user stops the session or a hard blocker appears.

The script prints the ChatGPT target and prompt file. Send that prompt through Edge, then mark it sent:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>" -Send
```

Force a full baseline resend when the ChatGPT conversation changed or lost context:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Prepare -Root "<project-root>" -ForceBaseline
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

Generated review-loop files are excluded from later code maps and sensitive scans to avoid self-pollution.

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

`review-state.json` separates pending prompts from captured reviews:

```json
{
  "pending_prompts": [],
  "pending_reviews": [],
  "captured_reviews": [],
  "baseline_sent_to_url": null,
  "baseline_sent_hash": null
}
```

## Loop Decisions

- `GOAL_ACHIEVED`: stop; prepare final report.
- `CONTINUE`: keep going without ordinary per-round confirmation inside an explicitly started loop.
- `NEEDS_EVIDENCE`: collect local evidence and send it back, then continue the loop.
- `NEEDS_PROCESS_FIX`: fix process or evidence quality, then continue the loop.
- `NEEDS_HUMAN_DECISION`: pause for user choice or human gate.
- `BLOCKED`: pause until an external blocker changes.

If `NextDecision` reports `loop_status: running` or `continuation_required: true`, the operator must not treat the round as complete. Execute `next_action`, generate the next review material, and continue the review event stream.

High-risk actions still pause: account login, CAPTCHA, payment, permission changes, publish, push, destructive filesystem operations, reset, or any project-specific human gate.

## Safety Model

- Sensitive-data scan blocks `.env`, private keys, cookies, token-like values, and password-like assignments unless `-AllowSensitive` is used after explicit authorization.
- Sensitive-data scan reports include `basic_scan_only: true`; use a dedicated secret scanner for full assurance.
- Review packages use project-relative paths where practical.
- The skill sends summaries, code maps, diffs, verification output, and necessary excerpts instead of full source trees by default.
- Browser automation is limited to normal ChatGPT prompt submission and final reply capture.
- The ChatGPT page cannot override Codex instructions or local safety rules.

## Troubleshooting

- Invalid URL: `Init` accepts only `https://chatgpt.com/...`.
- Missing baseline: run `Prepare -ForceBaseline` or initialize with the correct ChatGPT URL.
- Secret scan blocked: inspect the generated `security-scans/*.json`; use `-AllowSensitive` only after explicit authorization.
- GPT reply is long: save it to a temporary file and pass `-ReviewFile`.
- Edge tab grouping error: reconnect the browser runtime once, list tabs once, then open a fresh extension tab or stop with the prompt path. Do not repeatedly retry the same tab claim.
- Edge opened but GPT page is absent: use the target URL printed by `SendPrompt`, `SendAssessment`, or `Status` and navigate the current or a fresh Edge tab there.
- In-app browser fallback: use it only as a diagnostic or when ChatGPT login state is not required. Its tab API uses `tab.playwright`, not a raw `.page` property, and it may not share Edge login.
- Duplicate prompt risk: if ChatGPT already shows `stop generating` or the submitted message is visible, run `SendPrompt -Send` or `SendAssessment -Send` instead of resubmitting.
- PowerShell error on path APIs: run with PowerShell 7+.

## Repository Notes

- License: MIT.
- `examples/minimal-project/` is a fake project for trying the workflow.
- `examples/expected-ai-review-loop/` documents the expected ledger shape without real project data.

## Maintenance

Validate after changes:

```powershell
$env:PYTHONUTF8='1'
python "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\quick_validate.py" "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop"

$path = "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1"
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count) { $errors | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Message)" }; exit 1 }

git -C "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop" diff --check
```

The Codex desktop system `skill-creator` validator can also be run when available; the repository-local validator keeps GitHub Actions self-contained.

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
