---
name: gpt-pro-review-loop
description: Run a semi-automatic offline review loop between Codex and GPT Pro without MCP, DevSpace, tunnels, or direct GPT file access. Use when the user explicitly asks to send a project, Codex report, milestone status, implementation plan, verification result, or local practice assessment to GPT Pro for review through ChatGPT, then bring GPT Pro feedback back into Codex. Also use for the Chinese request "Pro 审阅循环".
---

# GPT Pro Review Loop

Chinese alias: `Pro 审阅循环`.

## Core Rule

Use this skill only after an explicit user request such as "use GPT Pro to review this project", "start the review loop", "$gpt-pro-review-loop", or "Pro 审阅循环".

This v2 skill is offline by design:

- Do not start DevSpace.
- Do not start Cloudflare Tunnel.
- Do not use MCP connectors or OAuth preflight.
- Do not give GPT Pro direct local file access.
- Do not assume GPT Pro can write local files.

Codex owns all local reads, writes, tests, and final execution decisions. GPT Pro reviews only the Markdown material and conversation context that Codex sends through ChatGPT.

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

   This writes under `docs/ai-review-loop/`, runs the sensitive-data scan, creates a project dossier, creates a code map, creates a round request, and assembles a ChatGPT prompt.

4. Send the prompt through Edge using `edge-browser-control`.

   First print the target URL and prompt path:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>"
   ```

   Then use `edge-browser-control` to open the target ChatGPT URL, paste the prompt file, and submit it. After the message is actually submitted, mark the prompt sent:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>" -Send
   ```

5. When GPT Pro replies in ChatGPT, read the visible reply through Edge and save it locally:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action CaptureFeedback -Root "<project-root>" -FeedbackText "<GPT reply>"
   ```

   For long replies, save the reply to a temporary file and pass `-FeedbackFile`.

6. Assess GPT Pro feedback against local reality before acting:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action AssessFeedback -Root "<project-root>" -AssessmentText "<Codex local assessment>"
   ```

   Each GPT recommendation must be classified as `accept`, `modify`, `reject`, or `needs-more-info` using local evidence such as code, tests, project goals, user constraints, cost, and risk. Do not treat GPT Pro feedback as a final verdict by itself.

7. Return the local practice assessment to GPT Pro:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendAssessment -Root "<project-root>"
   ```

   Send the generated prompt through Edge, then mark it sent:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendAssessment -Root "<project-root>" -Send
   ```

8. Pause before implementing changes or starting another formal review round unless the user explicitly confirms continuation.

9. Record project-local experience when the round produced a reusable lesson:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RecordExperience -Root "<project-root>" -ExperienceOutcome "success|blocked|needs-improvement" -ExperienceLesson "<short reusable lesson>" -ExperienceNotes "<sanitized notes>"
   ```

## One-Command Prepare

When the target ChatGPT URL is already configured and the user explicitly asks for a round:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Run -Root "<project-root>"
```

`Run` prepares the review package and prints the Edge handoff. It does not submit to ChatGPT unless the user or Codex explicitly performs the browser step.

## Local Practice Assessment Rules

- `accept`: GPT advice fits local code, tests, project goals, user scope, and risk budget.
- `modify`: GPT advice is directionally useful but must be narrowed or adapted.
- `reject`: GPT advice conflicts with local facts, user constraints, acceptance gates, or practical cost.
- `needs-more-info`: local evidence is insufficient; ask GPT or the user for a narrower question.

Always cite local evidence. Evidence can be a file path, command result, test failure, acceptance gate, project decision, or explicit user boundary.

## Safety Checks

- If `.env`, private keys, cookies, tokens, or password-like assignments are detected, stop unless the user explicitly authorizes `-AllowSensitive`.
- Do not send full source trees by default. Send summaries, code maps, diffs, verification output, and necessary excerpts.
- Use project-relative paths in review material. Avoid exposing local absolute paths.
- Keep browser automation limited to normal ChatGPT prompt submission and reply reading.
- Do not inspect cookies, passwords, browser storage, or session files.
- Do not enter account credentials, OAuth approvals, purchases, or permission changes through browser automation.
- If the ChatGPT conversation changes or GPT says context is missing, resend a compressed baseline before asking for another verdict.

## References

- Read `references/bridge-protocol.md` when inspecting or modifying `docs/ai-review-loop/` files.
- Read `references/chatgpt-browser-flow.md` when using Edge to send prompts or capture GPT replies.
- Read `references/experience-collection.md` when deciding what to record locally and what to promote to a GitHub issue draft.
