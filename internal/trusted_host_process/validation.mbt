///|
fn contains_nul(value : String) -> Bool {
  value.contains("\u0000")
}

///|
fn validate_relative_path(path : String) -> Unit raise TrustedHostProcessError {
  if path.is_blank() || contains_nul(path) || @pathx.is_absolute(path) {
    raise InvalidParameter("expected a non-empty relative path")
  }
  let normalized = @pathx.normalize(path)
  if normalized == ".." || normalized.has_prefix("../") {
    raise InvalidParameter("relative path escapes the trusted workspace")
  }
}

///|
fn validate_relative_paths(
  paths : Array[String],
) -> Unit raise TrustedHostProcessError {
  if paths.is_empty() {
    raise InvalidParameter("path list must not be empty")
  }
  if paths.length() > 4096 {
    raise InvalidParameter("path list exceeds the deployment limit")
  }
  for path in paths {
    validate_relative_path(path)
  }
}

///|
fn validate_commit_message(
  message : String,
) -> Unit raise TrustedHostProcessError {
  if message.is_blank() || contains_nul(message) || message.length() > 4096 {
    raise InvalidParameter(
      "commit message is empty or exceeds the deployment limit",
    )
  }
}

///|
fn validate_ref(value : String) -> Unit raise TrustedHostProcessError {
  if value.is_blank() ||
    value.length() > 256 ||
    contains_nul(value) ||
    value.has_prefix("-") ||
    value.contains("..") ||
    value.contains("@{") {
    raise InvalidParameter("invalid Git ref")
  }
  for char in value {
    guard char is ('a'..='z' | 'A'..='Z' | '0'..='9' | '/' | '-' | '_' | '.') else {
      raise InvalidParameter("invalid character in Git ref")
    }
  }
}

///|
fn validate_commit_id(value : String) -> Unit raise TrustedHostProcessError {
  if value.length() < 7 || value.length() > 64 {
    raise InvalidParameter("invalid commit identifier")
  }
  for char in value {
    guard char is ('a'..='f' | 'A'..='F' | '0'..='9') else {
      raise InvalidParameter("commit identifier must be hexadecimal")
    }
  }
}

///|
fn validate_absolute_destination(
  path : String,
) -> Unit raise TrustedHostProcessError {
  if !@pathx.is_absolute(path) || contains_nul(path) || path.length() > 4096 {
    raise InvalidParameter("worktree destination must be an absolute path")
  }
  let normalized = @pathx.normalize(path)
  if normalized == "/" {
    raise InvalidParameter(
      "worktree destination must not be the filesystem root",
    )
  }
}

///|
fn dangerous_git_config_line(line : String) -> Bool {
  let normalized = line.trim().to_lower()
  normalized.has_prefix("[filter ") ||
  normalized.has_prefix("[diff ") ||
  normalized.has_prefix("[merge ") ||
  normalized.has_prefix("[alias]") ||
  normalized.has_prefix("[credential]") ||
  normalized.has_prefix("[url ") ||
  normalized.has_prefix("hookspath") ||
  normalized.has_prefix("fsmonitor") ||
  normalized.has_prefix("sshcommand") ||
  normalized.has_prefix("pager")
}

///|
async fn repository_config_candidates(root : String) -> Array[String] {
  let dot_git = @pathx.join(root, ".git")
  let candidates : Array[String] = []
  let direct = @pathx.join(dot_git, "config")
  let direct_exists = @fsx.exists(direct) catch { _ => false }
  if direct_exists {
    candidates.push(direct)
  }
  let git_file = @fsx.read_file(dot_git) catch { _ => "" }
  if git_file.has_prefix("gitdir:") {
    let raw = git_file["gitdir:".length():].trim().to_owned()
    let git_dir = if @pathx.is_absolute(raw) {
      @pathx.normalize(raw)
    } else {
      @pathx.normalize(@pathx.join(root, raw))
    }
    candidates.push(@pathx.join(git_dir, "config"))
    let common = @fsx.read_file(@pathx.join(git_dir, "commondir")) catch {
      _ => ""
    }
    if !common.trim().is_blank() {
      let common_dir = if @pathx.is_absolute(common.trim()) {
        @pathx.normalize(common.trim())
      } else {
        @pathx.normalize(@pathx.join(git_dir, common.trim()))
      }
      candidates.push(@pathx.join(common_dir, "config"))
      candidates.push(@pathx.join(common_dir, "config.worktree"))
    }
  }
  candidates
}

///|
async fn reject_unsafe_repository_config(root : String) -> Unit {
  for config in repository_config_candidates(root) {
    let content = @fsx.read_file(config) catch { _ => continue }
    for line in content.split("\n") {
      if dangerous_git_config_line(line.to_owned()) {
        raise UnsafeRepositoryConfig(config)
      }
    }
  }
}
