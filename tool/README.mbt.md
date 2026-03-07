# Tool Package

The tool package provides the core abstractions for defining and executing tools that the AI agent can call.

## Core Types

### `ToolDesc`

Describes a tool's interface for the AI model.

```moonbit nocheck
///|
pub struct ToolDesc {
  description : String
  name : String
  schema : JsonSchema
} derive(ToJson, Eq, Show)
```

**Fields:**
- `description`: Human-readable description for the AI
- `name`: Unique identifier for the tool
- `schema`: JSON Schema defining the expected parameters

### `Tool[Output]`

A tool with its execution function.

```moonbit nocheck
///|
pub struct Tool[Output] {
  desc : ToolDesc
  // private: f : ToolFn[Output]
}
```

### `ToolFn[Output]`

The function type for tool execution.

```moonbit nocheck
///|
pub(all) struct ToolFn[Output](async (Json) -> ToolResult[Output] noraise)
```

### `ToolResult[Output]`

Result of a tool execution.

```moonbit nocheck
///|
pub enum ToolResult[Output] {
  Ok(Output)
  Error(Error, String)
} derive(ToJson)
```

### `AgentTool`

A tool adapted for agent use (output is JSON + rendered string).

```moonbit nocheck
///|
type AgentTool // Wraps Tool[(Json, String)]
```

### `JsonSchema`

Wrapper for JSON Schema validation.

```moonbit nocheck
///|
pub(all) struct JsonSchema(Json)
```

## Key APIs

### Tool Creation

```moonbit nocheck
pub fn[Output] Tool::new(
  description~ : String,
  name~ : String,
  schema~ : JsonSchema,
  f : ToolFn[Output],
) -> Tool[Output]
```

### Tool Execution

```moonbit nocheck
pub async fn[Output] Tool::call(
  tool : Tool[Output],
  args : Json,
) -> ToolResult[Output] noraise
```

### Result Constructors

```moonbit nocheck
pub fn[Output] ToolResult::ok(output : Output) -> ToolResult[Output]
pub fn[Output] ToolResult::error(
  output : String,
  error? : Error,
) -> ToolResult[Output]
```

### Conversion to AgentTool

```moonbit nocheck
pub fn[Output : ToJson + Show] Tool::to_agent_tool(
  self : Tool[Output],
) -> AgentTool
```

### OpenAI Conversion

```moonbit nocheck
pub fn ToolDesc::to_openai(
  tool_desc : ToolDesc,
) -> @openai.ChatCompletionToolParam
```

## Creating a Custom Tool

```moonbit nocheck
// Define the output type

///|
struct WeatherOutput {
  temperature : Double
  conditions : String
} derive(ToJson, Show)

// Define the JSON schema

///|
let weather_schema : @tool.JsonSchema = {
  "type": "object",
  "properties": { "location": { "type": "string", "description": "City name" } },
  "required": ["location"],
}

// Create the tool

///|
let weather_tool : @tool.Tool[WeatherOutput] = @tool.new(
  description="Get current weather for a location",
  name="get_weather",
  schema=weather_schema,
  @tool.ToolFn(async fn(args) -> @tool.ToolResult[WeatherOutput] noraise {
    guard args is { "location": String(location), .. } else {
      return @tool.error("Missing 'location' parameter")
    }

    // Simulate weather API call
    @tool.ok({ temperature: 72.5, conditions: "Sunny" })
  }),
)

// Convert for agent use

///|
let agent_tool = weather_tool.to_agent_tool()
```

## Tool Execution Flow

```
AI Model
    │
    ▼
Tool Call Request (JSON arguments)
    │
    ▼
Tool::call(args)
    │
    ├─► Validate args against schema
    │
    ├─► Execute ToolFn
    │
    ▼
ToolResult
    │
    ├─► Ok(Output) ──► to_json() ──► Return to AI
    │
    └─► Error(Error, String) ──► Return error message
```

## AgentTool vs Tool[Output]

- `Tool[Output]`: Generic tool with custom output type
- `AgentTool`: Tool adapted for agent use with `(Json, String)` output
  - `Json`: Structured result for AI consumption
  - `String`: Human-readable rendering

The `to_agent_tool()` method handles this conversion automatically.

## Usage with Agent

```moonbit nocheck
// Create tools
let cmd_tool = @execute_command.new(job_manager).to_agent_tool()
let file_tool = @read_file.new(file_manager).to_agent_tool()

// Add to agent
agent.add_tools([cmd_tool, file_tool])
```

## Dependencies

- `openai`: OpenAI API types for conversion
- `json`: JSON handling
