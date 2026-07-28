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
fn mooncode_runtime_horizon_task_contract(command : Json) -> Json {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let nested = mooncode_json_object_field_or_empty(payload, "task_contract")
  if mooncode_json_string(nested, "objective", default="") != "" ||
    mooncode_json_array_items(nested, "milestones").length() > 0 {
    nested
  } else {
    mooncode_json_object_field_or_empty(command, "task_contract")
  }
}

///|
fn mooncode_runtime_horizon_compact_request(command : Json) -> String {
  let request = mooncode_runtime_turn_prompt_text(command).trim().to_owned()
  let markers = [
    "\nFull authoritative plan follows:", "\nAuthoritative plan follows:", "\nComplete authoritative plan follows:",
    "\nFull execution log follows:",
  ]
  let mut end = request.length()
  for marker in markers {
    match request.find(marker) {
      Some(index) => if index < end { end = index }
      None => ()
    }
  }
  let compact = if end < request.length() {
    request[:end].to_owned() +
    "\n[Reference appendix omitted from repeated planner context.]"
  } else {
    request
  }
  if compact.length() > 12000 {
    compact[:12000].to_owned() +
    "\n[Request truncated to the executable task contract.]"
  } else {
    compact
  }
}

///|
fn mooncode_runtime_horizon_required_milestones(command : Json) -> Array[Json] {
  if !mooncode_runtime_turn_requires_verification(command) {
    return []
  }
  let explicit = mooncode_json_array_items(
    mooncode_runtime_horizon_task_contract(command),
    "milestones",
  )
  if explicit.length() > 0 {
    let milestones : Array[Json] = []
    for index, item in explicit {
      let id = mooncode_json_string(
        item,
        "id",
        default="milestone-\{index + 1}",
      )
      let title = mooncode_json_string(item, "title", default=id)
      let evidence_kind = mooncode_json_string(
        item,
        "evidence_kind",
        default=if mooncode_json_string(item, "path", default="") == "" {
          "mutation"
        } else {
          "path_changed"
        },
      )
      milestones.push({
        "id": id,
        "title": title,
        "evidence_kind": evidence_kind,
        "path": mooncode_json_string(item, "path", default=""),
        "context_paths": Json::array(
          mooncode_json_array_string_items(item, "context_paths").map(value => {
            value.to_json()
          }),
        ),
      })
    }
    return milestones
  }
  let request = mooncode_runtime_horizon_compact_request(command)
    .to_lower()
    .to_string()
  let final_kind = if mooncode_runtime_turn_requests_tests(request) {
    "test"
  } else {
    "check"
  }
  [
    {
      "id": "scope",
      "title": "Locate the owned implementation surface",
      "evidence_kind": "scope",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "implementation",
      "title": "Implement the requested behavior",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": if final_kind == "test" {
        "tests"
      } else {
        "verification"
      },
      "title": if final_kind == "test" {
        "Pass the requested typed tests"
      } else {
        "Pass typed verification"
      },
      "evidence_kind": final_kind,
      "path": "",
      "context_paths": [],
    },
  ]
}

///|
fn mooncode_runtime_horizon_contract(command : Json) -> Json {
  let supplied = mooncode_runtime_horizon_task_contract(command)
  let objective = mooncode_json_string(
    supplied,
    "objective",
    default=mooncode_runtime_horizon_compact_request(command),
  )
  {
    "kind": "mooncode-long-horizon-task.v1",
    "horizon_id": mooncode_runtime_horizon_id(command),
    "objective": objective,
    "constraints": Json::array(
      mooncode_json_array_string_items(supplied, "constraints").map(value => {
        value.to_json()
      }),
    ),
    "context_paths": Json::array(
      mooncode_json_array_string_items(supplied, "context_paths").map(value => {
        value.to_json()
      }),
    ),
    "milestones": Json::array(
      mooncode_runtime_horizon_required_milestones(command),
    ),
  }
}

///|
fn mooncode_runtime_horizon_contract_prompt(command : Json) -> String {
  if !mooncode_runtime_turn_requires_verification(command) {
    return ""
  }
  "Durable task contract: \{mooncode_runtime_horizon_contract(command).stringify()}\n"
}

///|
fn mooncode_runtime_horizon_latest_checkpoint(
  command : Json,
  results : Array[Json],
) -> Json {
  let expected = mooncode_runtime_horizon_id(command)
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let mut latest = mooncode_json_object_field_or_empty(
    payload, "horizon_checkpoint",
  )
  for result in results {
    if mooncode_json_bool(result, "accepted", default=false) &&
      mooncode_json_string(result, "tool", default="") == "checkpoint" {
      let metadata = mooncode_json_object_field_or_empty(
        mooncode_json_object_field_or_empty(result, "result"),
        "metadata",
      )
      if mooncode_json_string(metadata, "horizon_id", default="") == expected {
        latest = mooncode_json_object_field_or_empty(metadata, "checkpoint")
      }
    }
  }
  latest
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
  for event in events {
    if mooncode_json_string(event, "tool", default="") != "checkpoint" {
      continue
    }
    let tool_result = mooncode_json_object_field_or_empty(event, "tool_result")
    if !mooncode_json_bool(tool_result, "ok", default=false) {
      continue
    }
    let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
    if mooncode_json_string(metadata, "horizon_id", default="") == explicit {
      latest = mooncode_json_object_field_or_empty(metadata, "checkpoint")
    }
  }
  if mooncode_json_array_items(latest, "milestones").length() == 0 {
    command
  } else {
    let payload = mooncode_json_object_field_or_empty(command, "payload")
    mooncode_json_object_with_field(
      command,
      "payload",
      mooncode_json_object_with_field(payload, "horizon_checkpoint", latest),
    )
  }
}

///|
fn mooncode_runtime_horizon_last_failure(results : Array[Json]) -> Int {
  let mut failure = -1
  for index, result in results {
    if !mooncode_json_bool(result, "accepted", default=false) {
      failure = index
    }
  }
  failure
}

///|
fn mooncode_runtime_horizon_last_mutation(results : Array[Json]) -> Int {
  let mut mutation = -1
  for index, result in results {
    if mooncode_runtime_turn_result_is_mutation(result) {
      mutation = index
    }
  }
  mutation
}

///|
fn mooncode_runtime_horizon_has_scope_evidence(results : Array[Json]) -> Bool {
  results.any(result => {
    mooncode_json_bool(result, "accepted", default=false) &&
    (
      mooncode_json_string(result, "tool", default="") == "read" ||
      mooncode_json_string(result, "tool", default="") == "moon_ide"
    )
  })
}

///|
fn mooncode_runtime_horizon_path_changed(
  results : Array[Json],
  path : String,
) -> Bool {
  for result in results {
    for state in mooncode_runtime_turn_result_mutation_states(result) {
      if mooncode_json_string(state, "path", default="") == path &&
        mooncode_json_string(state, "before", default="") !=
        mooncode_json_string(state, "after", default="") {
        return true
      }
    }
  }
  false
}

///|
fn mooncode_runtime_horizon_has_verification(
  results : Array[Json],
  evidence_kind : String,
) -> Bool {
  let boundary = {
    let mutation = mooncode_runtime_horizon_last_mutation(results)
    let failure = mooncode_runtime_horizon_last_failure(results)
    if mutation > failure {
      mutation
    } else {
      failure
    }
  }
  for index, result in results {
    if index > boundary &&
      mooncode_runtime_turn_result_verification_kind(result) == evidence_kind {
      return true
    }
  }
  false
}

///|
fn mooncode_runtime_horizon_documentation_path(path : String) -> Bool {
  let normalized = path.to_lower().to_string()
  normalized.has_prefix("docs/") ||
  normalized.has_suffix(".md") ||
  normalized.has_suffix(".mdx") ||
  normalized.has_suffix(".rst")
}

///|
fn mooncode_runtime_horizon_has_substantive_mutation(
  command : Json,
  results : Array[Json],
) -> Bool {
  if !mooncode_runtime_turn_requires_verification(command) {
    return mooncode_runtime_turn_has_net_mutation(results)
  }
  for result in results {
    for state in mooncode_runtime_turn_result_mutation_states(result) {
      let path = mooncode_json_string(state, "path", default="")
      if mooncode_json_string(state, "before", default="") !=
        mooncode_json_string(state, "after", default="") &&
        !mooncode_runtime_horizon_documentation_path(path) {
        return true
      }
    }
  }
  false
}

///|
fn mooncode_runtime_horizon_result_is_substantive_mutation(
  command : Json,
  result : Json,
) -> Bool {
  if !mooncode_runtime_turn_requires_verification(command) {
    return mooncode_runtime_turn_result_is_mutation(result)
  }
  mooncode_runtime_turn_result_mutation_states(result).any(state => {
    let path = mooncode_json_string(state, "path", default="")
    mooncode_json_string(state, "before", default="") !=
    mooncode_json_string(state, "after", default="") &&
    !mooncode_runtime_horizon_documentation_path(path)
  })
}

///|
fn mooncode_runtime_horizon_checkpoint_milestone_status(
  checkpoint : Json,
  id : String,
) -> String {
  for milestone in mooncode_json_array_items(checkpoint, "milestones") {
    if mooncode_json_string(milestone, "id", default="") == id {
      return mooncode_json_string(milestone, "status", default="")
    }
  }
  ""
}

///|
fn mooncode_runtime_horizon_milestone_proven(
  command : Json,
  milestone : Json,
  results : Array[Json],
) -> Bool {
  let kind = mooncode_json_string(
    milestone,
    "evidence_kind",
    default="mutation",
  )
  match kind {
    "scope" => mooncode_runtime_horizon_has_scope_evidence(results)
    "mutation" =>
      mooncode_runtime_horizon_has_substantive_mutation(command, results)
    "path_changed" =>
      mooncode_runtime_horizon_path_changed(
        results,
        mooncode_json_string(milestone, "path", default=""),
      )
    "check" | "test" | "build" =>
      mooncode_runtime_horizon_has_verification(results, kind)
    _ => false
  }
}

///|
fn mooncode_runtime_horizon_checkpoint_error(
  command : Json,
  arguments : Json,
  results : Array[Json],
) -> String {
  let expected_id = mooncode_runtime_horizon_id(command)
  if mooncode_json_string(arguments, "horizon_id", default="") != expected_id {
    return "checkpoint horizon_id does not match the active task"
  }
  let supplied = mooncode_json_array_items(arguments, "milestones")
  if supplied.length() == 0 {
    return "checkpoint milestones must be non-empty"
  }
  let mut active_count = 0
  let mut pending_count = 0
  let seen : Map[String, Bool] = {}
  for milestone in supplied {
    let id = mooncode_json_string(milestone, "id", default="")
    let status = mooncode_json_string(milestone, "status", default="")
    if id == "" {
      return "checkpoint milestone id must be non-empty"
    }
    if seen.contains(id) {
      return "checkpoint milestone ids must be unique"
    }
    seen[id] = true
    if status == "active" {
      active_count += 1
    } else if status == "pending" {
      pending_count += 1
    } else if status != "done" {
      return "checkpoint milestone status must be pending, active, or done"
    }
  }
  if active_count > 1 || (pending_count > 0 && active_count != 1) {
    return "checkpoint must have exactly one active milestone while work remains"
  }
  let previous = mooncode_runtime_horizon_latest_checkpoint(command, results)
  let mut newly_done_mutations = 0
  let mut previously_done_mutations = 0
  for required in mooncode_runtime_horizon_required_milestones(command) {
    let required_id = mooncode_json_string(required, "id", default="")
    let mut matched = Json::object({})
    for milestone in supplied {
      if mooncode_json_string(milestone, "id", default="") == required_id {
        matched = milestone
        break
      }
    }
    if mooncode_json_string(matched, "id", default="") == "" {
      return "checkpoint is missing required milestone `\{required_id}`"
    }
    if mooncode_json_string(matched, "evidence_kind", default="") !=
      mooncode_json_string(required, "evidence_kind", default="") ||
      mooncode_json_string(matched, "path", default="") !=
      mooncode_json_string(required, "path", default="") {
      return "checkpoint changed the evidence contract for milestone `\{required_id}`"
    }
    let previous_status = mooncode_runtime_horizon_checkpoint_milestone_status(
      previous, required_id,
    )
    let matched_status = mooncode_json_string(matched, "status", default="")
    if previous_status == "done" &&
      mooncode_json_string(required, "evidence_kind", default="") == "mutation" {
      previously_done_mutations += 1
    }
    if previous_status == "done" && matched_status != "done" {
      return "checkpoint cannot reopen completed milestone `\{required_id}`"
    }
    if matched_status == "done" &&
      !mooncode_runtime_horizon_milestone_proven(command, required, results) {
      return "checkpoint milestone `\{required_id}` has no matching runtime evidence"
    }
    if matched_status == "done" &&
      previous_status != "done" &&
      mooncode_json_string(required, "evidence_kind", default="") == "mutation" {
      newly_done_mutations += 1
    }
  }
  let mut total_mutations = 0
  for result in results {
    if mooncode_runtime_horizon_result_is_substantive_mutation(command, result) {
      total_mutations += 1
    }
  }
  let available_mutations = total_mutations - previously_done_mutations
  if newly_done_mutations > available_mutations {
    return "checkpoint completes \{newly_done_mutations} new mutation milestone(s) with only \{available_mutations} unconsumed substantive mutation result(s) across the task"
  }
  ""
}

///|
fn mooncode_runtime_horizon_checkpoint_all_done(checkpoint : Json) -> Bool {
  let milestones = mooncode_json_array_items(checkpoint, "milestones")
  milestones.length() > 0 &&
  milestones.all(milestone => {
    mooncode_json_string(milestone, "status", default="") == "done"
  })
}

///|
fn mooncode_runtime_horizon_checkpoint_execution(
  command : Json,
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  prior_results : Array[Json],
  now~ : @clock.Timestamp,
) -> Json {
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let error = mooncode_runtime_horizon_checkpoint_error(
    command, arguments, prior_results,
  )
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
        "all_done": mooncode_runtime_horizon_checkpoint_all_done(checkpoint),
      },
    )
  } else {
    mooncode_tool_error_result("checkpoint", message=error, metadata={
      "horizon_id": mooncode_runtime_horizon_id(command),
      "checkpoint": checkpoint,
    })
  }
  {
    "accepted": error == "",
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": "checkpoint",
    "arguments": arguments,
    "result": result,
    "event": mooncode_tool_result_event(
      session_id,
      book_root,
      command_id,
      "checkpoint",
      result,
      now~,
    ),
  }
}

///|
fn mooncode_runtime_horizon_result_summary(result : Json) -> String {
  let tool = mooncode_json_string(result, "tool", default="unknown")
  let accepted = mooncode_json_bool(result, "accepted", default=false)
  let arguments = mooncode_json_object_field_or_empty(result, "arguments")
  let tool_result = mooncode_json_object_field_or_empty(result, "result")
  let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
  let path = mooncode_json_string(
    metadata,
    "path",
    default=mooncode_json_string(arguments, "path", default=""),
  )
  let command = mooncode_json_string(arguments, "command", default="")
  let message = mooncode_json_string(tool_result, "message", default="")
  "- \{tool}: \{if accepted { "accepted" } else { "failed" }}" +
  (if path == "" { "" } else { " path=\{path}" }) +
  (if command == "" { "" } else { " command=\{command}" }) +
  (if message == "" { "" } else { " — \{message}" })
}

///|
fn mooncode_runtime_horizon_progress_message(
  command : Json,
  results : Array[Json],
  remaining_steps : Int,
) -> Json {
  let checkpoint = mooncode_runtime_horizon_latest_checkpoint(command, results)
  let summaries : Array[String] = []
  let start = if results.length() > 4 { results.length() - 4 } else { 0 }
  for index in start..<results.length() {
    summaries.push(mooncode_runtime_horizon_result_summary(results[index]))
  }
  let recovery = if mooncode_runtime_horizon_last_failure(results) >= 0 {
    "\nRecovery rule: use the latest diagnostics, repair the active milestone before unrelated discovery, then rerun the same typed verification."
  } else {
    ""
  }
  let horizon = if remaining_steps < 0 {
    "Planner horizon: milestone-driven with no command-wide step ceiling. Continue until every required milestone has accepted evidence, then write the all-done checkpoint and finish. Do not rediscover completed milestones."
  } else {
    "Planner opportunities remaining: \{remaining_steps}. Reserve the final three for implementation/repair, typed verification, then an all-done checkpoint plus finish. Do not rediscover completed milestones."
  }
  {
    "role": "user",
    "content": "Latest accepted checkpoint:\n\{checkpoint.stringify(indent=2)}\n" +
    "Recent runtime evidence:\n\{if summaries.length() == 0 { "- none" } else { summaries.join("\n") }}\n" +
    horizon +
    recovery,
  }
}

///|
fn mooncode_runtime_horizon_completion_ready(
  command : Json,
  results : Array[Json],
) -> Bool {
  let checkpoint = mooncode_runtime_horizon_latest_checkpoint(command, results)
  if !mooncode_runtime_horizon_checkpoint_all_done(checkpoint) {
    return false
  }
  let mut checkpoint_index = -1
  let mut evidence_index = -1
  for index, result in results {
    if mooncode_runtime_turn_result_is_mutation(result) ||
      mooncode_runtime_turn_result_verification_kind(result) != "" {
      evidence_index = index
    }
    if mooncode_json_bool(result, "accepted", default=false) &&
      mooncode_json_string(result, "tool", default="") == "checkpoint" {
      checkpoint_index = index
    }
  }
  checkpoint_index >= evidence_index && checkpoint_index >= 0
}
