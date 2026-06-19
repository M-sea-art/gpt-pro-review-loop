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

Do not store the owner token in the project directory.
