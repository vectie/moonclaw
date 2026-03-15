# Moonclaw Root Package

The root package provides the main entry point for the Moonclaw AI coding agent framework.

## Core Struct

### `Moonclaw`

The primary struct that encapsulates an AI coding assistant instance.

```moonbit nocheck
///|
pub struct Moonclaw {
  logger : @pino.Logger
  agent : @agent.Agent
}
```

**Fields:**
- `logger`: Logger instance for recording agent activities
- `agent`: The underlying Agent instance that handles AI interactions

## Key APIs

### Creating a New Instance

```moonbit nocheck
pub async fn Moonclaw::new(
  name? : String,
  logger? : @pino.Logger,
  model~ : @model.Model,
  home? : String,
  cwd? : String,
  user_message? : String,
  web_search? : Bool = false,
) -> Moonclaw
```

Creates a new Moonclaw agent with:
- A configured AI model
- Default tools (execute_command, list_files, read_file, todo, search_files)
- Either `apply_patch` or `write_to_file` based on model capabilities

### Resuming a Session

```moonbit nocheck
pub async fn Moonclaw::resume_(
  logger? : @pino.Logger,
  model~ : @model.Model,
  home? : String,
  id : @uuid.Uuid,
  user_message? : String,
  web_search? : Bool,
) -> Moonclaw
```

Resumes a previously saved conversation by ID.

### Starting the Agent

```moonbit nocheck
pub async fn Moonclaw::start(self : Moonclaw, prompt? : String) -> Unit
```

Begins processing messages from the queue.

### Cleanup

```moonbit nocheck
pub fn Moonclaw::close(self : Moonclaw) -> Unit
```

Releases resources when done.

## Call Chain

```
Moonclaw::new()
    │
    ├─► @agent.new()           // Create agent instance
    │       │
    │       ├─► @conversation.Manager::new()
    │       ├─► @rules.Loader::new()
    │       ├─► @skills.Loader::new()
    │       └─► @context_pruner.Pruner::new()
    │
    └─► setup_agent()          // Register tools
            │
            ├─► @execute_command.new()
            ├─► @list_files.new()
            ├─► @read_file.new()
            ├─► @todo.new_tool()
            ├─► @search_files.new()
            └─► @apply_patch.new() or @write_to_file.new()
```

## Usage Example

```moonbit check
///|
test "moonclaw usage example" {
  // Create a model configuration
  ignore(
    @model.open_router_model(
      api_key="your-api-key",
      name=@model.CommonModels::Qwen3CoderPlus,
    ),
  )

  // Note: Moonclaw::new is async, so in real usage:
  // let moonclaw = Moonclaw::new(model~, cwd="/path/to/project")
  // moonclaw.start(prompt="Help me write a function")
  // defer moonclaw.close()
}
```

## Dependencies

- `agent`: Core agent functionality
- `model`: AI model configuration
- `ai`: Message types
- `tool`: Tool definitions
- `job`: Job management
- `file`: File management
- `prompt`: System prompts
- Various tool packages in `tools/`
