# DevSpace Session Notes

The skill uses DevSpace as a local MCP server and Cloudflare quick tunnel as the temporary public HTTPS entry point.

Runtime defaults:

- `DEVSPACE_ALLOWED_ROOTS` is exactly the current project root.
- `DEVSPACE_PUBLIC_BASE_URL` is the current quick tunnel origin.
- `DEVSPACE_OAUTH_OWNER_TOKEN` is generated per project runtime folder under `%LOCALAPPDATA%\gpt-pro-review-loop\`.
- `DEVSPACE_LOG_SHELL_COMMANDS=0`.
- `DEVSPACE_TOOL_MODE=full` so ChatGPT can inspect files without relying only on shell.

The public flow is:

```text
ChatGPT -> Cloudflare quick tunnel -> local cloudflared -> 127.0.0.1:<port> -> DevSpace -> allowed project root
```

The tunnel does not require opening inbound router/firewall ports because `cloudflared` makes outbound connections to Cloudflare. It is still a public HTTPS endpoint while running, so close it after the round.

Each quick tunnel URL is different. ChatGPT's MCP app/connector must point to the current `/mcp` URL. If ChatGPT cannot call DevSpace, open ChatGPT Settings > Connectors, edit or recreate the DevSpace MCP app with the current URL, and approve OAuth with the owner token printed by the session script.

Use a new ChatGPT chat for each review round. Existing `/c/` conversation URLs can preserve an older tool environment where the DevSpace app is not available, even when a newly opened project chat shows DevSpace. Treat that condition as a blocked connector preflight, not as a project review.

Before sending the review prompt, run `PreflightConnector`. It checks local and public `/healthz`, then watches `devspace.out.log` for a non-healthcheck HTTP request after preflight starts. PowerShell health checks are ignored. If the only log entries are local health checks, ChatGPT has not reached this DevSpace instance; the likely causes are stale MCP URL, disconnected app account, or OAuth failure before reaching DevSpace.

Failure handling:

- `devspace_or_tunnel_unreachable`: start a fresh session; do not use an old quick tunnel URL.
- `no_chatgpt_request_seen`: disconnect/reconnect or recreate the ChatGPT DevSpace app using the current `/mcp` URL while the tunnel is running.
- On either failure, close the quick tunnel and DevSpace before retrying.

Do not store the owner token in the project directory.
