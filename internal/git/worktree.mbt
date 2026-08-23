///|
pub async fn add_worktree(
  path : String,
  new_branch? : String,
  force_new_branch? : Bool = false,
  commit? : String,
  cwd? : StringView,
) -> Unit {
  let root = cwd.map(fn(value) { value.to_owned() }).unwrap_or(".")
  let destination = if @pathx.is_absolute(path) {
    path
  } else {
    @pathx.join(root, path)
  }
  let result = @trusted_host_process.run_git(
    root,
    WorktreeAdd(path=destination, branch=new_branch, commit~, force_new_branch~),
  )
  if result.status() != 0 {
    fail("trusted git worktree add failed: \{result.stderr()}")
  }
}

///|
pub async fn remove_worktree(
  path : String,
  force? : Bool = false,
  cwd? : StringView,
) -> Unit {
  let root = cwd.map(fn(value) { value.to_owned() }).unwrap_or(".")
  let destination = if @pathx.is_absolute(path) {
    path
  } else {
    @pathx.join(root, path)
  }
  let result = @trusted_host_process.run_git(
    root,
    WorktreeRemove(path=destination, force~),
  )
  if result.status() != 0 {
    fail("trusted git worktree remove failed: \{result.stderr()}")
  }
}

///|
pub async fn[T] with_worktree(
  path : String,
  new_branch? : String,
  force_new_branch? : Bool,
  commit? : String,
  cwd? : StringView,
  f : async () -> T,
) -> T {
  @async.with_task_group(group => {
    add_worktree(path, new_branch?, force_new_branch?, commit?, cwd?)
    group.add_defer(() => remove_worktree(path, force=true, cwd?))
    f()
  })
}
