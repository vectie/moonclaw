///|
pub struct WorktreeHandle {
  repo_root : String
  path : String
  branch_name : String
  task_key : String
} derive(ToJson, FromJson, Show)

///|
fn worktree_slug(text : String) -> String {
  let buf = StringBuilder::new()
  let mut chars_written = 0
  let mut last_dash = true
  for c in text.to_lower().to_array() {
    let normalized = match c {
      'a'..='z' => Some(c)
      '0'..='9' => Some(c)
      _ => None
    }
    match normalized {
      Some(c) => {
        if chars_written >= 32 {
          break
        }
        buf.write_char(c)
        chars_written += 1
        last_dash = false
      }
      None =>
        if !last_dash && chars_written < 32 {
          buf.write_char('-')
          chars_written += 1
          last_dash = true
        }
    }
  }
  let slug = buf.to_string().trim(chars="-").to_string()
  if slug.is_blank() {
    "task"
  } else {
    slug
  }
}

///|
fn default_worktree_base_dir(repo_root : String) -> String {
  let repo_parent = @pathx.dirname(repo_root)
  let repo_name = @pathx.basename(repo_root)
  @pathx.join(repo_parent, ".moonclaw-worktrees/\{repo_name}")
}

///|
pub async fn plan_worktree(
  cwd : String,
  task_key : String,
  base_dir? : String? = None,
  branch_name? : String? = None,
) -> WorktreeHandle {
  let repo_root = match @git.find_repo_root(cwd) {
    Some(repo_root) => repo_root
    None => fail("No git repository found for worktree planning: \{cwd}")
  }
  let slug = worktree_slug(task_key)
  let branch_name = branch_name.unwrap_or("moonclaw/\{slug}")
  let base_dir = base_dir.unwrap_or(default_worktree_base_dir(repo_root))
  let path = @pathx.join(base_dir, slug)
  WorktreeHandle::{ repo_root, path, branch_name, task_key }
}

///|
pub async fn create_worktree(
  handle : WorktreeHandle,
  commit? : String? = None,
  force_new_branch? : Bool = false,
) -> WorktreeHandle {
  @fsx.make_directory(
    @pathx.dirname(handle.path),
    recursive=true,
    exists_ok=true,
  )
  @git.add_worktree(
    handle.path,
    new_branch=handle.branch_name,
    force_new_branch~,
    commit?,
    cwd=handle.repo_root,
  )
  handle
}

///|
pub async fn remove_worktree(
  handle : WorktreeHandle,
  force? : Bool = true,
) -> Unit {
  @git.remove_worktree(handle.path, force~, cwd=handle.repo_root)
}

///|
pub async fn remove_worktree_path(
  cwd : String,
  path : String,
  repo_root? : String? = None,
  force? : Bool = true,
) -> Unit {
  let repo_root = match repo_root {
    Some(repo_root) => repo_root
    None =>
      match @git.find_repo_root(cwd) {
        Some(repo_root) => repo_root
        None => fail("No git repository found for worktree removal: \{cwd}")
      }
  }
  @git.remove_worktree(path, force~, cwd=repo_root)
}

///|
pub async fn[T] with_worktree(
  cwd : String,
  task_key : String,
  base_dir? : String? = None,
  branch_name? : String? = None,
  commit? : String? = None,
  force_new_branch? : Bool = false,
  f : async (WorktreeHandle) -> T,
) -> T {
  let handle = plan_worktree(cwd, task_key, base_dir~, branch_name~)
  @git.with_worktree(
    handle.path,
    new_branch=handle.branch_name,
    force_new_branch~,
    commit?,
    cwd=handle.repo_root,
    () => f(handle),
  )
}
