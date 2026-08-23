///|
fn mooncode_runtime_tool_approval_reason(tool_call : Json) -> String {
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let planner_local_validation = mooncode_runtime_planner_local_validation(
    tool_call,
  )
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let planner_generated = mooncode_json_string(tool_call, "planner", default="") ==
    "model-tool-call"
  if tool == "shell" {
    let raw_command = mooncode_json_string(arguments, "cmd", default="")
    let command = raw_command.to_lower().to_string()
    if mooncode_shell_has_git_commit(command) {
      return "Creating a git commit changes durable repository history and requires operator approval."
    }
    if mooncode_shell_has_git_worktree_overwrite(command) {
      return "This git command can overwrite tracked worktree content and requires operator approval."
    }
    if mooncode_shell_has_clean_dependency_install(command) {
      return "A clean dependency install can replace local dependency state and requires operator approval."
    }
    if mooncode_shell_has_sensitive_command(command) {
      return "This shell command can affect external systems, dependencies, or broad workspace state."
    }
    if mooncode_runtime_tool_is_demonstrably_read_only(tool_call) {
      let explicit_operator_boundary = mooncode_json_bool(
          tool_call,
          "requires_approval",
          default=false,
        ) ||
        mooncode_json_bool(arguments, "requires_approval", default=false) ||
        mooncode_json_string(
          tool_call,
          "approval",
          default=mooncode_json_string(arguments, "approval", default=""),
        ) ==
        "operator"
      if planner_generated || !explicit_operator_boundary {
        return ""
      }
    }
    return "Arbitrary shell text requires a separate operator approval bound to the exact ExecutionSandbox grant."
  }
  if tool == "browser" {
    let action = mooncode_json_string(arguments, "action", default="")
    let url = mooncode_json_string(arguments, "url", default="")
    if action == "open" && !mooncode_browser_loopback_url(url) {
      return "Navigating the native browser to a non-loopback destination requires operator approval."
    }
  }
  if tool == "moon_cmd" {
    let serialized = arguments.stringify().to_lower().to_string()
    if mooncode_moon_cmd_is_test_update(arguments) ||
      serialized.contains("publish") {
      return "This Moon command can update accepted outputs or publish a package."
    }
  }
  // Approval annotations are requests, not authority facts. The runtime keeps
  // them for mutation-capable and unclassified operations, but a planner cannot
  // turn an operation the runtime can prove read-only into a teacher pause.
  if planner_generated &&
    mooncode_runtime_tool_is_demonstrably_read_only(tool_call) {
    return ""
  }
  // Preserve caller-controlled authorization for operations whose authority
  // the runtime cannot prove, while ignoring approval annotations invented by
  // the model for canonical local validation.
  if !planner_local_validation &&
    (
      mooncode_json_bool(tool_call, "requires_approval", default=false) ||
      mooncode_json_bool(arguments, "requires_approval", default=false)
    ) {
    return "This operation explicitly requires operator approval."
  }
  let approval = mooncode_json_string(
    tool_call,
    "approval",
    default=mooncode_json_string(arguments, "approval", default=""),
  )
  if approval == "operator" && !planner_local_validation {
    return "This operation crosses an operator-controlled boundary."
  }
  ""
}

///|
async fn mooncode_runtime_bind_sandbox_approval_plan(
  book_root : String,
  request : Json,
) -> Json {
  let tool = mooncode_json_string(request, "tool", default="")
  if tool != "shell" && tool != "moon_cmd" {
    return request
  }
  let arguments = mooncode_json_object_field_or_empty(request, "arguments")
  guard arguments is Object(argument_fields) else { return request }
  let prepared = if tool == "shell" {
    mooncode_prepare_shell_approval_plan(book_root, arguments)
  } else {
    mooncode_prepare_moon_cmd_approval_plan(book_root, arguments)
  }
  match prepared {
    Ok(plan) => argument_fields["_execution_sandbox_plan"] = plan.to_json()
    Err(error) =>
      argument_fields["_execution_sandbox_plan_error"] = @json.to_json(error)
  }
  request
}

///|
fn mooncode_runtime_authorized_tool_call(
  tool_call : Json,
  approval : Json,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  if (tool != "shell" && tool != "moon_cmd") ||
    mooncode_json_string(approval, "state", default="") != "approved" {
    return tool_call
  }
  {
    "tool": tool,
    "arguments": mooncode_json_object_field_or_empty(approval, "arguments"),
  }
}

///|
fn mooncode_runtime_tool_is_demonstrably_read_only(tool_call : Json) -> Bool {
  if mooncode_runtime_tool_effect(tool_call) is ConcurrentRead {
    return true
  }
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  match tool {
    "read"
    | "read_skill"
    | "view_image"
    | "moon_ide"
    | "moon_check"
    | "checkpoint"
    | "finish" => true
    "browser" => {
      let action = mooncode_json_string(arguments, "action", default="")
      action == "snapshot" ||
      action == "screenshot" ||
      action == "set_viewport" ||
      action == "get" ||
      action == "eval" ||
      action == "console" ||
      action == "errors" ||
      action == "reload" ||
      action == "close" ||
      (
        action == "open" &&
        mooncode_browser_loopback_url(
          mooncode_json_string(arguments, "url", default=""),
        )
      )
    }
    "shell" =>
      mooncode_shell_is_demonstrably_read_only(
        mooncode_json_string(arguments, "cmd", default=""),
      )
    "moon_cmd" => {
      let command = mooncode_json_string(arguments, "command", default="")
      (command == "check" || command == "test" || command == "build") &&
      !mooncode_moon_cmd_is_test_update(arguments)
    }
    _ => false
  }
}

///|
fn mooncode_runtime_planner_local_validation(tool_call : Json) -> Bool {
  if mooncode_json_string(tool_call, "planner", default="") != "model-tool-call" {
    return false
  }
  let tool = mooncode_json_string(tool_call, "tool", default="")
  if tool == "moon_check" {
    return true
  }
  if tool != "moon_cmd" {
    return false
  }
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let command = mooncode_json_string(arguments, "command", default="")
  (
    command == "check" ||
    command == "test" ||
    command == "info" ||
    command == "fmt" ||
    command == "build"
  ) &&
  !mooncode_moon_cmd_is_test_update(arguments)
}

///|
fn mooncode_runtime_tool_requires_approval(tool_call : Json) -> Bool {
  mooncode_runtime_tool_approval_reason(tool_call) != ""
}

///|
fn mooncode_runtime_tool_approval_id(
  command_id : String,
  tool_call : Json,
  occurrence~ : Int,
) -> String {
  let explicit = mooncode_json_string(tool_call, "approval_id", default="")
  if explicit != "" {
    return explicit
  }
  let seed = command_id +
    ":" +
    mooncode_json_string(tool_call, "tool", default="") +
    ":" +
    occurrence.to_string() +
    ":" +
    mooncode_json_object_field_or_empty(tool_call, "arguments").stringify()
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(seed).to_fixedarray()),
  )
  "mooncode-approval-" + digest[:20].to_owned()
}

///|
fn mooncode_runtime_tool_approval_event(
  session_id : String,
  command_id : String,
  tool_call : Json,
  occurrence~ : Int,
  state~ : String,
  tool_call_id? : String = "",
  control_command_id? : String = "",
  decision_reason? : String = "",
  now~ : @clock.Timestamp,
) -> Json {
  let approval_id = mooncode_runtime_tool_approval_id(
    command_id,
    tool_call,
    occurrence~,
  )
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let tool_call_id = if tool_call_id == "" {
    mooncode_runtime_turn_tool_call_id(tool_call, step=occurrence + 1, index=0)
  } else {
    tool_call_id
  }
  let title = match state {
    "approved" => "Tool approved"
    "rejected" => "Tool rejected"
    _ => "Approval needed"
  }
  let detail = match state {
    "approved" =>
      "Operator approved `\{tool}`. MoonClaw may continue this turn."
    "rejected" =>
      if decision_reason == "" {
        "Operator rejected `\{tool}`. MoonClaw will not execute it."
      } else {
        "Operator rejected `\{tool}`. MoonClaw will not execute it. Reason: \{decision_reason}"
      }
    _ => mooncode_runtime_tool_approval_reason(tool_call)
  }
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{approval_id}-\{state}-\{if control_command_id == "" { "request" } else { control_command_id }}",
    "protocol": mooncode_protocol_version(),
    "contract_id": @moonlib_conversation.control_contract_id(),
    "control_kind": "tool-approval",
    "control_id": approval_id,
    "approval_id": approval_id,
    "session_id": session_id,
    "command_id": command_id,
    "target_command_id": command_id,
    "control_command_id": control_command_id,
    "decision_reason": decision_reason,
    "tool_call_id": tool_call_id,
    "tool": tool,
    "arguments": arguments,
    "lane": "approval",
    "kind": @moonlib_conversation.approval_event_kind(state),
    "event": @moonlib_conversation.approval_event_kind(state),
    "title": title,
    "status": if state == "pending" {
      "running"
    } else {
      "done"
    },
    "state": state,
    "detail": detail,
    "created_at": now,
    "source": "moonclaw-native-runtime-control",
  }
}

///|
fn mooncode_runtime_tool_approval_event_for_id(
  events : Array[Json],
  approval_id : String,
) -> Json {
  let mut latest = Json::object({})
  for event in events {
    if mooncode_json_string(event, "approval_id", default="") == approval_id &&
      mooncode_json_string(event, "kind", default="").has_prefix(
        "tool.approval_",
      ) {
      latest = event
    }
  }
  latest
}

///|
fn mooncode_runtime_tool_approval_request_for_id(
  events : Array[Json],
  approval_id : String,
) -> Json {
  for event in events {
    if mooncode_json_string(event, "approval_id", default="") == approval_id &&
      mooncode_json_string(event, "kind", default="") ==
      "tool.approval_requested" &&
      mooncode_json_string(event, "state", default="") == "pending" {
      return event
    }
  }
  Json::object({})
}

///|
/// Approval control is intentionally a tail-local operation. A pending request
/// is the last durable planner action before the runtime enters its waiting
/// state, so replaying every (potentially very large) planner checkpoint merely
/// to find it makes long-running sessions unable to accept an approval.
///
/// Parse only a bounded committed suffix and return matching approval events.
/// The normal journal append path still owns whole-prefix validation and
/// sequence continuity; this reader validates the canonical envelopes it does
/// consume and never mutates the journal.
async fn mooncode_runtime_recent_tool_approval_events(
  book_root : String,
  session_id : String,
  approval_id : String,
) -> Array[Json] {
  let path = mooncode_session_journal_path(book_root, session_id)
  if path == "" || !(@fsx.exists(path) catch { _ => false }) {
    return []
  }
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  file.lock(Shared)
  defer file.unlock()
  let committed_size = mooncode_newline_committed_size(file)
  if committed_size == 0L {
    return []
  }
  let max_tail_bytes = 4L * 1024L * 1024L
  let tail_size = if committed_size > max_tail_bytes {
    max_tail_bytes
  } else {
    committed_size
  }
  let start = committed_size - tail_size
  let starts_at_record_boundary = start == 0L ||
    file.read_exactly_at(1, position=start - 1L) == b"\n"
  let text = @encoding/utf8.decode(
    file.read_exactly_at(tail_size.to_int(), position=start),
  ) catch {
    _ => raise InvalidJournal("MoonCode approval journal tail is not UTF-8")
  }
  let lines = text.split("\n").collect()
  let first_line = if starts_at_record_boundary { 0 } else { 1 }
  let events : Array[Json] = []
  for index = first_line; index < lines.length(); index = index + 1 {
    let line = lines[index]
    if line.is_empty() {
      continue
    }
    let raw = line.to_owned()
    let record = @json.parse(raw) catch {
      _ =>
        raise InvalidJournal(
          "MoonCode approval journal tail contains invalid JSON",
        )
    }
    if record.stringify() != raw {
      raise InvalidJournal(
        "MoonCode approval journal tail contains a non-canonical record",
      )
    }
    if mooncode_json_string(record, "session_id", default="") != session_id {
      raise InvalidJournal(
        "MoonCode approval journal tail contains a different session",
      )
    }
    if mooncode_json_string(record, "record_kind", default="") !=
      mooncode_journal_event() {
      continue
    }
    let payload = mooncode_json_object_field_or_empty(record, "payload")
    if mooncode_json_string(payload, "approval_id", default="") == approval_id &&
      mooncode_json_string(payload, "kind", default="").has_prefix(
        "tool.approval_",
      ) {
      events.push(payload)
    }
  }
  events
}

///|
async fn mooncode_runtime_recent_tool_approval_event_for_id(
  book_root : String,
  session_id : String,
  approval_id : String,
) -> Json {
  mooncode_runtime_tool_approval_event_for_id(
    mooncode_runtime_recent_tool_approval_events(
      book_root, session_id, approval_id,
    ),
    approval_id,
  )
}

///|
async fn mooncode_runtime_wait_for_tool_approval(
  book_root : String,
  session_id : String,
  approval_id : String,
  timeout_ms~ : Int,
) -> Json {
  let mut elapsed = 0
  let mut latest = mooncode_runtime_recent_tool_approval_event_for_id(
    book_root, session_id, approval_id,
  )
  let mut state = mooncode_json_string(latest, "state", default="pending")
  while state != "approved" && state != "rejected" && elapsed < timeout_ms {
    let remaining = timeout_ms - elapsed
    let delay = if remaining < 100 { remaining } else { 100 }
    if delay <= 0 {
      break
    }
    @async.sleep(delay)
    elapsed += delay
    latest = mooncode_runtime_recent_tool_approval_event_for_id(
      book_root, session_id, approval_id,
    )
    state = mooncode_json_string(latest, "state", default="pending")
  }
  latest
}

///|
fn mooncode_runtime_approval_wait_ms(command : Json) -> Int {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let requested = mooncode_json_int(payload, "approval_wait_ms", default=300000)
  if requested < 0 {
    0
  } else if requested > 900000 {
    900000
  } else {
    requested
  }
}

///|
fn mooncode_runtime_rejected_tool_execution(
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  decision : Json,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let decision_reason = mooncode_json_string(
    decision,
    "decision_reason",
    default="",
  )
  let rejection_output = if decision_reason == "" {
    "The operator rejected `\{tool}`; do not execute it."
  } else {
    "The operator rejected `\{tool}`; do not execute it. Reason: \{decision_reason}"
  }
  {
    "accepted": true,
    "executed": false,
    "approval_state": "rejected",
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "arguments": arguments,
    "result": {
      "tool": tool,
      "is_error": false,
      "message": "Operator rejected this tool call.",
      "output": rejection_output,
      "metadata": {
        "approval_state": "rejected",
        "decision_reason": decision_reason,
      },
    },
    "event": decision,
  }
}

///|
fn mooncode_runtime_control_field(command : Json, key : String) -> String {
  let direct = mooncode_json_string(command, key, default="")
  if direct != "" {
    return direct
  }
  mooncode_json_string(
    mooncode_json_object_field_or_empty(command, "payload"),
    key,
    default="",
  )
}

///|
fn mooncode_runtime_control_receipt(
  session_id : String,
  book_root : String,
  command : Json,
  action~ : String,
  message~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_command_id(command)
  {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "status": "runtime-completed",
    "runtime_mode": "moonclaw-native-runtime-control",
    "claim_id": "moonclaw-control-\{mooncode_safe_session_id(session_id)}-\{command_id}",
    "consumer_id": "moonclaw-native-runtime-control",
    "completed_at": now,
    "control": action,
    "message": message,
    "command": command,
    "execution": {
      "accepted": true,
      "control": action,
      "message": message,
      "events": Json::array([]),
    },
    "events": Json::array([]),
  }
}

///|
async fn mooncode_runtime_tool_approval_control_request(
  session_id : String,
  book_root : String,
  command : Json,
) -> Json {
  let approval_id = mooncode_runtime_control_field(command, "approval_id")
  if approval_id == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode tool approval requires approval_id",
      },
    })
  }
  let events = mooncode_runtime_recent_tool_approval_events(
    book_root, session_id, approval_id,
  )
  let request = mooncode_runtime_tool_approval_request_for_id(
    events, approval_id,
  )
  if mooncode_json_string(request, "approval_id", default="") == "" {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode approval does not target a pending tool call",
        "metadata": { "session_id": session_id, "approval_id": approval_id },
      },
    })
  }
  let requested_tool = mooncode_json_string(request, "tool", default="")
  let requested_arguments = mooncode_json_object_field_or_empty(
    request, "arguments",
  )
  if (requested_tool == "shell" || requested_tool == "moon_cmd") &&
    !(requested_arguments is { "_execution_sandbox_plan": _, .. }) {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode process approval is not bound to a complete ExecutionSandbox grant",
        "metadata": {
          "session_id": session_id,
          "approval_id": approval_id,
          "execution_sandbox_required": true,
          "execution_sandbox_policy": "fail-closed",
        },
      },
    })
  }
  let requested_target = mooncode_runtime_control_field(
    command, "target_command_id",
  )
  let target_command_id = mooncode_json_string(
    request,
    "target_command_id",
    default="",
  )
  if requested_target != "" && requested_target != target_command_id {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode approval target does not match the pending tool call",
      },
    })
  }
  request
}

///|
async fn Daemon::mooncode_submit_tool_approval_control(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id : String,
  book_root : String,
  command : Json,
) -> Json {
  let approval_id = mooncode_runtime_control_field(command, "approval_id")
  let request = mooncode_runtime_tool_approval_control_request(
    session_id, book_root, command,
  )
  let target_command_id = mooncode_json_string(
    request,
    "target_command_id",
    default="",
  )
  let action = mooncode_json_string(command, "command", default="")
  let state = if action == "approve_tool" { "approved" } else { "rejected" }
  let decision_reason = mooncode_runtime_control_field(
      command, "decision_reason",
    )
    .trim()
    .to_owned()
  let decision_reason = if decision_reason == "" {
    mooncode_json_string(command, "text", default="").trim().to_owned()
  } else {
    decision_reason
  }
  let tool_call : Json = {
    "approval_id": approval_id,
    "tool_call_id": mooncode_json_string(request, "tool_call_id", default=""),
    "tool": mooncode_json_string(request, "tool", default=""),
    "arguments": mooncode_json_object_field_or_empty(request, "arguments"),
  }
  let decision = mooncode_runtime_tool_approval_event(
    session_id,
    target_command_id,
    tool_call,
    occurrence=0,
    state~,
    tool_call_id=mooncode_json_string(request, "tool_call_id", default=""),
    control_command_id=mooncode_command_id(command),
    decision_reason~,
    now=self.clock.now(),
  )
  let binding = self.mooncode_binding_for_session(session_id)
  ignore(binding.bind_book_root(book_root))
  binding.events.put(decision)
  self.mooncode_persist_event(binding, decision)
  let receipt = mooncode_runtime_control_receipt(
    session_id,
    book_root,
    command,
    action~,
    message="MoonClaw recorded `\{state}` for approval `\{approval_id}`.",
    now=self.clock.now(),
  )
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_runtime_receipt(),
      receipt,
    ),
  )
  self.mooncode_persist_session(binding)
  let service = self.mooncode_start_runtime_service(
    group~,
    session_id,
    book_root,
    command,
  )
  {
    "kind": "mooncode-tool-approval-control",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": true,
    "session_id": session_id,
    "book_root": book_root,
    "approval_id": approval_id,
    "target_command_id": target_command_id,
    "state": state,
    "decision_event": decision,
    "control_receipt": receipt,
    "service": service,
  }
}

///|
fn mooncode_runtime_cancelled_receipt(
  session_id : String,
  book_root : String,
  claim_item : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_json_string(claim_item, "command_id", default="")
  let claim = mooncode_json_object_field_or_empty(claim_item, "receipt")
  {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "status": "runtime-cancelled",
    "runtime_mode": "moonclaw-native-runtime-control",
    "claim_id": mooncode_json_string(claim, "claim_id", default=""),
    "consumer_id": "moonclaw-native-runtime-control",
    "completed_at": now,
    "control": "cancelled",
    "message": "MoonClaw cancelled the active MoonCode request.",
    "command": mooncode_json_object_field_or_empty(claim_item, "command"),
    "command_entry": mooncode_json_object_field_or_empty(
      claim_item, "command_entry",
    ),
    "execution": {
      "accepted": false,
      "cancelled": true,
      "control": "cancelled",
      "message": "MoonClaw cancelled the active MoonCode request.",
      "events": Json::array([]),
    },
    "events": Json::array([]),
  }
}

///|
async fn Daemon::mooncode_submit_cancel_control(
  self : Daemon,
  session_id : String,
  book_root : String,
  command : Json,
) -> Json {
  let binding = self.mooncode_binding_for_session(session_id)
  ignore(binding.bind_book_root(book_root))
  let claim_state = self.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  let claimed = mooncode_json_array_items(claim_state, "claimed_commands")
  let mut target_command_id = ""
  let mut claimed_item = Json::object({})
  if claimed.length() > 0 {
    claimed_item = claimed[0]
    target_command_id = mooncode_json_string(
      claimed_item,
      "command_id",
      default="",
    )
  }
  let requested_target = mooncode_runtime_control_field(
    command, "target_command_id",
  )
  if requested_target != "" && requested_target != target_command_id {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode cancellation does not target the active request",
        "metadata": {
          "session_id": session_id,
          "requested_target_command_id": requested_target,
          "active_target_command_id": target_command_id,
        },
      },
    })
  }
  let was_running = binding.runtime_service_running
  if was_running {
    match binding.runtime_service_task {
      Some(task) => {
        task.cancel()
        let _ = task.wait() catch { _ => () }
      }
      None => ()
    }
  }
  let mut cancelled_event = Json::object({})
  if target_command_id != "" {
    let item = claimed_item
    let now = self.clock.now()
    cancelled_event = {
      "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{target_command_id}-cancelled-\{mooncode_command_id(command)}",
      "protocol": mooncode_protocol_version(),
      "contract_id": @moonlib_conversation.control_contract_id(),
      "control_kind": "turn-cancellation",
      "control_id": mooncode_command_id(command),
      "session_id": session_id,
      "command_id": target_command_id,
      "target_command_id": target_command_id,
      "control_command_id": mooncode_command_id(command),
      "lane": "runtime",
      "kind": @moonlib_conversation.cancellation_event_kind(),
      "event": @moonlib_conversation.cancellation_event_kind(),
      "title": "Request cancelled",
      "status": "cancelled",
      "state": "cancelled",
      "detail": "MoonClaw stopped the active work for this request.",
      "created_at": now,
      "source": "moonclaw-native-runtime-control",
    }
    binding.events.put(cancelled_event)
    self.mooncode_persist_event(binding, cancelled_event)
    mooncode_goal_runtime_reconcile_supervisor_events(
      book_root,
      session_id,
      now.truncate_to_s(),
    )
    ignore(
      mooncode_append_session_journal(
        book_root,
        session_id,
        mooncode_journal_runtime_receipt(),
        mooncode_runtime_cancelled_receipt(session_id, book_root, item, now~),
      ),
    )
  }
  let receipt = mooncode_runtime_control_receipt(
    session_id,
    book_root,
    command,
    action="cancel",
    message=if target_command_id == "" {
      "MoonClaw found no active MoonCode request to cancel."
    } else {
      "MoonClaw cancelled request `\{target_command_id}`."
    },
    now=self.clock.now(),
  )
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_runtime_receipt(),
      receipt,
    ),
  )
  binding.active_command_id = ""
  self.mooncode_persist_session(binding)
  {
    "kind": "mooncode-cancel-control",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": true,
    "session_id": session_id,
    "book_root": book_root,
    "interrupted_runtime": was_running,
    "target_command_id": target_command_id,
    "status": if target_command_id == "" {
      "idle"
    } else {
      "cancelled"
    },
    "cancelled_event": cancelled_event,
    "control_receipt": receipt,
  }
}
