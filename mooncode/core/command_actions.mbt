///|
pub fn command_action_contract_id() -> String {
  "mooncode-command-actions.v1"
}

///|
pub fn command_prompt() -> String {
  "prompt"
}

///|
pub fn command_steer() -> String {
  "steer"
}

///|
pub fn command_run_tests() -> String {
  "run_tests"
}

///|
pub fn command_run_build() -> String {
  "run_build"
}

///|
pub fn command_run_eval() -> String {
  "run_eval"
}

///|
pub fn command_package() -> String {
  "package"
}

///|
pub fn command_commit() -> String {
  "commit"
}

///|
pub fn command_accept() -> String {
  "accept"
}

///|
pub fn command_reject() -> String {
  "reject"
}

///|
pub fn command_approve_tool() -> String {
  "approve_tool"
}

///|
pub fn command_reject_tool() -> String {
  "reject_tool"
}

///|
pub fn command_apply_patch() -> String {
  "apply_patch"
}

///|
pub fn command_revert_patch() -> String {
  "revert_patch"
}

///|
pub fn command_cancel() -> String {
  "cancel"
}

///|
pub fn command_note() -> String {
  "note"
}

///|
pub fn command_turn_actions() -> Array[String] {
  [command_prompt(), command_steer(), command_cancel()]
}

///|
pub fn command_advertised_actions() -> Array[String] {
  [
    command_prompt(),
    command_steer(),
    command_run_tests(),
    command_run_build(),
    command_run_eval(),
    command_package(),
    command_commit(),
    command_accept(),
    command_reject(),
    command_approve_tool(),
    command_reject_tool(),
    command_apply_patch(),
    command_revert_patch(),
    command_cancel(),
  ]
}

///|
pub fn command_supported_actions() -> Array[String] {
  let actions = command_advertised_actions()
  actions.push(command_note())
  actions
}

///|
pub fn command_action_is_advertised(action : String) -> Bool {
  command_advertised_actions().contains(action)
}

///|
pub fn command_action_is_supported(action : String) -> Bool {
  command_supported_actions().contains(action)
}

///|
pub fn command_action_is_turn(action : String) -> Bool {
  command_turn_actions().contains(action)
}

///|
pub fn command_action_is_prompt_or_steer(action : String) -> Bool {
  action == command_prompt() || action == command_steer()
}

///|
pub fn command_action_is_cancel(action : String) -> Bool {
  action == command_cancel()
}

///|
pub fn command_action_is_test(action : String) -> Bool {
  action == command_run_tests() || action == command_run_build()
}

///|
pub fn command_action_is_eval(action : String) -> Bool {
  action == command_run_eval()
}

///|
pub fn command_action_is_package(action : String) -> Bool {
  action == command_package()
}

///|
pub fn command_action_is_commit(action : String) -> Bool {
  action == command_commit()
}

///|
pub fn command_action_is_review_decision(action : String) -> Bool {
  action == command_accept() || action == command_reject()
}

///|
pub fn command_action_is_tool_approval(action : String) -> Bool {
  action == command_approve_tool() || action == command_reject_tool()
}

///|
pub fn command_action_is_patch(action : String) -> Bool {
  action == command_apply_patch() || action == command_revert_patch()
}

///|
pub fn command_action_requires_tool_harness(action : String) -> Bool {
  command_action_is_prompt_or_steer(action) ||
  action == command_run_tests() ||
  command_action_is_eval(action) ||
  command_action_is_package(action) ||
  command_action_is_commit(action) ||
  action == command_accept() ||
  command_action_is_patch(action)
}

///|
pub fn command_action_requires_runtime_completion_proof(
  action : String,
) -> Bool {
  action == command_run_tests() ||
  command_action_is_eval(action) ||
  command_action_is_package(action) ||
  command_action_is_commit(action) ||
  command_action_is_review_decision(action) ||
  command_action_is_patch(action) ||
  command_action_is_tool_approval(action)
}

///|
pub fn command_action_writes_review_receipt(action : String) -> Bool {
  command_action_is_review_decision(action) ||
  command_action_is_package(action) ||
  command_action_is_commit(action) ||
  command_action_is_tool_approval(action) ||
  command_action_is_patch(action)
}

///|
pub fn command_action_control(action : String) -> String {
  if action == command_prompt() {
    command_prompt()
  } else if action == command_steer() {
    command_steer()
  } else if action == command_cancel() {
    command_cancel()
  } else {
    "command"
  }
}

///|
pub fn command_action_approval(action : String) -> String {
  if command_action_is_review_decision(action) ||
    command_action_is_package(action) ||
    command_action_is_commit(action) ||
    command_action_is_tool_approval(action) ||
    command_action_is_patch(action) ||
    command_action_is_cancel(action) {
    "operator"
  } else if command_action_is_test(action) || command_action_is_eval(action) {
    "auto"
  } else if command_action_is_prompt_or_steer(action) {
    "user"
  } else {
    "none"
  }
}

///|
pub fn command_action_tool_hints(action : String) -> Array[String] {
  if command_action_is_test(action) {
    ["moon_ide", "moon_cmd", "moon_check", "shell"]
  } else if command_action_is_eval(action) {
    ["eval_harness", "moon_ide", "moon_cmd", "shell", "moon_check"]
  } else if command_action_is_package(action) {
    ["package_app_tool", "moon_ide", "moon_cmd", "moon_check", "shell"]
  } else if command_action_is_commit(action) {
    ["read", "moon_ide", "moon_cmd", "moon_check", "shell", "finish"]
  } else if action == command_accept() {
    ["finish", "package_app_tool"]
  } else if action == command_reject() {
    ["finish"]
  } else if command_action_is_tool_approval(action) {
    ["read", "edit", "write", "shell", "moon_ide", "moon_cmd", "moon_check"]
  } else if action == command_apply_patch() {
    ["moon_ide", "apply_patch", "moon_cmd", "moon_check"]
  } else if action == command_revert_patch() {
    ["moon_ide", "revert_patch", "moon_cmd", "moon_check"]
  } else if command_action_is_prompt_or_steer(action) {
    [
      "moon_ide", "read", "edit", "write", "shell", "moon_cmd", "moon_check", "finish",
    ]
  } else {
    []
  }
}

///|
pub fn command_action_expected_lanes(action : String) -> Array[String] {
  if command_action_is_test(action) {
    [event_lane_test(), event_lane_tool(), event_lane_runtime()]
  } else if command_action_is_eval(action) {
    [event_lane_runtime(), event_lane_test(), event_lane_review()]
  } else if command_action_is_package(action) {
    [event_lane_artifact(), event_lane_test(), event_lane_review()]
  } else if command_action_is_commit(action) {
    [event_lane_review(), event_lane_runtime(), event_lane_tool()]
  } else if command_action_is_review_decision(action) {
    [event_lane_review(), event_lane_artifact()]
  } else if command_action_is_tool_approval(action) {
    [event_lane_tool(), event_lane_runtime(), event_lane_review()]
  } else if command_action_is_patch(action) {
    [event_lane_diff(), event_lane_test(), event_lane_review()]
  } else if command_action_is_prompt_or_steer(action) {
    event_lanes()
  } else if command_action_is_cancel(action) {
    [event_lane_runtime()]
  } else {
    [event_lane_runtime()]
  }
}

///|
pub fn command_action_lane(action : String) -> String {
  if command_action_is_test(action) || command_action_is_eval(action) {
    event_lane_test()
  } else if command_action_is_package(action) {
    event_lane_artifact()
  } else if command_action_is_commit(action) ||
    command_action_is_review_decision(action) ||
    command_action_is_tool_approval(action) ||
    command_action_is_patch(action) {
    event_lane_review()
  } else {
    event_lane_runtime()
  }
}

///|
pub fn command_action_title(action : String, status : String) -> String {
  let label = if action == command_run_tests() {
    "Run tests"
  } else if action == command_run_build() {
    "Run build"
  } else if action == command_run_eval() {
    "Run eval"
  } else if action == command_package() {
    "Package result"
  } else if action == command_commit() {
    "Commit result"
  } else if action == command_accept() {
    "Accept result"
  } else if action == command_reject() {
    "Reject result"
  } else if action == command_approve_tool() {
    "Approve tool"
  } else if action == command_reject_tool() {
    "Reject tool"
  } else if action == command_apply_patch() {
    "Apply patch"
  } else if action == command_revert_patch() {
    "Revert patch"
  } else if action == command_cancel() {
    "Cancel session"
  } else if action == command_prompt() {
    "Prompt"
  } else if action == command_steer() {
    "Steer"
  } else {
    "Note"
  }
  "\{label}: \{status}"
}

///|
pub fn command_action_contract_json() -> Json {
  {
    "kind": "mooncode-command-action-contract",
    "protocol": protocol_version(),
    "contract_id": command_action_contract_id(),
    "event_lane_contract_id": event_lane_contract_id(),
    "runtime_event_name_contract_id": runtime_event_name_contract_id(),
    "turn_actions": command_turn_actions(),
    "advertised_actions": command_advertised_actions(),
    "supported_actions": command_supported_actions(),
    "actions": command_advertised_actions().map(action => {
      command_action_json(action)
    }),
    "rules": [
      "mooncode/core owns the supported MoonCode command action vocabulary", "internal MoonCode may execute action-specific behavior but must not publish a second command list",
      "prompt, steer, and cancel are ordered turn-control commands", "operator/review actions must remain command-scoped before they can write review receipts",
      "native runtime progress must reference this command contract plus the event lane and runtime event-name contracts",
    ],
  }
}

///|
fn command_action_json(action : String) -> Json {
  {
    "action": action,
    "control": command_action_control(action),
    "approval": command_action_approval(action),
    "lane": command_action_lane(action),
    "expected_lanes": command_action_expected_lanes(action),
    "tool_hints": command_action_tool_hints(action),
    "requires_tool_harness": command_action_requires_tool_harness(action),
    "requires_runtime_completion_proof": command_action_requires_runtime_completion_proof(
      action,
    ),
    "writes_review_receipt": command_action_writes_review_receipt(action),
  }
}
