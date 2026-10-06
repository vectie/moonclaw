///|
fn mooncode_runtime_cancel_require_command(
  commands : Array[Json],
  command : Json,
) -> Unit raise {
  let id = mooncode_command_id(command)
  for entry in commands {
    if id != "" &&
      mooncode_runtime_command_entry_id(entry) == id &&
      mooncode_json_object_field_or_empty(entry, "command").stringify() ==
      command.stringify() {
      return
    }
  }
  raise InvalidJournal(
    "MoonCode cancellation command identity no longer matches the accepted journal",
  )
}

///|
async fn mooncode_runtime_cancel_wait_local_task(
  task : @async.Task[Unit]?,
) -> Bool {
  match task {
    Some(task) => {
      task.cancel()
      let _ = task.wait() catch { _ => () }
      true
    }
    None => false
  }
}

///|
async fn mooncode_runtime_cancel_settle_selection(
  session_id : String,
  book_root : String,
  command : Json,
  selection : MoonCodeCancelSelection,
  task : @async.Task[Unit]?,
  now : () -> @clock.Timestamp,
) -> Json {
  let response = match selection {
    Settled(response) => response
    Active(item) => {
      let interrupted_runtime = mooncode_runtime_cancel_wait_local_task(task)
      let response = mooncode_runtime_cancel_active_atomic(
        session_id,
        book_root,
        command,
        item,
        interrupted_runtime~,
        now=now(),
      )
      response
    }
  }
  // The completed control can outlive a crash before goal reconciliation.
  // Reconcile the durable active-cancel source on both first settlement and
  // replay; a pending withdrawal must never terminate an unrelated goal.
  if mooncode_goal_runtime_is_active_cancel_source(
      mooncode_json_object_field_or_empty(response, "cancelled_event"),
    ) {
    mooncode_goal_runtime_reconcile_supervisor_events(
      book_root,
      session_id,
      now().truncate_to_s(),
    )
  }
  response
}

///|
/// Called after waiting for the selected local task, never while holding its
/// gates. A busy owner is retryable and cannot certify the target as stopped.
async fn mooncode_runtime_cancel_active_atomic(
  session_id : String,
  book_root : String,
  command : Json,
  selected : Json,
  interrupted_runtime~ : Bool,
  now~ : @clock.Timestamp,
) -> Json {
  let target = mooncode_json_string(selected, "command_id", default="")
  let control_id = mooncode_command_id(command)
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Shared)
  defer lifecycle_gate.unlock()
  let execution_lease = mooncode_open_session_execution_lease(
    book_root, session_id,
  )
  defer execution_lease.close()
  if !execution_lease.try_lock(Exclusive) {
    return {
      "kind": "mooncode-cancel-control",
      "protocol": mooncode_protocol_version(),
      "owner": "moonclaw",
      "accepted": true,
      "session_id": session_id,
      "book_root": book_root,
      "command_id": control_id,
      "target_command_id": target,
      "status": "busy",
      "busy_reason": "execution-lease-held",
      "interrupted_runtime": false,
      "retryable": true,
    }
  }
  defer execution_lease.unlock()
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  mooncode_require_active_session_state_locked(
    book_root,
    session_id,
    allow_create=true,
  )
  let journal = mooncode_read_session_journal_path(
    mooncode_session_journal_path(book_root, session_id),
    session_id,
  )
  let commands = mooncode_journal_entries(journal, mooncode_journal_command())
  let receipts = mooncode_journal_entries(
    journal,
    mooncode_journal_runtime_receipt(),
  )
  mooncode_runtime_cancel_require_command(commands, command)
  let target_command = mooncode_json_object_field_or_empty(selected, "command")
  mooncode_runtime_cancel_require_command(commands, target_command)
  if target == "" || target != mooncode_command_id(target_command) {
    raise InvalidJournal(
      "MoonCode cancellation selected target identity does not match its command",
    )
  }
  let mut selection_found = false
  let mut terminal : Json? = None
  for receipt in receipts {
    let id = mooncode_json_string(receipt, "command_id", default="")
    let status = mooncode_json_string(receipt, "status", default="")
    if id == control_id &&
      status == "runtime-completed" &&
      mooncode_json_string(receipt, "control", default="") == "cancel" {
      return mooncode_runtime_cancel_response(receipt)
    }
    if id == control_id && status == "runtime-cancel-requested" {
      let saved = mooncode_json_object_field_or_empty(receipt, "target_item")
      if mooncode_json_string(receipt, "target_command_id", default="") !=
        target ||
        mooncode_json_object_field_or_empty(saved, "command").stringify() !=
        target_command.stringify() {
        raise InvalidJournal(
          "MoonCode cancellation cannot change its durably selected target",
        )
      }
      selection_found = true
    }
    if id == target && mooncode_runtime_receipt_status_delivered(status) {
      terminal = Some(receipt)
    }
  }
  if !selection_found {
    raise InvalidJournal(
      "MoonCode active cancellation requires its durable exact-target selection",
    )
  }
  if terminal is Some(receipt) {
    let target_status = mooncode_json_string(receipt, "status", default="")
    let own_cancel = target_status == "runtime-cancelled" &&
      mooncode_json_string(receipt, "control_command_id", default="") ==
      control_id
    let events = mooncode_json_array_items(receipt, "events")
    let event = if own_cancel && !events.is_empty() {
      events[0]
    } else {
      Json::object({})
    }
    return match
      mooncode_runtime_finish_cancel_locked(
        session_id,
        book_root,
        command,
        target,
        event,
        interrupted_runtime=own_cancel &&
          mooncode_json_bool(receipt, "interrupted_runtime", default=false),
        cancel_status=if own_cancel { "cancelled" } else { "already-terminal" },
        target_status~,
        now~,
      ) {
      Settled(response) => response
      Active(_) =>
        fail("cancel settlement unexpectedly selected another target")
    }
  }
  // Re-read the exact claim under the execution lease and session lock instead
  // of writing a terminal receipt from the earlier, now stale selection.
  let state = mooncode_runtime_claim_state_from_logs(
    session_id,
    book_root,
    commands,
    receipts,
    journal_path=mooncode_session_journal_path(book_root, session_id),
  )
  let mut current : Json? = None
  for item in mooncode_json_array_items(state, "claimed_commands") {
    if mooncode_json_string(item, "command_id", default="") == target {
      current = Some(item)
    }
  }
  guard current is Some(item) else {
    raise InvalidJournal(
      "MoonCode cancellation target no longer has an active claim or terminal outcome",
    )
  }
  let event : Json = {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{target}-cancelled-\{control_id}",
    "protocol": mooncode_protocol_version(),
    "contract_id": @moonlib_conversation.control_contract_id(),
    "control_kind": "turn-cancellation",
    "control_id": control_id,
    "session_id": session_id,
    "command_id": target,
    "target_command_id": target,
    "control_command_id": control_id,
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
  let receipt = mooncode_runtime_cancelled_receipt(
    session_id,
    book_root,
    item,
    now~,
  )
  if receipt is Object(fields) {
    fields["control_command_id"] = control_id.to_json()
    fields["events"] = Json::array([event])
    fields["interrupted_runtime"] = interrupted_runtime.to_json()
  }
  ignore(
    mooncode_append_session_journal_once_locked(
      book_root,
      session_id,
      mooncode_journal_runtime_receipt(),
      receipt,
    ),
  )
  match
    mooncode_runtime_finish_cancel_locked(
      session_id,
      book_root,
      command,
      target,
      event,
      interrupted_runtime~,
      target_status="runtime-cancelled",
      now~,
    ) {
    Settled(response) => response
    Active(_) => fail("cancel settlement unexpectedly selected another target")
  }
}
