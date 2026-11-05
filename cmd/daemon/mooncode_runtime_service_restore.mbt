///|
/// One boot pass over the existing trusted Books. Execution ownership,
/// continuation hydration and queue draining remain the ordinary service's job.
async fn Daemon::mooncode_restore_runtime_services(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
) -> Unit {
  let config = @moondesk_sandbox_config.load(read_only=true) catch {
    error => {
      logger.error("MoonCode startup discovery: \{error}")
      return
    }
  }
  guard config is Some(config) else { return }
  for book_root in config.trusted_book_roots.unwrap_or([]) {
    try {
      if !config.allows_book_root(book_root) {
        continue
      }
      let root = mooncode_sessions_root(book_root)
      if !@fsx.exists(root) {
        continue
      }
      for entry in @fsx.list_directory(root) {
        if !(entry.kind is Directory) {
          continue
        }
        let session_id = entry.name
        if !mooncode_integration_session_id_valid(session_id) {
          continue
        }
        try {
          let journal = mooncode_read_session_journal(book_root, session_id)
          if mooncode_runtime_service_restore_payload(
              session_id, book_root, journal,
            )
            is Some(payload) {
            self.mooncode_bind_integration_session(book_root, session_id)
            ignore(
              self.mooncode_start_runtime_service(
                group~,
                session_id,
                book_root,
                payload,
              ),
            )
          }
        } catch {
          error =>
            logger.error(
              "MoonCode startup \{session_id}: \{mooncode_runtime_service_error_detail(error)}",
            )
        }
      }
    } catch {
      error => logger.error("MoonCode startup \{book_root}: \{error}")
    }
  }
}

///|
fn mooncode_runtime_service_restore_payload(
  session_id : String,
  book_root : String,
  journal : Array[Json],
) -> Json? raise {
  let state = mooncode_runtime_claim_state_from_journal(
    session_id, book_root, journal,
  )
  let pending = mooncode_json_array_items(state, "claimed_commands")
  pending.append(mooncode_json_array_items(state, "claimable_commands"))
  pending.append(mooncode_json_array_items(state, "order_blocked_commands"))
  if pending.is_empty() {
    return None
  }
  let events = mooncode_journal_entries(journal, mooncode_journal_event())
  if mooncode_runtime_service_pending_approval(events) is Some(checkpoint) &&
    pending.any(item => {
      mooncode_json_string(item, "command_id", default="") ==
      mooncode_json_string(checkpoint, "command_id", default="")
    }) &&
    !pending.any(item => {
      mooncode_json_string(item, "action", default="") == "cancel"
    }) {
    return None
  }
  let mut boundary_event = Json::empty_object()
  for event in events {
    if mooncode_runtime_service_event(event) ||
      mooncode_runtime_is_active_cancel_source(event) {
      boundary_event = event
    }
  }
  let kind = mooncode_json_string(boundary_event, "kind", default="")
  // A process cancellation records no completed turns. A user cancel resolves
  // its command through the normal turn and must keep the queue stopped.
  let interrupted = kind == "runtime.service_started" ||
    (
      mooncode_json_string(boundary_event, "stopped_by", default="") ==
      "cancelled" &&
      mooncode_json_int(boundary_event, "ran_turn_count", default=0) == 0
    )
  // A submission can commit just before the previous finish event. Resume
  // that drain gap too; an explicit bounded run does not promise to drain.
  let stopped_by = mooncode_json_string(
    boundary_event,
    "stopped_by",
    default="",
  )
  let unfinished_drain = kind == "runtime.service_finished" &&
    mooncode_json_bool(boundary_event, "auto_drain", default=true) &&
    (
      mooncode_runtime_service_queue_drain_allowed(boundary_event) ||
      stopped_by == "retryable" ||
      stopped_by == "approval"
    )
  let boundary = mooncode_journal_cursor_parse(
    mooncode_json_string(boundary_event, "journal_sequence", default="0"),
  )
  let newly_queued = pending.any(item => {
    let command = mooncode_json_object_field_or_empty(item, "command_entry")
    mooncode_journal_cursor_parse(
      mooncode_json_string(command, "journal_sequence", default="0"),
    ).compare(boundary) >
    0
  })
  if !interrupted && !unfinished_drain && !newly_queued {
    return None
  }
  // Preserve an interrupted manual service's loop options. An already finished
  // bounded service stays finished; a new submission uses ordinary defaults.
  if interrupted {
    let payload : Map[String, Json] = {
      "service_id": mooncode_runtime_service_id(session_id, boundary_event),
      "consumer_id": mooncode_runtime_service_consumer_id(boundary_event),
      "live_wait_ms": mooncode_runtime_service_live_wait_ms(boundary_event),
      "poll_ms": mooncode_runtime_loop_poll_ms(boundary_event),
    }
    if !mooncode_json_bool(boundary_event, "auto_drain", default=true) {
      payload["max_turns"] = Json(
        mooncode_runtime_loop_max_turns(boundary_event),
      )
    }
    Some(Json::object(payload))
  } else {
    Some(Json::empty_object())
  }
}
