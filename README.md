# Claude Code Log Viewer

A Phoenix LiveView application for viewing and debugging Claude Code API conversations in real-time.

## Features

- **Real-time log streaming** via WebSocket
- **Request/Response merging** - correlates requests with their responses
- **SSE message reconstruction** - rebuilds streaming responses into readable messages
- **ETS-backed storage** - logs persist across page refreshes and LiveView crashes
- **Filtering** - by type, text search, hide statsig events
- **Collapsible headers** - request/response headers hidden by default
- **Reverse proxy** on port 8080 - intercepts and logs API calls

## Setup

```bash
cd log_viewer
mix setup
mix phx.server
```

The log viewer runs on http://localhost:4000
The proxy runs on http://localhost:8080

## Usage

### Option 1: Use the Proxy (Recommended)

Set Claude Code to use the proxy as its API base URL:

```bash
export ANTHROPIC_BASE_URL=http://localhost:8080
```

All API calls will be proxied to Anthropic and logged in the viewer.

### Option 2: Use log_patch.js (Advanced)

See warning below. The patch intercepts fetch calls and sends logs to the viewer.

## Configuration

In `config/dev.exs`:

```elixir
# Change the upstream API target
config :log_viewer, :proxy_upstream, "https://api.anthropic.com"
```

## Architecture

- `LogViewer.LogStore` - ETS-backed GenServer for persistent log storage
- `LogViewerWeb.ProxyEndpoint` - Reverse proxy with request/response logging
- `LogViewerWeb.LogsLive` - LiveView for real-time log display

---

## WARNING: log_patch.js

**`log_patch.js` is for experienced users only.**

This file patches the Claude Code binary to intercept all fetch calls. It:

- Logs ALL request headers including **authorization tokens and API keys**
- Logs ALL request/response bodies which may contain **sensitive data**
- Writes to `~/.claude_requests.log` and sends to the log server

**Security risks:**
- Credentials are written to disk in plaintext
- Credentials are transmitted to the log server
- Anyone with access to the log file or viewer can see your API keys

**Only use if:**
- You understand the security implications
- You're on a secure, private machine
- You clean up log files after debugging
- You never commit credentials to version control

**Do not use in production or shared environments.**
