# Internal Packages

This directory contains internal utilities and supporting modules used by the main packages.

## Package Overview

| Package | Purpose |
|---------|---------|
| `broadcast` | Event distribution system |
| `cache` | Prompt caching for API optimization |
| `content_extractor` | Extract content from various file types |
| `context_pruner` | Token budget management |
| `conversation` | Conversation history persistence |
| `fsx` | Extended file system operations |
| `git` | Git operations |
| `httpx` | HTTP server and client utilities |
| `jsonx` | JSON utilities |
| `lru` | LRU cache implementation |
| `mock` | Mocking utilities for testing |
| `openai` | OpenAI API client |
| `openrouter` | OpenRouter model listing |
| `os` | OS utilities |
| `pathx` | Path manipulation |
| `pino` | Logging |
| `rand` | Random number generation |
| `readline` | Terminal readline |
| `rules` | Rule loading |
| `schema` | JSON Schema utilities |
| `signal` | Signal handling |
| `skills` | Skill loading |
| `spawn` | Process spawning |
| `tiktoken` | Token counting |
| `token_counter` | Token counting for messages |
| `tui` | Terminal UI components |
| `tty` | Terminal utilities |
| `uri` | URI parsing |
| `uuid` | UUID generation |

---

## broadcast

Fan-out event distribution with history.

```moonbit nocheck
struct Broadcast[T] {
  values : Array[T]
  read : @cond_var.Cond
  readers : Array[Reader[T]]
}

pub fn[T] Broadcast::new() -> Broadcast[T]
pub fn[T] Broadcast::put(self : Broadcast[T], data : T) -> Unit
pub async fn[T] Broadcast::read(self : Broadcast[T], index : Int) -> T
pub fn[T] Broadcast::add_listener(self : Broadcast[T], f : async (T) -> Unit) -> Unit
pub async fn[T] Broadcast::flush(self : Broadcast[T]) -> Unit
```

**Algorithm:**
- Maintains a history array of all broadcasted values
- Each listener tracks its own read index
- Slow consumers don't block fast ones
- Values kept until all listeners have consumed them

---

## context_pruner

Manages token budgets by pruning tool outputs.

```moonbit nocheck
struct Pruner {
  logger : @pino.Logger
  token_counter : @token_counter.Counter
  safe_zone_tokens : Int
}

pub struct PruneResult {
  pruned_ids : Array[@uuid.Uuid]
  origin_token_count : Int
  pruned_token_count : Int
}

pub fn Pruner::new(safe_zone_tokens~ : Int, logger~ : @pino.Logger) -> Pruner
pub async fn Pruner::calculate_pruning(
  pruner : Pruner,
  conversation : @conversation.Conversation,
  tools? : Array[@openai.ChatCompletionToolParam],
) -> PruneResult
```

**Algorithm:**
1. Count current tokens in conversation
2. If over budget, identify oldest `PostToolCall` events
3. Greedily prune until within budget
4. Replace tool outputs with placeholder text

---

## conversation

Conversation history persistence and management.

```moonbit nocheck
struct Conversation {
  id : @uuid.Uuid
  name : String
  cwd : String
  created_at : @clock.Timestamp
  mut updated_at : @clock.Timestamp
  mut events : Array[@event.Event]
  mut web_search : Bool
}

pub fn Conversation::messages(self : Conversation, include_system? : Bool) -> Array[@ai.Message]
pub fn Conversation::add_event(self : Conversation, event : @event.Event) -> Unit
pub fn Conversation::system_prompt(self : Conversation) -> String?
```

**Message Reconstruction:**
- Events are replayed to build message array
- `Pruned` events mark deleted content
- System prompt tracked via `SystemPromptSet` events

---

## openai

OpenAI API client with multi-provider support.

```moonbit nocheck
pub async fn chat(
  model~ : @model.Model,
  request : Request,
  logger? : @pino.Logger,
  extra_body? : Map[String, Json],
) -> ChatCompletion
```

**Supported Providers:**
- OpenAI (standard)
- Anthropic (converted format)
- CodexOAuth (ChatGPT backend)
- Copilot (GitHub Copilot)
- OpenRouter (via OpenAI format)

**Features:**
- Streaming response support
- Automatic retry with exponential backoff
- Token refresh for OAuth providers

---

## tiktoken

Token counting using tiktoken encoding.

```moonbit nocheck
pub fn cl100k_base() -> Encoding
pub fn o200k_base() -> Encoding

pub fn Encoding::encode(self : Encoding, text : String) -> Array[Int]
pub fn Encoding::decode(self : Encoding, tokens : ArrayView[Int]) -> String
```

**Encodings:**
- `cl100k_base`: Used by GPT-4, GPT-3.5-turbo
- `o200k_base`: Used by GPT-4o models

---

## token_counter

Token counting for API requests.

```moonbit nocheck
struct Counter {
  logger : @pino.Logger
  mut calibration : Map[String, CalibrationData]
}

pub fn Counter::new(logger~ : @pino.Logger) -> Counter
pub fn Counter::count_message(self : Counter, message : ChatCompletionMessageParam) -> Int
pub fn Counter::count_param(
  self : Counter,
  messages~ : Array[ChatCompletionMessageParam],
  tools? : Array[ChatCompletionToolParam],
) -> Int
pub fn Counter::calibrate(
  self : Counter,
  model_name~ : String,
  estimated_tokens~ : Int,
  actual_tokens~ : Int,
) -> Unit
```

**Calibration:**
- Tracks estimation accuracy per model
- Adjusts future estimates based on actual usage

---

## tui

Terminal UI components.

```moonbit nocheck
pub(all) struct TUI {
  terminal : Terminal
  mut chat_log : ChatLog
  mut editor : Editor
  mut status_loader : Loader
  // ...
}

pub fn TUI::new() -> TUI raise
pub async fn TUI::start(self : TUI) -> Unit
pub async fn TUI::render(self : TUI) -> Unit
pub fn TUI::handle_key(self : TUI, key : Key) -> Bool
```

**Components:**
- `Terminal`: Raw terminal handling
- `ChatLog`: Message display area
- `Editor`: Input field with history
- `Loader`: Animated status indicator

---

## spawn

Process spawning and management.

```moonbit nocheck
struct Manager {
  cwd : String
  // private fields
}

pub fn Manager::new(cwd~ : String) -> Manager
pub fn Manager::spawn(
  self : Manager,
  program : String,
  args : ArrayView[String],
  timeout? : Int,
  cwd? : String,
) -> Process
pub async fn Manager::start(self : Manager) -> Unit
```

---

## fsx

Extended file system operations.

```moonbit nocheck
pub fn exists(path : StringView) -> Bool
pub fn read_file(path : String) -> String raise
pub fn write_to_file(path : String, content : String) -> Unit raise
pub fn make_directory(path : String, recursive? : Bool, exists_ok? : Bool) -> Unit raise
pub fn resolve(path : String) -> String raise
pub fn stat(path : String) -> Stat raise
```

---

## pino

Structured logging.

```moonbit nocheck
struct Logger

pub fn logger(name : String, transport : Transport) -> Logger
pub fn Logger::info(self : Logger, msg : String, data? : Map[String, Json]) -> Unit
pub fn Logger::debug(self : Logger, msg : String, data? : Map[String, Json]) -> Unit
pub fn Logger::error(self : Logger, msg : String, data? : Map[String, Json]) -> Unit
pub fn Logger::warn(self : Logger, msg : String, data? : Map[String, Json]) -> Unit
```

**Transports:**
- File transport: `file:path/to/log.jsonl`
- Sink transport: Discards logs
- Custom transports supported

---

## rules

Rule loading from `.trae/rules/` directory.

```moonbit nocheck
struct Loader {
  cwd : String
  logger : @pino.Logger
  mut rules : Array[Rule]
}

pub fn Loader::new(cwd : String, logger~ : @pino.Logger) -> Loader
pub fn Loader::load(self : Loader) -> Unit
pub fn Loader::apply(self : Loader, messages : Array[@ai.Message]) -> Unit
```

---

## skills

Skill loading from `.trae/skills/` directory.

```moonbit nocheck
struct Loader {
  cwd : String
  logger : @pino.Logger
  mut skills : Array[Skill]
}

pub fn Loader::new(cwd : String, logger~ : @pino.Logger) -> Loader
pub fn Loader::load(self : Loader) -> Unit
pub fn Loader::load_and_apply(self : Loader, messages : Array[@ai.Message]) -> Unit
```

---

## uuid

UUID generation.

```moonbit nocheck
struct Uuid
struct Generator

pub fn generator(rand : @rand.Rand) -> Generator
pub fn Generator::v4(self : Generator) -> Uuid
pub fn Uuid::to_string(self : Uuid) -> String
```
