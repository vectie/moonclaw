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
    mooncode_runtime_turn_result_payload(result) ||
    mooncode_json_bool(
      mooncode_runtime_turn_result_payload(result),
      "is_error",
      default=true,
    ) ||
    !mooncode_json_bool(
      mooncode_runtime_turn_result_payload(result),
      "ok",
      default=false,
    ) {
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
/// Select exact successful process receipts only after the final known native
/// mutation/failure. Consumer validation additionally attributes sandbox source
/// changes against its independently captured source inventory.
fn mooncode_runtime_required_check_evidence(
  command : Json,
  results : Array[Json],
) -> Array[Json] {
  let boundary = mooncode_runtime_horizon_last_mutation(results).max(
    mooncode_runtime_horizon_last_failure(results),
  )
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
        mooncode_runtime_turn_result_payload(result),
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
    for state in mooncode_runtime_turn_result_mutation_states(result) {
      let path = mooncode_json_string(state, "path", default="")
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
    let resolved = mooncode_resolve_book_path(book_root, path)
    if !mooncode_json_bool(resolved, "ok", default=false) {
      raise InvalidJournal("verification input escapes the selected book")
    }
    let absolute = mooncode_json_string(resolved, "absolute_path", default="")
    let fingerprint = mooncode_runtime_input_fingerprint(absolute)
    versions.push({ "path": path, "fingerprint": fingerprint })
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
  let result = mooncode_runtime_turn_result_payload(execution)
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
  let boundary = mooncode_runtime_horizon_last_mutation(results).max(
    mooncode_runtime_horizon_last_failure(results),
  )
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
      mooncode_runtime_turn_result_payload(execution),
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
      let resolved = mooncode_resolve_book_path(book_root, path)
      if !mooncode_json_bool(resolved, "ok", default=false) {
        return "Verification input escapes the selected book."
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
    let resolved = mooncode_resolve_book_path(book_root, path)
    if !mooncode_json_bool(resolved, "ok", default=false) ||
      !(@fsx.exists(mooncode_json_string(resolved, "absolute_path", default="")) catch {
        _ => false
      }) {
      return "Required output `\{path}` is missing."
    }
  }
  ""
}
