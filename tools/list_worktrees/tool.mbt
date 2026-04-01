///|
pub struct ListWorktreesResult {
  repo_root : String
  current_cwd : String
  worktrees : Array[@worktree.WorktreeHandle]
} derive(ToJson, FromJson)

///|
pub impl Show for ListWorktreesResult with output(
  result : ListWorktreesResult,
  logger : &Logger,
) -> Unit {
  let lines = [
    "Repo: \{result.repo_root}",
    "Worktrees: \{result.worktrees.length()}",
  ]
  for handle in result.worktrees {
    lines.push("- \{handle.path} (\{handle.branch_name})")
  }
  logger.write_string(lines.join("\n"))
}

///|
pub fn new(cwd : String) -> @tool.Tool[ListWorktreesResult] {
  @tool.new(
    name="list_worktrees",
    description="List MoonClaw-managed git worktrees for the current repository.",
    schema={
      "type": "object",
      "properties": {
        "base_dir": {
          "type": "string",
          "description": "Optional explicit worktree base directory",
        },
      },
      "required": [],
    },
    async fn(args) -> @tool.ToolResult[ListWorktreesResult] noraise {
      let base_dir = match args {
        { "base_dir": String(base_dir), .. } => Some(base_dir)
        _ => None
      }
      let result = @worktree.list_worktrees(cwd, base_dir~) catch {
        error => return @tool.error("Error listing worktrees: \{error}")
      }
      @tool.ok(ListWorktreesResult::{
        repo_root: result.repo_root,
        current_cwd: cwd,
        worktrees: result.worktrees,
      })
    },
  )
}
