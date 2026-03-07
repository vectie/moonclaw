# Daemon vs Gateway Comparison

This document compares the two long-running service architectures in MoonClaw.

## Overview

### Daemon (`cmd/daemon/`)
A full-featured supervisor that manages per-workspace tasks with comprehensive process management.

### Gateway (`gateway/server/`)
A simpler HTTP gateway focused on agent execution with event streaming.

## Architecture

### Daemon

```
┌─────────────────────────────────────────────────────────────┐
│                         Daemon                               │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │ HTTP Server  │  │ Process Manager  │  │ Conversation │  │
│  │  (httpx)     │  │ (@spawn.Manager) │  │   Manager    │  │
│  └──────────────┘  └──────────────────┘  └──────────────┘  │
│                                                              │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │ Task Maps    │  │ OAuth Providers  │  │ Event        │  │
│  │ (by_cwd/id)  │  │ (Codex, Copilot) │  │ Broadcast    │  │
│  └──────────────┘  └──────────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Gateway

```
┌─────────────────────────────────────────────────────────────┐
│                         Gateway                              │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │ HTTP Server  │  │ Agent Runs Map   │  │ Event        │  │
│  │  (httpx)     │  │ (background)     │  │ Broadcast    │  │
│  └──────────────┘  └──────────────────┘  └──────────────┘  │
│                                                              │
│  ┌──────────────┐  ┌──────────────────┐                     │
│  │ Session      │  │ Dedupe Cache     │                     │
│  │ Manager      │  │ (idempotency)    │                     │
│  └──────────────┘  └──────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

## Feature Comparison

| Feature | Daemon | Gateway |
|---------|--------|---------|
| **Process Management** | `@spawn.Manager` with per-cwd tasks | Simple background task groups |
| **Conversation Management** | `@conversation.Manager` | Basic session tracking |
| **Authentication** | OAuth (Codex, Copilot) | Token-based only |
| **Event Streaming** | Via broadcast | SSE at `/v1/events` |
| **Task Tracking** | `by_cwd`, `by_id` maps | `agent_runs` map |
| **Idempotency** | Via queue system | Dedupe cache |
| **Lock File** | `~/.moonclaw/daemon.json` | `~/.moonclaw/gateway.json` |
| **Default Port** | 8090 | 18123 |
| **Complexity** | Higher | Lower |
| **Maturity** | Production-ready | New implementation |

## Endpoints

### Daemon Endpoints
- `GET /health` - Health check
- `POST /rpc` - RPC endpoint for all operations
- Authentication endpoints for OAuth providers

### Gateway Endpoints
- `GET /` - Gateway info dashboard
- `GET /health` - Health check with uptime
- `GET /v1/events` - SSE event stream
- `GET /v1/runs` - List agent runs
- `GET /v1/runs/{id}` - Get run status
- `POST /v1/agent` - Submit agent task
- `POST /v1/rpc` - RPC endpoint
- `POST /v1/shutdown` - Graceful shutdown

## Usage

### Daemon
```bash
# Start in foreground
moon run cmd/main -- daemon

# Start in background (detached)
moon run cmd/main -- daemon --detach
moon run cmd/main -- daemon -d

# With options
moon run cmd/main -- daemon --port 8090 --serve /path/to/workspace
```

### Gateway
```bash
# Start in foreground
moon run cmd/main -- gateway

# Start in background (detached)
moon run cmd/main -- gateway --detach
moon run cmd/main -- gateway -d

# With options
moon run cmd/main -- gateway --port 18123 --cwd /path/to/workspace
```

## When to Use Which

### Use Daemon when:
- You need OAuth authentication (Codex, Copilot)
- You want conversation persistence
- You need per-workspace task isolation
- You want production-ready stability

### Use Gateway when:
- You want a simpler, lightweight service
- You need SSE event streaming
- You want idempotent agent requests
- You're building custom integrations

## Future Considerations

Possible directions:
1. **Merge architectures** - Add gateway features (SSE, idempotency) to daemon
2. **Keep both** - Gateway for simple use cases, daemon for full features
3. **Gateway as proxy** - Gateway could forward to daemon for complex operations
