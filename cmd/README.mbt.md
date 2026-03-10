# CMD Packages

This directory contains command-line entry points for the Moonclaw application.

## Available Commands

| Command | Description |
|---------|-------------|
| `main` | Main CLI entry point |
| `daemon` | Background daemon server |
| `gateway` | HTTP/RPC gateway with channels and orchestration |
| `server` | HTTP server for AI interactions |
| `jsonl2md` | Convert JSONL logs to Markdown |
| `test` | Test utilities |

---

## main

The primary CLI entry point with multiple subcommands.

### Subcommands

#### `exec` / `execute`

Execute a single prompt and output results as JSON.

```bash
moonclaw exec -p "Write a function to sort an array"
moonclaw exec -p "Help me debug" -m claude-sonnet
```

**Output Format (JSON Lines):**
```json
{"method": "moonclaw.agent.tool_added", "params": {"tool": {...}}}
{"method": "moonclaw.agent.message", "params": {"message": {"role": "user", "content": "..."}}}
{"method": "moonclaw.agent.conversation_start", "params": {}}
{"method": "moonclaw.agent.request_completed", "params": {"usage": {...}, "message": {...}}}
{"method": "moonclaw.agent.post_tool_call", "params": {"tool_call": {...}, "json": {...}, "text": "..."}}
{"method": "moonclaw.agent.conversation_end", "params": {}}
```

#### `tui`

Launch the terminal UI.

```bash
moonclaw tui
```

**Features:**
- Interactive chat interface
- Real-time message display
- Command input with history
- Status indicators
- Tool execution folding via `Ctrl+O`
- Clean exit via `Ctrl+C` / `Ctrl+D`
- Live model / agent / session header state

Current architecture:

```text
moonclaw tui
  -> load model
  -> create or resume Moonclaw
  -> construct internal TUI
  -> wire callbacks
  -> listen to agent events
  -> run local event loop
```

#### `gateway`

Launch the long-running gateway service or interact with it.

```bash
moonclaw gateway start
moonclaw gateway connect
moonclaw gateway agent --message "Hello" --wait
moonclaw gateway health
```

Current capabilities behind the gateway:

- agent execution and waiting
- session management
- SSE events
- channel and extension registry
- Feishu webhook ingress
- agent mailboxes
- coordination tasks
- pipelines

#### `interactive`

Interactive conversation mode.

```bash
moonclaw interactive
```

---

## daemon

Long-lived background server for managing multiple agent sessions.

### Architecture

```
Daemon
    │
    ├── HTTP Server (port from config or ephemeral)
    │
    ├── Process Manager
    │
    ├── Task Registry (by_cwd, by_id)
    │
    └── Conversation Manager
```

### Key Components

```moonbit nocheck
struct Daemon {
  clock : &@clock.Clock
  models : @model.Loader
  uuid : @uuid.Generator
  process : @spawn.Manager
  by_cwd : Map[String, TaskLock]
  by_id : Map[@uuid.Uuid, Task]
  httpx : @httpx.Server
  port : Int
  events : @broadcast.Broadcast[Event]
  conversations : @conversation.Manager
  home : String
}
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Web UI |
| `/api/tasks` | GET | List tasks |
| `/api/tasks` | POST | Create task |
| `/api/tasks/:id` | GET | Get task |
| `/api/tasks/:id/events` | GET | Stream events |
| `/api/models` | GET | List models |
| `/api/auth/:provider` | GET | Start OAuth |
| `/api/auth/:provider/callback` | GET | OAuth callback |

### Lock File

The daemon uses a lock file at `~/.moonclaw/daemon.json`:
```json
{
  "version": "0.1.0",
  "port": 8080,
  "pid": 12345
}
```

### Usage

```bash
# Start daemon
moonclaw daemon

# With specific port
moonclaw daemon --port 3000

# Without lock (for testing)
moonclaw daemon --no-lock
```

---

## server

HTTP server for AI interactions without daemon complexity.

### Features

- Single conversation endpoint
- Message creation API
- System prompt configuration
- Tool management

### API

```moonbit nocheck
// Create message
POST /api/messages
{
  "role": "user",
  "content": "Hello"
}

// Set system prompt
PUT /api/system-prompt
{
  "prompt": "You are a helpful assistant."
}

// Set enabled tools
PUT /api/tools
{
  "tools": ["execute_command", "read_file"]
}
```

---

## jsonl2md

Convert JSONL conversation logs to readable Markdown.

### Usage

```bash
moonclaw jsonl2md input.jsonl output.md
```

### Output Format

```markdown
## User

Hello, how can you help?

## Assistant

I can help you with coding tasks...

### Tool Call: read_file

**Arguments:**
```json
{"path": "main.mbt"}
```

**Result:**
```
File contents...
```

## Assistant

Based on the file...
```

---

## Internal: test_utils

Testing utilities used across command tests.

```moonbit nocheck
pub fn create_test_event(desc : @event.EventDesc) -> @event.Event
pub fn create_test_conversation(events : Array[@event.Event]) -> @conversation.Conversation
```

---

## Argument Parsing

The main command uses a custom argument parser:

```moonbit nocheck
enum Command {
  Execute(prompt : String, model : String?)
  TUI
  Interactive
  Daemon(port : Int, lock : Bool)
  Server(port : Int)
  Jsonl2Md(input : String, output : String)
}
```

---

## Entry Point Flow

```
main()
    │
    ├─► Parse arguments
    │
    ├─► Initialize backtrace
    │
    └─► Dispatch to command
            │
            ├─► exec: Create Moonclaw, run, output JSON
            │
            ├─► tui: Initialize TUI, run event loop
            │
            ├─► daemon: Create Daemon, serve HTTP
            │
            └─► ...
```

---

## Configuration

Commands read configuration from:

1. `~/.moonclaw/models.json` - Model configurations
2. `~/.moonclaw/config.json` - General settings
3. `.trae/rules/` - Project rules
4. `.trae/skills/` - Project skills
5. Command-line arguments (highest priority)
