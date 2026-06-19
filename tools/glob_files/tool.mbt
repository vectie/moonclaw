///|
pub struct GlobFilesResult {
  root : String
  pattern : String
  matches : Array[String]
  total_matches : Int
  truncated : Bool
  respect_gitignore : Bool
} derive(ToJson, FromJson)

///|
pub impl Show for GlobFilesResult with fn output(
  result : GlobFilesResult,
  logger : &Logger,
) -> Unit {
  let lines = [
    "Root: \{result.root}",
    "Pattern: \{result.pattern}",
    "Matches: \{result.total_matches}",
  ]
  if result.matches.is_empty() {
    lines.push("")
    lines.push("No paths matched.")
    return logger.write_string(lines.join("\n"))
  }
  lines.push("")
  for path in result.matches {
    lines.push(path)
  }
  if result.truncated {
    lines.push("")
    lines.push("[truncated]")
  }
  logger.write_string(lines.join("\n"))
}

///|
fn resolve_glob_path(cwd : String, path : String) -> String raise {
  let path = if path.length() > 0 && path.has_prefix("~") {
    let os_home = @os.home()
    path.replace(old="~", new=os_home)
  } else {
    path
  }
  let resolved = if @pathx.is_absolute(path) {
    path.view()
  } else {
    @pathx.join(cwd, path)
  }
  @pathx.resolve(resolved)
}

///|
fn is_hidden_path(path : String) -> Bool {
  for segment in path.split("/") {
    if segment.has_prefix(".") && segment != "." && segment != ".." {
      return true
    }
  }
  false
}

///|
fn segment_matches(pattern : String, text : String) -> Bool {
  let pattern_chars = pattern.to_array()
  let text_chars = text.to_array()
  segment_matches_chars(pattern_chars, text_chars, 0, 0)
}

///|
fn segment_matches_chars(
  pattern_chars : Array[Char],
  text_chars : Array[Char],
  p_index : Int,
  t_index : Int,
) -> Bool {
  if p_index >= pattern_chars.length() {
    return t_index >= text_chars.length()
  }
  match pattern_chars[p_index] {
    '*' =>
      segment_matches_chars(pattern_chars, text_chars, p_index + 1, t_index) ||
      (
        t_index < text_chars.length() &&
        segment_matches_chars(pattern_chars, text_chars, p_index, t_index + 1)
      )
    '?' =>
      t_index < text_chars.length() &&
      segment_matches_chars(pattern_chars, text_chars, p_index + 1, t_index + 1)
    ch =>
      t_index < text_chars.length() &&
      ch == text_chars[t_index] &&
      segment_matches_chars(pattern_chars, text_chars, p_index + 1, t_index + 1)
  }
}

///|
fn glob_matches_segments(
  pattern_segments : Array[String],
  path_segments : Array[String],
  p_index : Int,
  s_index : Int,
) -> Bool {
  if p_index >= pattern_segments.length() {
    return s_index >= path_segments.length()
  }
  let pattern = pattern_segments[p_index]
  if pattern == "**" {
    if glob_matches_segments(
        pattern_segments,
        path_segments,
        p_index + 1,
        s_index,
      ) {
      return true
    }
    if s_index < path_segments.length() {
      return glob_matches_segments(
        pattern_segments,
        path_segments,
        p_index,
        s_index + 1,
      )
    }
    return false
  }
  guard s_index < path_segments.length() else { return false }
  segment_matches(pattern, path_segments[s_index]) &&
  glob_matches_segments(
    pattern_segments,
    path_segments,
    p_index + 1,
    s_index + 1,
  )
}

///|
fn glob_matches(pattern : String, relative_path : String) -> Bool {
  let normalized_pattern = pattern.trim().to_owned()
  let normalized_path = relative_path.trim().to_owned()
  if normalized_pattern.is_empty() || normalized_path.is_empty() {
    return false
  }
  let pattern_segments = normalized_pattern
    .split("/")
    .filter(fn(segment) { !segment.is_empty() })
    .map(fn(segment) { segment.to_owned() })
    .collect()
  let path_segments = normalized_path
    .split("/")
    .filter(fn(segment) { !segment.is_empty() })
    .map(fn(segment) { segment.to_owned() })
    .collect()
  glob_matches_segments(pattern_segments, path_segments, 0, 0)
}

///|
async fn collect_glob_matches(
  absolute_root : String,
  relative_root : String,
  pattern : String,
  cwd : String,
  include_hidden : Bool,
  include_directories : Bool,
  respect_gitignore : Bool,
  does_respect_gitignore~ : Ref[Bool],
  matches : Array[String],
  total_matches~ : Ref[Int],
  max_results : Int,
) -> Unit {
  let entries = @fsx.list_directory(absolute_root)
  for entry in entries {
    if entry.name is ".git" && respect_gitignore {
      continue
    }
    let absolute_path = @pathx.join(absolute_root, entry.name)
    let relative_path = if relative_root == "." {
      entry.name
    } else {
      @pathx.join(relative_root, entry.name)
    }
    if !include_hidden && is_hidden_path(relative_path) {
      continue
    }
    if respect_gitignore {
      let ignored_result = Ok(@git.is_ignored(absolute_path, cwd~)) catch {
        error => Err(error)
      }
      if ignored_result is Ok(ignored) {
        if ignored {
          continue
        }
      } else {
        does_respect_gitignore.val = false
      }
    }
    match entry.kind {
      Directory => {
        if include_directories && glob_matches(pattern, relative_path) {
          total_matches.val = total_matches.val + 1
          if matches.length() < max_results {
            matches.push(relative_path)
          }
        }
        collect_glob_matches(
          absolute_path,
          relative_path,
          pattern,
          cwd,
          include_hidden,
          include_directories,
          respect_gitignore,
          does_respect_gitignore~,
          matches,
          total_matches~,
          max_results,
        )
      }
      Regular | SymLink =>
        if glob_matches(pattern, relative_path) {
          total_matches.val = total_matches.val + 1
          if matches.length() < max_results {
            matches.push(relative_path)
          }
        }
      _ => ()
    }
  }
}

///|
async fn execute_glob_files(
  cwd : String,
  input : GlobFilesInput,
) -> GlobFilesResult {
  let root = input.path.unwrap_or(".")
  let absolute_root = resolve_glob_path(cwd, root) catch {
    error => fail("failed to resolve path: \{error}")
  }
  match @fsx.kind(absolute_root) {
    Directory => ()
    _ => fail("glob_files path must be a directory")
  }
  let max_results = match input.max_results {
    Some(value) => Int::max(1, value)
    None => 200
  }
  let respect_gitignore = input.respect_gitignore.unwrap_or(true)
  let include_hidden = input.include_hidden.unwrap_or(false)
  let include_directories = input.include_directories.unwrap_or(false)
  let matches = []
  let total_matches = Ref::Ref(0)
  let does_respect_gitignore = Ref::Ref(true)
  collect_glob_matches(
    absolute_root,
    ".",
    input.pattern,
    cwd,
    include_hidden,
    include_directories,
    respect_gitignore,
    does_respect_gitignore~,
    matches,
    total_matches~,
    max_results,
  )
  let display_root = @pathx.relative(cwd, absolute_root) catch {
    _ => absolute_root
  }
  {
    root: display_root,
    pattern: input.pattern,
    matches,
    total_matches: total_matches.val,
    truncated: total_matches.val > matches.length(),
    respect_gitignore: respect_gitignore && does_respect_gitignore.val,
  }
}

///|
pub fn new(cwd : String) -> @tool.Tool[GlobFilesResult] {
  @tool.new(
    name="glob_files",
    description="Find file paths by glob pattern. Use this before reading files when you need a focused candidate set.",
    schema~,
    async fn(args) -> @tool.ToolResult[GlobFilesResult] noraise {
      let input : GlobFilesInput = @json.from_json(args) catch {
        _ => return @tool.error("Error: 'pattern' parameter is required")
      }
      let result = execute_glob_files(cwd, input) catch {
        error => return @tool.error("Error running glob_files: \{error}")
      }
      @tool.ok(result)
    },
  )
}
