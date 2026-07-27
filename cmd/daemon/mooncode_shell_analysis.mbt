///|
const MOONCODE_SHELL_BOUNDARY_TOKEN = "\u{0}mooncode-shell-boundary\u{0}"

///|
fn mooncode_shell_push_word(
  words : Array[String],
  current : StringBuilder,
) -> Unit {
  if !current.is_empty() {
    words.push(current.to_string())
    current.reset()
  }
}

///|
/// Tokenize enough POSIX shell syntax to classify executable commands without
/// matching quoted prose. Operators become explicit boundary tokens so words
/// from separate commands cannot be combined into a false match.
fn mooncode_shell_words(command : String) -> Array[String] {
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
      ' ' | '\t' | '\r' => mooncode_shell_push_word(words, current)
      '\n' | ';' | '|' | '&' => {
        mooncode_shell_push_word(words, current)
        words.push(MOONCODE_SHELL_BOUNDARY_TOKEN)
      }
      _ => current.write_char(ch)
    }
  }
  if escaped {
    current.write_char('\\')
  }
  mooncode_shell_push_word(words, current)
  words
}

///|
fn mooncode_shell_word_is_assignment(word : String) -> Bool {
  word.contains("=") && !word.has_prefix("=")
}

///|
fn mooncode_shell_git_executable(word : String) -> Bool {
  word == "git" || word.has_suffix("/git")
}

///|
fn mooncode_shell_segment_executable_index(segment : Array[String]) -> Int {
  if segment.is_empty() {
    return -1
  }
  let mut index = 0
  while index < segment.length() &&
        mooncode_shell_word_is_assignment(segment[index]) {
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
            mooncode_shell_word_is_assignment(segment[index])
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
fn mooncode_shell_segment_has_git_subcommand(
  segment : Array[String],
  subcommands : ArrayView[String],
) -> Bool {
  let mut index = mooncode_shell_segment_executable_index(segment)
  if index < 0 || !mooncode_shell_git_executable(segment[index]) {
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
fn mooncode_shell_has_git_subcommand(
  command : String,
  subcommands : ArrayView[String],
) -> Bool {
  let segment : Array[String] = []
  for word in mooncode_shell_words(command) {
    if word == MOONCODE_SHELL_BOUNDARY_TOKEN {
      if mooncode_shell_segment_has_git_subcommand(segment, subcommands) {
        return true
      }
      segment.clear()
    } else {
      segment.push(word)
    }
  }
  mooncode_shell_segment_has_git_subcommand(segment, subcommands)
}

///|
fn mooncode_shell_has_git_commit(command : String) -> Bool {
  mooncode_shell_has_git_subcommand(command, ["commit"])
}

///|
fn mooncode_shell_has_git_worktree_overwrite(command : String) -> Bool {
  mooncode_shell_has_git_subcommand(command, ["restore", "checkout"])
}

///|
fn mooncode_shell_segment_has_clean_dependency_install(
  segment : Array[String],
) -> Bool {
  let index = mooncode_shell_segment_executable_index(segment)
  if index < 0 || index + 1 >= segment.length() {
    return false
  }
  let executable = segment[index]
  let command = segment[index + 1]
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
fn mooncode_shell_has_clean_dependency_install(command : String) -> Bool {
  let segment : Array[String] = []
  for word in mooncode_shell_words(command) {
    if word == MOONCODE_SHELL_BOUNDARY_TOKEN {
      if mooncode_shell_segment_has_clean_dependency_install(segment) {
        return true
      }
      segment.clear()
    } else {
      segment.push(word)
    }
  }
  mooncode_shell_segment_has_clean_dependency_install(segment)
}

///|
fn mooncode_shell_has_pipeline(command : String) -> Bool {
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
fn mooncode_shell_pipefail_enabled(command : String) -> Bool {
  let prefix : Array[String] = []
  for word in mooncode_shell_words(command) {
    if word == MOONCODE_SHELL_BOUNDARY_TOKEN {
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
fn mooncode_shell_pipeline_exit_ambiguous(command : String) -> Bool {
  mooncode_shell_has_pipeline(command) &&
  !mooncode_shell_pipefail_enabled(command)
}
