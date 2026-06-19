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
  project-goal-plan.md
  local-council.md
  goal-backlog.md
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
  "feedback_return_policy": "send_local_assessment_to_same_chat",
  "url_selection_policy": "ask_once_when_missing_or_changed",
  "quota_mode": "economy",
  "default_max_prompt_chars": 8000,
  "visual_evidence_policy": "attach_only_when_requested_or_new_hash",
  "external_review_policy": "send_only_when_new_evidence_or_explicit_review_needed",
  "active_goal_scope": "project_total",
  "terminal_goal_scope": "project_total",
  "completion_guard_policy": "project_total_only",
  "gpt_courtesy_footer": "谢谢你的工作，GPT朋友。",
  "courtesy_footer_policy": "after_first_external_review_in_continuous_loop",
  "pro_review_mode": "optional",
  "pro_tab_close_policy": "target_conversation",
  "local_council_mode": "enabled",
  "local_council_policy": "brainstorm_then_post_evaluation"
}
```

`review-state.json` tracks local loop state:

- `baseline_sent`: whether the full dossier and code map have been submitted to the configured ChatGPT conversation.
- `baseline_hash`: hash of the latest dossier and code map.
- `baseline_sent_to_url`: ChatGPT URL that received the latest baseline.
- `baseline_sent_hash`: baseline hash sent to that ChatGPT URL.
- `round_counter`: monotonically increasing local round number.
- `iteration_counter`: monotonically increasing loop iteration number.
- `loop_mode`: default `continuous_until_stopped`.
- `loop_status`: `idle`, `running`, `complete`, `paused`, or `blocked`.
- `latest_prompt`: prompt waiting for GPT Pro or already sent.
- `latest_review`: latest unified review event.
- `latest_assessment`: latest unified local assessment.
- `pending_prompts`: generated prompts waiting for browser submission.
- `pending_reviews`: compatibility field for old state files; new prompt writes should not use it.
- `captured_reviews`: captured external/internal review events.
- `goal_verdict`: `GOAL_ACHIEVED`, `CONTINUE`, `NEEDS_EVIDENCE`, `NEEDS_PROCESS_FIX`, `NEEDS_HUMAN_DECISION`, or `BLOCKED`.
- `next_action`: compact machine-readable next step.
- `stop_reason`: null unless the loop has stopped or paused.
- `continuation_required`: true when `NextDecision` leaves `loop_status` as `running`; the outer Codex agent must continue with `next_action` instead of giving a final answer.
- `url_confirmation_required`: true when this project needs a one-time user confirmation of its ChatGPT project/conversation URL.
- `url_confirmation_reason`: `missing_target_chatgpt_url`, `target_chatgpt_url_changed`, or null.
- `quota_mode`: `economy`, `balanced`, or `deep`; default is `economy`.
- `runtime_brief`: latest small JSON snapshot under `loop-runs/` for the current iteration.
- `browser_preflight_status`: one-per-iteration browser route status, usually `pending_edge_browser_control` before the Codex agent claims a tab.
- `browser_target_tab_id`: optional extension tab id recorded by the outer Codex browser flow.
- `latest_visual_evidence_hash`: latest contact sheet or screenshot hash if visual evidence is relevant.
- `last_visual_evidence_sent_hash`: last visual hash intentionally sent or attached to ChatGPT.
- `last_prompt_chars`: character count of the latest generated prompt.
- `cumulative_prompt_chars`: approximate running total of generated prompt characters.
- `should_send_to_gpt`: false when the next step is local-only and sending would be repetitive.
- `send_reason`: why GPT should or should not receive the next prompt.
- `local_only_next_action`: local action to run before another external review.
- `active_goal_scope`: current assessment scope, one of `task`, `milestone`, `test_line`, or `project_total`.
- `terminal_goal_scope`: scope required before the loop can complete; default `project_total`.
- `subgoal_verdict`: latest subgoal result, usually `GOAL_ACHIEVED` when a non-terminal scope passes.
- `project_goal_verdict`: latest total-project result, usually `CONTINUE` until the completion guard passes.
- `completion_guard_status`: `not_evaluated`, `project_goal_pass`, `subgoal_achieved_not_terminal`, `blocked_by_project_goal`, or `not_goal_achieved`.
- `blocking_gates`: compact blocker strings from project goal context.
- `project_blocker_queue`: normalized blocker entries with `id`, `source`, `raw_text`, `category`, `scope`, `status`, `action_kind`, and `recommended_next_action`.
- `current_blocker_id`: selected blocker id for the current local step.
- `current_blocker_category`: selected blocker category.
- `blocker_queue_updated_at`: timestamp of the latest queue rebuild.
- `local_progress_artifacts`: optional local artifact paths created while executing local-only steps.
- `stalled_local_action_count`: repeated local-only action count without new artifacts.
- `goal_context_sources`: project files used to build the latest goal context.
- `goal_achieved_is_terminal`: true only when a `GOAL_ACHIEVED` decision is allowed to stop the loop.
- `gpt_courtesy_footer_sent_count`: count of GPT-facing prompts that included the configured courtesy footer.
- `pro_review_mode`: `optional`, `required`, or `disabled`.
- `pro_tab_close_policy`: default `target_conversation`.
- `pro_tab_close_status`: `closed`, `blocked_no_target_tab`, `blocked_review_still_needed`, or null.
- `pro_tab_closed_at`: timestamp when the target tab close was recorded as complete.
- `local_council_mode`: default `enabled`.
- `latest_local_council_review`: latest review event with `reviewer=local-expert-council`.
- `progress_artifacts`: progress update artifacts that should trigger local council planning.
- `goal_backlog`: candidate goals proposed by post-evaluation.
- `active_generated_goal_id`: promoted generated goal id, if any.

## URL Confirmation

The ChatGPT target URL is project-local. A new project must not inherit another project's review conversation by default. If `url_confirmation_required` is true, Codex should ask the user once for the target ChatGPT project or conversation URL, then run `Init -TargetChatGptUrl` and continue. Later loop iterations reuse the saved URL without asking again unless the URL changes, is invalid, or the visible browser conversation is clearly different from the configured one.

Review material files should use project-relative paths and avoid local absolute paths.

`docs/ai-review-loop/` is excluded from later code maps and sensitive scans. If review history must be sent back to GPT Pro, Codex should generate a compact summary explicitly rather than relying on recursive file discovery.

## Material Types

- `dossiers/`: baseline project summary. First round only unless context is lost.
- `code-maps/`: filesystem and optional CodeGraph-derived structure summary.
- `round-requests/`: per-round delta, git status, diff stat, verification notes, and questions.
- `prompts/`: assembled ChatGPT messages for review requests or Codex assessment returns.
- `reviews/`: all external and internal review events. GPT Pro initial review, GPT Pro recheck, Codex efficiency process audit, and Codex efficiency goal audit all live here.
- `assessments/`: local-practice and combined-next-decision assessments.
- `loop-runs/`: small JSON records emitted by `NextDecision` and `runtime-brief.json` snapshots for low-quota reuse.
- `project-goal-plan.md`: compact local plan generated from `project_blocker_queue`.
- `local-council.md`: pointer and summary for the latest local expert council meeting.
- `goal-backlog.md`: Markdown rendering of candidate generated goals.

## Review Capture

GPT Pro cannot write local files. Codex captures visible ChatGPT replies and stores them under `reviews/` with metadata. Codex efficiency review and the local expert council use the same format:

```markdown
- reviewer: gpt-pro | codex-efficiency-auditor | local-expert-council
- phase: initial | recheck | process-audit | goal-audit | brainstorm | post-evaluation
- round:
- iteration:
- status: captured
- related_prompt:
```

Captured reviewer text is stored inside a fenced `text` block and is advisory evidence only.

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

Decisions must be grounded in local facts such as code, tests, acceptance gates, project goals, user boundaries, cost, or risk. The assessment also includes the overall goal verdict so the loop can continue, gather evidence, fix process, stop, or pause for the user. `CONTINUE`, `NEEDS_EVIDENCE`, and `NEEDS_PROCESS_FIX` are running states inside an explicitly started loop; they require the next iteration unless the user stops the session or a hard blocker appears.

The assessment is the handoff contract between "GPT suggested it" and "Codex should act." A recommendation without local evidence remains advisory.

## Quota And Send Gate

Economy mode is the default. It keeps full files under `docs/ai-review-loop/` but sends compact Markdown to ChatGPT:

- first baseline: bounded dossier and code-map excerpts.
- later rounds: delta, evidence hashes, key paths, verdict target, and narrow questions.
- Codex efficiency review: send only a compact summary, not the full local audit body.
- visual evidence: send path/hash by default; attach the image only when a visual gate needs it and the same hash has not already been sent.

`NextDecision` sets `should_send_to_gpt`. If it is false, the outer Codex agent should continue `local_only_next_action` and avoid an empty GPT prompt. If it is true, the agent can send the latest compact prompt because there is a new external-review question, new evidence, a requested recheck, or an explicit force flag.

## Pro Review Modes

- `optional`: default. Codex uses local judgment and the local expert council first. GPT Pro is sent only for a new external judgment, explicit recheck, forced review, or Pro-required next action.
- `required`: project-total terminal completion requires a captured `gpt-pro` review event unless blockers already prevent completion.
- `disabled`: no ChatGPT URL is required, no GPT prompt is generated, and no Pro tab is opened or closed.

## Local Expert Council

`RunLocalCouncil` records `reviewer=local-expert-council` under `reviews/`. It is a brainstorming meeting, not a risk-only audit.

The `Brainstorm` section must record unjudged ideas first and follow the seven rules: free ideas, suspend judgment, quantity first, build on others, record all ideas, evaluate later, and maintain an open inclusive meeting.

Only the later `Post-Evaluation` section classifies ideas into immediately local, needs evidence, needs external Pro, needs human decision, or future scope. Candidate goals are written to `goal_backlog` and rendered in `goal-backlog.md`; they do not expand implementation scope automatically. Human Gate, core-system, publish, push, remote authorization, or protected-scope goals are marked `needs_human_decision`.

## Pro Tab Close

`CloseProTab` records a close decision for the configured target conversation. It does not inspect browser cookies, storage, login state, or account data. The outer `edge-browser-control` flow performs the actual tab close.

## Project Goal Guard

`GOAL_ACHIEVED` is scoped. It does not automatically mean the whole project is done.

Terminal completion requires:

- `active_goal_scope: project_total`
- `terminal_goal_scope: project_total`
- no blocker evidence in the goal context

The goal context is a compact summary of files such as `AGENTS.md`, acceptance documents, human-gate notes, supervisor state, completion reports, roadmap files, and verifier output. If those sources contain `NOT_COMPLETE`, `NOT_READY`, failed gates, incomplete roadmap items, or equivalent blocker language, `NextDecision` must keep the loop running even if a review event says a local target is accepted.

When a non-terminal scope reaches `GOAL_ACHIEVED`, `NextDecision` records the subgoal result, sets `project_goal_verdict: CONTINUE`, and moves to `next_action: assess_parent_project_goal`.

When project-total blockers remain, the guard becomes a local progress engine:

- `blocking_gates` is normalized into `project_blocker_queue`.
- `project-goal-plan.md` and a `loop-runs/*-project-goal-plan.json` snapshot are written.
- The next open blocker is selected in this priority order: `local_fixable`, `needs_evidence`, `needs_external_review`, `human_gate`, `explicit_authorization_required`, `future_scope`.
- For local blockers, `should_send_to_gpt: false` and `local_only_next_action` is set to the blocker recommendation.
- If only `human_gate`, `explicit_authorization_required`, or `future_scope` blockers remain, the loop pauses with `NEEDS_HUMAN_DECISION`.
- If the same local action repeats twice without new `local_progress_artifacts`, the loop marks `NEEDS_PROCESS_FIX`.

Blocker text must preserve governance phrases such as `NOT_READY`, `NOT_HUMAN_VISUAL_SIGNOFF`, and `NOT_RUNTIME_APPROVED`; do not rewrite accurate project limits to satisfy the guard.

## GPT Courtesy Footer

For continuous loops, the first baseline prompt stays neutral. The second and later GPT-facing review or assessment prompts append:

```text
谢谢你的工作，GPT朋友。
```

The footer is prompt etiquette only. It is not part of local verdicts, gate text, or completion evidence.

## Offline Boundary

GPT Pro reviews only the Markdown material in the ChatGPT conversation. Codex remains responsible for reading local files, running tests, saving reviews, and deciding whether a recommendation fits local constraints.
