# AI Package

The ai package provides message types and utilities for representing AI conversations and responses.

## Core Types

### `Message`

Represents a message in the conversation with the AI model.

```moonbit nocheck
///|
pub enum Message {
  User(String)
  System(String)
  Assistant(String, tool_calls~ : Array[ToolCall])
  Tool(String, tool_call_id~ : String)
} derive(ToJson, Eq, Show)
```

**Variants:**
- `User`: A message from the user
- `System`: System prompt/instructions
- `Assistant`: Response from the AI, optionally with tool calls
- `Tool`: Result from a tool execution

### `ToolCall`

Represents a tool/function call request from the AI.

```moonbit nocheck
///|
pub struct ToolCall {
  id : String
  name : String
  arguments : String?
} derive(ToJson, Eq, Show)
```

### `Usage`

Token usage statistics from the API.

```moonbit nocheck
///|
pub struct Usage {
  input_tokens : Int
  output_tokens : Int
  total_tokens : Int
  cache_read_tokens : Int?
} derive(Eq, Show)
```

## Key APIs

### Message Constructors

```moonbit nocheck
pub fn user_message(content~ : String) -> Message
pub fn system_message(content~ : String) -> Message
pub fn assistant_message(content~ : String, tool_calls? : Array[ToolCall]) -> Message
pub fn tool_message(content~ : String, tool_call_id~ : String) -> Message
```

### Tool Call Constructor

```moonbit nocheck
pub fn tool_call(id~ : String, name~ : String, arguments? : String) -> ToolCall
```

### Usage Constructor

```moonbit nocheck
pub fn usage(
  input_tokens~ : Int,
  output_tokens~ : Int,
  total_tokens? : Int,
  cache_read_tokens? : Int,
) -> Usage
```

### OpenAI Conversion

The package provides bidirectional conversion with OpenAI types:

```moonbit nocheck
// Convert to OpenAI format
pub fn Message::to_openai(Self) -> @openai.ChatCompletionMessageParam

// Convert from OpenAI format
pub fn Message::from_openai(@openai.ChatCompletionMessageParam) -> Self
pub fn Message::from_openai_response(@openai.ChatCompletionMessage) -> Self

// ToolCall conversion
pub fn ToolCall::to_openai(Self) -> @openai.ChatCompletionMessageToolCall
pub fn ToolCall::from_openai_tool_call(@openai.ChatCompletionMessageToolCall) -> Self

// Usage conversion
pub fn Usage::from_openai(@openai.CompletionUsage) -> Self
pub fn Usage::to_openai(Self) -> @openai.CompletionUsage
```

## Usage Example

```moonbit nocheck
// Create messages for a conversation

///|
let system = @ai.system_message(content="You are a helpful assistant.")

///|
let user = @ai.user_message(content="What is 2+2?")

///|
let assistant = @ai.assistant_message(content="2+2 equals 4.")

// Create a tool call

///|
let tc = @ai.tool_call(
  id="call_123",
  name="calculate",
  arguments=Some("{\"expression\": \"2+2\"}"),
)

// Create assistant message with tool calls

///|
let assistant_with_tools = @ai.assistant_message(content="", tool_calls=[tc])

// Create tool response

///|
let tool_response = @ai.tool_message(tool_call_id="call_123", content="4")
```

## Dependencies

- `openai`: OpenAI API types for conversion
