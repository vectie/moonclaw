///|
/// Tool effects are explicit planner metadata, not model-authored hints.
/// They keep concurrency and batch boundaries fail-closed when a tool gains a
/// new argument or transport implementation.
priv enum MoonCodeToolEffect {
  ConcurrentRead
  ExclusiveMutation
  BatchSeal
}

///|
fn mooncode_runtime_tool_effect(tool_call : Json) -> MoonCodeToolEffect {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  match tool {
    "finish" => BatchSeal
    // Skill reads have a dedicated boundary: already-planned safe inspections
    // may finish, while later mutations wait for the model to consume the
    // skill. Keep them exclusive without bypassing that finer predicate.
    "read_skill" => ExclusiveMutation
    "read" | "view_image" | "moon_ide" | "moon_check" => ConcurrentRead
    "browser" => {
      let action = mooncode_json_string(arguments, "action", default="")
      if action == "snapshot" ||
        action == "screenshot" ||
        action == "get" ||
        action == "console" ||
        action == "errors" {
        ConcurrentRead
      } else {
        // Even loopback navigation, viewport changes, reload, close, and eval
        // mutate shared browser state. Keep them exclusive so observational
        // calls cannot race a state transition in the same model batch.
        ExclusiveMutation
      }
    }
    "shell" =>
      if !mooncode_json_bool(arguments, "background", default=false) &&
        mooncode_shell_is_demonstrably_read_only(
          mooncode_json_string(arguments, "cmd", default=""),
        ) {
        ConcurrentRead
      } else {
        ExclusiveMutation
      }
    "moon_cmd" => {
      let command = mooncode_json_string(arguments, "command", default="")
      if (command == "check" || command == "test" || command == "build") &&
        !mooncode_moon_cmd_is_test_update(arguments) {
        ConcurrentRead
      } else {
        ExclusiveMutation
      }
    }
    _ => ExclusiveMutation
  }
}

///|
fn mooncode_runtime_tool_effect_key(effect : MoonCodeToolEffect) -> String {
  match effect {
    ConcurrentRead => "concurrent_read"
    ExclusiveMutation => "exclusive_mutation"
    BatchSeal => "batch_seal"
  }
}

///|
fn mooncode_runtime_tool_effect_is_concurrent_read(tool_call : Json) -> Bool {
  mooncode_runtime_tool_effect(tool_call) is ConcurrentRead
}

///|
fn mooncode_runtime_tool_effect_is_batch_seal(tool_call : Json) -> Bool {
  mooncode_runtime_tool_effect(tool_call) is BatchSeal
}
