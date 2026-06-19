# Bridge Protocol

The skill creates project-local coordination files under `docs/ai-bridge/`.

Required layout:

```text
docs/ai-bridge/
  project-config.json
  bridge-state.json
  decisions.md
  inbox/
  codex-reports/
  gpt-pro-feedback/
  security-scans/
  experience-log.md
  experience-issues/
```

`project-config.json` records the target ChatGPT conversation and fixed policy defaults:

```json
{
  "target_chatgpt_url": "https://chatgpt.com/...",
  "allowed_root": "<project root>",
  "run_mode": "semi_auto",
  "review_scope": "whole_project",
  "gpt_write_policy": "feedback_only",
  "tunnel_policy": "quick_tunnel_per_session"
}
```

`bridge-state.json` tracks the current loop:

- `pending_for_gpt`: review reports waiting for GPT Pro.
- `pending_for_codex`: GPT feedback waiting for Codex.
- `active_session`: runtime metadata for the current short-lived tunnel.

Codex reports must include metadata fields:

```markdown
- id:
- created_at:
- source: codex
- target: gpt-pro
- status: ready_for_review
```

GPT feedback should be written only under `docs/ai-bridge/gpt-pro-feedback/` and should include:

```markdown
- id:
- created_at:
- source: gpt-pro
- target: codex
- status: ready_for_action
- related_report:
```

If GPT Pro writes elsewhere, treat that as an out-of-bounds write and pause.

Experience records are project-local by default:

- `experience-log.md` is the running local log of review-loop lessons.
- `experience-issues/` contains sanitized GitHub issue drafts for lessons that should improve the reusable skill.
- Public issue drafts should describe process behavior, not private project data.
