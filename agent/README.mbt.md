# Agent Package

The agent package provides the core AI agent functionality that manages conversations, executes tools, and handles the conversation loop.

## Core Structs

### `Agent`

The main agent struct that encapsulates all state and behavior for an AI assistant.

```moonbit nocheck
///|
pub(all) struct Agent {
  uuid : @uuid.Generator
  cwd : String
  model : @model.Model
  logger : @pino.Logger
  event_target : @broadcast.Broadcast[@event.Event]
  mut web_search : Bool
  // private fields: tools, history, input_queue, etc.
}
```

**Key Fields:**
- `uuid`: Generator for unique identifiers
- `cwd`: Current working directory for tool operations
- `model`: AI model configuration
- `event_target`: Broadcast channel for lifecycle events

### `QueuedMessage`

Represents a message waiting to be processed.

```moonbit nocheck
///|
pub struct QueuedMessage {
  id : @uuid.Uuid
  message : @ai.Message
  web_search : Bool
}
```

## Key APIs

### Creating an Agent

```moonbit nocheck
pub async fn new(
  name? : String,
  model : @model.Model,
  uuid? : @uuid.Generator,
  logger? : @pino.Logger,
  system_message? : String,
  user_message? : String,
  home? : StringView,
  cwd~ : StringView,
  web_search? : Bool = false,
  external_events? : @event.ExternalEventQueue,
  history? : @conversation.Conversation,
) -> Agent
```

### Loading an Existing Agent

```moonbit nocheck
pub async fn load(
  model : @model.Model,
  history : @conversation.Conversation,
  // ... other optional parameters
) -> Agent
```

### Managing Messages

```moonbit nocheck
// Queue a message for processing
pub fn Agent::queue_message(
  agent : Agent,
  message : @ai.Message,
  web_search? : Bool = agent.web_search,
) -> @uuid.Uuid

// Get all queued messages
pub fn Agent::queued_messages(self : Agent) -> Array[QueuedMessage]

// Clear all pending inputs
pub fn Agent::clear_inputs(self : Agent) -> Array[QueuedMessage]
```

### Tool Management

```moonbit nocheck
// Add a single tool
pub fn[Output : ToJson + Show] Agent::add_tool(
  self : Agent,
  tool : @tool.Tool[Output],
  enabled? : Bool
) -> Unit

// Add multiple tools
pub fn Agent::add_tools(Self, Array[@tool.AgentTool]) -> Unit

// Set which tools are enabled
pub fn Agent::set_enabled_tools(Self, @set.Set[String]) -> Unit
```

### Starting the Conversation

```moonbit nocheck
pub async fn Agent::start(agent : Agent) -> Unit
```

## Conversation Loop Algorithm

```
Agent::start()
    │
    ├─► Spawn event_target in background
    │
    └─► Loop:
            │
            ├─► poll_external_events()
            │       │
            │       ├─► Handle Cancelled → break
            │       └─► Handle UserMessage → inject into queue
            │
            ├─► Pop from pending_queue → input_queue
            │
            ├─► If input_queue empty → break
            │
            ├─► prepare_messages_for_request()
            │       │
            │       ├─► Calculate pruning
            │       ├─► Emit Pruned events
            │       └─► Apply prompt caching
            │
            ├─► @openai.chat() → Get response
            │
            ├─► Emit AssistantMessage event
            │
            ├─► Calibrate token counter
            │
            └─► Execute tool calls → Queue results
```

## Event System

The agent emits events throughout its lifecycle:

| Event | When |
|-------|------|
| `ModelLoaded` | Agent initialized with model |
| `PreConversation` | Conversation starts |
| `MessageQueued` | Message added to pending queue |
| `MessageUnqueued` | Message moved to input queue |
| `TokenCounted` | Tokens counted before request |
| `ContextPruned` | Context trimmed to fit budget |
| `AssistantMessage` | Response received from model |
| `PreToolCall` | Before tool execution |
| `PostToolCall` | After tool execution |
| `UserMessage` | User/Tool message injected |
| `PostConversation` | Conversation ends |
| `Cancelled` | Agent cancelled |

## Usage Example

```moonbit nocheck
// Create and configure agent
let agent = @agent.new(
  model=model_config,
  cwd="/project/path",
  system_message="You are a helpful coding assistant.",
)

// Add event listener
agent.add_listener(fn(event) {
  match event.desc {
    AssistantMessage(content, ..) => println(content)
    _ => ()
  }
})

// Add tools
agent.add_tools([
  @execute_command.new(job_manager).to_agent_tool(),
  @read_file.new(file_manager).to_agent_tool(),
])

// Queue initial message
agent.queue_message(@ai.user_message(content="Help me debug this code"))

// Start processing
agent.start()
```

## Dependencies

- `model`: Model configuration
- `ai`: Message types
- `event`: Event definitions
- `tool`: Tool types
- `conversation`: Conversation history
- `openai`: API client
- `context_pruner`: Token management
- `broadcast`: Event distribution
