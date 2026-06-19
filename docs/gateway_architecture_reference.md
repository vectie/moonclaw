# MoonClaw Gateway Architecture Reference

## 1. Overall Architecture Overview

MoonClaw is a **multi-channel messaging gateway** that enables AI agents to communicate through various platforms (WhatsApp, Telegram, Discord, iMessage, etc.). The architecture follows a **hub-and-spoke model** with a central gateway server that handles:

- **WebSocket-based control plane** for real-time bidirectional communication
- **HTTP endpoints** for REST-style API access (OpenAI-compatible, OpenResponses API)
- **Channel integrations** for external messaging platforms
- **Agent execution** via embedded Pi coding agent

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      Gateway Server                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ WebSocket    │  │ HTTP Server  │  │ Channel Manager      │  │
│  │ Handler      │  │ (REST APIs)  │  │ (WhatsApp, Discord,  │  │
│  │              │  │              │  │  Telegram, etc.)     │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │              │
│         └─────────────────┼──────────────────────┘              │
│                           │                                     │
│  ┌────────────────────────▼────────────────────────────────┐   │
│  │              Server Methods (RPC Handlers)               │   │
│  │  agent | chat | sessions | config | cron | health | ... │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│  ┌────────────────────────▼────────────────────────────────┐   │
│  │              Agent Execution Engine                       │   │
│  │  (Embedded Pi Agent - LLM orchestration, tools, memory)  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. How It Listens for Requests

### WebSocket Server Setup

The gateway uses a WebSocket server (`server.impl.ts`) that listens on a configurable port (default: 18123):

```typescript
// Key startup sequence:
export async function startGatewayServer(port = 18123, opts = {}) {
  // 1. Load and validate configuration
  // 2. Bootstrap authentication (generate token if missing)
  // 3. Create HTTP server + WebSocket server
  // 4. Attach WebSocket handlers
  // 5. Start channel managers
  // 6. Initialize cron service
  // 7. Start heartbeat runner
  // 8. Enable config hot-reload
}
```

### Connection Lifecycle (`ws-connection.ts`)

1. **Connection Open**: Client connects via WebSocket
2. **Challenge**: Server immediately sends a `connect.challenge` event with a nonce
3. **Handshake**: Client must send a `connect` request with auth credentials within a timeout
4. **Hello-OK**: Server responds with capabilities, methods, events, and session snapshot
5. **Ready**: Client can now make RPC requests

```typescript
// Challenge sent immediately on connection
send({
  type: "event",
  event: "connect.challenge",
  payload: { nonce: connectNonce, ts: Date.now() }
});

// Handshake timeout enforcement
const handshakeTimer = setTimeout(() => {
  if (!client) {
    close(1008, "handshake-timeout");
  }
}, handshakeTimeoutMs);
```

### Bind Modes

The gateway supports multiple bind modes:
- **loopback** (default): `127.0.0.1` only
- **lan**: `0.0.0.0` (all interfaces)
- **tailnet**: Tailscale VPN address only
- **auto**: Prefer loopback, fallback to LAN

---

## 3. How It Spawns Agents to Handle Tasks

### Agent Execution Flow

The agent execution follows a two-stage async pattern:

1. **Immediate Ack**: Server returns `status: "accepted"` immediately
2. **Background Execution**: Agent runs asynchronously
3. **Final Response**: Server sends completion response with `status: "ok"` or `status: "error"`

### Key Handler: `agent` Method (`agent.ts`)

```typescript
agent: async ({ params, respond, context }) => {
  // 1. Validate params
  // 2. Check idempotency (dedupe cache)
  // 3. Resolve session key and session entry
  // 4. Handle /reset or /new commands
  // 5. Inject timestamp
  // 6. Send immediate ack
  respond(true, { runId, status: "accepted", acceptedAt: Date.now() });
  
  // 7. Run agent asynchronously
  void agentCommand({ message, sessionKey, ... })
    .then(result => {
      respond(true, { runId, status: "ok", result });
    })
    .catch(err => {
      respond(false, { runId, status: "error" }, errorShape(...));
    });
}
```

### Agent Command Implementation (`agent.ts`)

The `agentCommand` function orchestrates:

1. **Session Resolution**: Load or create session from session store
2. **Workspace Setup**: Ensure agent workspace directory exists
3. **Model Selection**: Resolve model from config, session override, or fallback chain
4. **Skills Snapshot**: Build snapshot of available skills/tools
5. **Agent Execution**: Call `runEmbeddedPiAgent` with full context
6. **Delivery**: Optionally deliver response via messaging channel
7. **Session Update**: Persist token usage, model selection, etc.

### Embedded Pi Agent Runner (`run.ts`)

The actual LLM orchestration:

```typescript
export async function runEmbeddedPiAgent(params) {
  // 1. Resolve session lane (concurrency control)
  // 2. Load API keys for provider
  // 3. Build system prompt from workspace files
  // 4. Load session transcript
  // 5. Execute LLM API calls with tool handling
  // 6. Stream responses back via events
  // 7. Handle context overflow with compaction
  // 8. Return final result with usage stats
}
```

---

## 4. API Design and Request/Response Formats

### Protocol Versioning

The protocol declares a current contract version:
```typescript
export const PROTOCOL_VERSION = 1;
```

### Frame Types (`frames.ts`)

All communication uses one of three frame types:

#### Request Frame
```typescript
{
  type: "req",
  id: string,        // UUID for correlation
  method: string,    // e.g., "agent", "chat.send", "config.get"
  params?: unknown   // Method-specific parameters
}
```

#### Response Frame
```typescript
{
  type: "res",
  id: string,        // Matches request id
  ok: boolean,
  payload?: unknown,
  error?: {
    code: string,
    message: string,
    details?: unknown,
    retryable?: boolean,
    retryAfterMs?: number
  }
}
```

#### Event Frame
```typescript
{
  type: "event",
  event: string,     // e.g., "agent", "chat", "tick", "health"
  payload?: unknown,
  seq?: number,      // Sequence number for ordering
  stateVersion?: { presence?: number, health?: number }
}
```

### Connect Flow

**Client sends:**
```typescript
{
  type: "req",
  id: "uuid",
  method: "connect",
  params: {
    minProtocol: 1,
    maxProtocol: 1,
    client: {
      id: "client-id",
      displayName: "My Client",
      version: "1.0.0",
      platform: "darwin",
      mode: "cli" | "backend" | "webchat" | "probe"
    },
    auth: { token?: string, password?: string },
    role: "operator" | "node",
    scopes: ["operator.admin"],
    device?: {
      id: "device-id",
      publicKey: "base64url",
      signature: "signature",
      signedAt: timestamp
    }
  }
}
```

**Server responds (HelloOk):**
```typescript
{
  type: "hello-ok",
  protocol: 1,
  server: { version, commit, host, connId },
  features: { methods: [...], events: [...] },
  snapshot: { presence, health, stateVersion },
  policy: { maxPayload, maxBufferedBytes, tickIntervalMs }
}
```

### Key Methods (`server-methods-list.ts`)

| Method | Description |
|--------|-------------|
| `agent` | Run agent with message, returns accepted then final result |
| `agent.wait` | Wait for agent job completion |
| `agent.identity.get` | Get agent identity/avatar |
| `chat.send` | Send message to chat session |
| `chat.history` | Get chat history |
| `chat.abort` | Abort running chat |
| `sessions.list` | List all sessions |
| `sessions.reset` | Reset a session |
| `config.get/set/apply/patch` | Configuration management |
| `health` | Health check |
| `cron.add/update/remove/run` | Cron job management |
| `node.invoke` | Invoke remote node |

### Key Events

| Event | Description |
|-------|-------------|
| `connect.challenge` | Sent on connection, requires connect response |
| `agent` | Agent lifecycle events (start, delta, end, error) |
| `chat` | Chat stream events (delta, final, error) |
| `tick` | Heartbeat tick every 30s |
| `health` | Health snapshot updates |
| `shutdown` | Server shutting down |

---

## 5. Key Components and Their Responsibilities

### 5.1 GatewayServer (`server.impl.ts`)

**Responsibility**: Main orchestrator for the entire gateway

**Key duties**:
- Configuration loading and validation
- Authentication bootstrap
- HTTP/WebSocket server creation
- Plugin loading
- Channel manager initialization
- Cron service setup
- Heartbeat runner
- Config hot-reload
- Graceful shutdown

### 5.2 Server Methods (`server-methods.ts`)

**Responsibility**: RPC method dispatch and authorization

```typescript
export async function handleGatewayRequest(opts) {
  // 1. Authorize method by role and scope
  // 2. Rate limit control-plane writes
  // 3. Find handler
  // 4. Execute handler with context
}
```

**Handler signature**:
```typescript
type GatewayRequestHandler = (opts: {
  req: RequestFrame;
  params: Record<string, unknown>;
  client: GatewayClient | null;
  respond: (ok: boolean, payload?: unknown, error?: ErrorShape) => void;
  context: GatewayRequestContext;
}) => Promise<void> | void;
```

### 5.3 GatewayClient (`client.ts`)

**Responsibility**: Client-side WebSocket connection management

**Features**:
- Automatic reconnection with backoff
- Request/response correlation via pending map
- Tick watchdog (detect silent stalls)
- TLS fingerprint validation
- Device authentication

### 5.4 Session Management

**Session Store** (`~/.moonclaw/agents/<agentId>/sessions/sessions.json`):
```typescript
type SessionEntry = {
  sessionId: string;
  updatedAt: number;
  channel?: string;
  thinkingLevel?: string;
  modelOverride?: string;
  providerOverride?: string;
  skillsSnapshot?: SkillsSnapshot;
  // ... delivery context fields
};
```

**Session Transcript** (`~/.moonclaw/agents/<agentId>/sessions/<sessionId>.jsonl`):
- JSONL format with parent chain for compaction
- Uses `SessionManager` from Pi agent for proper message linking

### 5.5 Channel Manager (`server-channels.ts`)

**Responsibility**: Manage messaging channel connections

- Start/stop channels (WhatsApp, Discord, Telegram, etc.)
- Handle channel login/logout
- Provide runtime snapshots

### 5.6 Node Registry (`node-registry.ts`)

**Responsibility**: Track connected mobile/desktop nodes

- Register/unregister nodes on connect/disconnect
- Route events to specific nodes
- Support remote skill execution

### 5.7 Exec Approval Manager (`exec-approval-manager.ts`)

**Responsibility**: Handle command execution approvals

- Queue approval requests
- Track decisions
- Support mobile node approval flows

### 5.8 Dedupe Cache (`server-shared.ts`)

**Responsibility**: Idempotency for agent runs

```typescript
type DedupeEntry = {
  ts: number;
  ok: boolean;
  payload?: unknown;
  error?: ErrorShape;
};
```

### 5.9 Broadcast System (`server-broadcast.ts`)

**Responsibility**: Event distribution to clients

```typescript
type BroadcastFn = (
  event: string,
  payload: unknown,
  opts?: { dropIfSlow?: boolean; stateVersion?: StateVersion }
) => void;
```

---

## 6. Authentication and Authorization

### Auth Modes
- **token**: Static bearer token
- **password**: Password-based auth
- **device**: Public key signature challenge

### Role-Based Access
- **operator**: Full access (CLI, Control UI)
- **node**: Limited access (mobile nodes)

### Scope-Based Authorization (`method-scopes.ts`)

```typescript
const SCOPE_PERMISSIONS = {
  "operator.admin": ["*"],
  "operator.config.read": ["config.get", "config.schema"],
  "operator.config.write": ["config.set", "config.apply", "config.patch"],
  "operator.sessions.read": ["sessions.list", "sessions.preview"],
  // ...
};
```

---

## 7. Concurrency Model

### Lanes (`lanes.ts`)

The gateway uses "lanes" for concurrency control:
- **Global lane**: For global operations
- **Session lane**: Per-session serialization (one agent run per session at a time)
- **Subagent lane**: For spawned subagents

### Command Queue (`command-queue.ts`)

- FIFO queue per lane
- Supports abort signals
- Priority handling

---

## 8. Configuration Hot Reload

### Reload Modes (`config-reload.ts`)

| Mode | Behavior |
|------|----------|
| `off` | No reload |
| `hot` | Apply safe changes only |
| `restart` | Restart on reload-required changes |
| `hybrid` | Hot when safe, restart when required |

---

## 9. Implementation Notes for MoonBit

### Recommended Approach

1. **Protocol Layer**: Define frame types as discriminated unions with JSON serialization
2. **WebSocket Handler**: Use an event-driven architecture with message handlers
3. **Method Registry**: Use a hashmap from method names to handler functions
4. **Session Store**: Use SQLite or JSON files with proper locking
5. **Agent Runner**: Consider spawning separate processes or using async tasks

### Key Patterns to Replicate

1. **Two-stage async responses**: Accept immediately, send final result later
2. **Idempotency via dedupe cache**: Prevent duplicate agent runs
3. **Challenge-response auth**: Prevent replay attacks
4. **Tick watchdog**: Detect stalled connections
5. **Graceful shutdown**: Broadcast shutdown event before closing

### File Structure Suggestion

```
gateway/
  protocol/
    frames.mbt          # Frame type definitions
    schema.mbt          # JSON schema validators
  server/
    ws.mbt              # WebSocket server
    methods.mbt         # Method handlers
    session.mbt         # Session management
    auth.mbt            # Authentication
  client/
    client.mbt          # Gateway client
  agent/
    runner.mbt          # Agent execution
    context.mbt         # Agent context building
```

---

## 10. Key Files Reference

| File | Description |
|------|-------------|
| `src/gateway/server.impl.ts` | Main gateway server implementation |
| `src/gateway/server/ws-connection.ts` | WebSocket connection handling |
| `src/gateway/server-methods/agent.ts` | Agent method handler |
| `src/gateway/server-methods-list.ts` | List of all server methods |
| `src/gateway/protocol/schema/frames.ts` | Frame type definitions |
| `src/gateway/client.ts` | Client-side connection management |
| `src/commands/agent.ts` | Agent command orchestration |
| `src/agents/pi-embedded-runner/run.ts` | Embedded agent runner |
| `src/gateway/server-channels.ts` | Channel manager |
| `src/gateway/node-registry.ts` | Node registry for mobile/desktop |
| `src/gateway/exec-approval-manager.ts` | Command approval handling |
| `src/gateway/server-shared.ts` | Shared utilities including dedupe cache |
| `src/gateway/server-broadcast.ts` | Event broadcasting |
| `src/gateway/method-scopes.ts` | Scope-based authorization |
| `src/agents/lanes.ts` | Concurrency control lanes |
| `src/process/command-queue.ts` | Command queue implementation |
| `src/gateway/config-reload.ts` | Configuration hot reload |

---

This architecture provides a robust foundation for building a similar gateway service in MoonBit, with clear separation of concerns and well-defined interfaces between components.
