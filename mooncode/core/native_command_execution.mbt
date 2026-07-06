///|
// Native command execution, tool, and result contracts shared by Moondesk and MoonClaw.

///|
pub fn native_command_contract_id() -> String {
  "mooncode-native-command-execution.v1"
}

///|
pub fn native_command_execution_plan_kind() -> String {
  "mooncode-native-command-execution-plan"
}

///|
pub fn native_command_tool_contract_kind() -> String {
  "mooncode-native-tool-contract"
}

///|
pub fn native_command_result_contract_kind() -> String {
  "mooncode-native-result-contract"
}

///|
pub fn native_command_eval_report_manifest_event() -> String {
  "eval_report.manifest"
}

///|
pub fn native_command_package_manifest_event() -> String {
  "package.manifest"
}

///|
pub fn native_command_package_index_event() -> String {
  "package.index"
}

///|
pub fn native_command_review_receipt_event() -> String {
  "review.receipt"
}

///|
pub fn native_command_tool_authorization_event() -> String {
  "tool_authorization"
}

///|
pub fn native_command_runtime_event_sink() -> String {
  "POST /api/mooncode/sessions/<session-id>/runtime-events"
}

///|
pub fn native_command_eval_report_sink() -> String {
  "POST /api/mooncode/sessions/<session-id>/eval-report"
}

///|
pub fn native_command_runtime_replay_sink() -> String {
  "POST /api/mooncode/sessions/<session-id>/runtime-replay"
}

///|
pub fn native_command_runtime_claim_sink() -> String {
  "POST /api/mooncode/sessions/<session-id>/runtime-claim"
}

///|
pub fn native_command_tool_sequence(action : String) -> Array[String] {
  if command_action_is_test(action) ||
    command_action_is_eval(action) ||
    action == command_commit() {
    [
      runtime_tool_read(),
      runtime_tool_moon_ide(),
      runtime_tool_moon_cmd(),
      runtime_tool_moon_check(),
      runtime_tool_shell(),
      runtime_tool_finish(),
    ]
  } else if action == command_package() {
    [
      runtime_tool_read(),
      runtime_tool_moon_ide(),
      runtime_tool_moon_cmd(),
      runtime_tool_moon_check(),
      runtime_tool_shell(),
      runtime_tool_package_app_tool(),
      runtime_tool_finish(),
    ]
  } else if action == command_accept() {
    [
      runtime_tool_read(),
      runtime_tool_package_app_tool(),
      runtime_tool_finish(),
    ]
  } else if action == command_reject() {
    [runtime_tool_read(), runtime_tool_finish()]
  } else if action == command_apply_patch() {
    [
      runtime_tool_read(),
      runtime_tool_moon_ide(),
      runtime_tool_apply_patch(),
      runtime_tool_moon_cmd(),
      runtime_tool_moon_check(),
      runtime_tool_finish(),
    ]
  } else if action == command_revert_patch() {
    [
      runtime_tool_read(),
      runtime_tool_moon_ide(),
      runtime_tool_revert_patch(),
      runtime_tool_moon_cmd(),
      runtime_tool_moon_check(),
      runtime_tool_finish(),
    ]
  } else if command_action_is_tool_approval(action) {
    [runtime_tool_finish()]
  } else if command_action_is_prompt_or_steer(action) {
    [
      runtime_tool_moon_ide(),
      runtime_tool_read(),
      runtime_tool_edit(),
      runtime_tool_write(),
      runtime_tool_moon_cmd(),
      runtime_tool_moon_check(),
      runtime_tool_finish(),
    ]
  } else {
    [runtime_tool_finish()]
  }
}

///|
pub fn native_command_allowed_tool_sequence(
  action : String,
  web_search : Bool,
) -> Array[String] {
  let tools : Array[String] = []
  for tool in native_command_tool_sequence(action) {
    tools.push(tool)
  }
  if web_search {
    if !tools.contains(runtime_tool_web_search()) {
      tools.push(runtime_tool_web_search())
    }
    if !tools.contains(runtime_tool_web_fetch()) {
      tools.push(runtime_tool_web_fetch())
    }
  }
  tools
}

///|
pub fn native_command_expected_events(action : String) -> Array[String] {
  if command_action_is_test(action) {
    [
      runtime_event_tool_call(),
      runtime_event_tool_result(),
      runtime_event_test_result(),
      runtime_event_runtime_finished(),
    ]
  } else if action == command_run_eval() {
    [
      runtime_event_tool_call(),
      runtime_event_tool_result(),
      runtime_event_test_result(),
      native_command_eval_report_manifest_event(),
      runtime_event_runtime_finished(),
    ]
  } else if action == command_package() {
    [
      runtime_event_tool_call(),
      runtime_event_tool_result(),
      runtime_event_artifact(),
      native_command_package_manifest_event(),
      native_command_package_index_event(),
      runtime_event_package_verified(),
      runtime_event_runtime_finished(),
    ]
  } else if action == command_commit() {
    [
      runtime_event_tool_call(),
      runtime_event_tool_result(),
      runtime_event_commit_created(),
      runtime_event_runtime_finished(),
    ]
  } else if action == command_apply_patch() {
    [
      runtime_event_tool_call(),
      runtime_event_diff(),
      runtime_event_patch_applied(),
      runtime_event_test_result(),
      runtime_event_runtime_finished(),
    ]
  } else if action == command_revert_patch() {
    [
      runtime_event_tool_call(),
      runtime_event_diff(),
      runtime_event_patch_reverted(),
      runtime_event_test_result(),
      runtime_event_runtime_finished(),
    ]
  } else if command_action_is_review_decision(action) {
    [
      native_command_review_receipt_event(),
      runtime_event_artifact(),
      runtime_event_runtime_finished(),
    ]
  } else if command_action_is_tool_approval(action) {
    [
      native_command_tool_authorization_event(),
      native_command_review_receipt_event(),
      runtime_event_runtime_finished(),
    ]
  } else if command_action_is_prompt_or_steer(action) {
    [
      runtime_event_assistant_delta(),
      runtime_event_reasoning_delta(),
      runtime_event_tool_call(),
      runtime_event_tool_result(),
      runtime_event_diff(),
      runtime_event_test_result(),
      runtime_event_artifact(),
      runtime_event_runtime_finished(),
    ]
  } else if action == command_cancel() {
    [runtime_event_runtime_aborted(), runtime_event_runtime_finished()]
  } else {
    [runtime_event_runtime_update(), runtime_event_runtime_finished()]
  }
}

///|
pub fn native_command_required_outputs(action : String) -> Array[String] {
  if action == command_run_tests() {
    ["test command", "exit code", "test_result event"]
  } else if action == command_run_build() {
    ["build command", "exit code", "test_result event"]
  } else if action == command_run_eval() {
    [
      "tool_harness result", "file_edit result", "patch_review result", "command_execution result",
      "package_output result", "native eval report", "eval_report.manifest event",
    ]
  } else if action == command_package() {
    [
      "source inventory", "package manifest", "package index", "artifact event",
      "package_verified proof event",
    ]
  } else if action == command_commit() {
    ["git status before commit", "commit SHA", "commit_created proof event"]
  } else if action == command_accept() {
    ["review receipt", "accepted MoonBook output note"]
  } else if action == command_reject() {
    ["review receipt", "rejection note"]
  } else if action == command_apply_patch() {
    [
      "diff event", "changed paths", "patch_applied proof event", "selected-hunk proof metadata",
      "post-change verification metadata",
    ]
  } else if action == command_revert_patch() {
    [
      "diff event", "changed paths", "patch_reverted proof event", "selected-hunk proof metadata",
      "post-change verification metadata",
    ]
  } else if command_action_is_tool_approval(action) {
    ["tool authorization decision"]
  } else if command_action_is_prompt_or_steer(action) {
    ["transcript progress", "tool/diff/test/artifact events as applicable"]
  } else if action == command_cancel() {
    ["terminal runtime event"]
  } else {
    ["runtime update"]
  }
}

///|
pub fn native_command_recommended_commands(
  action : String,
  context_path : String,
) -> Array[String] {
  if action == command_run_tests() {
    if context_path.has_suffix(".mbt") || context_path.contains("moon.pkg") {
      ["moon check", "moon test"]
    } else {
      ["moon check", "moon test", "package-specific test command if present"]
    }
  } else if action == command_run_build() {
    if context_path.has_suffix(".mbt") || context_path.contains("moon.pkg") {
      ["moon build", "moon check"]
    } else {
      ["moon build", "moon check", "package-specific build command if present"]
    }
  } else if action == command_run_eval() {
    [
      "run tool_harness eval fixtures",
      "run file_edit eval fixtures",
      "run patch_review eval fixtures",
      "run command_execution eval fixtures",
      "run package_output eval fixtures",
      native_command_eval_report_sink(),
    ]
  } else if action == command_package() {
    ["moon check", "moon test", "build/package selected artifact"]
  } else if action == command_commit() {
    [
      "git status --short", "git diff --check", "git commit with reviewed message",
    ]
  } else if command_action_is_patch(action) {
    ["moon check", "moon test"]
  } else {
    []
  }
}

///|
pub fn native_command_default_package_kind(action : String) -> String {
  if action == command_package() {
    "app-tool"
  } else {
    ""
  }
}

///|
pub fn native_command_tool_policies(
  action : String,
  context_path : String,
) -> Array[Json] {
  let policies : Array[Json] = []
  for tool in native_command_tool_sequence(action) {
    policies.push(native_command_tool_policy(tool, action, context_path))
  }
  policies
}

///|
pub fn native_command_tool_policy(
  tool : String,
  action : String,
  context_path : String,
) -> Json {
  match tool {
    "read" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="auto",
        mutates_files=false,
        required_inputs=["path"],
        proof_events=[runtime_event_tool_call(), runtime_event_tool_result()],
        guardrails=[
          "resolve path relative to selected MoonBook root", "reject parent traversal and absolute paths outside the book",
          "return bounded content with path and byte metadata",
        ],
      )
    "edit" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="review",
        mutates_files=true,
        required_inputs=["path", "old", "new"],
        proof_events=[
          runtime_event_tool_call(),
          runtime_event_file_change(),
          runtime_event_diff(),
          runtime_event_tool_result(),
        ],
        guardrails=[
          "require recent bounded read context before replacing text", "reject empty old text or stale old text without applying partial edits",
          "run MoonBit manifest guardrails before editing moon.mod or moon.pkg",
          "emit diff evidence before review or packaging gates can pass",
        ],
      )
    "write" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="review",
        mutates_files=true,
        required_inputs=["path", "content"],
        proof_events=[
          runtime_event_tool_call(),
          runtime_event_file_change(),
          runtime_event_diff(),
          runtime_event_tool_result(),
        ],
        guardrails=[
          "write only inside executable MoonBook roots or reviewed wiki paths", "reject new moon.mod.json files for MoonBit code",
          "reject JSON-shaped moon.mod or moon.pkg content", "emit full-path diff evidence for operator review",
        ],
      )
    "shell" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="policy",
        mutates_files=false,
        required_inputs=["cmd"],
        proof_events=[
          runtime_event_tool_call(),
          runtime_event_tool_result(),
          runtime_event_runtime_update(),
        ],
        guardrails=[
          "accept argv arrays instead of raw shell strings", "run under selected MoonBook root or a book-relative cwd",
          "require bounded timeout and capped output", "destructive, networked, or broad workspace commands require operator policy approval",
        ],
      )
    "moon_ide" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="auto",
        mutates_files=false,
        required_inputs=["action"],
        proof_events=[
          runtime_event_tool_call(),
          runtime_event_tool_result(),
          runtime_event_runtime_update(),
        ],
        guardrails=[
          "run only read-only moon ide actions: doc, outline, peek_def, hover, or find_references",
          "resolve cwd and path relative to selected MoonBook root", "prefer semantic discovery before broad source reads or edits",
          "cap output so semantic lookup cannot flood the transcript",
        ],
      )
    "moon_cmd" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="policy",
        mutates_files=true,
        required_inputs=["command"],
        proof_events=[
          runtime_event_tool_call(),
          runtime_event_tool_result(),
          runtime_event_test_result(),
          runtime_event_runtime_update(),
          runtime_event_diff(),
        ],
        guardrails=[
          "run selected moon commands directly instead of asking the shell to parse raw prose",
          "require book-relative cwd, bounded output, and explicit target/program args",
          "treat fmt and test --update as mutation-capable and require policy approval plus diff proof",
          "require test_update_kind and test_update_reason before snapshot-updating tests",
        ],
      )
    "moon_check" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="auto",
        mutates_files=false,
        required_inputs=[],
        proof_events=[
          runtime_event_tool_call(),
          runtime_event_tool_result(),
          runtime_event_test_result(),
        ],
        guardrails=[
          "prefer moon check before broad moon test while iterating", "capture command, exit code, target, and bounded diagnostics",
          "publish test_result evidence for action-plan and acceptance gates",
        ],
      )
    "package_app_tool" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="operator",
        mutates_files=true,
        required_inputs=["artifact_root"],
        proof_events=[
          runtime_event_tool_call(),
          runtime_event_artifact(),
          native_command_package_manifest_event(),
          native_command_package_index_event(),
          runtime_event_package_verified(),
        ],
        guardrails=[
          "package only accepted or runtime-proven code artifacts", "bind package manifest to source paths inside the selected MoonBook",
          "write package index under portable/app-tool or another MoonBook-owned output root",
        ],
      )
    "finish" =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="auto",
        mutates_files=false,
        required_inputs=["summary"],
        proof_events=[runtime_event_runtime_finished()],
        guardrails=[
          "summarize changed paths, test evidence, artifacts, and residual risks",
          "do not claim accepted output without review, test, or package evidence",
        ],
      )
    _ =>
      native_command_tool_policy_entry(
        tool,
        action,
        context_path,
        approval="unknown",
        mutates_files=false,
        required_inputs=[],
        proof_events=[runtime_event_tool_result()],
        guardrails=["runtime must reject unknown tools before execution"],
      )
  }
}

///|
fn native_command_tool_policy_entry(
  tool : String,
  action : String,
  context_path : String,
  approval~ : String,
  mutates_files~ : Bool,
  required_inputs~ : Array[String],
  proof_events~ : Array[String],
  guardrails~ : Array[String],
) -> Json {
  {
    "tool": tool,
    "action": action,
    "context_path": context_path,
    "approval": approval,
    "mutates_files": mutates_files,
    "required_inputs": required_inputs,
    "proof_events": proof_events,
    "guardrails": guardrails,
    "runtime_owner": "moonclaw",
    "ui_owner": "moondesk",
    "artifact_owner": "moonbook",
  }
}

///|
pub fn native_command_execution_plan(
  action : String,
  context_path : String,
  package_kind : String,
  workspace_root : String,
  control : String,
  approval : String,
  web_search : Bool,
) -> Json {
  let resolved_package_kind = if package_kind == "" {
    native_command_default_package_kind(action)
  } else {
    package_kind
  }
  {
    "kind": native_command_execution_plan_kind(),
    "protocol": protocol_version(),
    "action": action,
    "control": control,
    "approval": approval,
    "target": if context_path == "" {
      "moonbook"
    } else {
      context_path
    },
    "context_path": context_path,
    "web_search": web_search,
    "tool_sequence": native_command_allowed_tool_sequence(action, web_search),
    "tool_policies": Json::array(
      native_command_tool_policies(action, context_path),
    ),
    "expected_events": native_command_expected_events(action),
    "required_outputs": native_command_required_outputs(action),
    "recommended_commands": native_command_recommended_commands(
      action, context_path,
    ),
    "package_kind": resolved_package_kind,
    "review_required": approval == "operator",
    "path_policy": {
      "book_root": workspace_root,
      "context_path": context_path,
      "rule": "All reads, edits, shell commands, tests, and generated artifacts must stay inside the selected MoonBook unless an operator approves a broader workspace explicitly.",
    },
  }
}

///|
pub fn native_command_tool_contract(action : String) -> Json {
  native_command_tool_contract_for_command(action, false)
}

///|
pub fn native_command_tool_contract_for_command(
  action : String,
  web_search : Bool,
) -> Json {
  {
    "kind": native_command_tool_contract_kind(),
    "web_search": web_search,
    "allowed_tools": native_command_allowed_tool_sequence(action, web_search),
    "tool_policies": Json::array(native_command_tool_policies(action, "")),
    "mutating_tools_require_review": true,
    "shell_requires_bounded_timeout": true,
    "moon_check_required_for_code_changes": true,
    "approval_boundary": "Moondesk records approvals; MoonClaw must enforce them before read/edit/write/shell/moon_check/package tools execute.",
  }
}

///|
pub fn native_command_result_contract(action : String) -> Json {
  let required_events = native_command_expected_events(action)
  let required_outputs = native_command_required_outputs(action)
  let event_sink = native_command_runtime_event_sink()
  let eval_report_sink = if action == command_run_eval() {
    native_command_eval_report_sink()
  } else {
    ""
  }
  let ack_sink = native_command_runtime_replay_sink()
  {
    "kind": native_command_result_contract_kind(),
    "required_events": required_events,
    "required_outputs": required_outputs,
    "event_sink": event_sink,
    "eval_report_sink": eval_report_sink,
    "ack_sink": ack_sink,
    "execution_checklist": Json::array(
      native_command_execution_checklist(
        action, required_events, required_outputs, event_sink, eval_report_sink,
        ack_sink,
      ),
    ),
    "completion_rule": "A runtime consumer should append typed progress events, then acknowledge the command as runtime-completed or failed through runtime replay.",
  }
}

///|
pub fn native_command_execution_checklist(
  action : String,
  required_events : Array[String],
  required_outputs : Array[String],
  event_sink : String,
  eval_report_sink : String,
  ack_sink : String,
) -> Array[Json] {
  let items : Array[Json] = []
  let mut index = 1
  let push_step = fn(
    id : String,
    title : String,
    owner : String,
    required_event : String,
    required_output : String,
    endpoint : String,
    blocking : Bool,
  ) {
    items.push({
      "index": index,
      "id": id,
      "title": title,
      "owner": owner,
      "required_event": required_event,
      "required_output": required_output,
      "endpoint": endpoint,
      "blocking": blocking,
    })
    index += 1
  }
  push_step(
    "claim-command",
    "Claim the runtime command before execution",
    "moonclaw",
    "runtime-claimed receipt",
    "claim id",
    native_command_runtime_claim_sink(),
    true,
  )
  for tool in native_command_tool_sequence(action) {
    push_step(
      "run-tool-\{tool}",
      "Run tool: \{tool}",
      "moonclaw",
      "",
      "",
      "",
      true,
    )
  }
  for event in required_events {
    push_step(
      "emit-event-\{event}",
      "Emit event: \{event}",
      "moonclaw",
      event,
      "",
      event_sink,
      true,
    )
  }
  for output in required_outputs {
    push_step(
      "produce-output-\{index}",
      "Produce output: \{output}",
      "moonclaw",
      "",
      output,
      "",
      true,
    )
  }
  if eval_report_sink != "" {
    push_step(
      "publish-native-eval-report", "Publish native eval report", "moonclaw", "native eval report",
      "eval-report manifest", eval_report_sink, true,
    )
  }
  push_step(
    "ack-command", "Acknowledge command completion", "moonclaw", "runtime-completed or runtime-failed receipt",
    "ack receipt", ack_sink, true,
  )
  items
}

///|
pub fn native_command_execution_contract_json() -> Json {
  {
    "kind": "mooncode-native-command-execution-contract",
    "protocol": protocol_version(),
    "contract_id": native_command_contract_id(),
    "execution_plan_kind": native_command_execution_plan_kind(),
    "tool_contract_kind": native_command_tool_contract_kind(),
    "result_contract_kind": native_command_result_contract_kind(),
    "runtime_owner": "moonclaw",
    "ui_owner": "moondesk",
    "artifact_owner": "moonbook",
    "supported_actions": command_supported_actions(),
    "event_sink": native_command_runtime_event_sink(),
    "eval_report_sink": native_command_eval_report_sink(),
    "ack_sink": native_command_runtime_replay_sink(),
    "claim_sink": native_command_runtime_claim_sink(),
    "tool_sequences": native_command_action_sequence_rows(),
    "expected_event_policy": [
      native_command_action_events_row(command_prompt()),
      native_command_action_events_row(command_run_eval()),
      native_command_action_events_row(command_package()),
      native_command_action_events_row(command_apply_patch()),
      native_command_action_events_row(command_cancel()),
    ],
    "required_output_policy": [
      native_command_action_outputs_row(command_run_tests()),
      native_command_action_outputs_row(command_run_eval()),
      native_command_action_outputs_row(command_package()),
      native_command_action_outputs_row(command_apply_patch()),
      native_command_action_outputs_row(command_accept()),
    ],
    "rules": [
      "mooncode/core owns action-to-tool sequence policy", "mooncode/core owns expected-event and required-output policy",
      "mooncode/core owns per-tool guardrails and native command result checklist",
      "internal MoonCode and MoonClaw may delegate to this contract but must not publish duplicate native command policy tables",
    ],
  }
}

///|
fn native_command_action_sequence_rows() -> Array[Json] {
  [
    native_command_action_sequence_row(command_prompt()),
    native_command_action_sequence_row(command_run_tests()),
    native_command_action_sequence_row(command_run_build()),
    native_command_action_sequence_row(command_run_eval()),
    native_command_action_sequence_row(command_package()),
    native_command_action_sequence_row(command_commit()),
    native_command_action_sequence_row(command_accept()),
    native_command_action_sequence_row(command_reject()),
    native_command_action_sequence_row(command_approve_tool()),
    native_command_action_sequence_row(command_reject_tool()),
    native_command_action_sequence_row(command_apply_patch()),
    native_command_action_sequence_row(command_revert_patch()),
    native_command_action_sequence_row(command_cancel()),
    native_command_action_sequence_row(command_note()),
  ]
}

///|
fn native_command_action_sequence_row(action : String) -> Json {
  { "action": action, "tools": native_command_tool_sequence(action) }
}

///|
fn native_command_action_events_row(action : String) -> Json {
  {
    "action": action,
    "expected_events": native_command_expected_events(action),
  }
}

///|
fn native_command_action_outputs_row(action : String) -> Json {
  {
    "action": action,
    "required_outputs": native_command_required_outputs(action),
  }
}
