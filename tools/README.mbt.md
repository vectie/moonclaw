# Tools Packages

This directory contains tool implementations that the AI agent can use.

## Available Tools

| Tool | Description |
|------|-------------|
| `execute_command` | Run shell commands |
| `read_file` | Read file contents |
| `read_multiple_files` | Read multiple files at once |
| `write_to_file` | Write/append to files |
| `replace_in_file` | Search and replace in files |
| `apply_patch` | Apply unified diff patches |
| `list_files` | List directory contents |
| `search_files` | Search for patterns in files |
| `todo` | Task list management |
| `list_jobs` | List background jobs |
| `wait_job` | Wait for job completion |

---

## execute_command

Execute shell commands with timeout and output capture.

```moonbit nocheck
pub struct CommandOutput {
  text : String
  truncated_lines : Int
  original_lines : Int
}

pub enum CommandResult {
  Completed(command~ : String, status~ : Int, stdout~ : String, stderr~ : String, max_output_lines~ : Int)
  TimedOut(command~ : String, timeout~ : Int, stdout~ : String, stderr~ : String, max_output_lines~ : Int)
  Background(command~ : String, job_id~ : @job.Id)
}

pub fn new(ctx : @job.Manager) -> @tool.Tool[CommandResult]
```

**Parameters:**
- `command`: Shell command to execute (required)
- `timeout`: Timeout in milliseconds (default: 600000)
- `max_output_lines`: Maximum lines to capture (default: 100)
- `working_directory`: Working directory (default: cwd)
- `background`: Run in background (not fully supported)

---

## read_file

Read file contents with optional line range.

```moonbit nocheck
pub fn new(manager : @file.Manager) -> @tool.Tool[ReadFileToolResult]
```

**Parameters:**
- `path`: File path (required)
- `start_line`: Start line number (1-indexed)
- `end_line`: End line number

**Features:**
- Token limit enforcement (25000 tokens max)
- Line number formatting
- Automatic path resolution

---

## read_multiple_files

Read multiple files in a single call.

```moonbit nocheck
pub fn new(manager : @file.Manager) -> @tool.Tool[ReadMultipleFilesResult]
```

**Parameters:**
- `paths`: Array of file paths (required)

**Features:**
- Batch file reading
- Error handling per file
- Combined output

---

## write_to_file

Write or append content to a file.

```moonbit nocheck
pub fn new(cwd : String) -> @tool.Tool[Result]
```

**Parameters:**
- `path`: File path (required)
- `content`: Content to write (required)
- `separator`: Separator between existing and new content (default: newline)

**Behavior:**
- Creates file if it doesn't exist
- Appends if file exists
- Creates parent directories as needed

---

## replace_in_file

Search and replace text in files.

```moonbit nocheck
pub fn new(cwd : String) -> @tool.Tool[ReplaceResult]
```

**Parameters:**
- `path`: File path (required)
- `old_str`: Text to find (required)
- `new_str`: Replacement text (required)

**Behavior:**
- Finds first occurrence of `old_str`
- Replaces with `new_str`
- Fails if `old_str` not found

---

## apply_patch

Apply unified diff patches to files.

```moonbit nocheck
pub fn new(cwd : String) -> @tool.Tool[ApplyPatchResult]
```

**Parameters:**
- `patch`: Unified diff format patch (required)

**Patch Format:**
```diff
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line1
-old line
+new line
 line3
```

**Features:**
- Parses unified diff format
- Applies changes to files
- Used by GPT-5.1+ models

---

## list_files

List directory contents.

```moonbit nocheck
pub fn new(manager : @file.Manager) -> @tool.Tool[ListFilesResult]
```

**Parameters:**
- `path`: Directory path (default: cwd)
- `recursive`: List recursively (default: false)

**Output:**
- File/directory names
- Types (file/directory)
- Sizes

---

## search_files

Search for patterns in files using ripgrep.

```moonbit nocheck
pub fn new(cwd : String) -> @tool.Tool[SearchResult]
```

**Parameters:**
- `pattern`: Regex pattern (required)
- `path`: Directory to search (default: cwd)
- `glob`: File pattern filter (e.g., `*.mbt`)

**Features:**
- Regex pattern matching
- File type filtering
- Context lines around matches

---

## todo

Task list management for tracking progress.

```moonbit nocheck
pub fn new_tool(list : Todo) -> @tool.Tool[TodoResult]
```

**Actions:**
- `read`: Get current todo list
- `create`: Create new todo list from content
- `add_task`: Add a single task
- `update`: Update task properties
- `mark_progress`: Mark task as in progress
- `mark_completed`: Mark task as completed

**Parameters:**
- `action`: Action to perform (required)
- `content`: Task content
- `task_id`: Task ID for updates
- `priority`: `high`, `medium`, or `low`
- `status`: `pending`, `in_progress`, or `completed`
- `notes`: Additional notes

**Storage:**
- Persisted to `.moonclaw/todos/{uuid}.json`

---

## list_jobs

List background jobs.

```moonbit nocheck
pub fn new(manager : @job.Manager) -> @tool.Tool[ListJobsResult]
```

**Output:**
- Job IDs
- Job names
- Status (running/completed)

---

## wait_job

Wait for a background job to complete.

```moonbit nocheck
pub fn new(manager : @job.Manager) -> @tool.Tool[WaitJobResult]
```

**Parameters:**
- `job_id`: Job ID to wait for (required)

**Output:**
- Exit code
- Final status

---

## Tool Registration Pattern

```moonbit nocheck
// Create tool with context
let tool = @execute_command.new(job_manager)

// Convert to agent tool
let agent_tool = tool.to_agent_tool()

// Add to agent
agent.add_tool(tool)
// or
agent.add_tools([tool1.to_agent_tool(), tool2.to_agent_tool()])
```

## Creating Custom Tools

```moonbit nocheck
// 1. Define output type
struct MyOutput {
  result : String
} derive(ToJson, Show)

// 2. Define schema
let my_schema : @tool.JsonSchema = {
  "type": "object",
  "properties": {
    "input": { "type": "string" },
  },
  "required": ["input"],
}

// 3. Create tool
let my_tool : @tool.Tool[MyOutput] = @tool.new(
  description="My custom tool",
  name="my_tool",
  schema=my_schema,
  @tool.ToolFn(async fn(args) -> @tool.ToolResult[MyOutput] noraise {
    // Parse args
    guard args is { "input": String(input), .. } else {
      return @tool.error("Missing 'input' parameter")
    }
    
    // Do work
    @tool.ok({ result: "processed: " + input })
  }),
)
```
