///|
/// Independent execution properties, not permissions or a task state machine.
/// Unknown tools stay serial and cannot be replayed without a result.
pub struct Policy {
  parallel_read : Bool
  after_skill : Bool
  replay : Bool
  local_operation : Bool
  local_validation : Bool
}

///|
fn policy(
  parallel_read~ : Bool = false,
  after_skill~ : Bool = false,
  replay~ : Bool = false,
  local_operation~ : Bool = false,
  local_validation~ : Bool = false,
) -> Policy {
  { parallel_read, after_skill, replay, local_operation, local_validation, }
}

///|
fn string_field(arguments : Json, key : String) -> String {
  match arguments {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
pub fn moon_cmd_is_test_update(arguments : Json) -> Bool {
  if string_field(arguments, "command") != "test" {
    return false
  }
  let update = arg => arg == "--update" || arg == "-u"
  if update(string_field(arguments, "arg")) {
    return true
  }
  match arguments {
    { "args": Array(args), .. } =>
      args.any(arg => {
        match arg {
          String(value) => update(value)
          _ => false
        }
      })
    _ => false
  }
}

///|
/// Classify execution properties; the executor still validates and authorizes.
///
/// ```mbt check
/// test {
///   assert_false(@mooncode_tools.classify("read_skill", {}).parallel_read)
/// }
/// ```
pub fn classify(tool : String, arguments : Json) -> Policy {
  match tool {
    "read" | "view_image" =>
      policy(
        parallel_read=true,
        after_skill=true,
        replay=true,
        local_operation=true,
      )
    // Loading instructions is not a filesystem mutation. Later semantic
    // actions wait until the model has consumed those instructions.
    "read_skill" | "finish" | "checkpoint" =>
      policy(replay=true, local_operation=true)
    "mcp_list_tools" =>
      policy(parallel_read=true, replay=true, local_operation=true)
    "moon_ide" => policy(parallel_read=true, local_operation=true)
    "moon_check" =>
      policy(parallel_read=true, local_operation=true, local_validation=true)
    "glob" | "grep" | "web_fetch" | "web_search" => policy(after_skill=true)
    "shell" => {
      let read_only = shell_is_demonstrably_read_only(
        string_field(arguments, "cmd"),
      )
      let background = arguments is { "background": true, .. }
      policy(
        parallel_read=read_only && !background,
        after_skill=read_only && !background,
        local_operation=read_only,
      )
    }
    "moon_cmd" => {
      let command = string_field(arguments, "command")
      let check = (
          command == "check" || command == "test" || command == "build"
        ) &&
        !moon_cmd_is_test_update(arguments)
      policy(
        parallel_read=check,
        local_operation=check,
        local_validation=check || command == "info" || command == "fmt",
      )
    }
    "browser" => {
      let action = string_field(arguments, "action")
      let observation = ["snapshot", "screenshot", "get", "console", "errors"].contains(
        action,
      )
      // Browser-local transitions may be autonomous but must remain serial.
      // This does not classify arbitrary JavaScript as free of side effects.
      policy(
        parallel_read=observation,
        local_operation=observation ||
          ["set_viewport", "eval", "reload", "close"].contains(action) ||
          (
            action == "open" &&
            browser_loopback_url(string_field(arguments, "url"))
          ),
      )
    }
    _ => policy()
  }
}

///|
pub fn browser_loopback_url(url : String) -> Bool {
  let lower = url.trim().to_lower().to_owned()
  lower.has_prefix("http://127.0.0.1") ||
  lower.has_prefix("https://127.0.0.1") ||
  lower.has_prefix("http://localhost") ||
  lower.has_prefix("https://localhost") ||
  lower.has_prefix("http://[::1]") ||
  lower.has_prefix("https://[::1]")
}
