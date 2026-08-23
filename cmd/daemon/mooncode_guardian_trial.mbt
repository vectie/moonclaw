///|
const MOONCODE_GUARDIAN_TRIAL_CONTRACT : String = "moonclaw.guardian-trial.v1"

///|
fn mooncode_guardian_trial_enabled(command : Json) -> Bool {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_bool(payload, "planner_guardian_high_risk_trial", default=false)
}

///|
fn mooncode_guardian_trial_action_kind(tool_call : Json) -> String {
  match mooncode_json_string(tool_call, "tool", default="") {
    "shell" => "shell"
    "browser" => "browser"
    "moon_cmd" | "moon_check" => "moon"
    "write" | "edit" | "apply_patch" => "workspace_mutation"
    _ => "other_mutation"
  }
}

///|
fn mooncode_guardian_trial_risk_signals(tool_call : Json) -> Array[String] {
  let signals : Array[String] = []
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  if mooncode_runtime_tool_effect(tool_call) is ExclusiveMutation {
    signals.push("exclusive_mutation")
  }
  if tool == "shell" {
    signals.push("arbitrary_shell")
    let command = mooncode_json_string(arguments, "cmd", default="")
      .to_lower()
      .to_string()
    if mooncode_shell_has_git_commit(command) {
      signals.push("durable_history")
    }
    if mooncode_shell_has_git_worktree_overwrite(command) {
      signals.push("worktree_overwrite")
    }
    if mooncode_shell_has_clean_dependency_install(command) {
      signals.push("dependency_replacement")
    }
    if mooncode_shell_has_sensitive_command(command) {
      signals.push("sensitive_command")
    }
  } else if tool == "browser" {
    let action = mooncode_json_string(arguments, "action", default="")
    let url = mooncode_json_string(arguments, "url", default="")
    if action == "open" && !mooncode_browser_loopback_url(url) {
      signals.push("external_navigation")
    }
  } else if tool == "moon_cmd" {
    if mooncode_moon_cmd_is_test_update(arguments) {
      signals.push("accepted_output_update")
    }
    if arguments.stringify().to_lower().contains("publish") {
      signals.push("external_publish")
    }
  }
  if mooncode_json_bool(tool_call, "requires_approval", default=false) ||
    mooncode_json_bool(arguments, "requires_approval", default=false) ||
    mooncode_json_string(
      tool_call,
      "approval",
      default=mooncode_json_string(arguments, "approval", default=""),
    ) ==
    "operator" {
    signals.push("explicit_operator_boundary")
  }
  signals
}

///|
fn mooncode_guardian_trial_observation(tool_call : Json) -> Json? {
  if !mooncode_runtime_tool_requires_approval(tool_call) {
    return None
  }
  let signals = mooncode_guardian_trial_risk_signals(tool_call)
  Some({
    "contract": MOONCODE_GUARDIAN_TRIAL_CONTRACT,
    "mode": "shadow",
    "reviewer": "local_policy_qualifier",
    "eligible": true,
    "behavior_changed": false,
    "action_kind": mooncode_guardian_trial_action_kind(tool_call),
    "runtime_policy": "operator_review",
    "risk_level": "high",
    "user_authorization": "unknown",
    "outcome": "review_required",
    "risk_signals": Json::array(signals.map(Json::string)),
    "risk_signal_count": signals.length(),
    "external_inference_performed": false,
  })
}

///|
fn mooncode_guardian_trial_event(
  command : Json,
  tool_call : Json,
  now : @clock.Timestamp,
) -> Json? {
  if !mooncode_guardian_trial_enabled(command) {
    return None
  }
  guard mooncode_guardian_trial_observation(tool_call) is Some(observation) else {
    return None
  }
  let event = mooncode_event(
    session_id=mooncode_json_string(command, "session_id", default=""),
    command_id=mooncode_command_id(command),
    lane="runtime",
    kind="runtime.guardian_trial",
    title="High-risk Guardian shadow qualification",
    status="done",
    detail="A local high-risk shadow qualification completed. Operator approval behavior was unchanged.",
    now~,
  )
  Some(mooncode_json_object_with_field(event, "guardian_trial", observation))
}
