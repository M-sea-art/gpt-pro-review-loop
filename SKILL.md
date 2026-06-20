---
name: gpt-pro-review-loop
description: Run a compact offline review loop between Codex, GPT Pro, and Codex efficiency review using Markdown review packages, code maps, ChatGPT conversation memory, local assessments, and next-decision events. Use when the user explicitly asks to send a project, Codex report, milestone status, implementation plan, verification result, or local practice assessment to GPT Pro for review through ChatGPT, then bring feedback back into Codex. Also use for the Chinese request "Pro 审阅循环".
---

# GPT Pro Review Loop

Chinese alias: `Pro 审阅循环`.

## What This Skill Does

This skill turns a local Codex project into review material that GPT Pro can read in a normal ChatGPT conversation. Codex prepares the project dossier, code map, per-round delta, and prompt; GPT Pro reviews that material; Codex captures the reply; Codex efficiency review can add process or goal audit notes; Codex then checks all review events against local facts and records one next decision.

The loop is useful when the user wants an outside GPT Pro review without granting direct local project access.

v1.5 makes GPT Pro optional. The default is `pro_review_mode=optional`: Codex runs the project-total guard and local expert council first, then sends GPT Pro only for a new external judgment, a recheck request, a forced review, or a required-mode completion gate. `pro_review_mode=disabled` never generates GPT prompts or opens ChatGPT.

Default quota mode is `economy`: keep full evidence in the project ledger, but send GPT Pro compact Markdown summaries and deltas unless the user or GPT explicitly needs a broader baseline.

Default terminal goal scope is `project_total`. A task, milestone, or test-line can be achieved without ending the continuous loop; Codex must continue upward until the project-total completion guard passes, the user stops the session, or a hard blocker appears.

When project-total blockers remain, the skill normalizes them into a queue and chooses a concrete `local_only_next_action`. `should_send_to_gpt=false` means execute that local action; it is not a completion signal.

Every continuous loop can also run a local expert council review. The council is a brainstorming meeting, not a risk-only audit: it records unjudged ideas first, then performs post-evaluation and writes candidate new goals into a backlog without expanding implementation scope.

Codex efficiency audit is the loop's process supervisor. It is not just another advisory reviewer: it provides read-only capability scan input, periodic audit, stall/pivot status, Done Gate, and final closure checks. The loop stores those events in the same `reviews/` stream, but `NextDecision` treats Done Gate and stall/pivot fields as control evidence.

v1.7 adds a project understanding layer before review:

- `project-goal-model.md`: project total goal, subgoal/gate sources, completion gates, and non-completion boundaries.
- `project-architecture.md`: read-only architecture snapshot covering project type, stack, entry points, key modules, verification commands, and protected boundaries.
- `architecture-brief.md`: compressed 4k-8k character brief for GPT Pro, sent on the first baseline or when the architecture hash changes.
- `goal-slices.md`: small goal queue where each slice has acceptance evidence, recommended capability route, Human Gate status, and current progress.

GPT Pro is an external expert in the review panel, not the final judge. Its comments must flow through local assessment, efficiency audit, expert council, project-total guard, and Done Gate before Codex acts or claims completion.

The mental model is:

```text
review package -> external/internal review -> local assessment -> next decision
```

## Core Rule

Use this skill only after an explicit user request such as "use GPT Pro to review this project", "start the review loop", "$gpt-pro-review-loop", or "Pro 审阅循环".

This skill is offline by design:

- Send review material as Markdown through ChatGPT.
- Use ChatGPT conversation memory as the long-running review context.
- Keep all local reads, writes, tests, and implementation inside Codex.
- Do not give GPT Pro direct local file access.
- Do not assume GPT Pro can write local files.
- Treat GPT Pro as optional external review unless the project config says `pro_review_mode=required`.

Codex owns all local reads, writes, tests, and final execution decisions. GPT Pro reviews only the Markdown material and conversation context that Codex sends through ChatGPT.

GPT Pro, Codex efficiency review, and the local expert council are `reviewer` values in the same event stream. Do not create separate subsystems, directories, or bespoke actions for rechecks, process audits, goal audits, local brainstorming, or combined verdicts when the generic review and assessment fields can express the same thing.

## Workflow

1. Resolve the current project root. Prefer an explicit user path; otherwise use the current working directory or Git top-level directory.
2. Ensure the project has a target ChatGPT project or conversation URL:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Init -Root "<project-root>" -TargetChatGptUrl "https://chatgpt.com/..."
   ```

   If the project has no configured URL, ask the user once for the ChatGPT project/conversation URL before preparing or sending review material. After the user confirms it, store it with `Init -TargetChatGptUrl`; do not ask again in later loop iterations unless the URL changes, is invalid, or the browser is clearly on a different ChatGPT conversation.

   If the user wants a fully local loop, initialize or update with:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Init -Root "<project-root>" -ProReviewMode disabled
   ```

   `-ProReviewMode optional|required|disabled` controls whether GPT Pro is a supplement, a required completion reviewer, or completely disabled.

   `-EfficiencyAuditMode off|light|standard|strict` controls how much Codex efficiency supervision is attached. Default is `standard`.

   - `off`: no efficiency audit integration.
   - `light`: capability scan and Done Gate only.
   - `standard`: capability scan, periodic audit after progress, Done Gate, final closure.
   - `strict`: also run preflight/process checks around repeated failure, subgoal/project completion, and Human Gate boundaries.

   Project understanding controls:

   ```powershell
   -GoalDiscoveryMode auto|docs_first|explicit_only
   -ArchitectureAnalysisMode light|standard|deep
   -ArchitectureBriefMaxChars 8000
   -IncludeArchitectureBriefForPro
   ```

   `auto` reads user/project docs such as `AGENTS.md`, README, roadmap, acceptance docs, Human Gate docs, completion reports, and verifier output. `explicit_only` pauses with `NEEDS_HUMAN_DECISION` if the project total goal cannot be established from an explicit existing state.

3. Prepare the offline review package:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action PrepareCompactReview -Root "<project-root>"
   ```

   This writes under `docs/ai-review-loop/`, refreshes project understanding, runs the sensitive-data scan, creates a project dossier, creates a code map, creates a round request, assembles a compact ChatGPT prompt, and writes a runtime brief. Use `-ForceBaseline` when the ChatGPT conversation lost context or the user explicitly wants a full baseline resend. Use `-QuotaMode balanced` or `-QuotaMode deep` only when the compact prompt is insufficient.

   Explicit understanding actions:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RefreshProjectUnderstanding -Root "<project-root>"
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action BuildGoalModel -Root "<project-root>"
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action AnalyzeArchitecture -Root "<project-root>"
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action BuildArchitectureBrief -Root "<project-root>" -ArchitectureBriefMaxChars 8000
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action BuildGoalSlices -Root "<project-root>"
   ```

   The complete architecture snapshot stays local. GPT Pro receives only `architecture-brief.md` when it is new or changed. If GPT Pro says context is insufficient, regenerate the brief with a larger bound such as `-ArchitectureBriefMaxChars 12000` instead of sending the whole project.

   Use `-GoalScope task|milestone|test_line|project_total` to label the current review target. Keep `project_total` as the terminal scope unless the user explicitly changes the project governance model. Compact prompts include `Goal Context` so GPT Pro and Codex efficiency review can distinguish a subgoal from total project completion.

   If `pro_review_mode=disabled`, this step still creates local dossier/code-map/request material but does not create a GPT prompt.

   Useful quota parameters:

   ```powershell
   -QuotaMode economy|balanced|deep
   -MaxPromptChars 8000
   -AttachVisualEvidence
   ```

   Default image behavior is path/hash only. Attach visual evidence only for visual gates, and do not resend the same contact sheet hash in the same ChatGPT conversation.

4. Send the prompt through Edge using `edge-browser-control`.

   `edge-browser-control` is a Codex skill/instruction set, not necessarily a same-named callable tool. Do not conclude that Edge control is unavailable just because no direct tool named `edge-browser-control` appears in the active tool list. Read `C:\Users\Administrator\.codex\skills\edge-browser-control\SKILL.md` and use the official Codex Edge/Chrome extension backend described there. Do not substitute a generic Playwright browser, in-app browser, or unauthenticated browser for the user's logged-in Edge ChatGPT state.

   First print the target URL and prompt path:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>"
   ```

   Before the first browser operation in an iteration, run one lightweight browser preflight and then reuse the recorded runtime brief:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action PreflightBrowser -Root "<project-root>"
   ```

   Then use `edge-browser-control` to open the target ChatGPT URL, paste the prompt file, and submit it. Do not repeatedly probe browser-client exports, tab APIs, or locator APIs in the same iteration. After the message is actually submitted, mark the prompt sent:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action SendPrompt -Root "<project-root>" -Send
   ```

   If Edge opens but no ChatGPT conversation page is present, navigate the current or a fresh Edge tab to the target URL printed by `SendPrompt`, `SendAssessment`, or `Status`. If Edge tab claiming or grouping fails, read `references/chatgpt-browser-flow.md` and follow its fallback rules. Do not repeatedly retry the same failing tab claim, and do not use stale browser snippets that expect a raw `.page` property.

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

   `GOAL_ACHIEVED` stops only when the active goal scope is `project_total` and the completion guard finds no project blockers. For `task`, `milestone`, or `test_line`, `GOAL_ACHIEVED` becomes `SUBGOAL_ACHIEVED`: keep `loop_status=running`, set `next_action=assess_parent_project_goal`, and continue the loop. If project documents, gates, verifier output, roadmap items, or supervisor state still say `NOT_COMPLETE`, `NOT_READY`, or equivalent, build `project_blocker_queue`, write `project-goal-plan.md`, and continue with the selected `local_only_next_action`. `CONTINUE`, `NEEDS_EVIDENCE`, and `NEEDS_PROCESS_FIX` are not completion states inside an explicitly started loop; they require Codex to execute `next_action`, prepare the next review event, and keep cycling unless the user stops the session or a hard blocker appears. `NEEDS_HUMAN_DECISION` and `BLOCKED` pause.

    `NextDecision` also records whether the next iteration should be sent to GPT:

    - `should_send_to_gpt=false`: continue local execution or evidence collection first; do not send an empty repeat prompt.
    - `should_send_to_gpt=true`: send because there is a new external-review question, a recheck request, new evidence, or `-ForceExternalReview`.
    - `send_reason` and `local_only_next_action` explain the choice.

   For explicit local planning without a full review round:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action BuildProjectGoalPlan -Root "<project-root>"
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action NextLocalAction -Root "<project-root>"
   ```

   Execute `local_only_next_action` before sending GPT another prompt. If only Human Gate, protected scope, or explicit authorization blockers remain, pause for the user.

   In default efficiency mode, `GOAL_ACHIEVED` is still not enough for project-total completion. `NextDecision` must first have `done_gate_verdict=DONE_GATE_PASS`; otherwise it keeps the loop running or pauses for the relevant human decision.

10. Run the local expert council after a progress update or when the loop needs a fresh local plan:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RecordProgress -Root "<project-root>" -ProgressArtifact "<path>"
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunLocalCouncil -Root "<project-root>"
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action PromoteGoal -Root "<project-root>"
   ```

   The council writes `reviews/*local-expert-council*`, `local-council.md`, and `goal-backlog.md`. Brainstorm ideas are recorded before any judgment. Post-evaluation then classifies ideas as immediately local, evidence-needed, Pro-needed, human decision, or future scope. Generated goals stay in backlog until promoted, and human-gated goals remain marked `needs_human_decision`.

   If a capability scan exists, post-evaluation must cite recommended capability routes for candidate goals. For game projects this can include `@game-studio`, `$game-studio:game-playtest`, or related Game Studio child skills. If the route status is `installed-not-exposed`, treat it as a recommendation only, not a callable active capability.

11. Close the Pro tab after the target conversation no longer needs a response:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action CloseProTab -Root "<project-root>"
   ```

   The script records `pro_tab_close_status`. The outer `edge-browser-control` flow performs the actual tab close for the matching configured ChatGPT conversation. Do not read cookies, storage, or account state.

12. Record project-local experience when the round produced a reusable lesson:

   ```powershell
   & "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RecordExperience -Root "<project-root>" -ExperienceOutcome "success|blocked|needs-improvement" -ExperienceLesson "<short reusable lesson>" -ExperienceNotes "<sanitized notes>"
   ```

## Codex Efficiency Supervisor Actions

Use these when the loop needs explicit process supervision:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunCapabilityScan -Root "<project-root>" -AuditContext "game Godot browser playtest"
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunEfficiencyAudit -Root "<project-root>" -PeriodicAudit
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunDoneGate -Root "<project-root>"
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunFinalClosure -Root "<project-root>"
```

Rules:

- `RunCapabilityScan` reuses `codex-efficiency-auditor/scripts/audit_codex_capabilities.py`; do not copy or reimplement inventory logic.
- Capability Scan is read-only recommendation input. It does not install, expose, authenticate, or authorize tools.
- In game/playable/Godot/Phaser/Three/WebGL/sprite/playtest contexts, Game Studio should appear as a top route when detected. Respect `installed-not-exposed`.
- `RecordProgress` triggers `periodic-audit` in `standard` and `strict` modes.
- `stale_count >= 2` means pivot/process fix; do not keep repeating the same `local_only_next_action`.
- `RunDoneGate` is mandatory before default project-total terminal completion.
- `RunFinalClosure` records final process closure after project-total guard and Done Gate pass.

## One-Command Prepare

When the target ChatGPT URL is already configured and the user explicitly asks for a round:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action Run -Root "<project-root>"
```

`Run` prepares the review package and prints the Edge handoff. It does not submit to ChatGPT unless the user or Codex explicitly performs the browser step.

## Continuous Loop

When the user explicitly starts continuous review, use:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunLoop -Root "<project-root>" -PreflightBrowser
```

`RunLoop` is the compact loop entry for the outer Codex agent. In optional mode it starts local-first: if the current next action does not require GPT Pro, it records runtime state and runs the local expert council instead of generating an empty GPT handoff. In `standard` and `strict` efficiency modes, it ensures a capability scan exists first so the council and decision engine have capability-route context. The PowerShell script prepares local ledger material and writes a runtime brief; it does not control Edge or wait for ChatGPT by itself. After explicit authorization, Codex must continue ordinary next rounds without confirmation until `NextDecision` reports terminal project-total completion, `NEEDS_HUMAN_DECISION`, `BLOCKED`, or the user stops the session. A `running` loop status with `continuation_required=true` is an instruction to keep working, not a final-answer point. Safety blockers, human gates, external account/login/CAPTCHA, publish/push, destructive file operations, and permission changes still pause.

For subgoal reviews:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RunLoop -Root "<project-root>" -GoalScope test_line
```

This can mark the test-line as achieved, but it must not stop the overall loop unless the project-total guard also passes.

## Local Practice Assessment Rules

- `GOAL_ACHIEVED`: acceptance gates and evidence show the assessed scope is done; it is terminal only for `project_total` when the completion guard passes.
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

## Efficiency Audit State Fields

The loop records:

- `efficiency_audit_mode`
- `latest_capability_scan`
- `latest_efficiency_audit`
- `latest_done_gate`
- `latest_final_closure`
- `capability_scan_basis`
- `top_capability_family`
- `top_capability_status`
- `recommended_capability_routes`
- `stale_count`
- `stall_pivot_status`
- `done_gate_verdict`
- `final_closure_verdict`

## Safety Checks

- If `.env`, private keys, cookies, tokens, or password-like assignments are detected, stop unless the user explicitly authorizes `-AllowSensitive`.
- Treat the built-in sensitive-data scan as a basic blocker, not a full secret audit.
- Exclude `docs/ai-review-loop/` from generated code maps and sensitive scanning to avoid sending previous review logs back into later rounds by accident.
- Do not send full source trees by default. Send summaries, code maps, diffs, verification output, and necessary excerpts.
- Do not send GPT another prompt unless `should_send_to_gpt=true`, `-ForceExternalReview` is used, or a new external-review question has appeared.
- When `should_send_to_gpt=false`, keep working locally on `local_only_next_action`; do not final unless the loop is paused, blocked, or project-total complete.
- In continuous loops, the second and later GPT-facing prompts automatically append `谢谢你的工作，GPT朋友。`; this is courtesy text only and must not affect local verdicts or gates.
- Reuse `runtime_brief` inside one loop iteration instead of rereading full prompts, full state JSON, full gate docs, or full audit text.
- Use project-relative paths in review material. Avoid exposing local absolute paths.
- Keep browser automation limited to normal ChatGPT prompt submission and reply reading.
- Use low-frequency completion checks after submission; do not high-frequency poll or repeatedly dump page DOM/screenshots.
- Do not inspect cookies, passwords, browser storage, or session files.
- Do not enter account credentials, purchases, or permission changes through browser automation.
- If the ChatGPT conversation changes or GPT says context is missing, resend a compressed baseline before asking for another verdict.
- If a new project has no ChatGPT target URL, stop and ask the user once. Do not guess a conversation URL from unrelated projects.
- The script requires PowerShell 7+.

## References

- Read `references/bridge-protocol.md` when inspecting or modifying `docs/ai-review-loop/` files.
- Read `references/chatgpt-browser-flow.md` when using Edge to send prompts or capture GPT replies.
- Read `references/experience-collection.md` when deciding what to record locally and what to promote to a GitHub issue draft.
