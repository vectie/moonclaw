# Event Package

The event package defines the event system used throughout the agent lifecycle for tracking and responding to state changes.

## Core Types

### `Event`

The main event structure with metadata.

```moonbit nocheck
///|
pub struct Event {
  id : @uuid.Uuid
  created : @clock.Timestamp
  desc : EventDesc
} derive(Eq, Show)
```

### `EventDesc`

Enumeration of all possible event types in the agent lifecycle.

```moonbit nocheck
///|
pub(all) enum EventDesc {
  ModelLoaded(name~ : String)
  PreConversation
  PostConversation
  SystemPromptSet(String?)
  MessageUnqueued(id~ : @uuid.Uuid)
  MessageQueued(id~ : @uuid.Uuid)
  ToolAdded(@tool.ToolDesc)
  PreToolCall(@ai.ToolCall)
  PostToolCall(@ai.ToolCall, result~ : Result[Json, Json], rendered~ : String)
  TokenCounted(Int)
  ContextPruned(origin_token_count~ : Int, pruned_token_count~ : Int)
  AssistantMessage(
    usage~ : @ai.Usage?,
    tool_calls~ : Array[@ai.ToolCall],
    String
  )
  UserMessage(String)
  Cancelled
  Failed(Json)
  Pruned(id~ : @uuid.Uuid)
}
```

## Event Categories

### Lifecycle Events

| Event | Description |
|-------|-------------|
| `ModelLoaded` | AI model has been loaded |
| `PreConversation` | Conversation is starting |
| `PostConversation` | Conversation has ended |
| `Cancelled` | Agent was cancelled |
| `Failed` | An error occurred |

### Message Events

| Event | Description |
|-------|-------------|
| `SystemPromptSet` | System prompt was set/cleared |
| `MessageQueued` | Message added to pending queue |
| `MessageUnqueued` | Message moved to processing |
| `UserMessage` | User or tool message content |
| `AssistantMessage` | Response from AI model |

### Tool Events

| Event | Description |
|-------|-------------|
| `ToolAdded` | Tool registered with agent |
| `PreToolCall` | Before tool execution |
| `PostToolCall` | After tool execution (with result) |

### Context Management Events

| Event | Description |
|-------|-------------|
| `TokenCounted` | Token count calculated |
| `ContextPruned` | Context trimmed for budget |
| `Pruned` | Specific event pruned from history |

## Key APIs

### Event Creation

```moonbit nocheck
pub fn Event::new(
  id~ : @uuid.Uuid,
  created? : @clock.Timestamp,
  desc : EventDesc,
) -> Event
```

### Event Classification

```moonbit nocheck
// Is this an incoming/external event?
pub fn Event::is_incoming(self : Event) -> Bool

// Does this event end the conversation?
pub fn Event::is_stopping(self : Event) -> Bool

// Does this event start the conversation?
pub fn Event::is_starting(self : Event) -> Bool

// Is this a cancellation event?
pub fn Event::is_cancellation(self : Event) -> Bool
```

## EventTarget

A type for emitting events to listeners.

```moonbit nocheck
type EventTarget

pub fn EventTarget::new(
  uuid? : @uuid.Generator,
  clock? : &@clock.Clock
) -> Self raise

pub fn EventTarget::emit(Self, EventDesc, id? : @uuid.Uuid) -> Unit
pub fn EventTarget::add_listener(Self, async (Event) -> Unit) -> Unit
pub async fn EventTarget::start(Self) -> Unit
pub async fn EventTarget::flush(Self) -> Unit
```

## ExternalEventQueue

A queue for receiving external events from the environment.

```moonbit nocheck
type ExternalEventQueue

pub fn ExternalEventQueue::new() -> Self raise
pub fn ExternalEventQueue::poll(Self) -> Array[Event]
pub fn ExternalEventQueue::send(Self, EventDesc) -> Unit
```

## Typical Event Flow

```
ModelLoaded
    │
    ▼
SystemPromptSet
    │
    ▼
MessageQueued ──► MessageUnqueued ──► UserMessage
    │
    ▼
PreConversation
    │
    ▼
TokenCounted
    │
    ▼
ContextPruned (if needed)
    │
    ▼
AssistantMessage
    │
    ├──► PreToolCall ──► PostToolCall ──► UserMessage (tool result)
    │                                    │
    │                                    └──► (loop back for more tool calls)
    │
    ▼
PostConversation
```

## Usage Example

```moonbit nocheck
// Create event target
let target = @event.EventTarget::new()

// Add listener
target.add_listener(fn(event) {
  match event.desc {
    AssistantMessage(content, ..) => println("AI: \{content}")
    PostToolCall(tc, result~, ..) => println("Tool \{tc.name}: \{result}")
    _ => ()
  }
})

// Start processing events
target.start()

// Emit events
target.emit(UserMessage("Hello!"))
target.emit(AssistantMessage(usage=None, tool_calls=[], "Hi there!"))
```

## Dependencies

- `ai`: Message and tool call types
- `tool`: Tool descriptor types
- `uuid`: Unique identifiers
- `clock`: Timestamps
