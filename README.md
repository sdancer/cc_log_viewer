# Claude Code Log Viewer

Real-time viewer for debugging Claude Code API conversations.

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

## ⚠️ log_patch.js

For advanced users only. Patches Claude Code to intercept fetch calls.

**Logs credentials and sensitive data in plaintext.** Only use on secure, private machines. Clean up logs after debugging.
