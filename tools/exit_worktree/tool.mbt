///|
pub struct ExitWorktreeResult {
  path : String
  repo_root : String
  removed : Bool
} derive(ToJson, FromJson)

///|
pub impl Show for ExitWorktreeResult with output(
  result : ExitWorktreeResult,
  logger : &Logger,
) -> Unit {
  logger.write_string(
    ["Worktree removed: \{result.path}", "Repo: \{result.repo_root}"].join("\n"),
  )
}

///|
async fn effective_repo_root(
  cwd : String,
  repo_root : String?,
) -> String noraise {
  match repo_root {
    Some(repo_root) => repo_root
    None => {
      let detected = @git.find_repo_root(cwd) catch { _ => None }
      match detected {
        Some(repo_root) => repo_root
        None => cwd
      }
    }
  }
}

///|
pub fn new(cwd : String) -> @tool.Tool[ExitWorktreeResult] {
  @tool.new(
    name="exit_worktree",
    description="Remove a previously created git worktree. This cleans up the isolated checkout but does not merge or move changes automatically.",
    schema={
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Path to the worktree to remove",
        },
        "repo_root": {
          "type": "string",
          "description": "Optional repository root when the current cwd is not inside the parent repository",
        },
        "force": {
          "type": "boolean",
          "description": "Whether to force removal even with local changes",
        },
      },
      "required": ["path"],
    },
    async fn(args) -> @tool.ToolResult[ExitWorktreeResult] noraise {
      guard args is { "path": String(path), .. } else {
        return @tool.error("Error: 'path' parameter is required")
      }
      let repo_root = match args {
        { "repo_root": String(repo_root), .. } => Some(repo_root)
        _ => None
      }
      let force = match args {
        { "force": False, .. } => false
        _ => true
      }
      @worktree.remove_worktree_path(cwd, path, repo_root~, force~) catch {
        error => return @tool.error("Error removing worktree: \{error}")
      }
      let resolved_repo_root = effective_repo_root(cwd, repo_root)
      @tool.ok(ExitWorktreeResult::{
        path,
        repo_root: resolved_repo_root,
        removed: true,
      })
    },
  )
}
