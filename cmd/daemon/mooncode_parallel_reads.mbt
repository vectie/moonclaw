///|
/// Return a stable identity for redundant-work and path-alias detection.
///
/// Local file observations use their resolved MoonBook path so `a.txt` and
/// `./a.txt` cannot enter one batch as apparently independent reads. Other
/// read-only tools use their exact normalized call shape; their ExecutionSandbox
/// runs are isolated and therefore do not share build or process scratch state.
async fn mooncode_runtime_parallel_read_identity(
  book_root : String,
  tool_call : Json,
) -> String {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  if tool == "read" || tool == "view_image" {
    let path = mooncode_json_string(arguments, "path", default="")
    if path == "" {
      return ""
    }
    let resolved = mooncode_workspace_path(book_root, path)
    if !mooncode_json_bool(resolved, "ok", default=false) {
      return ""
    }
    return tool +
      ":path:" +
      mooncode_json_string(resolved, "absolute_path", default="")
  }
  if tool == "shell" {
    let cwd = mooncode_tool_cwd(book_root, arguments)
    if !mooncode_json_bool(cwd, "ok", default=false) {
      return ""
    }
    return "shell:cwd:" +
      mooncode_json_string(cwd, "absolute_path", default="") +
      ":cmd:" +
      mooncode_json_string(arguments, "cmd", default="")
  }
  if tool == "browser" ||
    tool == "moon_ide" ||
    tool == "moon_cmd" ||
    tool == "moon_check" {
    return tool + ":arguments:" + arguments.stringify()
  }
  ""
}

///|
/// A model-authored batch may run concurrently only when every call has one
/// explicit, executable read effect and all ordinary runtime guards agree.
async fn mooncode_runtime_turn_parallel_read_batch_allowed(
  book_root : String,
  plan : Json,
  tool_calls : Array[Json],
  resuming_step~ : Bool,
) -> Bool {
  if resuming_step ||
    tool_calls.length() < 2 ||
    mooncode_json_string(plan, "planner_mode", default="") !=
    mooncode_planner_mode_model_tool_calls() {
    return false
  }
  let seen_identities : Map[String, Unit] = Map([])
  for tool_call in tool_calls {
    if mooncode_json_string(tool_call, "validation_error", default="") != "" ||
      !mooncode_runtime_tool_policy(tool_call).parallel_read ||
      !mooncode_tool_supported(
        mooncode_json_string(tool_call, "tool", default=""),
      ) ||
      mooncode_runtime_tool_requires_approval(tool_call) {
      return false
    }
    let identity = mooncode_runtime_parallel_read_identity(book_root, tool_call)
    if identity == "" || seen_identities.contains(identity) {
      return false
    }
    seen_identities[identity] = ()
  }
  true
}

///|
/// Execute a previously validated concurrent-read batch. Structured
/// concurrency cancels peer tasks if execution itself raises, while contained
/// tool errors remain ordinary results. Waiting task handles in insertion order
/// keeps the returned array aligned exactly with the model's source order.
async fn Daemon::mooncode_runtime_turn_execute_parallel_reads(
  self : Daemon,
  command : Json,
  session_id : String,
  book_root : String,
  tool_calls : Array[Json],
) -> Array[Json] {
  let bodies = tool_calls.map(tool_call => {
    mooncode_runtime_turn_tool_body(command, tool_call)
  })
  let timestamps = tool_calls.map(_ => self.clock.now())
  @async.with_task_group(group => {
    let tasks = Array(capacity=tool_calls.length())
    for index in 0..<tool_calls.length() {
      tasks.push(
        group.spawn(() => {
          mooncode_execute_tool_call(
            session_id,
            book_root,
            bodies[index],
            now=timestamps[index],
          )
        }),
      )
    }
    let ordered : Array[Json] = []
    for task in tasks {
      ordered.push(task.wait())
    }
    ordered
  })
}
