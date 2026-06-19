# Offline Review Loop Protocol

The skill creates project-local coordination files under `docs/ai-review-loop/`.

This protocol is intentionally file-based. It gives Codex a durable ledger of what was sent for review, what each reviewer replied, how Codex judged the review events against local facts, and what the next loop decision is.

Required layout:

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

`project-config.json` records the ChatGPT target and fixed v2 policy:

```json
{
  "target_chatgpt_conversation_url": "https://chatgpt.com/...",
  "target_chatgpt_url": "https://chatgpt.com/...",
  "transport": "browser_dossier",
  "run_mode": "continuous_until_stopped",
  "review_memory": "chatgpt_project_conversation",
  "baseline_policy": "first_round_full_then_delta",
  "sensitive_scan_policy": "block_unless_allow_sensitive",
  "code_map_policy": "filesystem_map_with_optional_codegraph_context",
  "codex_assessment_required": true,
  "feedback_return_policy": "send_local_assessment_to_same_chat"
}
```

`review-state.json` tracks local loop state:

- `baseline_sent`: whether the full dossier and code map have been submitted to the configured ChatGPT conversation.
- `baseline_hash`: hash of the latest dossier and code map.
- `round_counter`: monotonically increasing local round number.
- `iteration_counter`: monotonically increasing loop iteration number.
- `loop_mode`: default `continuous_until_stopped`.
- `loop_status`: `idle`, `running`, `complete`, `paused`, or `blocked`.
- `latest_prompt`: prompt waiting for GPT Pro or already sent.
- `latest_review`: latest unified review event.
- `latest_assessment`: latest unified local assessment.
- `goal_verdict`: `GOAL_ACHIEVED`, `CONTINUE`, `NEEDS_EVIDENCE`, `NEEDS_PROCESS_FIX`, `NEEDS_HUMAN_DECISION`, or `BLOCKED`.
- `next_action`: compact machine-readable next step.
- `stop_reason`: null unless the loop has stopped or paused.

Review material files should use project-relative paths and avoid local absolute paths.

## Material Types

- `dossiers/`: baseline project summary. First round only unless context is lost.
- `code-maps/`: filesystem and optional CodeGraph-derived structure summary.
- `round-requests/`: per-round delta, git status, diff stat, verification notes, and questions.
- `prompts/`: assembled ChatGPT messages for review requests or Codex assessment returns.
- `reviews/`: all external and internal review events. GPT Pro initial review, GPT Pro recheck, Codex efficiency process audit, and Codex efficiency goal audit all live here.
- `assessments/`: local-practice and combined-next-decision assessments.
- `loop-runs/`: small JSON records emitted by `NextDecision`.

## Review Capture

GPT Pro cannot write local files. Codex captures visible ChatGPT replies and stores them under `reviews/` with metadata. Codex efficiency review uses the same format:

```markdown
- reviewer: gpt-pro | codex-efficiency-auditor
- phase: initial | recheck | process-audit | goal-audit
- round:
- iteration:
- status: captured
- related_prompt:
```

## Local Assessment

Codex must assess every actionable review recommendation before implementation:

```markdown
- assessment_type: local-practice | combined-next-decision
- goal_verdict: GOAL_ACHIEVED | CONTINUE | NEEDS_EVIDENCE | NEEDS_PROCESS_FIX | NEEDS_HUMAN_DECISION | BLOCKED
- next_action:

| GPT recommendation | Codex decision | Local evidence | Action |
|---|---|---|---|
| ... | accept|modify|reject|needs-more-info | ... | ... |
```

Decisions must be grounded in local facts such as code, tests, acceptance gates, project goals, user boundaries, cost, or risk. The assessment also includes the overall goal verdict so the loop can continue, gather evidence, fix process, stop, or pause for the user.

The assessment is the handoff contract between "GPT suggested it" and "Codex should act." A recommendation without local evidence remains advisory.

## Offline Boundary

GPT Pro reviews only the Markdown material in the ChatGPT conversation. Codex remains responsible for reading local files, running tests, saving reviews, and deciding whether a recommendation fits local constraints.
