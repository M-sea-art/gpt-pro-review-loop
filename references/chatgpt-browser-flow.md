# ChatGPT Browser Flow

The helper script `scripts/edge_send_review_prompt.py` connects to an existing Edge remote-debugging session at `http://127.0.0.1:9222`.

Expected flow:

1. Edge is already logged in to ChatGPT.
2. Edge was launched with remote debugging enabled.
3. The project config contains a ChatGPT project or conversation URL.
4. The PowerShell script generates an inbox prompt file.
5. The Python helper opens the target URL and inserts the prompt into the ChatGPT composer.
6. With `-Send`, the helper presses Enter to submit.

If the helper cannot find the composer, leave ChatGPT open and paste the generated prompt file manually. The review prompt path is printed by the PowerShell script.

The browser helper does not update ChatGPT connector settings by itself. When the quick tunnel URL changes, Codex should verify the connector points to the current `mcp_url` before sending the prompt.
