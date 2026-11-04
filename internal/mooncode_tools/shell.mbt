///|
pub const SHELL_BOUNDARY_TOKEN = "\u{0}mooncode-shell-boundary\u{0}"

///|
fn shell_push_word(words : Array[String], current : StringBuilder) -> Unit {
  if !current.is_empty() {
    words.push(current.to_string())
    current.reset()
  }
}

///|
/// Tokenize enough POSIX shell syntax to classify executable commands without
/// matching quoted prose. Operators become explicit boundary tokens so words
/// from separate commands cannot be combined into a false match.
pub fn shell_words(command : String) -> Array[String] {
  let words : Array[String] = []
  let current = StringBuilder()
  let mut single_quoted = false
  let mut double_quoted = false
  let mut escaped = false
  for ch in command {
    if escaped {
      if ch != '\n' {
        current.write_char(ch)
      }
      escaped = false
      continue
    }
    if single_quoted {
      if ch == '\'' {
        single_quoted = false
      } else {
        current.write_char(ch)
      }
      continue
    }
    if double_quoted {
      if ch == '"' {
        double_quoted = false
      } else if ch == '\\' {
        escaped = true
      } else {
        current.write_char(ch)
      }
      continue
    }
    match ch {
      '\\' => escaped = true
      '\'' => single_quoted = true
      '"' => double_quoted = true
      ' ' | '\t' | '\r' => shell_push_word(words, current)
      '\n' | ';' | '|' | '&' => {
        shell_push_word(words, current)
        words.push(SHELL_BOUNDARY_TOKEN)
      }
      _ => current.write_char(ch)
    }
  }
  if escaped {
    current.write_char('\\')
  }
  shell_push_word(words, current)
  words
}

///|
fn shell_word_is_assignment(word : String) -> Bool {
  word.contains("=") && !word.has_prefix("=")
}

///|
fn shell_git_executable(word : String) -> Bool {
  word == "git" || word.has_suffix("/git")
}

///|
fn shell_segment_executable_index_from(
  segment : Array[String],
  start : Int32,
) -> Int32 {
  if segment.is_empty() {
    return -1
  }
  let mut index = start
  while index < segment.length() && shell_word_is_assignment(segment[index]) {
    index += 1
  }
  if index < segment.length() && segment[index] == "command" {
    index += 1
    while index < segment.length() && segment[index].has_prefix("-") {
      index += 1
    }
  }
  if index < segment.length() && segment[index] == "env" {
    index += 1
    while index < segment.length() &&
          (
            segment[index].has_prefix("-") ||
            shell_word_is_assignment(segment[index])
          ) {
      index += 1
    }
  }
  if index >= segment.length() {
    -1
  } else {
    index
  }
}

///|
pub fn shell_segment_executable_index(segment : Array[String]) -> Int32 {
  shell_segment_executable_index_from(segment, 0)
}

///|
fn shell_segment_has_git_subcommand(
  segment : Array[String],
  subcommands : ArrayView[String],
) -> Bool {
  let mut index = shell_segment_executable_index(segment)
  if index < 0 || !shell_git_executable(segment[index]) {
    return false
  }
  index += 1
  while index < segment.length() {
    let word = segment[index]
    if subcommands.contains(word) {
      return true
    }
    if word == "--" {
      index += 1
      return index < segment.length() && subcommands.contains(segment[index])
    }
    if !word.has_prefix("-") {
      return false
    }
    if (
        word == "-C" ||
        word == "-c" ||
        word == "--git-dir" ||
        word == "--work-tree" ||
        word == "--namespace" ||
        word == "--exec-path"
      ) &&
      index + 1 < segment.length() {
      index += 2
    } else {
      index += 1
    }
  }
  false
}

///|
fn shell_has_git_subcommand(
  command : String,
  subcommands : ArrayView[String],
) -> Bool {
  let segment : Array[String] = []
  for word in shell_words(command) {
    if word == SHELL_BOUNDARY_TOKEN {
      if shell_segment_has_git_subcommand(segment, subcommands) {
        return true
      }
      segment.clear()
    } else {
      segment.push(word)
    }
  }
  shell_segment_has_git_subcommand(segment, subcommands)
}

///|
fn shell_segment_has_git_commit(segment : Array[String]) -> Bool {
  if shell_segment_has_git_subcommand(segment, ["commit"]) {
    return true
  }
  let executable_index = shell_segment_executable_index(segment)
  if executable_index < 0 {
    return false
  }
  let executable = segment[executable_index]
  if !shell_executable_is(executable, "sh") &&
    !shell_executable_is(executable, "bash") &&
    !shell_executable_is(executable, "zsh") {
    return false
  }
  let nested_index = shell_nested_command_index(segment, executable_index)
  nested_index >= 0 && shell_has_git_commit(segment[nested_index])
}

///|
pub fn shell_has_git_commit(command : String) -> Bool {
  let segment : Array[String] = []
  for word in shell_words(command) {
    if word == SHELL_BOUNDARY_TOKEN {
      if shell_segment_has_git_commit(segment) {
        return true
      }
      segment.clear()
    } else {
      segment.push(word)
    }
  }
  shell_segment_has_git_commit(segment)
}

///|
pub fn shell_has_git_workspace_mutation(command : String) -> Bool {
  shell_has_git_subcommand(command, [
    "add", "am", "apply", "branch", "checkout", "cherry-pick", "clean", "commit",
    "config", "init", "merge", "mv", "rebase", "reset", "restore", "revert", "rm",
    "stash", "switch", "tag",
  ])
}

///|
pub fn shell_has_git_worktree_overwrite(command : String) -> Bool {
  shell_has_git_subcommand(command, ["restore", "checkout"])
}

///|
fn shell_segment_has_clean_dependency_install(segment : Array[String]) -> Bool {
  let index = shell_segment_executable_index(segment)
  if index < 0 || index + 1 >= segment.length() {
    return false
  }
  let executable = segment[index]
  let command_index = shell_subcommand_index_after_options(segment, index, [
    "--cache", "--prefix", "--registry", "--userconfig", "--workspace", "-C", "-w",
  ])
  if command_index < 0 || shell_segment_requests_help(segment, command_index) {
    return false
  }
  let command = segment[command_index]
  if (executable == "npm" || executable.has_suffix("/npm")) && command == "ci" {
    return true
  }
  if command != "install" {
    return false
  }
  let immutable = segment.contains("--immutable") ||
    segment.contains("--frozen-lockfile")
  immutable &&
  (
    executable == "pnpm" ||
    executable.has_suffix("/pnpm") ||
    executable == "yarn" ||
    executable.has_suffix("/yarn") ||
    executable == "bun" ||
    executable.has_suffix("/bun")
  )
}

///|
pub fn shell_has_clean_dependency_install(command : String) -> Bool {
  let segment : Array[String] = []
  for word in shell_words(command) {
    if word == SHELL_BOUNDARY_TOKEN {
      if shell_segment_has_clean_dependency_install(segment) {
        return true
      }
      segment.clear()
    } else {
      segment.push(word)
    }
  }
  shell_segment_has_clean_dependency_install(segment)
}

///|
fn shell_executable_is(word : String, name : String) -> Bool {
  word == name || word.has_suffix("/" + name)
}

///|
fn shell_subcommand_index_after_options(
  segment : Array[String],
  executable_index : Int32,
  options_with_values : ArrayView[String],
) -> Int32 {
  let mut index = executable_index + 1
  while index < segment.length() {
    let word = segment[index]
    if word == "--" {
      index += 1
      break
    }
    if !word.has_prefix("-") {
      break
    }
    if options_with_values.contains(word) && !word.contains("=") {
      index += 2
    } else {
      index += 1
    }
  }
  if index < segment.length() {
    index
  } else {
    -1
  }
}

///|
fn shell_segment_requests_help(
  segment : Array[String],
  subcommand_index : Int32,
) -> Bool {
  for index in (subcommand_index + 1)..<segment.length() {
    let word = segment[index]
    if word == "--" {
      return false
    }
    if word == "--help" || word == "-h" {
      return true
    }
  }
  false
}

///|
fn shell_nested_command_index(
  segment : Array[String],
  executable_index : Int32,
) -> Int32 {
  let mut index = executable_index + 1
  while index < segment.length() {
    let word = segment[index]
    if word == "--" || !word.has_prefix("-") {
      return -1
    }
    if word == "-c" ||
      (!word.has_prefix("--") && word.length() > 1 && word[1:].contains("c")) {
      return if index + 1 < segment.length() { index + 1 } else { -1 }
    }
    if word == "--rcfile" ||
      word == "--init-file" ||
      word == "-o" ||
      word == "+o" ||
      word == "-O" ||
      word == "+O" {
      index += 2
    } else {
      index += 1
    }
  }
  -1
}

///|
fn shell_segment_verification_kind(segment : Array[String]) -> String {
  let executable_index = shell_segment_executable_index(segment)
  if executable_index < 0 {
    return ""
  }
  let executable = segment[executable_index]
  if shell_executable_is(executable, "sh") ||
    shell_executable_is(executable, "bash") ||
    shell_executable_is(executable, "zsh") {
    let nested_index = shell_nested_command_index(segment, executable_index)
    return if nested_index < 0 {
      ""
    } else {
      shell_verification_kind(segment[nested_index])
    }
  }
  if shell_executable_is(executable, "test") || executable == "[" {
    return "check"
  }
  if shell_executable_is(executable, "git") &&
    shell_segment_has_git_subcommand(segment, ["diff"]) &&
    segment.contains("--check") {
    return "check"
  }
  if shell_executable_is(executable, "gh") {
    let subcommand_index = shell_subcommand_index_after_options(
      segment,
      executable_index,
      ["--hostname", "-R", "--repo"],
    )
    if subcommand_index >= 0 &&
      segment[subcommand_index] == "pr" &&
      subcommand_index + 1 < segment.length() &&
      segment[subcommand_index + 1] == "checks" {
      return "check"
    }
    return ""
  }
  let moon_index = if shell_executable_is(executable, "time") {
    shell_subcommand_index_after_options(segment, executable_index, ["-f", "-o"])
  } else {
    executable_index
  }
  if moon_index < 0 || !shell_executable_is(segment[moon_index], "moon") {
    return ""
  }
  let subcommand_index = shell_subcommand_index_after_options(
    segment,
    moon_index,
    ["--source-dir", "--target-dir"],
  )
  if subcommand_index < 0 {
    return ""
  }
  let subcommand = segment[subcommand_index]
  if subcommand == "check" || subcommand == "info" {
    "check"
  } else if subcommand == "test" {
    "test"
  } else if subcommand == "build" {
    "build"
  } else {
    ""
  }
}

///|
fn shell_verification_kind(command : String) -> String {
  let segment : Array[String] = []
  let mut kind = ""
  for word in shell_words(command) {
    if word == SHELL_BOUNDARY_TOKEN {
      if !segment.is_empty() {
        kind = shell_segment_verification_kind(segment)
        segment.clear()
      }
    } else {
      segment.push(word)
    }
  }
  if !segment.is_empty() {
    kind = shell_segment_verification_kind(segment)
  }
  kind
}

///|
pub fn shell_verifies_kind(command : String, expected : String) -> Bool {
  if expected != "check" && expected != "test" && expected != "build" {
    return false
  }
  shell_verification_kind(command) == expected
}

///|
fn shell_segment_has_sensitive_command(segment : Array[String]) -> Bool {
  let index = shell_segment_executable_index(segment)
  if index < 0 {
    return false
  }
  let executable = segment[index]
  if shell_executable_is(executable, "curl") {
    return !shell_segment_is_safe_loopback_curl(segment, index)
  }
  if shell_executable_is(executable, "sudo") ||
    shell_executable_is(executable, "rm") ||
    shell_executable_is(executable, "wget") ||
    shell_executable_is(executable, "ssh") ||
    shell_executable_is(executable, "scp") ||
    shell_executable_is(executable, "brew") {
    return true
  }
  if shell_executable_is(executable, "git") {
    return shell_segment_has_git_subcommand(segment, ["push", "reset"])
  }
  if shell_executable_is(executable, "sh") ||
    shell_executable_is(executable, "bash") ||
    shell_executable_is(executable, "zsh") {
    let nested_index = shell_nested_command_index(segment, index)
    return nested_index >= 0 &&
      shell_has_sensitive_command(segment[nested_index])
  }
  let subcommand_index = shell_subcommand_index_after_options(segment, index, [
    "--cache", "--cwd", "--dir", "--prefix", "--registry", "--userconfig", "--workspace",
    "-C", "-w",
  ])
  if subcommand_index < 0 ||
    shell_segment_requests_help(segment, subcommand_index) {
    return false
  }
  let subcommand = segment[subcommand_index]
  if shell_executable_is(executable, "gh") {
    return subcommand == "run" &&
      subcommand_index + 1 < segment.length() &&
      segment[subcommand_index + 1] == "rerun"
  }
  if shell_executable_is(executable, "moon") {
    return subcommand == "publish"
  }
  if shell_executable_is(executable, "npm") {
    return subcommand == "publish" || subcommand == "install"
  }
  if shell_executable_is(executable, "pnpm") {
    return subcommand == "publish" || subcommand == "add"
  }
  if shell_executable_is(executable, "yarn") {
    return subcommand == "add"
  }
  if shell_executable_is(executable, "pip") ||
    shell_executable_is(executable, "pip3") {
    return subcommand == "install"
  }
  false
}

///|
/// A GET/HEAD-only request to a loopback preview is local observation. Any
/// upload, body, output-file, custom mutating method, or remote URL remains
/// sensitive.
fn shell_segment_is_safe_loopback_curl(
  segment : Array[String],
  executable_index : Int32,
) -> Bool {
  let mut index = executable_index + 1
  let mut url_seen = false
  while index < segment.length() {
    let word = segment[index]
    if word == "-X" || word == "--request" {
      if index + 1 >= segment.length() {
        return false
      }
      let method_ = segment[index + 1].to_upper()
      if method_ != "GET" && method_ != "HEAD" {
        return false
      }
      index += 2
      continue
    }
    if word.has_prefix("--request=") {
      let method_ = word[10:].to_upper()
      if method_ != "GET" && method_ != "HEAD" {
        return false
      }
      index += 1
      continue
    }
    if word == "-d" ||
      word == "--data" ||
      word == "--data-raw" ||
      word == "--data-binary" ||
      word == "-F" ||
      word == "--form" ||
      word == "-T" ||
      word == "--upload-file" ||
      word == "-O" ||
      word == "--remote-name" {
      return false
    }
    if word == "-o" || word == "--output" {
      if index + 1 < segment.length() && segment[index + 1] == "/dev/null" {
        index += 2
        continue
      }
      return false
    }
    if word.has_prefix("--data=") ||
      word.has_prefix("--data-raw=") ||
      word.has_prefix("--data-binary=") ||
      word.has_prefix("--form=") ||
      word.has_prefix("--upload-file=") ||
      (word.has_prefix("--output=") && word != "--output=/dev/null") {
      return false
    }
    if word.has_prefix("http://") || word.has_prefix("https://") {
      if !browser_loopback_url(word) {
        return false
      }
      url_seen = true
    }
    index += 1
  }
  url_seen
}

///|
pub fn shell_has_sensitive_command(command : String) -> Bool {
  let (substitutions_valid, outer_command, substitutions) = shell_extract_command_substitutions(
    command,
  )
  if !substitutions_valid {
    return true
  }
  for substitution in substitutions {
    if !shell_is_demonstrably_read_only(substitution) {
      return true
    }
  }
  let segment : Array[String] = []
  for word in shell_words(outer_command) {
    if word == SHELL_BOUNDARY_TOKEN {
      if shell_segment_has_sensitive_command(segment) {
        return true
      }
      segment.clear()
    } else {
      segment.push(word)
    }
  }
  shell_segment_has_sensitive_command(segment)
}

///|
fn shell_segment_is_read_only_awk(
  segment : Array[String],
  executable_index : Int32,
) -> Bool {
  let mut index = executable_index + 1
  while index < segment.length() {
    let word = segment[index]
    if word == "--" {
      index += 1
      break
    }
    if !word.has_prefix("-") {
      break
    }
    if word == "-f" ||
      word == "--file" ||
      word.has_prefix("--file=") ||
      word == "-e" ||
      word == "--source" ||
      word.has_prefix("--source=") {
      return false
    }
    if word == "-F" || word == "-v" || word == "--assign" {
      index += 2
    } else if word.has_prefix("-F") ||
      word.has_prefix("-v") ||
      word.has_prefix("--assign=") {
      index += 1
    } else {
      return false
    }
  }
  if index >= segment.length() {
    return false
  }
  let program = segment[index].to_lower().to_string()
  !program.contains("system") &&
  !program.contains("getline") &&
  !program.contains(">") &&
  !program.contains("|") &&
  !program.contains("@load")
}

///|
fn shell_segment_is_read_only_git(segment : Array[String]) -> Bool {
  shell_segment_has_git_subcommand(segment, [
    "annotate", "blame", "cat-file", "describe", "diff", "diff-files", "diff-index",
    "diff-tree", "for-each-ref", "grep", "log", "ls-files", "ls-tree", "merge-base",
    "name-rev", "rev-list", "rev-parse", "show", "show-ref", "status", "verify",
  ])
}

///|
fn shell_segment_is_read_only_gh(
  segment : Array[String],
  index : Int32,
) -> Bool {
  if index + 2 >= segment.length() || segment.contains("--web") {
    return false
  }
  segment[index + 1] == "run" &&
  (segment[index + 2] == "view" || segment[index + 2] == "list")
}

///|
fn shell_segment_read_only_executable_index(segment : Array[String]) -> Int32 {
  let mut index = shell_segment_executable_index(segment)
  if index < 0 {
    return -1
  }
  let executable = segment[index]
  if !shell_executable_is(executable, "time") {
    return index
  }
  index += 1
  while index < segment.length() && segment[index].has_prefix("-") {
    let option = segment[index]
    if option == "-o" || option == "--output" || option.has_prefix("--output=") {
      return -1
    }
    if (option == "-f" || option == "--format") && !option.contains("=") {
      index += 2
    } else {
      index += 1
    }
  }
  if index < segment.length() {
    index
  } else {
    -1
  }
}

///|
fn shell_segment_is_demonstrably_read_only(segment : Array[String]) -> Bool {
  if segment.is_empty() {
    return true
  }
  let index = shell_segment_read_only_executable_index(segment)
  if index < 0 {
    return false
  }
  let executable = segment[index]
  if shell_executable_is(executable, "git") {
    return shell_segment_is_read_only_git(segment[index:].to_owned())
  }
  if shell_executable_is(executable, "gh") {
    return shell_segment_is_read_only_gh(segment, index)
  }
  if shell_executable_is(executable, "npm") ||
    shell_executable_is(executable, "pnpm") ||
    shell_executable_is(executable, "yarn") ||
    shell_executable_is(executable, "bun") {
    return segment[index + 1:].contains("--help") ||
      segment[index + 1:].contains("-h")
  }
  if shell_executable_is(executable, "curl") {
    return shell_segment_is_safe_loopback_curl(segment, index)
  }
  if shell_executable_is(executable, "moon") {
    let subcommand_index = shell_subcommand_index_after_options(
      segment,
      index,
      ["-C", "--directory"],
    )
    if subcommand_index < 0 {
      return false
    }
    let subcommand = segment[subcommand_index]
    if subcommand != "check" && subcommand != "test" && subcommand != "build" {
      return false
    }
    return !segment.contains("--update") && !segment.contains("-u")
  }
  if shell_executable_is(executable, "sh") ||
    shell_executable_is(executable, "bash") ||
    shell_executable_is(executable, "zsh") {
    let nested_index = shell_nested_command_index(segment, index)
    return nested_index >= 0 &&
      shell_is_demonstrably_read_only(segment[nested_index])
  }
  if shell_executable_is(executable, "find") {
    for word in segment[index + 1:] {
      if word == "-delete" ||
        word == "-exec" ||
        word == "-execdir" ||
        word == "-ok" ||
        word == "-okdir" ||
        word == "-fprint" ||
        word == "-fprintf" ||
        word == "-fls" {
        return false
      }
    }
    return true
  }
  if shell_executable_is(executable, "sort") {
    for word in segment[index + 1:] {
      if word == "-o" || word == "--output" || word.has_prefix("--output=") {
        return false
      }
    }
    return true
  }
  if shell_executable_is(executable, "sed") {
    for word in segment[index + 1:] {
      if word == "-i" ||
        word.has_prefix("-i") ||
        word == "--in-place" ||
        word.has_prefix("--in-place=") ||
        word == "w" ||
        word.has_prefix("w ") {
        return false
      }
    }
    return true
  }
  if shell_executable_is(executable, "awk") {
    return shell_segment_is_read_only_awk(segment, index)
  }
  for
    name in [
      "basename", "cut", "dirname", "echo", "false", "file", "grep", "head", "jq",
      "ls", "printf", "pwd", "rg", "set", "stat", "tail", "test", "tr", "true", "type",
      "uniq", "wc", "which",
    ] {
    if shell_executable_is(executable, name) {
      return true
    }
  }
  false
}

///|
fn shell_is_demonstrably_read_only(command : String) -> Bool {
  if command.trim().is_empty() ||
    command.contains("<(") ||
    command.contains(">(") {
    return false
  }
  let (substitutions_valid, outer_command, substitutions) = shell_extract_command_substitutions(
    command,
  )
  if !substitutions_valid ||
    shell_has_file_output_redirection(outer_command) ||
    shell_has_in_place_authoring(outer_command) {
    return false
  }
  for substitution in substitutions {
    if !shell_is_demonstrably_read_only(substitution) {
      return false
    }
  }
  let segment : Array[String] = []
  let mut executable_seen = false
  for word in shell_words(outer_command) {
    if word == SHELL_BOUNDARY_TOKEN {
      if !segment.is_empty() {
        executable_seen = true
        if !shell_segment_is_demonstrably_read_only(segment) {
          return false
        }
        segment.clear()
      }
    } else {
      segment.push(word)
    }
  }
  if !segment.is_empty() {
    executable_seen = true
    if !shell_segment_is_demonstrably_read_only(segment) {
      return false
    }
  }
  executable_seen
}

///|
fn shell_command_substitution_at(
  chars : Array[Char],
  start : Int32,
) -> (String, Int32)? {
  if start + 1 >= chars.length() ||
    chars[start] != '$' ||
    chars[start + 1] != '(' {
    return None
  }
  if start + 2 < chars.length() && chars[start + 2] == '(' {
    return None
  }
  let content = StringBuilder()
  let mut depth = 1
  let mut index = start + 2
  let mut single_quoted = false
  let mut double_quoted = false
  let mut escaped = false
  while index < chars.length() {
    let ch = chars[index]
    if escaped {
      content.write_char(ch)
      escaped = false
      index += 1
      continue
    }
    if ch == '\\' && !single_quoted {
      content.write_char(ch)
      escaped = true
      index += 1
      continue
    }
    if ch == '\'' && !double_quoted {
      single_quoted = !single_quoted
      content.write_char(ch)
      index += 1
      continue
    }
    if ch == '"' && !single_quoted {
      double_quoted = !double_quoted
      content.write_char(ch)
      index += 1
      continue
    }
    if !single_quoted && !double_quoted {
      if ch == '$' && index + 1 < chars.length() && chars[index + 1] == '(' {
        depth += 1
        content.write_string("$(")
        index += 2
        continue
      }
      if ch == '(' {
        depth += 1
      } else if ch == ')' {
        depth -= 1
        if depth == 0 {
          return Some((content.to_string(), index + 1))
        }
      }
    }
    content.write_char(ch)
    index += 1
  }
  None
}

///|
fn shell_extract_command_substitutions(
  command : String,
) -> (Bool, String, Array[String]) {
  let chars = command.to_array()
  let outer = StringBuilder()
  let substitutions : Array[String] = []
  let mut index = 0
  let mut single_quoted = false
  let mut double_quoted = false
  let mut escaped = false
  while index < chars.length() {
    let ch = chars[index]
    if single_quoted {
      outer.write_char(ch)
      if ch == '\'' {
        single_quoted = false
      }
      index += 1
      continue
    }
    if escaped {
      outer.write_char(ch)
      escaped = false
      index += 1
      continue
    }
    if ch == '\\' {
      outer.write_char(ch)
      escaped = true
      index += 1
      continue
    }
    if ch == '\'' && !double_quoted {
      outer.write_char(ch)
      single_quoted = true
      index += 1
      continue
    }
    if ch == '"' {
      double_quoted = !double_quoted
      outer.write_char(ch)
      index += 1
      continue
    }
    if ch == '`' {
      return (false, "", [])
    }
    if ch == '$' && index + 1 < chars.length() && chars[index + 1] == '(' {
      match shell_command_substitution_at(chars, index) {
        Some((content, next_index)) => {
          substitutions.push(content)
          outer.write_string("mooncode-substitution")
          index = next_index
          continue
        }
        None => return (false, "", [])
      }
    }
    outer.write_char(ch)
    index += 1
  }
  if single_quoted || double_quoted || escaped {
    return (false, "", [])
  }
  (true, outer.to_string(), substitutions)
}

///|
fn shell_compound_command_executable_index(segment : Array[String]) -> Int32 {
  let mut index = 0
  while index < segment.length() &&
        ["!", "(", "{", "do", "then", "else", "elif", "if", "while", "until"].contains(
          segment[index],
        ) {
    index += 1
  }
  shell_segment_executable_index_from(segment, index)
}

///|
fn shell_sed_short_option(option : String) -> (Bool, Bool) {
  let chars = option.to_array()
  if chars.length() < 2 || chars[0] != '-' || chars[1] == '-' {
    return (false, false)
  }
  for index in 1..<chars.length() {
    match chars[index] {
      'i' => return (true, false)
      'e' | 'f' => return (false, index + 1 == chars.length())
      _ => ()
    }
  }
  (false, false)
}

///|
fn shell_segment_has_in_place_sed(segment : Array[String]) -> Bool {
  let executable_index = shell_compound_command_executable_index(segment)
  if executable_index < 0 {
    return false
  }
  let executable = segment[executable_index]
  if shell_executable_is(executable, "sh") ||
    shell_executable_is(executable, "bash") ||
    shell_executable_is(executable, "zsh") {
    let nested_index = shell_nested_command_index(segment, executable_index)
    return nested_index >= 0 &&
      shell_has_in_place_authoring(segment[nested_index])
  }
  let mut option_index = executable_index + 1
  if shell_executable_is(executable, "busybox") {
    if option_index >= segment.length() || segment[option_index] != "sed" {
      return false
    }
    option_index += 1
  } else if !shell_executable_is(executable, "sed") {
    return false
  }
  while option_index < segment.length() {
    let option = segment[option_index]
    if option == "--" {
      return false
    }
    if option == "--in-place" || option.has_prefix("--in-place=") {
      return true
    }
    if option == "--expression" || option == "--file" {
      option_index += 2
      continue
    }
    if option.has_prefix("--expression=") || option.has_prefix("--file=") {
      option_index += 1
      continue
    }
    let (in_place, consumes_next) = shell_sed_short_option(option)
    if in_place {
      return true
    }
    option_index += if consumes_next { 2 } else { 1 }
  }
  false
}

///|
pub fn shell_has_in_place_authoring(command : String) -> Bool {
  let segment : Array[String] = []
  for word in shell_words(command) {
    if word == SHELL_BOUNDARY_TOKEN {
      if shell_segment_has_in_place_sed(segment) {
        return true
      }
      segment.clear()
    } else {
      segment.push(word)
    }
  }
  shell_segment_has_in_place_sed(segment)
}

///|
fn shell_word_is_interpreter(word : String) -> Bool {
  shell_executable_is(word, "python") ||
  shell_executable_is(word, "python3") ||
  word.contains("/python3.") ||
  shell_executable_is(word, "pypy") ||
  shell_executable_is(word, "pypy3") ||
  shell_executable_is(word, "node") ||
  shell_executable_is(word, "deno") ||
  shell_executable_is(word, "bun") ||
  shell_executable_is(word, "ruby") ||
  shell_executable_is(word, "perl") ||
  shell_executable_is(word, "php")
}

///|
/// Inline interpreters remain useful for bounded read-only inspection, but
/// their file-writing APIs must not bypass MoonCode's reviewable mutation
/// tools. This recognizes the concrete write primitives rather than rejecting
/// all interpreter use.
pub fn shell_has_inline_interpreter_authoring(command : String) -> Bool {
  let mut has_interpreter = false
  for word in shell_words(command) {
    if word != SHELL_BOUNDARY_TOKEN && shell_word_is_interpreter(word) {
      has_interpreter = true
      break
    }
  }
  if !has_interpreter {
    return false
  }
  let compact = command
    .to_lower()
    .to_string()
    .replace_all(old=" ", new="")
    .replace_all(old="\t", new="")
  let writable_open = compact.contains("open(") &&
    [
      ",\"w\"", ",\"wb\"", ",\"a\"", ",\"ab\"", ",\"x\"", ",\"xb\"", ",'w'", ",'wb'",
      ",'a'", ",'ab'", ",'x'", ",'xb'",
    ].any(mode => compact.contains(mode))
  writable_open ||
  compact.contains(".write_text(") ||
  compact.contains(".write_bytes(") ||
  compact.contains("file.write(") ||
  compact.contains("file.open(") ||
  compact.contains(".writefile(") ||
  compact.contains(".writefilesync(") ||
  compact.contains(".appendfile(") ||
  compact.contains(".appendfilesync(") ||
  compact.contains("fs.writefile(") ||
  compact.contains("fs.writefilesync(") ||
  compact.contains("fs.appendfile(") ||
  compact.contains("fs.appendfilesync(") ||
  compact.contains("deno.write") ||
  compact.contains("os.rename(") ||
  compact.contains("os.replace(") ||
  compact.contains("shutil.copy")
}

///|
fn shell_chars_match(
  chars : Array[Char],
  start : Int32,
  expected : String,
) -> Bool {
  let expected_chars = expected.to_array()
  if start + expected_chars.length() > chars.length() {
    return false
  }
  for index, expected_char in expected_chars {
    if chars[start + index] != expected_char {
      return false
    }
  }
  true
}

///|
pub fn shell_has_file_output_redirection(command : String) -> Bool {
  let chars = command.to_array()
  let mut single_quoted = false
  let mut double_quoted = false
  let mut escaped = false
  for index, ch in chars {
    if escaped {
      escaped = false
      continue
    }
    if single_quoted {
      if ch == '\'' {
        single_quoted = false
      }
      continue
    }
    if double_quoted {
      if ch == '"' {
        double_quoted = false
      } else if ch == '\\' {
        escaped = true
      }
      continue
    }
    match ch {
      '\\' => escaped = true
      '\'' => single_quoted = true
      '"' => double_quoted = true
      '>' => {
        let mut target = index + 1
        if target < chars.length() && chars[target] == '>' {
          target += 1
        }
        while target < chars.length() &&
              (chars[target] == ' ' || chars[target] == '\t') {
          target += 1
        }
        let target_is_descriptor = target < chars.length() &&
          (chars[target] == '&' || chars[target] == '(')
        let target_is_dev_null = shell_chars_match(chars, target, "/dev/null")
        if !target_is_descriptor && !target_is_dev_null {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

///|
fn shell_has_pipeline(command : String) -> Bool {
  let chars = command.to_array()
  let mut single_quoted = false
  let mut double_quoted = false
  let mut escaped = false
  for index, ch in chars {
    if escaped {
      escaped = false
      continue
    }
    if single_quoted {
      if ch == '\'' {
        single_quoted = false
      }
      continue
    }
    if double_quoted {
      if ch == '"' {
        double_quoted = false
      } else if ch == '\\' {
        escaped = true
      }
      continue
    }
    match ch {
      '\\' => escaped = true
      '\'' => single_quoted = true
      '"' => double_quoted = true
      '|' => {
        let previous_is_pipe = index > 0 && chars[index - 1] == '|'
        let next_is_pipe = index + 1 < chars.length() && chars[index + 1] == '|'
        if !previous_is_pipe && !next_is_pipe {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

///|
fn shell_pipefail_enabled(command : String) -> Bool {
  let prefix : Array[String] = []
  for word in shell_words(command) {
    if word == SHELL_BOUNDARY_TOKEN {
      break
    }
    prefix.push(word)
  }
  if prefix.length() < 3 || prefix[0] != "set" {
    return false
  }
  for index in 1..<prefix.length() {
    if prefix[index] == "-o" &&
      index + 1 < prefix.length() &&
      prefix[index + 1] == "pipefail" {
      return true
    }
    if prefix[index].has_prefix("-") &&
      prefix[index].contains("o") &&
      index + 1 < prefix.length() &&
      prefix[index + 1] == "pipefail" {
      return true
    }
  }
  false
}

///|
pub fn shell_pipeline_exit_ambiguous(command : String) -> Bool {
  shell_has_pipeline(command) && !shell_pipefail_enabled(command)
}
