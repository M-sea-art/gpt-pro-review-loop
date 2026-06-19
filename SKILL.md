---
name: gpt-pro-review-loop
description: Run a compact offline review loop between Codex, GPT Pro, and Codex efficiency review using Markdown review packages, code maps, ChatGPT conversation memory, local assessments, and next-decision events. Use when the user explicitly asks to send a project, Codex report, milestone status, implementation plan, verification result, or local practice assessment to GPT Pro for review through ChatGPT, then bring feedback back into Codex. Also use for the Chinese request "Pro 审阅循环".
---

# GPT Pro Review Loop

Chinese alias: `Pro 审阅循环`.

## What This Skill Does

This skill turns a local Codex project into review material that GPT Pro can read in a normal ChatGPT conversation. Codex prepares the project dossier, code map, per-round delta, and prompt; GPT Pro reviews that material; Codex captures the reply; Codex efficiency review can add process or goal audit notes; Codex then checks all review events against local facts and records one next decision.

The loop is useful when the user wants an outside GPT Pro review without granting direct local project access.

The mental model is:

```text
review package -> external/internal review -> local assessment -> next decision
```

## Core Rule

Use this skill only after an explicit user request such as "use GPT Pro to review this project", "start the review loop", "$gpt-pro-review-loop", or "Pro 审阅循环".

This v2 skill is offline by design:

- Send review material as Markdown through ChatGPT.
- Use ChatGPT conversation memory as the long-running review context.
- Keep all local reads, writes, tests, and implementation inside Codex.
- Do not give GPT Pro direct local file access.
- Do not assume GPT Pro can write local files.

Codex owns all local reads, writes, tests, and final execution decisions. GPT Pro reviews only the Markdown material and conversation context that Codex sends through ChatGPT.

GPT Pro and Codex efficiency review are both `reviewer` values in the same event stream. Do not create separate subsystems, directories, or bespoke actions for rechecks, process audits, goal audits, or combined verdicts when the generic review and assessment fields can express the same thing.

## Workflow

1. Resolve the current project root. Prefer an explicit user path; otherwise use the current working directory or Git top-level directory.
2. Ensure the project has a target ChatGPT project or conversation URL:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Init -Root "<project-root>" -TargetChatGptUrl "https://chatgpt.com/..."
   ```

3. Prepare the offline review package:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Prepare -Root "<project-root>"
   ```

   This writes under `docs/ai-review-loop/`, runs the sensitive-data scan, creates a project dossier, creates a code map, creates a round request, and assembles a ChatGPT prompt. Use `-ForceBaseline` when the ChatGPT conversation lost context or the user explicitly wants a full baseline resend.

4. Send the prompt through Edge using `edge-browser-control`.

   First print the target URL and prompt path:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>"
   ```

   Then use `edge-browser-control` to open the target ChatGPT URL, paste the prompt file, and submit it. After the message is actually submitted, mark the prompt sent:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>" -Send
   ```

   If Edge tab claiming or grouping fails, read `references/chatgpt-browser-flow.md` and follow its fallback rules. Do not repeatedly retry the same failing tab claim, and do not use stale browser snippets that expect a raw `.page` property.

5. After submitting the prompt, automatically wait for GPT Pro to finish with low-frequency Edge checks. Do not require the user to watch the page. When generation completes, read the latest visible GPT Pro reply through Edge and save it as a review event:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action CaptureReview -Root "<project-root>" -Reviewer gpt-pro -Phase initial -ReviewText "<GPT reply>"
   ```

   For long replies, save the reply to a temporary file and pass `-ReviewFile`.

   Completion detection should be conservative: check for the ChatGPT stop-generating control no more often than every 30-60 seconds, avoid full-page dumps during the wait, and capture only the final assistant reply after the stop control disappears. Hand off to the user only for login, CAPTCHA, permission, or account-security blockers.

6. Optionally capture Codex efficiency review in the same event stream:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action CaptureReview -Root "<project-root>" -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "<audit>"
   ```

   The efficiency review checks execution quality, evidence quality, false-completion risk, empty polling, repeated failure, scope drift, and whether the overall goal is achieved.

7. Assess the review events against local reality before acting:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action AssessFeedback -Root "<project-root>" -AssessmentType combined-next-decision -GoalVerdict CONTINUE -NextAction "collect_evidence" -AssessmentText "<Codex local assessment>"
   ```

   Each GPT recommendation must be classified as `accept`, `modify`, `reject`, or `needs-more-info` using local evidence such as code, tests, project goals, user constraints, cost, and risk. Do not treat GPT Pro feedback as a final verdict by itself.

8. Return the local practice assessment to GPT Pro:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendAssessment -Root "<project-root>"
   ```

   Send the generated prompt through Edge, then mark it sent:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendAssessment -Root "<project-root>" -Send
   ```

9. Decide the next loop state:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action NextDecision -Root "<project-root>"
   ```

   `GOAL_ACHIEVED` stops with a final report requirement. `CONTINUE`, `NEEDS_EVIDENCE`, and `NEEDS_PROCESS_FIX` can continue automatically inside an explicitly started loop. `NEEDS_HUMAN_DECISION` and `BLOCKED` pause.

10. Record project-local experience when the round produced a reusable lesson:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RecordExperience -Root "<project-root>" -ExperienceOutcome "success|blocked|needs-improvement" -ExperienceLesson "<short reusable lesson>" -ExperienceNotes "<sanitized notes>"
   ```

## One-Command Prepare

When the target ChatGPT URL is already configured and the user explicitly asks for a round:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Run -Root "<project-root>"
```

`Run` prepares the review package and prints the Edge handoff. It does not submit to ChatGPT unless the user or Codex explicitly performs the browser step.

## Continuous Loop

When the user explicitly starts continuous review, use:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunLoop -Root "<project-root>"
```

`RunLoop` is the compact loop entry for the outer Codex agent. The PowerShell script prepares local ledger material and prints the browser handoff; it does not control Edge or wait for ChatGPT by itself. After explicit authorization, Codex may continue ordinary next rounds without confirmation until `NextDecision` reports `GOAL_ACHIEVED`, `NEEDS_HUMAN_DECISION`, `BLOCKED`, or the user stops the session. Safety blockers, human gates, external account/login/CAPTCHA, publish/push, destructive file operations, and permission changes still pause.

## Local Practice Assessment Rules

- `GOAL_ACHIEVED`: acceptance gates and evidence show the requested goal is done.
- `CONTINUE`: proceed to the next ordinary implementation, evidence, or review step.
- `NEEDS_EVIDENCE`: automatically gather missing local evidence and send it back.
- `NEEDS_PROCESS_FIX`: fix loop/process quality before continuing.
- `NEEDS_HUMAN_DECISION`: pause for user choice or human gate.
- `BLOCKED`: pause because Codex cannot continue without an external state change.
- `accept`: GPT advice fits local code, tests, project goals, user scope, and risk budget.
- `modify`: GPT advice is directionally useful but must be narrowed or adapted.
- `reject`: GPT advice conflicts with local facts, user constraints, acceptance gates, or practical cost.
- `needs-more-info`: local evidence is insufficient; ask GPT or the user for a narrower question.

Always cite local evidence. Evidence can be a file path, command result, test failure, acceptance gate, project decision, or explicit user boundary.

## Safety Checks

- If `.env`, private keys, cookies, tokens, or password-like assignments are detected, stop unless the user explicitly authorizes `-AllowSensitive`.
- Treat the built-in sensitive-data scan as a basic blocker, not a full secret audit.
- Exclude `docs/ai-review-loop/` from generated code maps and sensitive scanning to avoid sending previous review logs back into later rounds by accident.
- Do not send full source trees by default. Send summaries, code maps, diffs, verification output, and necessary excerpts.
- Use project-relative paths in review material. Avoid exposing local absolute paths.
- Keep browser automation limited to normal ChatGPT prompt submission and reply reading.
- Use low-frequency completion checks after submission; do not high-frequency poll or repeatedly dump page DOM/screenshots.
- Do not inspect cookies, passwords, browser storage, or session files.
- Do not enter account credentials, purchases, or permission changes through browser automation.
- If the ChatGPT conversation changes or GPT says context is missing, resend a compressed baseline before asking for another verdict.
- The script requires PowerShell 7+.

## References

- Read `references/bridge-protocol.md` when inspecting or modifying `docs/ai-review-loop/` files.
- Read `references/chatgpt-browser-flow.md` when using Edge to send prompts or capture GPT replies.
- Read `references/experience-collection.md` when deciding what to record locally and what to promote to a GitHub issue draft.
