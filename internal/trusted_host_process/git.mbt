///|
let git_executable : String = "/usr/bin/git"

///|
fn git_environment() -> Map[String, String] {
  {
    "HOME": "/dev/null",
    "PATH": "/usr/bin:/bin",
    "LANG": "C",
    "LC_ALL": "C",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_TERMINAL_PROMPT": "0",
    "GIT_ASKPASS": "/usr/bin/false",
    "GIT_PAGER": "cat",
  }
}

///|
fn git_prefix() -> Array[String] {
  [
    "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "diff.external=",
    "-c", "protocol.file.allow=never", "-c", "user.name=MoonClaw", "-c", "user.email=moonclaw@local",
  ]
}

///|
fn GitOperation::arguments(
  self : GitOperation,
) -> Array[String] raise TrustedHostProcessError {
  match self {
    Init => ["init", "--quiet"]
    CheckIgnore(paths) => {
      validate_relative_paths(paths)
      ["check-ignore", "--", ..paths]
    }
    ListFiles => ["ls-files", "--"]
    AddFiles(paths) => {
      validate_relative_paths(paths)
      ["add", "--", ..paths]
    }
    AddAll => ["add", "-A", "--"]
    Commit(message) => {
      validate_commit_message(message)
      ["commit", "--no-verify", "-m", message]
    }
    StatusPorcelain => ["status", "--porcelain"]
    StatusProductPorcelain =>
      [
        "status", "--porcelain", "--", ".", ":(exclude).moonsuite", ":(exclude).tmp",
      ]
    StatusShort => ["status", "--short"]
    RecentLog(count) => {
      if count < 1 || count > 20 {
        raise InvalidParameter("recent-log count must be between 1 and 20")
      }
      ["log", "--oneline", "-n", count.to_string()]
    }
    RevListCount => ["rev-list", "--count", "HEAD"]
    Head => ["rev-parse", "--verify", "HEAD"]
    HeadTree => ["rev-parse", "--verify", "HEAD^{tree}"]
    CurrentBranch => ["branch", "--show-current"]
    ListHeadTree => ["ls-tree", "-r", "--name-only", "HEAD"]
    CommitSubject => ["log", "-1", "--pretty=%s"]
    DiffCheck => ["diff", "--no-ext-diff", "--check"]
    DiffNamesBetween(base~, target~) => {
      validate_commit_id(base)
      validate_commit_id(target)
      ["diff", "--no-ext-diff", "--name-only", base, target, "--"]
    }
    DiffTree(commit) => {
      validate_commit_id(commit)
      [
        "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", "-z", commit,
        "--", ".", ":(exclude).moonsuite", ":(exclude).tmp",
      ]
    }
    AddProductAll =>
      ["add", "-A", "--", ".", ":(exclude).moonsuite", ":(exclude).tmp"]
    RestoreHeadFiles(paths) => {
      validate_relative_paths(paths)
      ["restore", "--source=HEAD", "--", ..paths]
    }
    DiffNoIndex(original~, modified~) => {
      validate_relative_path(original)
      validate_relative_path(modified)
      [
        "diff", "--no-ext-diff", "--no-index", "--no-prefix", "--unified=3", "--",
        original, modified,
      ]
    }
    WorktreeList => ["worktree", "list", "--porcelain"]
    WorktreeAdd(path~, branch~, commit~, force_new_branch~) => {
      validate_absolute_destination(path)
      let args : Array[String] = ["worktree", "add"]
      match branch {
        Some(branch) => {
          validate_ref(branch)
          if force_new_branch {
            args.push("-B")
          } else {
            args.push("-b")
          }
          args.push(branch)
        }
        None => ()
      }
      args.push("--")
      args.push(path)
      match commit {
        Some(commit) => {
          validate_ref(commit)
          args.push(commit)
        }
        None => ()
      }
      args
    }
    WorktreeRemove(path~, force~) => {
      validate_absolute_destination(path)
      let args = ["worktree", "remove"]
      if force {
        args.push("--force")
      }
      args.push("--")
      args.push(path)
      args
    }
    FmtTrackedPaths =>
      [
        "diff", "--name-only", "-z", "--relative", "--no-ext-diff", "HEAD", "--",
        ".",
      ]
    FmtUntrackedPaths =>
      ["ls-files", "--others", "--exclude-standard", "-z", "--", "."]
    FmtPathDiff(path) => {
      validate_relative_path(path)
      ["diff", "--binary", "--no-ext-diff", "HEAD", "--", path]
    }
    FmtRestorePath(path) => {
      validate_relative_path(path)
      ["restore", "--worktree", "--", path]
    }
  }
}

///|
/// Execute a MoonClaw-owned Git bookkeeping operation. The executable is an
/// absolute platform tool, the environment is replaced with a minimal fixed
/// map, repository hooks/external diffs/fsmonitor are disabled, and local
/// configuration capable of launching helper processes is refused.
pub async fn run_git(
  workspace_root : String,
  operation : GitOperation,
  timeout_ms? : Int = 10000,
) -> GitResult {
  if !@fsx.exists(git_executable) {
    raise HostToolUnavailable(git_executable)
  }
  let root = @fs.realpath(workspace_root) catch {
    _ => raise InvalidWorkspace("workspace root does not resolve")
  }
  if !@pathx.is_absolute(root) || root == "/" {
    raise InvalidWorkspace("workspace root must be a canonical non-root path")
  }
  reject_unsafe_repository_config(root)
  if timeout_ms < 1 || timeout_ms > 120000 {
    raise InvalidParameter("timeout exceeds the trusted host-process limit")
  }
  let args = [..git_prefix(), ..operation.arguments()]
  let process = run_host_process(
    git_executable,
    args,
    timeout=timeout_ms,
    cwd=root,
    env=git_environment(),
    inherit_env=false,
  )
  {
    status: process.status,
    stdout: process.stdout,
    stderr: process.stderr,
    elapsed: process.elapsed,
  }
}
