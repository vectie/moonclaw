///|
pub struct WorktreeHandle {
  repo_root : String
  path : String
  branch_name : String
  task_key : String
} derive(ToJson, FromJson, Debug)

///|
pub struct WorktreeList {
  repo_root : String
  base_dir : String
  worktrees : Array[WorktreeHandle]
} derive(ToJson, FromJson, Debug)

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
  let slug = buf.to_string().trim(chars="-").to_owned()
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
fn path_is_inside_base_dir(path : String, base_dir : String) -> Bool {
  let normalized_path = @pathx.normalize(path)
  let normalized_base_dir = @pathx.normalize(base_dir)
  normalized_path == normalized_base_dir ||
  normalized_path.has_prefix("\{normalized_base_dir}/")
}

///|
fn parse_worktree_list_output(
  repo_root : String,
  base_dir : String,
  stdout : String,
) -> Array[WorktreeHandle] {
  let worktrees : Array[WorktreeHandle] = []
  let mut current_path : String? = None
  let mut current_branch_name = ""
  let mut current_task_key = ""
  let flush = () => {
    guard current_path is Some(path) else { return }
    if path_is_inside_base_dir(path, base_dir) {
      worktrees.push(WorktreeHandle::{
        repo_root,
        path,
        branch_name: current_branch_name,
        task_key: current_task_key,
      })
    }
  }
  for raw_line in stdout.split("\n") {
    let line = raw_line.trim_end().to_owned()
    if line.is_blank() {
      flush()
      current_path = None
      current_branch_name = ""
      current_task_key = ""
    } else if line.has_prefix("worktree ") {
      current_path = Some(line["worktree ".length():].trim().to_owned())
      current_branch_name = ""
      current_task_key = match current_path {
        Some(path) => @pathx.basename(path).to_owned()
        None => ""
      }
    } else if line.has_prefix("branch refs/heads/") {
      current_branch_name = line["branch refs/heads/".length():]
        .trim()
        .to_owned()
    }
  }
  flush()
  worktrees
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
pub async fn list_worktrees(
  cwd : String,
  base_dir? : String? = None,
) -> WorktreeList {
  let repo_root = match @git.find_repo_root(cwd) {
    Some(repo_root) => repo_root
    None => fail("No git repository found for worktree listing: \{cwd}")
  }
  let base_dir = base_dir.unwrap_or(default_worktree_base_dir(repo_root))
  let process = @spawn.spawn(
    "git",
    ["worktree", "list", "--porcelain"],
    cwd=repo_root,
  )
  process.check() catch {
    error => fail("Failed to list git worktrees for \{repo_root}: \{error}")
  }
  let worktrees = parse_worktree_list_output(
    repo_root,
    base_dir,
    process.stdout,
  )
  WorktreeList::{ repo_root, base_dir, worktrees }
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
