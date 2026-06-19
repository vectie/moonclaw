///|
pub struct EnterWorktreeResult {
  handle : @worktree.WorktreeHandle
  created : Bool
  note : String
} derive(ToJson, FromJson)

///|
pub impl Show for EnterWorktreeResult with fn output(
  result : EnterWorktreeResult,
  logger : &Logger,
) -> Unit {
  logger.write_string(
    [
      "Worktree: \{result.handle.path}",
      "Branch: \{result.handle.branch_name}",
      "Repo: \{result.handle.repo_root}",
      "",
      result.note,
    ].join("\n"),
  )
}

///|
async fn path_exists(path : String) -> Bool noraise {
  @fsx.exists(path) catch {
    _ => false
  }
}

///|
pub fn new(cwd : String) -> @tool.Tool[EnterWorktreeResult] {
  @tool.new(
    name="enter_worktree",
    description="Create or reuse an isolated git worktree for a coding subtask. This provisions the worktree and returns its path and branch; it does not automatically change the agent cwd.",
    schema={
      "type": "object",
      "properties": {
        "task_key": {
          "type": "string",
          "description": "Short task label used to derive the worktree path and default branch name",
        },
        "base_dir": {
          "type": "string",
          "description": "Optional base directory for the worktree root",
        },
        "branch_name": {
          "type": "string",
          "description": "Optional explicit branch name",
        },
        "commit": {
          "type": "string",
          "description": "Optional commit-ish to base the worktree on",
        },
        "force_new_branch": {
          "type": "boolean",
          "description": "Whether to replace an existing branch with the same name",
        },
      },
      "required": ["task_key"],
    },
    async fn(args) -> @tool.ToolResult[EnterWorktreeResult] noraise {
      guard args is { "task_key": String(task_key), .. } else {
        return @tool.error("Error: 'task_key' parameter is required")
      }
      let base_dir = match args {
        { "base_dir": String(path), .. } => Some(path)
        _ => None
      }
      let branch_name = match args {
        { "branch_name": String(name), .. } => Some(name)
        _ => None
      }
      let commit = match args {
        { "commit": String(commit), .. } => Some(commit)
        _ => None
      }
      let force_new_branch = match args {
        { "force_new_branch": True, .. } => true
        _ => false
      }
      let handle = @worktree.plan_worktree(
        cwd,
        task_key,
        base_dir~,
        branch_name~,
      ) catch {
        error => return @tool.error("Error planning worktree: \{error}")
      }
      let existed = path_exists(handle.path)
      let created = if existed {
        false
      } else {
        ignore(
          @worktree.create_worktree(handle, commit~, force_new_branch~) catch {
            error => return @tool.error("Error creating worktree: \{error}")
          },
        )
        true
      }
      let note = if created {
        "Worktree created. Use this path explicitly in follow-up tools or shell commands."
      } else {
        "Existing worktree reused. Use this path explicitly in follow-up tools or shell commands."
      }
      @tool.ok({ handle, created, note })
    },
  )
}
