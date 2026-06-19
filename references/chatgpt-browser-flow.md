# ChatGPT Browser Flow

The helper script `scripts/edge_send_review_prompt.py` connects to an existing Edge remote-debugging session at `http://127.0.0.1:9222`.

Expected flow:

1. Edge is already logged in to ChatGPT.
2. Edge was launched with remote debugging enabled.
3. The project config contains a ChatGPT project or new-chat URL.
4. The PowerShell script generates an inbox prompt file.
5. Connector preflight has passed. `SendPrompt` refuses to run until DevSpace logs a non-healthcheck request from ChatGPT for the current MCP URL.
6. The Python helper opens the target URL and inserts the prompt into the ChatGPT composer.
7. With `-Send`, the helper presses Enter to submit.

The helper is called with `--require-new-chat` by default. It refuses existing ChatGPT `/c/` conversation URLs because DevSpace apps may not attach to old chats. If the user supplied a project-scoped old chat URL during `Init`, the PowerShell script derives and stores the project URL before the helper runs.

If the helper cannot find the composer, leave ChatGPT open and paste the generated prompt file manually. The review prompt path is printed by the PowerShell script.

The browser helper does not update ChatGPT connector settings by itself. When the quick tunnel URL changes, Codex should verify the connector points to the current `mcp_url` before sending the prompt.

Each review prompt includes a GPT-side connector confirmation. GPT Pro must first confirm that DevSpace is visible in the new chat, the active connector points at the current MCP URL, and the report can be read. If that fails, the round is blocked and should not be treated as a technical review.

If browser automation fails before sending, keep the tunnel open only long enough for the user to paste the generated prompt manually after connector preflight has passed. Close the session when the user pauses or the attempt is blocked.
