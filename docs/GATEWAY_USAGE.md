# MoonClaw Gateway Usage Guide

## Quick Start

### Starting the Gateway

```bash
# Start the gateway server (runs in foreground)
moonclaw gateway start

# Start with custom port
moonclaw gateway start --port 18790

# Start with custom home directory
moonclaw gateway start --home ~/.my-moonclaw
```

The gateway will start and listen on `http://localhost:18789` by default.

### Checking Gateway Status

```bash
# Check if gateway is running and healthy
moonclaw gateway health

# Example output:
# Status: ok
# Uptime: 1h 23m
# Active sessions: 5
# Pending requests: 0
```

### Running an Agent Task

```bash
# Send a message to the gateway and wait for completion
moonclaw gateway agent --message "Hello, can you help me with a task?" --wait

# Send with specific model
moonclaw gateway agent --message "Analyze this code" --model qwen-max --wait

# Send with session continuity (conversation history)
moonclaw gateway agent --message "Continue from last time" --session my-conversation --wait
```

### Connecting to Gateway

```bash
# Test connection to gateway
moonclaw gateway connect

# Example output:
# Connected to gateway v0.1.0
# Protocol version: 1
# Available methods: connect, agent, agent.wait, sessions.list, health
```

## Architecture Overview

The MoonClaw Gateway follows a **long-running service architecture** similar to OpenClaw:

```
┌─────────────────────────────────────────────────────────┐
│                  MoonClaw Gateway                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │              HTTP Server (port 18789)             │  │
│  │  /v1/health    - Health check endpoint           │  │
│  │  /v1/agent     - Run agent task                  │  │
│  │  /v1/sessions  - List/reset sessions             │  │
│  │  /v1/rpc       - JSON-RPC endpoint               │  │
│  └──────────────────────────────────────────────────┘  │
│                            │                            │
│  ┌────────────────────────▼──────────────────────────┐  │
│  │           RPC Method Handlers                     │  │
│  │  connect | agent | agent.wait | sessions.list    │  │
│  └────────────────────────┬──────────────────────────┘  │
│                           │                             │
│  ┌────────────────────────▼──────────────────────────┐  │
│  │           Agent Execution Engine                   │  │
│  │  - Spawns agent instances on demand               │  │
│  │  - Manages conversation history                   │  │
│  │  - Handles tool execution                         │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Key Features

1. **Long-Running Service**: Gateway stays running in the background, ready to handle requests
2. **Agent Spawning**: Spawns agent instances on-demand to handle tasks
3. **Session Management**: Maintains conversation history across requests
4. **Idempotency**: Dedupe cache prevents duplicate agent runs
5. **Health Monitoring**: Built-in health checks and status reporting

## API Reference

### Health Endpoint

```bash
curl http://localhost:18789/v1/health
```

Response:
```json
{
  "status": "ok",
  "uptime_ms": 3600000,
  "active_sessions": 5,
  "pending_requests": 0
}
```

### Agent Endpoint

```bash
curl -X POST http://localhost:18789/v1/agent \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello, world!",
    "session_key": "my-session",
    "model": "qwen-max"
  }'
```

Response (immediate ack):
```json
{
  "run_id": "uuid-here",
  "status": "accepted",
  "accepted_at": 1234567890
}
```

### Sessions List

```bash
curl http://localhost:18789/v1/sessions
```

## Comparison with OpenClaw

| Feature | OpenClaw | MoonClaw Gateway |
|---------|----------|------------------|
| Protocol | WebSocket + HTTP | HTTP + JSON-RPC |
| Agent Execution | Embedded Pi agent | MoonBit agent |
| Status Command | `openclaw status` | `moonclaw gateway health` |
| Config | YAML/JSON | Environment + files |
| Channels | WhatsApp, Discord, etc. | HTTP API only (for now) |

## Troubleshooting

### Gateway Won't Start

```bash
# Check if port is already in use
lsof -i :18789

# Check logs
moonclaw gateway start 2>&1 | head -50
```

### Agent Requests Timeout

```bash
# Increase timeout
moonclaw gateway agent --message "..." --wait --timeout 120000

# Check gateway health
moonclaw gateway health
```

### Session Issues

```bash
# List active sessions
curl http://localhost:18789/v1/sessions

# Reset a session
curl -X POST http://localhost:18789/v1/sessions/my-session/reset
```

## Next Steps

1. **Start the gateway**: `moonclaw gateway start`
2. **Test connection**: `moonclaw gateway connect`
3. **Run your first agent**: `moonclaw gateway agent --message "Hello!" --wait`
4. **Monitor health**: `moonclaw gateway health`

For more advanced usage, see the [Gateway Architecture Reference](./OPENCLAW_REFERENCE.md).
