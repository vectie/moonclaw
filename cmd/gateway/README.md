# MoonClaw Gateway - Long-Running AI Agent Service

## Overview

The MoonClaw Gateway is a **long-running backend service** that listens for AI agent requests and spawns agents to handle tasks, similar to OpenClaw's architecture.

## Quick Start

### 1. Start the Gateway

```bash
# Start the gateway server
moonclaw gateway start

# Gateway will listen on http://localhost:18789
```

### 2. Check Status

```bash
# Using the status script
./scripts/gateway-status.sh

# Or using the health command
moonclaw gateway health
```

Example output:
```
🦞 MoonClaw Gateway Status Check

Checking gateway at http://localhost:18789...
✅ Gateway is reachable

Gateway Status
┌─────────────────┬────────────────────────────────────────────────────────┐
│ Item            │ Value                                                  │
├─────────────────┼────────────────────────────────────────────────────────┤
│ Dashboard       │ http://127.0.0.1:18789/                                │
│ Gateway         │ ws://127.0.0.1:18789 (reachable)                       │
│ Status          │ ok                                                     │
│ Uptime          │ 1h 23m                                                 │
│ Sessions        │ 5 active                                               │
│ Pending         │ 0 pending                                              │
└─────────────────┴────────────────────────────────────────────────────────┘

✅ Gateway is running properly!
```

### 3. Run an Agent Task

```bash
# Send a message and wait for completion
moonclaw gateway agent --message "Hello, can you help me?" --wait

# Output:
# Agent request accepted: run-uuid-123
# Waiting for completion...
# Agent completed
# {"run_id":"run-uuid-123","status":"completed",...}
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  MoonClaw Gateway                        │
│                                                          │
│  HTTP Server (localhost:18789)                          │
│  ├── /v1/health     - Health check                      │
│  ├── /v1/agent      - Run agent task                    │
│  ├── /v1/sessions   - Manage sessions                   │
│  └── /v1/rpc        - JSON-RPC endpoint                 │
│                                                          │
│  Agent Runner                                           │
│  ├── Spawns agents on demand                            │
│  ├── Manages conversation history                       │
│  └── Handles tool execution                             │
└─────────────────────────────────────────────────────────┘
```

## Commands

### `moonclaw gateway start`

Start the gateway server.

```bash
moonclaw gateway start [--port PORT] [--cwd DIR] [--home DIR]
```

Options:
- `--port PORT`: Port to listen on (default: 18789)
- `--cwd DIR`: Working directory (default: current)
- `--home DIR`: Home directory for config (default: ~/.moonclaw)

### `moonclaw gateway health`

Check gateway health status.

```bash
moonclaw gateway health [--url URL] [--token TOKEN]
```

Options:
- `--url URL`: Gateway URL (default: http://localhost:18789)
- `--token TOKEN`: Auth token (if required)

### `moonclaw gateway agent`

Run an agent task.

```bash
moonclaw gateway agent --message "Your message" [--wait] [--session KEY] [--model NAME]
```

Options:
- `--message MSG`: Message to send (required)
- `--session KEY`: Session key for conversation continuity
- `--model NAME`: Model to use
- `--cwd DIR`: Working directory
- `--wait`: Wait for completion
- `--timeout MS`: Timeout for waiting (default: 60000)

### `moonclaw gateway connect`

Test connection to gateway.

```bash
moonclaw gateway connect [--url URL] [--token TOKEN]
```

### `moonclaw gateway status`

Show comprehensive status (via script).

```bash
./scripts/gateway-status.sh [--url URL] [--all]
```

## API Reference

### Health Check

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

### Run Agent

```bash
curl -X POST http://localhost:18789/v1/agent \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello!",
    "session_key": "my-session",
    "model": "default"
  }'
```

Response (immediate acknowledgment):
```json
{
  "run_id": "uuid-123",
  "status": "accepted",
  "accepted_at": 1234567890
}
```

### List Sessions

```bash
curl http://localhost:18789/v1/sessions
```

Response:
```json
{
  "sessions": [
    {
      "session_id": "my-session",
      "updated_at": 1234567890,
      "model_override": null
    }
  ]
}
```

### JSON-RPC Endpoint

```bash
curl -X POST http://localhost:18789/v1/rpc \
  -H "Content-Type: application/json" \
  -d '{
    "type": "req",
    "id": "uuid-123",
    "method": "connect",
    "params": {
      "minProtocol": 1,
      "maxProtocol": 1,
      "client": {
        "id": "client-123",
        "displayName": "My Client",
        "version": "1.0.0",
        "platform": "darwin",
        "mode": "cli"
      }
    }
  }'
```

## Comparison with OpenClaw

| Feature | OpenClaw | MoonClaw Gateway |
|---------|----------|------------------|
| **Command** | `openclaw status` | `./scripts/gateway-status.sh` |
| **Protocol** | WebSocket + HTTP | HTTP + JSON-RPC |
| **Port** | 18789 | 18789 |
| **Agent** | Embedded Pi agent | MoonBit agent |
| **Channels** | WhatsApp, Discord, etc. | HTTP API |
| **Config** | YAML files | Environment + flags |

## Troubleshooting

### Gateway Won't Start

```bash
# Check if port is in use
lsof -i :18789

# Kill existing process
kill -9 $(lsof -t -i :18789)

# Try starting again
moonclaw gateway start
```

### Gateway Not Responding

```bash
# Check health
moonclaw gateway health

# Check logs (if running in foreground)
# Look for error messages in the output

# Restart gateway
# Stop existing process and run:
moonclaw gateway start
```

### Agent Tasks Timeout

```bash
# Increase timeout
moonclaw gateway agent --message "..." --wait --timeout 120000

# Check gateway is healthy
moonclaw gateway health

# Check model configuration
# Ensure models are properly configured in ~/.moonclaw/
```

## Development

### Building

```bash
# Build the project
moon build

# Run tests
moon test
```

### Testing Gateway

```bash
# Start gateway in background
moonclaw gateway start &

# Wait for it to start
sleep 2

# Run health check
moonclaw gateway health

# Test agent
moonclaw gateway agent --message "test" --wait

# Stop gateway
kill %1
```

## Next Steps

1. **Start the gateway**: `moonclaw gateway start`
2. **Verify it's running**: `./scripts/gateway-status.sh`
3. **Run your first agent**: `moonclaw gateway agent --message "Hello!" --wait`
4. **Explore the API**: See [API Reference](#api-reference) above
5. **Read architecture**: See [OPENCLAW_REFERENCE.md](./OPENCLAW_REFERENCE.md)

## License

Same as MoonClaw project.
