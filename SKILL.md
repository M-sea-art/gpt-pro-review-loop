---
name: gpt-pro-review-loop
description: Run a semi-automatic review loop between Codex and GPT Pro through DevSpace MCP and ChatGPT. Use when the user explicitly asks to send a project, Codex execution report, milestone status, implementation plan, or verification results to GPT Pro for review, then bring GPT Pro feedback back into the local project for Codex to act on. Also use for the Chinese request "Pro 审阅循环". This skill starts only after explicit user authorization because it can expose the current project through a short-lived public tunnel.
---

# GPT Pro Review Loop

Chinese alias: `Pro 审阅循环`.

## Core Rule

Use this skill only after an explicit user request such as "use GPT Pro to review this project", "start the review loop", "$gpt-pro-review-loop", or "Pro 审阅循环". Do not start DevSpace, Cloudflare Tunnel, or browser automation implicitly.

Default v1 policy:

- Run mode: semi-automatic, one review round at a time.
- Review scope: GPT Pro may read the current project root through DevSpace.
- GPT write policy: GPT Pro writes feedback only under `docs/ai-bridge/gpt-pro-feedback/`.
- Tunnel policy: open a Cloudflare quick tunnel for the review round, then close it.
- Execution policy: Codex implements changes after reading feedback; GPT Pro should not directly edit source code.

## Workflow

1. Resolve the current project root. Prefer an explicit user path; otherwise use the current working directory or the Git top-level directory if that is clearly the project.
2. Ensure the project has a target ChatGPT project/conversation URL. If missing and the user has not provided one, ask for it before starting the tunnel.
3. Initialize bridge files:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Init -Root "<project-root>" -TargetChatGptUrl "<chatgpt-url>"
   ```

4. Prepare the review package and run the sensitive-data scan:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Prepare -Root "<project-root>"
   ```

   If the scan fails, stop and report the findings. Continue only if the user explicitly authorizes `-AllowSensitive`.

5. Start the short-lived DevSpace session only after the user has authorized the review round:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action StartSession -Root "<project-root>"
   ```

6. Confirm the ChatGPT DevSpace app/connector points at the `mcp_url` printed by the script. If the quick tunnel URL changed since the connector was created, update or recreate the ChatGPT MCP app before asking GPT Pro to review.
7. Send the generated review prompt to the configured ChatGPT conversation:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>" -Send
   ```

   Omit `-Send` if you want the prompt inserted into the composer for manual review before submission.

8. Wait for GPT Pro feedback:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action WaitFeedback -Root "<project-root>" -FeedbackTimeoutSeconds 900
   ```

9. Read the new feedback file, summarize the actionable items, and pause. Do not start the next loop until the user confirms the next round.
10. Stop the public exposure:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action StopSession -Root "<project-root>"
   ```

## One-Command Round

When the target ChatGPT URL is already configured and the user explicitly asks for a round, run:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Run -Root "<project-root>" -Send
```

This prepares the report, starts DevSpace and the quick tunnel, opens the ChatGPT conversation, sends the review prompt, waits for feedback, checks for out-of-bounds writes, and leaves the round paused for Codex to summarize. It still requires the user to confirm any next round.

## Safety Checks

- Treat `DEVSPACE_ALLOWED_ROOTS` as the hard project boundary. Never widen it automatically.
- If `.env`, private keys, cookies, tokens, or password-like assignments are detected, stop unless the user explicitly authorizes `-AllowSensitive`.
- If GPT changes files outside `docs/ai-bridge/gpt-pro-feedback/`, stop and report the changed paths before doing anything else.
- Close the quick tunnel at the end of each round or when the user pauses.
- Do not paste owner tokens, OAuth callbacks, cookies, or browser session data into ChatGPT.

## References

- Read `references/bridge-protocol.md` when inspecting or modifying the project bridge files.
- Read `references/devspace-session.md` when troubleshooting DevSpace, tunnel, OAuth, or connector setup.
- Read `references/chatgpt-browser-flow.md` when browser automation fails or ChatGPT UI changes.
