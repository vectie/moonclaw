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
| `glob_files` | Find file paths by glob pattern |
| `list_resources` | List typed runtime resources |
| `read_resource` | Read typed runtime resources by URI |
| `runtime_context` | Inspect current job/run/step execution context |
| `list_worktrees` | List managed git worktrees for the current repository |
| `delegate_run` | Build a typed bounded child-run delegation request |
| `enter_worktree` | Provision an isolated git worktree |
| `exit_worktree` | Remove an isolated git worktree |
| `patch_edit` | Preview or apply structured patch edits |
| `search_files` | Search for patterns in files |
| `todo` | Task list management |
| `list_jobs` | List background jobs |
| `wait_job` | Wait for job completion |
| `web_fetch` | Fetch and clean URL content |

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

## glob_files

Find matching file paths without reading file contents.

```moonbit nocheck
pub fn new(cwd : String) -> @tool.Tool[GlobFilesResult]
```

**Parameters:**
- `pattern`: Glob pattern to match, supporting `*`, `?`, and `**`
- `path`: Directory to search from (default: `.`)
- `max_results`: Maximum paths to return (default: `200`)
- `respect_gitignore`: Skip gitignored paths when possible (default: `true`)
- `include_hidden`: Include hidden files and directories (default: `false`)
- `include_directories`: Return matching directories too (default: `false`)

**Features:**
- Recursive globbing
- Gitignore-aware path discovery
- Bounded typed result set

---

## list_resources

List typed runtime resources by kind.

```moonbit nocheck
pub fn new(cwd : String, home? : String?) -> @tool.Tool[ListResourcesResult]
```

**Supported kinds:**
- `file`
- `skill`
- `worktree`
- `provider`

**Parameters:**
- `kind`: Resource kind to list
- `path`: Base path for file resources
- `pattern`: Glob pattern for file resources
- `max_results`: Maximum resources to return
- `include_hidden`: Include hidden file resources

**Features:**
- URI-based discovery for files, skills, worktrees, and providers
- First-class discovery of managed git worktrees
- Provider registry discovery via `.moonclaw/providers.json`
- Structured metadata for downstream `read_resource` calls

---

## read_resource

Read typed runtime resources by URI.

```moonbit nocheck
pub fn new(cwd : String, home? : String?) -> @tool.Tool[ReadResourceResult]
```

**Supported URIs:**
- `file://relative/or/absolute/path`
- `skill://skill-name`
- `worktree://worktree-key`
- `provider://provider-name`

**Parameters:**
- `uri`: Resource URI to read
- `max_chars`: Maximum characters to return (default: `20000`)

**Features:**
- Typed file, skill, worktree, and provider resource reads
- Runtime-aware `cwd` / `home` resolution
- Structured metadata in the result payload

---

## web_search

Search the public web for source leads with explicit provenance.

```moonbit nocheck
pub fn new() -> @tool.Tool[WebSearchResult]
```

**Parameters:**
- `query`: Search query string
- `max_results`: Maximum number of search items to return

**Features:**
- Public-web background search
- Stable `search_url` in the result payload
- Per-result source metadata including `domain` and `rank`

---

## web_fetch

Fetch a URL and return cleaned page text with fetch provenance.

```moonbit nocheck
pub fn new() -> @tool.Tool[WebFetchResult]
```

**Parameters:**
- `url`: HTTP or HTTPS URL to fetch
- `max_chars`: Maximum returned text size

**Features:**
- Cleaned text extraction from HTML or plain text responses
- Explicit `final_url` and `domain`
- Structured metadata including scheme, host, path, and HTML extraction mode

---

## delegate_run

Create a typed bounded child-run request surface.

```moonbit nocheck
pub fn new() -> @tool.Tool[DelegateRunResult]
```

**Parameters:**
- `title`: Short delegation title
- `request_text`: Child task request
- `expected_output`: Optional expected output
- `child_profile`: Optional child profile override
- `execution_mode`: Optional child execution mode
- `execution_target`: Optional child execution target
- `include_parent_outputs`: Include parent outputs in the child request
- `max_depth`: Bounded child depth

**Features:**
- Explicit `job.delegate` request surface
- Bounded delegation metadata
- Structured `step_config` output for runtime delegation
- Uses the execution-layer name `delegate_run` to distinguish delegated child runs from workflow subplans

---

## enter_worktree

Provision an isolated git worktree for a coding subtask.

```moonbit nocheck
pub fn new(cwd : String) -> @tool.Tool[EnterWorktreeResult]
```

**Parameters:**
- `task_key`: Short task label used to derive the worktree path and default branch name
- `base_dir`: Optional base directory for the worktree root
- `branch_name`: Optional explicit branch name
- `commit`: Optional commit-ish to base the worktree on
- `force_new_branch`: Replace an existing branch with the same name

**Features:**
- Repo-root-based worktree planning
- Stable slug and branch derivation
- Returns the created worktree path for follow-up commands

---

## exit_worktree

Remove a previously created git worktree.

```moonbit nocheck
pub fn new(cwd : String) -> @tool.Tool[ExitWorktreeResult]
```

**Parameters:**
- `path`: Path to the worktree to remove
- `repo_root`: Optional repository root when `cwd` is not inside the parent repository
- `force`: Force removal even with local changes (default: `true`)

**Features:**
- Cleans up isolated checkouts
- Works with repo-root inference or explicit repo root

---

## patch_edit

Preview or apply a structured patch edit with an explicit mode contract.

```moonbit nocheck
pub fn new(cwd : String) -> @tool.Tool[PatchEditResult]
```

**Parameters:**
- `patch`: V4A patch content
- `mode`: `preview` or `apply`

**Features:**
- Patch validation without mutation in preview mode
- Structured file-change report in both preview and apply modes
- Reuses the same patch format as `apply_patch`
- Uses the execution-layer name `patch_edit` to distinguish patch editing from higher-level run/workflow mutations

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
- Persisted to `.moonsuite/products/moonclaw/todos/current_session.json`
  for the owning suite or standalone workspace.

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

## web_fetch

Fetch a URL and return cleaned text content.

```moonbit nocheck
pub fn new() -> @tool.Tool[WebFetchResult]
```

**Parameters:**
- `url`: HTTP or HTTPS URL to fetch (required)
- `max_chars`: Maximum number of characters to return (default: 5000)

**Behavior:**
- fetches the target URL
- returns plain text for text responses
- strips common HTML markup for HTML pages
- extracts page title when available
- truncates oversized results predictably

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
