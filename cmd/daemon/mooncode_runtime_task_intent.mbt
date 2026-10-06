///|
fn mooncode_runtime_turn_task_intent(command : Json) -> String? {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  match mooncode_json_string(payload, "task_intent", default="") {
    "workspace_change" => Some("workspace_change")
    "read_only" => Some("read_only")
    _ => {
      let request = mooncode_runtime_turn_prompt_text(command)
        .to_lower()
        .to_string()
      let action = mooncode_json_string(command, "command", default="prompt")
      if (action == "prompt" || action == "steer") &&
        !mooncode_runtime_turn_model_has_mutation_intent(action, request) &&
        mooncode_runtime_turn_model_is_read_only_request(request) {
        Some("read_only")
      } else {
        None
      }
    }
  }
}

///|
fn mooncode_runtime_turn_model_needs_coding_tools(
  command : Json,
  request : String,
) -> Bool {
  match mooncode_runtime_turn_task_intent(command) {
    Some("workspace_change") => return true
    Some("read_only") => return false
    _ => ()
  }
  let action = mooncode_json_string(command, "command", default="prompt")
  if mooncode_runtime_turn_model_has_mutation_intent(action, request) {
    return true
  }
  if mooncode_runtime_turn_model_is_read_only_request(request) {
    return false
  }
  mooncode_runtime_turn_request_has_word(request, "code") ||
  mooncode_runtime_turn_request_has_word(request, "script") ||
  mooncode_runtime_turn_request_has_word(request, "tool") ||
  mooncode_runtime_turn_request_has_word(request, "app") ||
  mooncode_runtime_turn_request_has_word(request, "miniapp") ||
  mooncode_runtime_turn_request_has_word(request, "site")
}

///|
fn mooncode_runtime_turn_model_has_mutation_intent(
  action : String,
  request : String,
) -> Bool {
  let request = mooncode_runtime_turn_affirmative_request(request)
  action == "package" ||
  mooncode_runtime_turn_request_has_word(request, "implement") ||
  mooncode_runtime_turn_request_has_word(request, "fix") ||
  mooncode_runtime_turn_request_has_word(request, "debug") ||
  mooncode_runtime_turn_request_has_word(request, "refactor") ||
  mooncode_runtime_turn_request_has_word(request, "edit") ||
  mooncode_runtime_turn_request_has_word(request, "write") ||
  mooncode_runtime_turn_request_has_word(request, "create") ||
  mooncode_runtime_turn_request_has_word(request, "build") ||
  mooncode_runtime_turn_request_has_word(request, "modify") ||
  mooncode_runtime_turn_request_has_word(request, "change") ||
  mooncode_runtime_turn_request_has_word(request, "update") ||
  mooncode_runtime_turn_requests_tests(request)
}

///|
fn mooncode_runtime_turn_model_is_read_only_request(request : String) -> Bool {
  let unquoted = mooncode_runtime_turn_unquoted_request(request)
  let request = mooncode_runtime_turn_affirmative_request(request)
  mooncode_runtime_turn_has_nonmutation_constraint(unquoted) ||
  mooncode_runtime_turn_request_has_word(request, "audit") ||
  mooncode_runtime_turn_request_has_word(request, "inspect") ||
  request.contains("explain") ||
  request.contains("summarize") ||
  request.contains("summarise") ||
  request.contains("describe") ||
  request.contains("analyze") ||
  request.contains("analyse") ||
  request.contains("review") ||
  request.contains("compare") ||
  request.contains("evaluate") ||
  request.has_prefix("read ") ||
  request.has_prefix("open ") ||
  request.has_prefix("inspect ") ||
  request.has_prefix("what ") ||
  request.has_prefix("tell ")
}

///|
/// Ignore quoted examples when inferring task purpose. The original prompt is
/// still passed unchanged to the planner. Apostrophes within words are retained.
fn mooncode_runtime_turn_unquoted_request(request : String) -> String {
  let chars = request.iter().to_array()
  let output = StringBuilder()
  let mut quote : Char? = None
  for index, char in chars {
    match quote {
      Some(delimiter) => if char == delimiter { quote = None }
      None => {
        let starts_quote = char == '"' ||
          char == '`' ||
          (
            char == '\'' &&
            (index == 0 || chars[index - 1] == ' ' || chars[index - 1] == '\n')
          )
        if starts_quote {
          quote = Some(char)
          output.write_string(" ")
        } else if char == '\n' ||
          char == ';' ||
          char == '!' ||
          char == '?' ||
          (
            char == '.' &&
            (
              index + 1 == chars.length() ||
              chars[index + 1] == ' ' ||
              chars[index + 1] == '\n'
            )
          ) {
          output.write_string(" ; ")
        } else if char == '\t' || char == '\r' || char == ',' {
          output.write_string(" ")
        } else {
          output.write_char(char)
        }
      }
    }
  }
  output.to_string()
}

///|
/// Bounded clause-level inference, not a general language parser. Negation
/// applies through the current clause, including coordinated "edit or fix".
/// A new sentence/clause or "but/however" resumes affirmative intent, so a
/// restriction on generated files does not erase an earlier source-fix request.
fn mooncode_runtime_turn_affirmative_request(request : String) -> String {
  let words = mooncode_runtime_turn_unquoted_request(request)
    .split(" ")
    .filter(word => word != "")
    .map(word => word.to_owned())
    .to_array()
  let output : Array[String] = []
  let mut negated = false
  for index, word in words {
    if word == ";" || word == "but" || word == "however" {
      negated = false
    } else if word == "no" ||
      word == "never" ||
      word == "without" ||
      word == "don't" ||
      word == "don’t" ||
      (
        (word == "do" || word == "must" || word == "should") &&
        words.get(index + 1) == Some("not")
      ) {
      negated = true
    } else if !negated {
      output.push(word)
    }
  }
  output.join(" ")
}

///|
fn mooncode_runtime_turn_has_nonmutation_constraint(request : String) -> Bool {
  for
    prefix in [
      "do not ", "don't ", "don’t ", "must not ", "should not ", "never ", "no ",
      "without ",
    ] {
    for
      verb in [
        "edit", "fix", "modify", "change", "write", "writing", "creat", "refactor",
      ] {
      if request.contains(prefix + verb) {
        return true
      }
    }
  }
  request.contains("read-only") || request.contains("read only")
}
