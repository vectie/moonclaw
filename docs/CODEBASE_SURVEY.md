# MoonClaw Codebase Architecture Survey

## Project Overview

**MoonClaw** (module name: `vectie/moonclaw`) is an AI-powered coding assistant built in MoonBit. It provides an agent-based architecture for interacting with various LLM providers and executing tools to perform file operations, code modifications, and other tasks.

## Project Structure

The project follows MoonBit's package organization where each directory is a package with its own `moon.pkg` file.

### Top-Level Directories

| Directory | Purpose |
|-----------|---------|
| `/agent` | Core agent implementation with conversation loop, tool execution |
| `/ai` | Message types and AI abstractions |
| `/clock` | Time and timestamp utilities |
| `/cmd` | Command-line entry points (daemon, server, main CLI, gateway, etc.) |
| `/event` | Event system for agent lifecycle |
| `/file` | File manager abstraction |
| `/gateway` | **NEW** Gateway service architecture (protocol, server, client) |
| `/internal` | Internal utilities and integrations |
| `/job` | Job management system |
| `/model` | Model configuration and loading |
| `/oauth` | OAuth implementations (Codex, Copilot) |
| `/prompt` | System prompts |
| `/sdk` | SDK for Java, Node.js, Python |
| `/tool` | Tool abstraction and JSON schema |
| `/tools` | Concrete tool implementations |
| `/ui` | UI components (VS Code extension, web) |

## Main Entry Points

The main CLI entry point is at `cmd/main/main.mbt`:

```moonbit
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  match args[1:] {
    ["conversations"] => @conversation.list()
    ["conversation", .. rest] => @conversation.show(rest)
    ["server", .. rest] => @server.start(rest)
    ["daemon", .. rest] => @daemon.start(rest)
    ["gateway", .. rest] => @gateway.main()
    ["exec", .. rest] => @exec.exec(rest)
    ["tui", .. rest] => @tui.tui_interactive(rest)
    ["version"] => println(@buildinfo.version)
    [.. rest] => @interactive.interactive(rest)
  }
}
```

### Main Modes

1. **Interactive Mode** (default) - Terminal-based interactive chat
2. **Server Mode** (`server`) - HTTP server with REST API and SSE events
3. **Daemon Mode** (`daemon`) - Long-lived supervisor managing multiple tasks
4. **Gateway Mode** (`gateway`) - **NEW** Long-running gateway service with agent spawning

## Core Architecture

### 1. Agent System (`agent/agent.mbt`)

The `Agent` struct is the central orchestrator:

```moonbit
pub(all) struct Agent{
  uuid : @uuid.Generator
  cwd : String
  model : @model.Model
  logger : @pino.Logger
  priv tools : Map[String, Tool]
  priv history : @conversation.Conversation
  priv mut input_queue : Array[@ai.Message]
  priv pending_queue : @deque.Deque[QueuedMessage]
  event_target : @broadcast.Broadcast[@event.Event]
  priv token_counter : @token_counter.Counter
  priv context_pruner : @context_pruner.Pruner
  priv session_manager : @conversation.Manager
  priv rules : @rules.Loader
  priv skills : @skills.Loader
  mut web_search : Bool
  priv external_events : @event.ExternalEventQueue
}
```

**Key Agent Functions:**
- `Agent::start()` - Main conversation loop
- `Agent::queue_message()` - Queue messages for processing
- `Agent::execute_tool()` - Execute tool calls from the model
- `Agent::add_tool()` - Register tools

### 2. Conversation Flow

```
User Message → Queue → Agent::start() loop:
  1. Poll external events (cancellation, immediate messages)
  2. Prepare messages (token counting, context pruning, caching)
  3. Send to OpenAI API
  4. Receive AssistantMessage
  5. Execute tool calls if any
  6. Loop until no more tool calls
  7. PostConversation event
```

### 3. Event System (`event/event.mbt`)

Events track the entire conversation lifecycle:

```moonbit
pub(all) enum EventDesc {
  ModelLoaded(name~ : String)
  PreConversation
  PostConversation
  SystemPromptSet(String?)
  MessageQueued(id~ : @uuid.Uuid)
  MessageUnqueued(id~ : @uuid.Uuid)
  ToolAdded(@tool.ToolDesc)
  PreToolCall(@ai.ToolCall)
  PostToolCall(@ai.ToolCall, result~ : Result[Json, Json], rendered~ : String)
  TokenCounted(Int)
  ContextPruned(origin_token_count~ : Int, pruned_token_count~ : Int)
  AssistantMessage(usage~ : @ai.Usage?, tool_calls~ : Array[@ai.ToolCall], String)
  UserMessage(String)
  Cancelled
  Failed(Json)
  Pruned(id~ : @uuid.Uuid)
}
```

## OpenAI Integration (`internal/openai/ai.mbt`)

The OpenAI integration supports multiple providers:

```moonbit
pub async fn chat(
  model~ : @model.Model,
  request : Request,
  logger? : @pino.Logger,
  extra_body? : Map[String, Json],
) -> ChatCompletion {
  match model.model_type {
    SaaS(CodexOAuth) => chat_codex(model~, request, logger~)
    SaaS(Copilot) => chat_copilot(model~, request, logger~)
    SaaS(Anthropic) => chat_anthropic(model~, request, logger~)
    _ => chat_openai(model~, request, logger~, extra_body~)
  }
}
```

### Supported Providers

- **OpenAI** - Standard OpenAI API
- **Anthropic** - Claude models with message format conversion
- **CodexOAuth** - ChatGPT Codex via OAuth
- **Copilot** - GitHub Copilot via OAuth
- **Qwen** - Alibaba's Qwen models
- **Kimi** - Moonshot AI's Kimi models
- **OpenRouter** - Multi-model proxy

### Key Files in `internal/openai/`

| File | Description |
|------|-------------|
| `ai.mbt` | Main chat completion logic |
| `request.mbt` | Request structure |
| `builder.mbt` | Stream response builder |
| `responses/types.mbt` | Codex Responses API types |

## Server Architecture

### Daemon Mode (`cmd/daemon/daemon.mbt`)

The daemon is a long-lived supervisor that:
- Manages multiple per-workspace tasks
- Provides REST API for task management
- Handles OAuth authentication flows

**Key Routes:**
```
GET  /                      → UI index.html
GET  /v1/events             → SSE event stream
GET  /v1/models             → List available models
POST /v1/task               → Create new task
GET  /v1/tasks              → List all tasks
GET  /v1/task/{id}          → Get task details
GET  /v1/task/{id}/events   → Task event stream
GET  /v1/auth/status        → Auth status
POST /v1/auth/codex/start   → Start Codex OAuth
POST /v1/auth/copilot/start → Start Copilot OAuth
```

### Server Mode (`cmd/server/server.mbt`)

Single-task HTTP server with:
- REST API for message creation
- SSE for real-time events
- Tool management endpoints

**Key Routes:**
```
GET  /v1/status           → Agent status (idle/busy)
POST /v1/message          → Create message
GET  /v1/events           → SSE event stream
GET  /v1/tools            → List tools
POST /v1/enabled-tools    → Enable/disable tools
POST /v1/cancel           → Cancel running task
```

## NEW: Gateway Service Architecture

### Overview

The new gateway service provides a long-running backend service that can spawn agents to handle tasks, It's inspired by the OpenClaw reference design and provides:

1. **Frame-based Protocol** - Request/Response/Event frames
2. **Two-stage Async Responses** - Accept immediately, execute in background
3. **Session Management** - With persisted JSON-backed session state plus dedupe cache
4. **Channel Runtime Persistence** - Persistent channel config and auto-start intent
5. **Challenge-Response Auth** - Token-based authentication

### Gateway Protocol (`gateway/protocol/`)

#### Frame Types

```moonbit
pub enum Frame {
  Req(Request)
  Res(Response)
  Event(EventFrame)
}

pub struct Request {
  id : String
  method : String
  params : Json?
}

pub struct Response {
  id : String
  ok : Bool
  payload : Json?
  error : ErrorShape?
}

pub struct EventFrame {
  event : String
  payload : Json?
  seq : Int?
  state_version : StateVersion?
}
```

#### Key Payload Types

```moonbit
pub struct AgentParams {
  message : String
  session_key : String?
  cwd : String?
  model : String?
  provider : String?
  run_id : String?
  idempotency_key : String?
}

pub struct AgentAcceptedPayload {
  run_id : String
  status : String
  accepted_at : Int
}
```

### Gateway Server (`gateway/server/`)

#### Core Components

```moonbit
pub struct Gateway {
  clock : @clock.Clock
  uuid : @uuid.Generator
  httpx : @httpx.Server
  port : Int
  events : @broadcast.Broadcast[GatewayEvent]
  auth : AuthConfig
  sessions : SessionManager
  dedupe : DedupeCache
  logger : @pino.Logger
  home : String
  cwd : String
  models : @model.Loader
  mut started_at : Int
  mut pending_requests : Int
}
```

#### Key Endpoints

```
GET  /                      → Index with API info
GET  /health                → Health check
GET  /v1/events             → SSE event stream
GET  /v1/runs               → List runs
POST /v1/rpc                → RPC endpoint (frame-based)
POST /v1/agent              → Agent execution endpoint
GET  /v1/channels           → List channels
GET  /v1/channels/{id}      → Get channel details
POST /v1/channels/{id}/configure → Configure channel accounts
POST /v1/channels/{id}/start     → Start a channel account
POST /v1/channels/{id}/stop      → Stop a channel account
GET  /v1/extensions         → List extensions
POST /v1/mailbox            → Create mailbox
POST /v1/coordination       → Create coordination task
POST /v1/pipeline           → Create pipeline
POST /v1/shutdown           → Shutdown gateway
```

#### Two-Stage Async Response Pattern

```moonbit
async fn Gateway::handle_agent(self, r, w) {
  // 1. Check dedupe cache for idempotency
  // 2. Send immediate acceptance (HTTP 202)
  let accepted = AgentAcceptedPayload::{ run_id, status: "accepted", ... }
  w.write_header(202)
  w.write(accepted.to_json().stringify())
  w.flush()
  
  // 3. Execute agent in background
  let result = self.execute_agent(run_id~, params)
  
  // 4. Store result in dedupe cache
  self.dedupe.set(idempotency_key, entry)
}
```

### Gateway Client (`gateway/client/`)

```moonbit
pub struct Client {
  base_url : String
  token : String?
  http : @http.Client
  uuid : @uuid.Generator
  logger : @pino.Logger
  mut connected : Bool
}

pub async fn Client::connect(self) -> Result[HelloOk, String]
pub async fn Client::agent(self, message~) -> Result[AgentAcceptedPayload, String]
pub async fn Client::wait_agent(self, run_id~) -> Result[Json, String]
pub async fn Client::health(self) -> Result[HealthPayload, String]
```

## Model Loading (`model/loader.mbt`)

Models are loaded from configuration files:
- `.moonclaw/models/models.json` (project-level)
- `~/.moonclaw/models/models.json` (user-level)

The loader auto-detects models from environment variables:
- `OPENROUTER_API_KEY` / `OPENAI_API_KEY`
- `QWEN_API_KEY` / `DASHSCOPE_API_KEY`
- `KIMI_API_KEY` / `MOONSHOT_API_KEY`

## Tool System

### Tool Abstraction (`tool/tool.mbt`)

```moonbit
pub struct Tool[Output] {
  desc : ToolDesc
  priv f : ToolFn[Output]
}

pub enum ToolResult[Output] {
  Ok(Output)
  Error(Error, String)
}
```

### Available Tools (in `/tools/`)

| Tool | Description |
|------|-------------|
| `read_file` | Read file contents with line range support |
| `read_multiple_files` | Read multiple files at once |
| `write_to_file` | Write content to files |
| `replace_in_file` | Search and replace in files |
| `list_files` | List directory contents |
| `search_files` | Search files using regex |
| `execute_command` | Execute shell commands |
| `apply_patch` | Apply unified diff patches |
| `todo` | Task/todo management |
| `list_jobs` | List background jobs |
| `wait_job` | Wait for job completion |

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                           │
│  (CLI / TUI / HTTP Server / VS Code Extension / SDK / Gateway)  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                          Agent                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Conversation │  │    Tools     │  │   External Events    │  │
│  │   History    │  │   Registry   │  │       Queue          │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │    Rules     │  │   Skills     │  │   Context Pruner     │  │
│  │    Loader    │  │   Loader     │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      OpenAI Integration                          │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌─────────────┐  │
│  │   OpenAI   │ │ Anthropic  │ │  Copilot   │ │    Codex    │  │
│  │    API     │ │   Claude   │ │   OAuth    │ │    OAuth    │  │
│  └────────────┘ └────────────┘ └────────────┘ └─────────────┘  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐                  │
│  │   Qwen     │ │    Kimi    │ │OpenRouter  │                  │
│  └────────────┘ └────────────┘ └────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Tool Execution                              │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌─────────────┐  │
│  │ read_file  │ │write_to_file│ │search_files│ │execute_cmd  │  │
│  └────────────┘ └────────────┘ └────────────┘ └─────────────┘  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌─────────────┐  │
│  │apply_patch │ │replace_file│ │   todo     │ │  list_jobs  │  │
│  └────────────┘ └────────────┘ └────────────┘ └─────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## SDK Support

The project provides SDKs for external integration:
- **Java SDK** (`/sdk/java`) - Maven-based Java client
- **Node.js SDK** (`/sdk/nodejs`) - TypeScript client
- **Python SDK** (`/sdk/python`) - Python client

## Key Configuration Files

1. **moon.mod.json** - Module definition with dependencies:
   - `moonbitlang/async` - Async runtime
   - `moonbitlang/x` - Standard library extensions
   - `moonbitlang/regexp` - Regex support
   - `moonbit-community/yaml` - YAML parsing

2. **Model Configuration** - `.moonclaw/models/models.json`:
   - Model definitions with API keys, base URLs, and token limits

3. **OAuth Credentials** - Stored in `~/.moonclaw/`:
   - Codex: `codex_credentials.json`
   - Copilot: `copilot_credentials.json`

## Key Internal Packages

### `/internal/httpx`
HTTP server utilities with JSON support, CORS, SSE streaming, and file serving.

### `/internal/fsx`
File system utilities including read/write, directory operations, file locking, and temp directories.

### `/internal/pino`
Logging system with console and file transports, supporting multiple log levels.

### `/internal/broadcast`
Broadcast channel for event distribution to multiple subscribers.

### `/internal/uuid`
UUID generation (v4) with configurable generators.

### `/internal/rand`
Random number generation using ChaCha8.

## Summary

MoonClaw is a sophisticated AI coding assistant built in MoonBit with:

1. **Multi-provider support** - Works with OpenAI, Anthropic, GitHub Copilot, Codex, Qwen, Kimi, and OpenRouter
2. **Agent-based architecture** - Event-driven conversation loop with tool execution
3. **Flexible deployment** - CLI, TUI, HTTP server, daemon mode, or gateway mode
4. **Rich tool ecosystem** - File operations, code modification, command execution
5. **Context management** - Token counting, context pruning, prompt caching
6. **OAuth integration** - Seamless authentication for Copilot and Codex
7. **Multi-language SDK** - Java, Node.js, Python clients for integration
8. **NEW: Gateway Service** - Long-running backend service with agent spawning capability
