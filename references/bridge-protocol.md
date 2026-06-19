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

`project-config.json` records the target ChatGPT project/new-chat entry point and fixed policy defaults:

```json
{
  "target_chatgpt_project_url": "https://chatgpt.com/...",
  "target_chatgpt_url": "https://chatgpt.com/...",
  "legacy_target_chatgpt_url": null,
  "allowed_root": "<project root>",
  "run_mode": "semi_auto",
  "review_scope": "whole_project",
  "gpt_write_policy": "feedback_only",
  "tunnel_policy": "quick_tunnel_per_session",
  "conversation_policy": "new_chat_per_review_round",
  "connector_preflight_required": true
}
```

`target_chatgpt_project_url` is the primary send target. Existing ChatGPT `/c/` conversation URLs are not valid send targets because apps/connectors may not attach to old chats. When a project-scoped old chat URL is provided, the script derives the project URL, stores the original in `legacy_target_chatgpt_url`, and sends future rounds to the project/new-chat entry point.

`bridge-state.json` tracks the current loop:

- `pending_for_gpt`: review reports waiting for GPT Pro.
- `pending_for_codex`: GPT feedback waiting for Codex.
- `active_session`: runtime metadata for the current short-lived tunnel.
- `active_session.target_chatgpt_project_url`: the project/new-chat URL used by browser automation.
- `active_session.conversation_policy`: normally `new_chat_per_review_round`.
- `active_session.connector_preflight_required`: must be true for v1 rounds.
- `active_session.oauth_discovery`: local record of DevSpace OAuth `.well-known` metadata checks.
- `active_session.connector_preflight`: connection gate state before prompt sending.

Connector preflight states:

- `not_started`: session exists, but ChatGPT reachability has not been checked.
- `waiting`: Codex verified health/OAuth metadata and is waiting for ChatGPT to reconnect or approve the app and call the current DevSpace endpoint.
- `passed`: DevSpace logged a non-healthcheck, non-error request after preflight started; `SendPrompt` may continue.
- `blocked`: DevSpace/tunnel was unreachable or no ChatGPT request reached DevSpace before timeout.

Common blocked reasons:

- `devspace_or_tunnel_unreachable`: local `/healthz` or public `/healthz` failed.
- `oauth_metadata_unreachable`: DevSpace OAuth discovery metadata did not return valid metadata for the current MCP URL.
- `oauth_request_rejected`: ChatGPT reached DevSpace, but an OAuth/connection request returned an error.
- `no_chatgpt_request_seen`: the tunnel was healthy, but DevSpace saw no ChatGPT-side request; usually stale MCP URL or OAuth failure before reaching DevSpace.

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

If Codex connector preflight fails or GPT Pro cannot access DevSpace in the new chat, treat the round as `BLOCKED`. Do not infer any project approval from a blocked connector preflight.

Experience records are project-local by default:

- `experience-log.md` is the running local log of review-loop lessons.
- `experience-issues/` contains sanitized GitHub issue drafts for lessons that should improve the reusable skill.
- Public issue drafts should describe process behavior, not private project data.
