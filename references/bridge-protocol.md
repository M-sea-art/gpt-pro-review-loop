# Offline Review Loop Protocol

The skill creates project-local coordination files under `docs/ai-review-loop/`.

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
  gpt-feedback/
  codex-assessments/
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
  "run_mode": "semi_auto",
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
- `latest_prompt`: prompt waiting for GPT Pro or already sent.
- `latest_feedback`: GPT Pro feedback captured by Codex from ChatGPT.
- `latest_assessment`: Codex's local practice assessment.
- `pending_for_gpt`: prompt files that need GPT Pro review.
- `pending_for_codex`: GPT feedback files waiting for Codex assessment.
- `pending_assessments_for_gpt`: Codex assessments that should be returned to GPT Pro.

Review material files should use project-relative paths and avoid local absolute paths.

## Material Types

- `dossiers/`: baseline project summary. First round only unless context is lost.
- `code-maps/`: filesystem and optional CodeGraph-derived structure summary.
- `round-requests/`: per-round delta, git status, diff stat, verification notes, and questions.
- `prompts/`: assembled ChatGPT messages for review requests or Codex assessment returns.
- `gpt-feedback/`: replies copied from ChatGPT by Codex.
- `codex-assessments/`: local practice assessment of GPT recommendations.

## Feedback Capture

GPT Pro cannot write local files. Codex captures visible ChatGPT replies and stores them under `gpt-feedback/` with metadata:

```markdown
- source: gpt-pro
- target: codex
- transport: browser_dossier
- status: ready_for_codex_local_assessment
- related_prompt:
```

## Local Assessment

Codex must assess every actionable GPT recommendation before implementation:

```markdown
| GPT recommendation | Codex decision | Local evidence | Action |
|---|---|---|---|
| ... | accept|modify|reject|needs-more-info | ... | ... |
```

Decisions must be grounded in local facts such as code, tests, acceptance gates, project goals, user boundaries, cost, or risk.

## Offline Boundary

GPT Pro reviews only the Markdown material in the ChatGPT conversation. Codex remains responsible for reading local files, running tests, saving feedback, and deciding whether a recommendation fits local constraints.
