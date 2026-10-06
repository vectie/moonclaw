///|
/// This opt-in verdict covers native journal evidence. Source inventory,
/// index/HEAD equality and original-task acceptance remain consumer-owned.
fn mooncode_nochange_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn mooncode_nochange_policy(command : Json) -> Json {
  mooncode_nochange_field(
    mooncode_runtime_horizon_task_contract(command),
    "completion_policy",
  )
}

///|
fn mooncode_nochange_policy_error(command : Json) -> String {
  let policy = mooncode_nochange_policy(command)
  if policy == Json::null() {
    return ""
  }
  if mooncode_runtime_turn_task_intent(command) != Some("workspace_change") {
    return "completion_policy requires workspace_change task intent"
  }
  if mooncode_json_string(policy, "contract", default="") !=
    "mooncode.completion-outcome.v1" ||
    mooncode_json_string(policy, "no_change_reason", default="") !=
    "already_satisfied" ||
    mooncode_json_string(policy, "evidence_scope", default="") !=
    "native_tool_journal" ||
    mooncode_json_string(policy, "acceptance_scope", default="") !=
    "engineering_only" {
    return "completion_policy has an unsupported version, reason, or evidence/acceptance scope"
  }
  let outcomes = mooncode_json_array_items(policy, "allowed_outcomes")
  if outcomes.length() != 2 ||
    !outcomes.contains("mutation".to_json()) ||
    !outcomes.contains("no_change".to_json()) {
    return "completion_policy.allowed_outcomes must explicitly permit mutation and no_change"
  }
  let alternatives = mooncode_json_array_items(
    policy, "alternative_milestone_ids",
  )
  let seen : Map[String, Bool] = Map([])
  let milestones = mooncode_runtime_horizon_required_milestones(command)
  for alternative in alternatives {
    guard alternative is String(id) && id != "" && !seen.contains(id) else {
      return "completion_policy alternative milestone ids must be nonempty and unique"
    }
    seen[id] = true
    if !milestones.any(item => {
        mooncode_json_string(item, "id", default="") == id &&
        ["mutation", "path_changed"].contains(
          mooncode_json_string(item, "evidence_kind", default=""),
        )
      }) {
      return "completion_policy alternative must name an original mutation/path_changed milestone"
    }
  }
  let checks = mooncode_json_array_items(policy, "required_checks")
  if checks.is_empty() {
    return "completion_policy requires at least one exact check"
  }
  seen.clear()
  for check in checks {
    let id = mooncode_json_string(check, "id", default="")
    if id.trim().is_empty() ||
      seen.contains(id) ||
      !["shell", "moon_cmd"].contains(
        mooncode_json_string(check, "tool", default=""),
      ) ||
      mooncode_json_string(check, "command", default="").trim().is_empty() ||
      mooncode_json_string(check, "cwd", default="").trim().is_empty() ||
      mooncode_nochange_field(check, "exit_code") != (0).to_json() {
      return "completion_policy checks require unique ids and exact tool/command/cwd/zero exit"
    }
    seen[id] = true
  }
  ""
}

///|
fn mooncode_nochange_enabled(command : Json) -> Bool {
  mooncode_nochange_policy(command) != Json::null() &&
  mooncode_nochange_policy_error(command) == ""
}

///|
fn mooncode_nochange_copy_proposal(value : Json, proposal : Json) -> Json {
  let mut value = value
  for key in ["completion_outcome", "no_change"] {
    if proposal is Object(fields) && fields.contains(key) {
      value = mooncode_json_object_with_field(value, key, fields[key])
    }
  }
  value
}

///|
fn mooncode_nochange_result_event_id(command : Json, result : Json) -> String {
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
    mooncode_nochange_field(event, "tool_result") !=
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
fn mooncode_nochange_cwd(command : Json, value : String) -> String {
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
fn mooncode_nochange_check_evidence(
  command : Json,
  results : Array[Json],
) -> Array[Json] {
  let boundary = mooncode_runtime_horizon_last_mutation(results).max(
    mooncode_runtime_horizon_last_failure(results),
  )
  let proofs : Array[Json] = []
  for
    check in mooncode_json_array_items(
      mooncode_nochange_policy(command),
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
        mooncode_nochange_cwd(
          command,
          mooncode_json_string(metadata, "cwd", default=""),
        ) ==
        mooncode_nochange_cwd(
          command,
          mooncode_json_string(check, "cwd", default=""),
        ) &&
        mooncode_nochange_field(metadata, "exit_code") == (0).to_json() &&
        !mooncode_json_bool(metadata, "pipeline_exit_ambiguous", default=false) &&
        mooncode_json_string(metadata, "execution_sandbox_policy", default="") ==
        "grant-bound" &&
        mooncode_json_string(metadata, "run_id", default="") != "" &&
        mooncode_json_string(metadata, "approval_id", default="") != "" &&
        mooncode_json_string(sandbox, "command_digest", default="") != "" &&
        mooncode_json_bool(sandbox, "cleanup_verified", default=false) {
        event_id = mooncode_nochange_result_event_id(command, result)
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
fn mooncode_nochange_proposal_error(
  command : Json,
  proposal : Json,
  results : Array[Json],
) -> String {
  if proposal is Object(fields) &&
    fields.contains("completion_outcome") &&
    !(fields["completion_outcome"] is String(_)) {
    return "completion outcome must be a supported string"
  }
  let outcome = mooncode_json_string(proposal, "completion_outcome", default="")
  if outcome != "no_change" {
    if outcome != "" && outcome != "mutation" {
      return "unknown completion outcome"
    }
    if mooncode_nochange_field(proposal, "no_change") != Json::null() {
      return "no_change evidence requires the explicit no_change outcome"
    }
    return ""
  }
  if !mooncode_nochange_enabled(command) {
    return "no_change requires a valid immutable completion_policy"
  }
  let observation = mooncode_json_object_field_or_empty(proposal, "no_change")
  if mooncode_json_string(observation, "reason", default="") !=
    "already_satisfied" ||
    mooncode_json_string(observation, "observation", default="")
    .trim()
    .is_empty() {
    return "no_change requires already_satisfied and a nonempty worker observation"
  }
  if mooncode_runtime_turn_has_net_mutation(results) {
    return "no_change conflicts with retained net native mutation evidence"
  }
  let refs = mooncode_json_array_items(observation, "evidence_refs")
  if refs.is_empty() {
    return "no_change requires accepted native evidence references"
  }
  let seen : Map[String, Bool] = Map([])
  for reference in refs {
    guard reference is String(id) && id != "" && !seen.contains(id) else {
      return "no_change evidence references must be nonempty and unique"
    }
    seen[id] = true
    if results
      .filter(result => mooncode_nochange_result_event_id(command, result) == id)
      .length() !=
      1 {
      return "no_change evidence reference does not identify one accepted native result"
    }
  }
  let checks = mooncode_nochange_check_evidence(command, results)
  if checks.length() !=
    mooncode_json_array_items(
      mooncode_nochange_policy(command),
      "required_checks",
    ).length() {
    return "no_change has missing, failed, mismatched, or stale required checks"
  }
  for check in checks {
    if !seen.contains(mooncode_json_string(check, "event_id", default="")) {
      return "no_change evidence references omit a required check"
    }
  }
  ""
}

///|
fn mooncode_nochange_alternative(
  command : Json,
  proposal : Json,
  milestone : Json,
) -> Bool {
  mooncode_json_string(proposal, "completion_outcome", default="") ==
  "no_change" &&
  mooncode_json_string(milestone, "resolution", default="") ==
  "already_satisfied" &&
  mooncode_json_array_string_items(
    mooncode_nochange_policy(command),
    "alternative_milestone_ids",
  ).contains(mooncode_json_string(milestone, "id", default=""))
}

///|
fn mooncode_nochange_finish_verdict(
  command : Json,
  results : Array[Json],
) -> MoonCodeCompletionVerdict {
  let finish = results[results.length() - 1]
  let proposal = mooncode_json_object_field_or_empty(finish, "arguments")
  let metadata = mooncode_json_object_field_or_empty(
    mooncode_runtime_turn_result_payload(finish),
    "metadata",
  )
  if mooncode_json_string(metadata, "completion_outcome", default="") !=
    "no_change" ||
    mooncode_nochange_field(metadata, "no_change") !=
    mooncode_nochange_field(proposal, "no_change") {
    return {
      accepted: false,
      reason: "no_change finish metadata does not match its structured proposal",
    }
  }
  let error = mooncode_nochange_proposal_error(command, proposal, results)
  if error != "" {
    return { accepted: false, reason: error, }
  }
  let checkpoint = mooncode_runtime_horizon_latest_checkpoint(command, results)
  if mooncode_json_string(checkpoint, "completion_outcome", default="") !=
    "no_change" ||
    mooncode_nochange_field(checkpoint, "no_change") !=
    mooncode_nochange_field(proposal, "no_change") {
    return {
      accepted: false,
      reason: "no_change finish must match the final accepted checkpoint proposal",
    }
  }
  if !mooncode_runtime_horizon_completion_ready(command, results) {
    return {
      accepted: false,
      reason: "no_change requires a fresh accepted all-done checkpoint",
    }
  }
  let checkpoint_error = mooncode_runtime_horizon_checkpoint_error(
    command, checkpoint, results,
  )
  if checkpoint_error != "" {
    return { accepted: false, reason: checkpoint_error, }
  }
  let requires_tests = mooncode_runtime_turn_requests_tests(
    mooncode_runtime_turn_prompt_text(command).to_lower().to_string(),
  )
  let boundary = mooncode_runtime_horizon_last_mutation(results).max(
    mooncode_runtime_horizon_last_failure(results),
  )
  let original_verification = results
    .mapi((index, result) => {
      let kind = mooncode_runtime_turn_result_verification_kind(result)
      index > boundary &&
      (if requires_tests { kind == "test" } else { kind != "" })
    })
    .any(value => value)
  if !original_verification {
    return {
      accepted: false,
      reason: "no_change still requires the original typed verification after mutation/failure",
    }
  }
  {
    accepted: true,
    reason: "no_change has matching native journal evidence and all required checks; original-task acceptance is unevaluated",
  }
}

///|
fn mooncode_nochange_verdict_projection(
  verdict : MoonCodeCompletionVerdict,
  command : Json,
  results : Array[Json],
) -> Json {
  let basic = mooncode_runtime_turn_completion_verdict_json(verdict)
  if results.is_empty() {
    return basic
  }
  let proposal = mooncode_json_object_field_or_empty(
    results[results.length() - 1],
    "arguments",
  )
  if mooncode_json_string(proposal, "completion_outcome", default="") !=
    "no_change" {
    return basic
  }
  let mut value = mooncode_nochange_copy_proposal(basic, proposal)
  value = mooncode_json_object_with_field(
    value, "completion_contract", "mooncode.completion-outcome.v1",
  )
  value = mooncode_json_object_with_field(
    value, "acceptance_scope", "engineering_only",
  )
  value = mooncode_json_object_with_field(
    value, "original_task_acceptance", "unevaluated",
  )
  mooncode_json_object_with_field(
    value,
    "required_check_evidence",
    Json::array(mooncode_nochange_check_evidence(command, results)),
  )
}

///|
fn mooncode_nochange_proposal_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "reason": { "type": "string", "enum": ["already_satisfied"] },
      "observation": { "type": "string" },
      "evidence_refs": { "type": "array", "items": { "type": "string" } },
    },
    "required": ["reason", "observation", "evidence_refs"],
    "additionalProperties": false,
  }
}

///|
fn mooncode_nochange_parameter_schema(
  parameters : Json,
  enabled~ : Bool,
) -> Json {
  if !enabled {
    return parameters
  }
  let mut properties = mooncode_json_object_field_or_empty(
    parameters, "properties",
  )
  properties = mooncode_json_object_with_field(
    properties,
    "completion_outcome",
    { "type": "string", "enum": ["mutation", "no_change"] },
  )
  properties = mooncode_json_object_with_field(
    properties,
    "no_change",
    mooncode_nochange_proposal_schema(),
  )
  if mooncode_nochange_field(properties, "milestones") != Json::null() {
    let milestones = mooncode_json_object_field_or_empty(
      properties, "milestones",
    )
    let item = mooncode_json_object_field_or_empty(milestones, "items")
    let item_properties = mooncode_json_object_with_field(
      mooncode_json_object_field_or_empty(item, "properties"),
      "resolution",
      { "type": "string", "enum": ["already_satisfied"] },
    )
    properties = mooncode_json_object_with_field(
      properties,
      "milestones",
      mooncode_json_object_with_field(
        milestones,
        "items",
        mooncode_json_object_with_field(item, "properties", item_properties),
      ),
    )
  }
  mooncode_json_object_with_field(parameters, "properties", properties)
}
