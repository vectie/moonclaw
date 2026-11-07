///|
/// Task completion uses native execution facts; semantic quality remains with
/// the primary agent and explicit product adoption remains a separate fact.
fn mooncode_task_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn mooncode_task_contract_error(command : Json) -> String {
  let seen : Map[String, Bool] = Map([])
  for
    check in mooncode_json_array_items(
      mooncode_runtime_horizon_task_contract(command),
      "required_checks",
    ) {
    let id = mooncode_json_string(check, "id", default="")
    if id.trim().is_empty() ||
      seen.contains(id) ||
      !["shell", "moon_cmd"].contains(
        mooncode_json_string(check, "tool", default=""),
      ) ||
      mooncode_json_string(check, "command", default="").trim().is_empty() ||
      mooncode_json_string(check, "cwd", default="").is_empty() {
      return "required_checks need unique ids and exact tool, command and cwd"
    }
    seen[id] = true
  }
  ""
}

///|
fn mooncode_runtime_result_event_id(command : Json, result : Json) -> String {
  let event = mooncode_json_object_field_or_empty(result, "event")
  if !mooncode_json_bool(result, "accepted", default=false) ||
    mooncode_json_string(event, "source", default="") !=
    "moonclaw-native-tool-exec" ||
    mooncode_json_string(event, "command_id", default="") !=
    mooncode_command_id(command) ||
    mooncode_json_string(event, "session_id", default="") !=
    mooncode_json_string(command, "session_id", default="") ||
    mooncode_json_string(event, "book_root", default="") !=
    mooncode_book_root(command) ||
    mooncode_json_string(event, "tool", default="") !=
    mooncode_json_string(result, "tool", default="") ||
    mooncode_task_field(event, "tool_result") !=
    mooncode_tool_result_value(result) ||
    mooncode_json_bool(
      mooncode_tool_result_value(result),
      "is_error",
      default=true,
    ) ||
    !mooncode_json_bool(mooncode_tool_result_value(result), "ok", default=false) {
    return ""
  }
  mooncode_json_string(event, "id", default="")
}

///|
fn mooncode_runtime_check_cwd(command : Json, value : String) -> String {
  if value == "." {
    mooncode_book_root(command)
  } else {
    value
  }
}

///|
// Ordinary failed observations need recovery, but do not invalidate checks of
// unchanged inputs. Mutations, failed checks and uncertain effects invalidate
// those results.
fn mooncode_runtime_verification_boundary(results : Array[Json]) -> Int32 {
  let mut boundary = -1
  for index, result in results {
    let metadata = mooncode_json_object_field_or_empty(
      mooncode_tool_result_value(result),
      "metadata",
    )
    let tool = mooncode_json_string(result, "tool", default="")
    if (
        mooncode_runtime_turn_result_is_mutation(result) &&
        !mooncode_runtime_turn_result_is_commit_boundary(result)
      ) ||
      (
        !mooncode_json_bool(result, "accepted", default=false) &&
        (
          mooncode_runtime_turn_call_is_verification(result) ||
          ["write", "edit", "apply_patch", "revert_patch"].contains(tool) ||
          mooncode_json_bool(metadata, "outcome_unknown", default=false)
        )
      ) {
      boundary = index
    }
  }
  boundary
}

///|
/// Match declared checks to successful native process receipts after the latest
/// input-changing operation, failed verification or uncertain effect.
fn mooncode_runtime_required_check_evidence(
  command : Json,
  results : Array[Json],
) -> Array[Json] {
  let boundary = mooncode_runtime_verification_boundary(results)
  let proofs : Array[Json] = []
  for
    check in mooncode_json_array_items(
      mooncode_runtime_horizon_task_contract(command),
      "required_checks",
    ) {
    let mut event_id = ""
    for index, result in results {
      if index <= boundary ||
        !["shell", "moon_cmd"].contains(
          mooncode_json_string(result, "tool", default=""),
        ) {
        continue
      }
      let metadata = mooncode_json_object_field_or_empty(
        mooncode_tool_result_value(result),
        "metadata",
      )
      let tool = mooncode_json_string(result, "tool", default="")
      let process_command = mooncode_json_string(
        metadata,
        if tool == "shell" {
          "cmd"
        } else {
          "command"
        },
        default="",
      )
      let sandbox = mooncode_json_object_field_or_empty(
        metadata, "sandbox_evidence",
      )
      if process_command == mooncode_json_string(check, "command", default="") {
        event_id = ""
      }
      if tool == mooncode_json_string(check, "tool", default="") &&
        process_command == mooncode_json_string(check, "command", default="") &&
        mooncode_runtime_check_cwd(
          command,
          mooncode_json_string(metadata, "cwd", default=""),
        ) ==
        mooncode_runtime_check_cwd(
          command,
          mooncode_json_string(check, "cwd", default=""),
        ) &&
        mooncode_task_field(metadata, "exit_code") == Json(0) &&
        !mooncode_json_bool(metadata, "pipeline_exit_ambiguous", default=false) &&
        mooncode_json_string(metadata, "execution_sandbox_policy", default="") ==
        "grant-bound" &&
        mooncode_json_string(metadata, "run_id", default="") != "" &&
        mooncode_json_string(metadata, "approval_id", default="") != "" &&
        mooncode_json_string(sandbox, "command_digest", default="") != "" &&
        mooncode_json_bool(sandbox, "cleanup_verified", default=false) {
        event_id = mooncode_runtime_result_event_id(command, result)
      }
    }
    if event_id != "" {
      proofs.push({
        "id": mooncode_json_string(check, "id", default=""),
        "event_id": event_id,
      })
    }
  }
  proofs
}

///|
// Track files already touched by this task and explicitly declared check inputs.
// This is proportional provenance, not a snapshot of the whole workspace.
async fn mooncode_runtime_check_inputs(
  book_root : String,
  command : Json,
  results : Array[Json],
) -> Array[Json] {
  let paths : Array[String] = []
  for result in results {
    for path in mooncode_runtime_turn_result_mutation_paths(result) {
      if path != "" && !paths.contains(path) {
        paths.push(path)
      }
    }
  }
  for
    check in mooncode_json_array_items(
      mooncode_runtime_horizon_task_contract(command),
      "required_checks",
    ) {
    for path in mooncode_json_array_string_items(check, "input_paths") {
      if !paths.contains(path) {
        paths.push(path)
      }
    }
  }
  let versions : Array[Json] = []
  for path in paths {
    let resolved = mooncode_workspace_path(book_root, path)
    if !mooncode_json_bool(resolved, "ok", default=false) {
      raise InvalidJournal("verification input escapes the selected book")
    }
    let absolute = mooncode_json_string(resolved, "absolute_path", default="")
    let fingerprint = mooncode_runtime_input_fingerprint(absolute)
    versions.push({
      "path": path,
      "absolute_path": absolute,
      "fingerprint": fingerprint,
    })
  }
  versions
}

///|
async fn mooncode_runtime_input_fingerprint(path : String) -> String {
  let content = @fs.read_file(path) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return "missing"
    _ => return "unreadable"
  }
  "sha256:" +
  @crypto.bytes_to_hex_string(@crypto.sha256(content.binary().to_fixedarray()))
}

///|
fn mooncode_runtime_bind_check_inputs(
  execution : Json,
  inputs : Array[Json],
  command : Json,
) -> Json {
  if mooncode_runtime_turn_result_verification_kind(execution) == "" {
    return execution
  }
  let result = mooncode_tool_result_value(execution)
  let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    |> mooncode_json_object_with_field(
      "verification_inputs",
      Json::array(inputs),
    )
    |> mooncode_json_object_with_field(
      "task_revision",
      Json(
        mooncode_sha256_hex(
          mooncode_runtime_horizon_contract(command).stringify(),
        ),
      ),
    )
  let result = mooncode_json_object_with_field(result, "metadata", metadata)
  let event = mooncode_json_object_field_or_empty(execution, "event")
    |> mooncode_json_object_with_field("tool_result", result)
  mooncode_json_object_with_field(execution, "result", result)
  |> mooncode_json_object_with_field("event", event)
}

///|
async fn mooncode_runtime_finish_input_error(
  book_root : String,
  command : Json,
  results : Array[Json],
) -> String {
  let boundary = mooncode_runtime_verification_boundary(results)
  let required = mooncode_runtime_required_check_evidence(command, results)
  let seen : Map[String, Bool] = Map([])
  for index = results.length() - 1; index > boundary; index = index - 1 {
    let execution = results[index]
    let kind = mooncode_runtime_turn_result_verification_kind(execution)
    let event_id = mooncode_json_string(
      mooncode_json_object_field_or_empty(execution, "event"),
      "id",
      default="",
    )
    if kind == "" ||
      (
        seen.contains(kind) &&
        !required.any(r => {
          mooncode_json_string(r, "event_id", default="") == event_id
        })
      ) {
      continue
    }
    seen[kind] = true
    let metadata = mooncode_json_object_field_or_empty(
      mooncode_tool_result_value(execution),
      "metadata",
    )
    let revision = mooncode_json_string(metadata, "task_revision", default="")
    if revision != "" &&
      revision !=
      mooncode_sha256_hex(
        mooncode_runtime_horizon_contract(command).stringify(),
      ) {
      return "Verification belongs to an earlier task revision; rerun the necessary checks."
    }
    for input in mooncode_json_array_items(metadata, "verification_inputs") {
      let path = mooncode_json_string(input, "path", default="")
      let resolved = mooncode_workspace_path(book_root, path)
      if !mooncode_json_bool(resolved, "ok", default=false) {
        return "Verification input escapes the selected book."
      }
      if mooncode_json_string(input, "absolute_path", default="") !=
        mooncode_json_string(resolved, "absolute_path", default="") {
        return "Verification resource identity changed for `\{path}`; rerun the necessary check."
      }
      let before = mooncode_json_string(input, "fingerprint", default="")
      if before == "unreadable" ||
        before !=
        mooncode_runtime_input_fingerprint(
          mooncode_json_string(resolved, "absolute_path", default=""),
        ) {
        return "Verification is stale for `\{path}`; inspect the change and rerun the necessary check."
      }
    }
  }
  for
    output in mooncode_json_array_items(
      mooncode_runtime_horizon_task_contract(command),
      "outputs",
    ) {
    let path = mooncode_json_string(output, "path", default="")
    if path == "" {
      continue
    }
    let resolved = mooncode_workspace_path(book_root, path)
    if !mooncode_json_bool(resolved, "ok", default=false) ||
      !(@fsx.exists(mooncode_json_string(resolved, "absolute_path", default="")) catch {
        _ => false
      }) {
      return "Required output `\{path}` is missing."
    }
  }
  ""
}

///|
priv struct MoonCodeCompletionVerdict {
  accepted : Bool
  reason : String
}

///|
fn mooncode_runtime_turn_result_is_mutation(result : Json) -> Bool {
  let payload = mooncode_tool_result_value(result)
  let tool = mooncode_json_string(result, "tool", default="")
  let accepted = mooncode_json_bool(
    result,
    "accepted",
    default=tool == "shell" &&
      mooncode_json_string(result, "kind", default="") == "tool_result" &&
      mooncode_json_string(result, "status", default="") == "done" &&
      mooncode_json_bool(payload, "ok", default=false),
  )
  if !accepted {
    return false
  }
  let metadata = mooncode_json_object_field_or_empty(payload, "metadata")
  tool == "write" ||
  tool == "edit" ||
  tool == "apply_patch" ||
  tool == "revert_patch" ||
  (
    tool == "commit" &&
    mooncode_json_string(
      mooncode_json_object_field_or_empty(
        mooncode_json_object_field_or_empty(result, "result"),
        "metadata",
      ),
      "evidence_kind",
      default="",
    ) ==
    "runtime.commit_created"
  ) ||
  (
    tool == "shell" &&
    mooncode_json_string(metadata, "cmd", default="") != "" &&
    !@mooncode_tools.classify("shell", {
      "cmd": mooncode_json_string(metadata, "cmd", default=""),
    }).parallel_read
  )
}

///|
fn mooncode_runtime_turn_result_is_commit_boundary(result : Json) -> Bool {
  let payload = mooncode_tool_result_value(result)
  let metadata = mooncode_json_object_field_or_empty(payload, "metadata")
  let tool = mooncode_json_string(result, "tool", default="")
  (
    tool == "commit" &&
    mooncode_json_string(metadata, "evidence_kind", default="") ==
    "runtime.commit_created"
  ) ||
  (
    tool == "shell" &&
    mooncode_json_bool(metadata, "post_commit_boundary", default=false) &&
    mooncode_json_bool(metadata, "post_commit_capture_valid", default=false) &&
    mooncode_json_string(metadata, "commit_sha", default="") != ""
  )
}

///|
fn mooncode_runtime_turn_result_mutation_paths(result : Json) -> Array[String] {
  if !mooncode_runtime_turn_result_is_mutation(result) {
    return []
  }
  let metadata = mooncode_json_object_field_or_empty(
    mooncode_tool_result_value(result),
    "metadata",
  )
  let tool = mooncode_json_string(result, "tool", default="")
  if tool == "commit" ||
    (
      tool == "shell" &&
      mooncode_json_bool(metadata, "post_commit_boundary", default=false)
    ) {
    return mooncode_json_array_string_items(metadata, "changed_paths")
  }
  if tool == "shell" {
    return mooncode_json_array_string_items(
      mooncode_json_object_field_or_empty(metadata, "sandbox_evidence"),
      "changed_paths",
    )
  }
  let files = mooncode_json_array_items(metadata, "files")
  let candidates = if files.is_empty() { [metadata] } else { files }
  let paths : Array[String] = []
  for candidate in candidates {
    if !mooncode_json_bool(candidate, "changed", default=false) {
      continue
    }
    let path = mooncode_json_string(
      candidate,
      "file_path",
      default=mooncode_json_string(candidate, "path", default=""),
    )
    if path != "" {
      paths.push(path)
    }
  }
  paths
}

///|
fn mooncode_runtime_turn_result_verification_kind(result : Json) -> String {
  if !mooncode_json_bool(result, "accepted", default=false) {
    return ""
  }
  let tool = mooncode_json_string(result, "tool", default="")
  let metadata = mooncode_json_object_field_or_empty(
    mooncode_tool_result_value(result),
    "metadata",
  )
  if metadata is Object(fields) &&
    fields.get("exit_code") is Some(exit_code) &&
    exit_code != Json(0) {
    return ""
  }
  if tool == "moon_cmd" {
    let command = mooncode_json_string(
      mooncode_json_object_field_or_empty(result, "arguments"),
      "command",
      default="",
    )
    if command == "check" || command == "test" || command == "build" {
      return command
    }
    return ""
  }
  if tool == "shell" {
    let arguments = mooncode_json_object_field_or_empty(result, "arguments")
    let claimed = mooncode_json_string(
      arguments,
      "verification_kind",
      default="",
    )
    if @mooncode_tools.shell_verifies_kind(
        mooncode_json_string(arguments, "cmd", default=""),
        claimed,
      ) {
      return claimed
    }
    return ""
  }
  ""
}

///|
fn mooncode_runtime_turn_completion_verdict_json(
  verdict : MoonCodeCompletionVerdict,
) -> Json {
  {
    "kind": "mooncode-coding-completion-verdict",
    "accepted": verdict.accepted,
    "reason": verdict.reason,
  }
}

///|
fn mooncode_runtime_turn_recoverable_horizon_finish(
  command : Json,
  plan : Json,
  tool_calls : Array[Json],
  tool_results : Array[Json],
) -> Bool {
  if mooncode_json_string(plan, "planner_mode", default="") !=
    mooncode_planner_mode_model_tool_calls() ||
    !mooncode_runtime_turn_tool_calls_include_finish(tool_calls) {
    return false
  }
  !mooncode_runtime_turn_completion_verdict(command, tool_results).accepted
}

///|
fn mooncode_runtime_turn_horizon_finish_rejection_message(
  command : Json,
  tool_calls : Array[Json],
  tool_results : Array[Json],
) -> String {
  if !mooncode_runtime_turn_tool_calls_include_finish(tool_calls) {
    return ""
  }
  let verdict = mooncode_runtime_turn_completion_verdict(command, tool_results)
  if verdict.accepted {
    ""
  } else {
    "Completion was rejected by the durable task contract: \{verdict.reason}. Continue the same task from the retained evidence. Resolve the gap, then call finish again when the deliverable is ready."
  }
}

///|
/// The agent owns semantic delivery. Runtime completion checks explicit task
/// requirements, not prompt vocabulary or quotas of successful tool actions.
fn mooncode_runtime_turn_completion_verdict(
  command : Json,
  results : Array[Json],
) -> MoonCodeCompletionVerdict {
  guard results.last() is Some(finish) else {
    return { accepted: false, reason: "no MoonCode tool result was recorded", }
  }
  if mooncode_json_string(finish, "tool", default="") != "finish" ||
    !mooncode_json_bool(finish, "accepted", default=false) {
    return {
      accepted: false,
      reason: mooncode_json_string(
        mooncode_tool_result_value(finish),
        "message",
        default="the final MoonCode tool result is not an accepted finish",
      ),
    }
  }
  let action = mooncode_json_string(command, "command", default="prompt")
  if action != "prompt" &&
    action != "steer" &&
    results.any(result => !mooncode_json_bool(result, "accepted", default=false)) {
    return {
      accepted: false,
      reason: "the requested command did not execute successfully",
    }
  }
  let checks = mooncode_json_array_items(
    mooncode_runtime_horizon_task_contract(command),
    "required_checks",
  )
  if mooncode_runtime_required_check_evidence(command, results).length() !=
    checks.length() {
    return {
      accepted: false,
      reason: "required checks need successful current execution receipts",
    }
  }
  {
    accepted: true,
    reason: "the final finish satisfies the explicit task contract",
  }
}
