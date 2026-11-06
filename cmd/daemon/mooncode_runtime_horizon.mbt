///|
fn mooncode_runtime_horizon_explicit_id(command : Json) -> String {
  let direct = mooncode_json_string(command, "horizon_id", default="")
  if direct != "" {
    return direct
  }
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let payload_id = mooncode_json_string(payload, "horizon_id", default="")
  if payload_id != "" {
    return payload_id
  }
  let contract = mooncode_json_object_field_or_empty(payload, "task_contract")
  mooncode_json_string(contract, "horizon_id", default="")
}

///|
fn mooncode_runtime_horizon_id(command : Json) -> String {
  let explicit = mooncode_runtime_horizon_explicit_id(command)
  if explicit != "" {
    explicit
  } else {
    mooncode_command_id(command)
  }
}

///|
fn mooncode_runtime_commit_event_horizon_id(event : Json) -> String {
  let direct = mooncode_runtime_horizon_explicit_id(event)
  if direct != "" {
    return direct
  }
  let commit_result = mooncode_json_object_field_or_empty(
    event, "commit_result",
  )
  let result_id = mooncode_runtime_horizon_explicit_id(commit_result)
  if result_id != "" {
    return result_id
  }
  let event_packet = mooncode_json_object_field_or_empty(
    event, "command_packet",
  )
  let packet_id = mooncode_runtime_horizon_explicit_id(event_packet)
  if packet_id != "" {
    return packet_id
  }
  mooncode_runtime_horizon_explicit_id(
    mooncode_json_object_field_or_empty(commit_result, "command_packet"),
  )
}

///|
fn mooncode_runtime_horizon_task_contract(command : Json) -> Json {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  match payload {
    Object(fields) if fields.get("task_contract") is Some(Object(_) as contract) =>
      contract
    _ => mooncode_json_object_field_or_empty(command, "task_contract")
  }
}

///|
fn mooncode_runtime_horizon_contract(command : Json) -> Json {
  let supplied = mooncode_runtime_horizon_task_contract(command)
  {
    "kind": "mooncode-task",
    "id": mooncode_runtime_horizon_id(command),
    "revision": mooncode_json_string(
      command,
      "task_revision",
      default=mooncode_json_string(
        supplied,
        "revision",
        default=mooncode_command_id(command),
      ),
    ),
    "objective": mooncode_json_string(
      supplied,
      "objective",
      default=mooncode_runtime_turn_prompt_text(command),
    ),
    "constraints": Json::array(
      mooncode_json_array_items(supplied, "constraints"),
    ),
    "outputs": Json::array(mooncode_json_array_items(supplied, "outputs")),
    "required_checks": Json::array(
      mooncode_json_array_items(supplied, "required_checks"),
    ),
    "updates": Json::array(mooncode_json_array_items(command, "task_updates")),
    "context_paths": Json::array(
      mooncode_json_array_items(supplied, "context_paths"),
    ),
  }
}

///|
fn mooncode_runtime_horizon_attach_checkpoint(
  command : Json,
  events : Array[Json],
) -> Json {
  let explicit = mooncode_runtime_horizon_explicit_id(command)
  if explicit == "" {
    return command
  }
  let mut latest = Json::object({})
  let retained_evidence : Array[Json] = []
  let seen_commits : Map[String, Bool] = Map([])
  let mut horizon_started = false
  for event in events {
    if mooncode_json_string(event, "tool", default="") == "checkpoint" {
      let tool_result = mooncode_json_object_field_or_empty(
        event, "tool_result",
      )
      if mooncode_json_bool(tool_result, "ok", default=false) {
        let metadata = mooncode_json_object_field_or_empty(
          tool_result, "metadata",
        )
        if mooncode_json_string(metadata, "horizon_id", default="") == explicit {
          latest = mooncode_json_object_field_or_empty(metadata, "checkpoint")
          horizon_started = true
        } else {
          horizon_started = false
        }
      }
      continue
    }
    if horizon_started &&
      mooncode_json_string(event, "kind", default="") ==
      "runtime.commit_created" &&
      mooncode_json_string(event, "status", default="") == "done" {
      if mooncode_runtime_commit_event_horizon_id(event) != explicit {
        continue
      }
      let commit_sha = mooncode_json_string(event, "commit_sha", default="")
      if commit_sha == "" || seen_commits.contains(commit_sha) {
        continue
      }
      let direct_paths = mooncode_json_array_string_items(
        event, "changed_paths",
      )
      let commit_result = mooncode_json_object_field_or_empty(
        event, "commit_result",
      )
      let result_paths = mooncode_json_array_string_items(
        commit_result, "changed_paths",
      )
      let status_before = mooncode_json_string(
        event,
        "status_before",
        default=mooncode_json_string(commit_result, "status_before", default=""),
      )
      let changed_paths = if !direct_paths.is_empty() {
        direct_paths
      } else if !result_paths.is_empty() {
        result_paths
      } else {
        mooncode_runtime_commit_status_paths(status_before)
      }
      if changed_paths.is_empty() {
        continue
      }
      seen_commits[commit_sha] = true
      retained_evidence.push({
        "tool": "commit",
        "accepted": true,
        "result": {
          "metadata": {
            "evidence_kind": "runtime.commit_created",
            "commit_sha": commit_sha,
            "changed_paths": Json::array(changed_paths.map(path => Json(path))),
          },
        },
      })
    }
  }
  if mooncode_json_array_items(latest, "milestones").is_empty() &&
    retained_evidence.is_empty() {
    return command
  }
  let mut payload = mooncode_json_object_field_or_empty(command, "payload")
  if mooncode_json_array_items(latest, "milestones").length() > 0 {
    payload = mooncode_json_object_with_field(
      payload, "horizon_checkpoint", latest,
    )
  }
  if !retained_evidence.is_empty() {
    payload = mooncode_json_object_with_field(
      payload,
      "horizon_evidence",
      Json::array(retained_evidence),
    )
  }
  mooncode_json_object_with_field(command, "payload", payload)
}

///|
fn mooncode_runtime_horizon_retained_evidence(command : Json) -> Array[Json] {
  mooncode_json_array_items(
    mooncode_json_object_field_or_empty(command, "payload"),
    "horizon_evidence",
  )
}

///|
fn mooncode_runtime_horizon_checkpoint_error(
  command : Json,
  arguments : Json,
) -> String {
  if mooncode_json_string(arguments, "horizon_id", default="") !=
    mooncode_runtime_horizon_id(command) {
    return "checkpoint horizon_id does not match the active task"
  }
  let seen : Map[String, Bool] = Map([])
  for milestone in mooncode_json_array_items(arguments, "milestones") {
    let id = mooncode_json_string(milestone, "id", default="")
    if id == "" || seen.contains(id) {
      return "checkpoint milestone ids must be nonempty and unique"
    }
    seen[id] = true
    if !["pending", "active", "done"].contains(
        mooncode_json_string(milestone, "status", default=""),
      ) {
      return "invalid milestone status"
    }
  }
  ""
}

///|
fn mooncode_runtime_horizon_checkpoint_execution(
  command : Json,
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let error = mooncode_runtime_horizon_checkpoint_error(command, arguments)
  let checkpoint : Json = {
    "horizon_id": mooncode_runtime_horizon_id(command),
    "milestones": Json::array(
      mooncode_json_array_items(arguments, "milestones"),
    ),
    "next_action": mooncode_json_string(arguments, "next_action", default=""),
  }
  let result = if error == "" {
    mooncode_tool_ok_result(
      "checkpoint",
      message="long-horizon task checkpoint recorded",
      output=checkpoint.stringify(),
      metadata={
        "horizon_id": mooncode_runtime_horizon_id(command),
        "checkpoint": checkpoint,
      },
    )
  } else {
    mooncode_tool_error_result("checkpoint", message=error, metadata={
      "horizon_id": mooncode_runtime_horizon_id(command),
      "checkpoint": checkpoint,
    })
  }
  mooncode_tool_execution(
    session_id,
    book_root,
    command_id,
    "checkpoint",
    arguments,
    result,
    now~,
  )
}

///|
fn mooncode_runtime_turn_task_intent(command : Json) -> String? {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  match mooncode_json_string(payload, "task_intent", default="") {
    "workspace_change" => Some("workspace_change")
    "read_only" => Some("read_only")
    _ => None
  }
}
