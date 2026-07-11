///|
// Runtime evidence and proof-gate vocabulary shared by MoonDesk and MoonClaw.

///|
pub fn runtime_evidence_contract_id() -> String {
  "mooncode-runtime-evidence.v1"
}

///|
pub fn command_runtime_evidence_kind() -> String {
  "mooncode-command-runtime-evidence"
}

///|
pub fn session_runtime_evidence_kind() -> String {
  "mooncode-session-runtime-evidence"
}

///|
pub fn tool_harness_evidence_kind() -> String {
  "mooncode-tool-harness-evidence"
}

///|
pub fn runtime_completion_proof_gate_kind() -> String {
  "mooncode-runtime-completion-proof-gate"
}

///|
pub fn runtime_evidence_status_proven() -> String {
  "proven"
}

///|
pub fn runtime_evidence_status_failed() -> String {
  "failed"
}

///|
pub fn runtime_evidence_status_missing() -> String {
  "missing-evidence"
}

///|
pub fn runtime_evidence_status_no_required_events() -> String {
  "no-required-events"
}

///|
pub fn runtime_evidence_status_no_commands() -> String {
  "no-commands"
}

///|
pub fn runtime_required_event_status_proven() -> String {
  "proven"
}

///|
pub fn runtime_required_event_status_failed() -> String {
  "failed"
}

///|
pub fn runtime_required_event_status_missing() -> String {
  "missing"
}

///|
pub fn tool_harness_status_no_tools() -> String {
  "no-tools"
}

///|
pub fn runtime_completion_gate_status_blocked() -> String {
  "blocked"
}

///|
pub fn runtime_completion_gate_status_passed() -> String {
  "passed"
}

///|
pub fn runtime_completion_gate_status_not_required() -> String {
  "not-required"
}

///|
pub fn action_plan_state_blocked() -> String {
  "blocked"
}

///|
pub fn action_plan_state_queued_for_runtime() -> String {
  "queued-for-runtime"
}

///|
pub fn action_plan_state_runtime_retry() -> String {
  "runtime-retry"
}

///|
pub fn action_plan_state_running() -> String {
  "running"
}

///|
pub fn action_plan_state_awaiting_proof() -> String {
  "awaiting-proof"
}

///|
pub fn action_plan_state_ready_for_review() -> String {
  "ready-for-review"
}

///|
pub fn action_plan_state_completed() -> String {
  "completed"
}

///|
pub fn action_plan_status_blocked() -> String {
  "blocked"
}

///|
pub fn action_plan_status_running() -> String {
  "running"
}

///|
pub fn action_plan_status_queued() -> String {
  "queued"
}

///|
pub fn action_plan_status_review_ready() -> String {
  "review-ready"
}

///|
pub fn action_plan_status_complete() -> String {
  "complete"
}

///|
pub fn action_plan_status_waiting_for_proof() -> String {
  "waiting-for-proof"
}

///|
pub fn action_plan_status_empty() -> String {
  "empty"
}

///|
pub fn action_plan_next_run_or_replay_runtime_commands() -> String {
  "run_or_replay_runtime_commands"
}

///|
pub fn action_plan_next_retry_failed_runtime_receipt() -> String {
  "retry_failed_runtime_receipt"
}

///|
pub fn action_plan_next_await_runtime_proof() -> String {
  "await_runtime_proof"
}

///|
pub fn action_plan_next_await_commit_proof() -> String {
  "await_commit_proof"
}

///|
pub fn action_plan_next_start_or_resume_session() -> String {
  "start_or_resume_session"
}

///|
pub fn action_plan_next_ready_for_book_review() -> String {
  "ready_for_book_review"
}

///|
pub fn runtime_evidence_command_rule() -> String {
  "Required runtime events are proven only by command-scoped MoonCode events. Unscoped events may still render in the transcript, but they do not satisfy this command-level proof."
}

///|
pub fn tool_harness_evidence_rule() -> String {
  "MoonClaw must run each expected tool through the typed tool boundary and emit command-scoped tool_call/tool_result proof. MoonDesk records and renders the verdict; it does not execute tools."
}

///|
pub fn runtime_completion_proof_gate_rule() -> String {
  "Proof-sensitive actions may not be marked runtime-completed until command-scoped required runtime events and typed tool-harness proof are present either in the prior append log or in this acknowledgement payload."
}

///|
pub fn session_runtime_evidence_rule() -> String {
  "This projection is the session-level proof contract. MoonDesk records and displays it, while MoonClaw must satisfy it with command-scoped runtime events."
}

///|
pub fn runtime_evidence_required_events(
  action : String,
  summary_required_events : Array[String],
) -> Array[String] {
  if summary_required_events.length() == 0 {
    native_command_expected_events(action)
  } else {
    summary_required_events
  }
}

///|
pub fn runtime_evidence_required_outputs(
  action : String,
  summary_required_outputs : Array[String],
) -> Array[String] {
  if summary_required_outputs.length() == 0 {
    native_command_required_outputs(action)
  } else {
    summary_required_outputs
  }
}

///|
pub fn runtime_evidence_status_for_required_events(
  required_event_count : Int,
  missing_count : Int,
  failed_count : Int,
) -> String {
  if required_event_count == 0 {
    runtime_evidence_status_no_required_events()
  } else if failed_count > 0 {
    runtime_evidence_status_failed()
  } else if missing_count > 0 {
    runtime_evidence_status_missing()
  } else {
    runtime_evidence_status_proven()
  }
}

///|
pub fn runtime_evidence_is_proven(
  required_event_count : Int,
  missing_count : Int,
  failed_count : Int,
) -> Bool {
  required_event_count > 0 && missing_count == 0 && failed_count == 0
}

///|
pub fn tool_harness_status_for_counts(
  expected_tool_count : Int,
  failed_tool_count : Int,
  missing_tool_count : Int,
) -> String {
  if expected_tool_count == 0 {
    tool_harness_status_no_tools()
  } else if failed_tool_count > 0 {
    runtime_evidence_status_failed()
  } else if missing_tool_count > 0 {
    runtime_evidence_status_missing()
  } else {
    runtime_evidence_status_proven()
  }
}

///|
pub fn tool_harness_is_proven(
  expected_tool_count : Int,
  failed_tool_count : Int,
  missing_tool_count : Int,
) -> Bool {
  expected_tool_count > 0 && failed_tool_count == 0 && missing_tool_count == 0
}

///|
pub fn tool_harness_expected_tools(
  action : String,
  summary_tool_sequence : Array[String],
) -> Array[String] {
  if summary_tool_sequence.length() > 0 {
    runtime_evidence_dedup_strings(summary_tool_sequence)
  } else {
    runtime_evidence_dedup_strings(native_command_tool_sequence(action))
  }
}

///|
pub fn tool_harness_case_status(
  failed_seen : Bool,
  call_seen : Bool,
  result_seen : Bool,
) -> String {
  if failed_seen {
    runtime_evidence_status_failed()
  } else if call_seen && result_seen {
    runtime_evidence_status_proven()
  } else {
    runtime_required_event_status_missing()
  }
}

///|
pub fn session_runtime_evidence_status_for_counts(
  command_count : Int,
  failed_count : Int,
  failed_required_event_count : Int,
  missing_count : Int,
  missing_runtime_command_count : Int,
  missing_required_event_count : Int,
) -> String {
  if command_count == 0 {
    runtime_evidence_status_no_commands()
  } else if failed_count > 0 || failed_required_event_count > 0 {
    runtime_evidence_status_failed()
  } else if missing_count > 0 ||
    missing_runtime_command_count > 0 ||
    missing_required_event_count > 0 {
    runtime_evidence_status_missing()
  } else {
    runtime_evidence_status_proven()
  }
}

///|
pub fn runtime_evidence_required_event_result(
  required : String,
  status : String,
  event : Json,
) -> Json {
  {
    "required_event": required,
    "status": status,
    "event_id": runtime_evidence_json_string(event, "id", default=""),
    "event_kind": runtime_evidence_json_string(event, "kind", default=""),
    "event_status": runtime_evidence_json_string(event, "status", default=""),
    "event_title": runtime_evidence_json_string(event, "title", default=""),
    "event_path": runtime_evidence_json_string(event, "path", default=""),
    "event_detail": runtime_evidence_json_string(event, "detail", default=""),
    "tool_call_id": runtime_evidence_json_string(
      event,
      "tool_call_id",
      default="",
    ),
  }
}

///|
pub fn runtime_evidence_event_satisfies(
  required : String,
  event : Json,
) -> Bool {
  let kind = runtime_evidence_json_string(event, "kind", default="")
  match required {
    "tool_call" =>
      runtime_evidence_json_string(event, "tool_call_id", default="") != "" &&
      runtime_evidence_json_string(event, "status", default="") == "running"
    "tool_result" =>
      runtime_evidence_json_string(event, "tool_call_id", default="") != "" &&
      kind != "tool_call_decode_error" &&
      runtime_evidence_json_string(event, "status", default="") != "running"
    "runtime_finished" => kind == "finish"
    "review.receipt" => kind.has_prefix("receipt.")
    "package_verified" => kind == "runtime.package_verified"
    "package_built" => kind == "runtime.package_built"
    "commit_created" => kind == "runtime.commit_created"
    "patch_applied" => kind == "runtime.patch_applied"
    "patch_reverted" => kind == "runtime.patch_reverted"
    "native eval report" => kind == native_command_eval_report_manifest_event()
    _ => kind == required
  }
}

///|
pub fn runtime_evidence_event_fails_required(
  required : String,
  event : Json,
) -> Bool {
  if runtime_evidence_json_string(event, "status", default="") !=
    runtime_evidence_status_failed() {
    return false
  }
  let kind = runtime_evidence_json_string(event, "kind", default="")
  let source_event = runtime_evidence_json_string(
    event,
    "source_event",
    default="",
  )
  match required {
    "tool_call" =>
      kind == "tool_call_decode_error" &&
      source_event != "tool_result" &&
      runtime_evidence_json_string(event, "tool_call_id", default="") != ""
    "tool_result" =>
      kind == "tool_call_decode_error" &&
      source_event == "tool_result" &&
      runtime_evidence_json_string(event, "tool_call_id", default="") != ""
    _ => runtime_evidence_event_satisfies(required, event)
  }
}

///|
pub fn runtime_evidence_events_with_status(
  event_results : Array[Json],
  status : String,
) -> Array[String] {
  let result : Array[String] = []
  for item in event_results {
    if runtime_evidence_json_string(item, "status", default="") == status {
      result.push(
        runtime_evidence_json_string(item, "required_event", default=""),
      )
    }
  }
  result
}

///|
pub fn runtime_completion_requires_proof(action : String) -> Bool {
  command_action_requires_runtime_completion_proof(action)
}

///|
pub fn runtime_completion_tool_harness_blocked(
  proof_required : Bool,
  expected_tool_count : Int,
  tool_harness_status : String,
) -> Bool {
  proof_required &&
  expected_tool_count > 0 &&
  tool_harness_status != runtime_evidence_status_proven() &&
  tool_harness_status != tool_harness_status_no_tools()
}

///|
pub fn runtime_completion_blocked(
  proof_required : Bool,
  evidence_status : String,
  tool_harness_blocked : Bool,
) -> Bool {
  proof_required &&
  (evidence_status != runtime_evidence_status_proven() || tool_harness_blocked)
}

///|
pub fn runtime_completion_proof_gate_status(
  proof_required : Bool,
  completion_blocked : Bool,
) -> String {
  if completion_blocked {
    runtime_completion_gate_status_blocked()
  } else if proof_required {
    runtime_completion_gate_status_passed()
  } else {
    runtime_completion_gate_status_not_required()
  }
}

///|
pub fn runtime_replay_ack_effective_status(
  requested_status : String,
  completion_blocked : Bool,
) -> String {
  if requested_status == runtime_receipt_status_completed() &&
    completion_blocked {
    runtime_receipt_status_proof_missing()
  } else {
    requested_status
  }
}

///|
pub fn runtime_completion_proof_gate(
  action : String,
  evidence : Json,
  prior_event_count : Int,
  submitted_event_count : Int,
  missing_required_events : Array[Json],
  failed_required_events : Array[Json],
) -> Json {
  let proof_required = runtime_completion_requires_proof(action)
  let evidence_status = runtime_evidence_json_string(
    evidence,
    "status",
    default=runtime_evidence_status_missing(),
  )
  let tool_harness_status = runtime_evidence_json_string(
    evidence,
    "tool_harness_status",
    default=runtime_evidence_status_missing(),
  )
  let expected_tool_count = runtime_evidence_json_int(
    evidence,
    "tool_harness_expected_tool_count",
    default=0,
  )
  let tool_harness_blocked = runtime_completion_tool_harness_blocked(
    proof_required, expected_tool_count, tool_harness_status,
  )
  let completion_blocked = runtime_completion_blocked(
    proof_required, evidence_status, tool_harness_blocked,
  )
  {
    "kind": runtime_completion_proof_gate_kind(),
    "protocol": protocol_version(),
    "action": action,
    "proof_required_for_completion": proof_required,
    "completion_blocked": completion_blocked,
    "status": runtime_completion_proof_gate_status(
      proof_required, completion_blocked,
    ),
    "evidence_status": evidence_status,
    "tool_harness_status": tool_harness_status,
    "tool_harness_completion_blocked": tool_harness_blocked,
    "tool_harness_expected_tool_count": expected_tool_count,
    "tool_harness_proven_tool_count": runtime_evidence_json_int(
      evidence,
      "tool_harness_proven_tool_count",
      default=0,
    ),
    "tool_harness_missing_tool_count": runtime_evidence_json_int(
      evidence,
      "tool_harness_missing_tool_count",
      default=0,
    ),
    "tool_harness_failed_tool_count": runtime_evidence_json_int(
      evidence,
      "tool_harness_failed_tool_count",
      default=0,
    ),
    "prior_event_count": prior_event_count,
    "submitted_event_count": submitted_event_count,
    "required_event_count": runtime_evidence_json_int(
      evidence,
      "required_event_count",
      default=0,
    ),
    "proven_required_event_count": runtime_evidence_json_int(
      evidence,
      "proven_required_event_count",
      default=0,
    ),
    "missing_required_event_count": runtime_evidence_json_int(
      evidence,
      "missing_required_event_count",
      default=0,
    ),
    "failed_required_event_count": runtime_evidence_json_int(
      evidence,
      "failed_required_event_count",
      default=0,
    ),
    "missing_required_events": Json::array(missing_required_events),
    "failed_required_events": Json::array(failed_required_events),
    "rule": runtime_completion_proof_gate_rule(),
  }
}

///|
pub fn action_plan_status_for_counts(
  pending_runtime_count : Int,
  running_count : Int,
  blocked_count : Int,
  ready_for_review_count : Int,
  completed_count : Int,
  action_count : Int,
) -> String {
  if blocked_count > 0 {
    action_plan_status_blocked()
  } else if running_count > 0 {
    action_plan_status_running()
  } else if pending_runtime_count > 0 {
    action_plan_status_queued()
  } else if ready_for_review_count > 0 {
    action_plan_status_review_ready()
  } else if action_count > 0 && completed_count == action_count {
    action_plan_status_complete()
  } else if action_count > 0 {
    action_plan_status_waiting_for_proof()
  } else {
    action_plan_status_empty()
  }
}

///|
pub fn action_plan_runtime_state_precondition_state(
  runtime_state : String,
) -> String {
  if runtime_state == runtime_receipt_status_failed() ||
    runtime_state == "expired-claim" {
    action_plan_state_runtime_retry()
  } else if runtime_state == runtime_claim_status_claimed() {
    action_plan_state_running()
  } else if runtime_state == runtime_replay_status_pending() ||
    runtime_state == "not-recorded" {
    action_plan_state_queued_for_runtime()
  } else {
    ""
  }
}

///|
pub fn action_plan_state_with_tool_harness(
  action : String,
  runtime_state : String,
  state : String,
  expected_tool_count : Int,
  tool_harness_status : String,
) -> String {
  if runtime_state != runtime_claim_status_delivered() ||
    !command_action_requires_tool_harness(action) ||
    state == action_plan_state_blocked() ||
    state == action_plan_state_queued_for_runtime() ||
    state == action_plan_state_running() ||
    state == action_plan_state_runtime_retry() ||
    expected_tool_count == 0 {
    return state
  }
  if tool_harness_status == runtime_evidence_status_proven() ||
    tool_harness_status == tool_harness_status_no_tools() {
    state
  } else if tool_harness_status == runtime_evidence_status_failed() {
    action_plan_state_runtime_retry()
  } else {
    action_plan_state_awaiting_proof()
  }
}

///|
pub fn runtime_evidence_contract_json() -> Json {
  {
    "kind": "mooncode-runtime-evidence-contract",
    "protocol": protocol_version(),
    "contract_id": runtime_evidence_contract_id(),
    "command_runtime_evidence_kind": command_runtime_evidence_kind(),
    "session_runtime_evidence_kind": session_runtime_evidence_kind(),
    "tool_harness_evidence_kind": tool_harness_evidence_kind(),
    "runtime_completion_proof_gate_kind": runtime_completion_proof_gate_kind(),
    "evidence_statuses": [
      runtime_evidence_status_proven(),
      runtime_evidence_status_failed(),
      runtime_evidence_status_missing(),
      runtime_evidence_status_no_required_events(),
      runtime_evidence_status_no_commands(),
    ],
    "required_event_statuses": [
      runtime_required_event_status_proven(),
      runtime_required_event_status_failed(),
      runtime_required_event_status_missing(),
    ],
    "tool_harness_statuses": [
      runtime_evidence_status_proven(),
      runtime_evidence_status_failed(),
      runtime_evidence_status_missing(),
      tool_harness_status_no_tools(),
    ],
    "completion_gate_statuses": [
      runtime_completion_gate_status_blocked(),
      runtime_completion_gate_status_passed(),
      runtime_completion_gate_status_not_required(),
    ],
    "action_plan_proof_states": [
      action_plan_state_queued_for_runtime(),
      action_plan_state_runtime_retry(),
      action_plan_state_running(),
      action_plan_state_awaiting_proof(),
      action_plan_state_ready_for_review(),
      action_plan_state_completed(),
      action_plan_state_blocked(),
    ],
    "required_event_mappings": [
      runtime_evidence_required_event_mapping(
        "tool_call", "tool_call_id + running status",
      ),
      runtime_evidence_required_event_mapping(
        "tool_result", "tool_call_id + non-running status",
      ),
      runtime_evidence_required_event_mapping("runtime_finished", "finish"),
      runtime_evidence_required_event_mapping("review.receipt", "receipt.*"),
      runtime_evidence_required_event_mapping(
        "package_verified", "runtime.package_verified",
      ),
      runtime_evidence_required_event_mapping(
        "commit_created", "runtime.commit_created",
      ),
      runtime_evidence_required_event_mapping(
        "patch_applied", "runtime.patch_applied",
      ),
      runtime_evidence_required_event_mapping(
        "patch_reverted", "runtime.patch_reverted",
      ),
      runtime_evidence_required_event_mapping(
        "native eval report",
        native_command_eval_report_manifest_event(),
      ),
    ],
    "rules": [
      runtime_evidence_command_rule(),
      tool_harness_evidence_rule(),
      runtime_completion_proof_gate_rule(),
      session_runtime_evidence_rule(),
      "internal MoonCode may scan concrete event logs, but reusable proof status, required-event, and completion-gate policy must come from mooncode/core",
    ],
  }
}

///|
fn runtime_evidence_required_event_mapping(
  required : String,
  satisfies : String,
) -> Json {
  { "required_event": required, "satisfies": satisfies }
}

///|
fn runtime_evidence_dedup_strings(items : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for item in items {
    if item != "" && !result.contains(item) {
      result.push(item)
    }
  }
  result
}

///|
fn runtime_evidence_json_string(
  json : Json,
  key : String,
  default~ : String,
) -> String {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(String(value)) => value
        _ => default
      }
    _ => default
  }
}

///|
fn runtime_evidence_json_int(json : Json, key : String, default~ : Int) -> Int {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(Number(value, ..)) => value.to_int()
        _ => default
      }
    _ => default
  }
}
