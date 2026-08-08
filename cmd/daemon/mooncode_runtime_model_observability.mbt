///|
fn mooncode_runtime_turn_model_retry_event(
  command : Json,
  model_name : String,
  attempt : Int,
  summary : String,
  delay_ms : Int,
  provider_error_class? : String = "transient",
  retry_after_ms? : Int? = None,
  overload_compaction_tier? : Int = 0,
  retry_request_chars? : Int = 0,
  now~ : @clock.Timestamp,
) -> Json {
  let event = mooncode_event(
    session_id=mooncode_json_string(command, "session_id", default=""),
    command_id=mooncode_command_id(command),
    lane="runtime",
    kind="runtime.planner_retrying",
    title="MoonCode model planner waiting to retry",
    status="waiting",
    detail="Model `\{model_name}` attempt \{attempt} failed with a transient provider error: \{summary}. MoonClaw preserved the checkpoint and will retry in \{delay_ms}ms with overload compaction tier \{overload_compaction_tier} (\{retry_request_chars} request chars).",
    now~,
  )
  let event = mooncode_json_object_with_field(
    event,
    "provider_error_class",
    Json::string(provider_error_class),
  )
  let event = mooncode_json_object_with_field(
    event,
    "retry_after_ms",
    match retry_after_ms {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
  )
  let event = mooncode_json_object_with_field(
    event,
    "overload_compaction_tier",
    Json::number(overload_compaction_tier.to_double()),
  )
  mooncode_json_object_with_field(
    event,
    "retry_request_chars",
    Json::number(retry_request_chars.to_double()),
  )
}

///|
async fn mooncode_runtime_turn_record_model_retry(
  command : Json,
  model_name : String,
  attempt : Int,
  summary : String,
  delay_ms : Int,
  provider_error_class? : String = "transient",
  retry_after_ms? : Int? = None,
  overload_compaction_tier? : Int = 0,
  retry_request_chars? : Int = 0,
) -> Unit {
  let book_root = mooncode_book_root(command)
  let session_id = mooncode_json_string(command, "session_id", default="")
  if book_root == "" || session_id == "" || mooncode_command_id(command) == "" {
    return
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    mooncode_runtime_turn_model_retry_event(
      command,
      model_name,
      attempt,
      summary,
      delay_ms,
      provider_error_class~,
      retry_after_ms~,
      overload_compaction_tier~,
      retry_request_chars~,
      now=@clock.epoch.now(),
    ),
  ) catch {
    _ => ()
  }
}

///|
fn mooncode_runtime_turn_model_retry_recovered_event(
  command : Json,
  model_name : String,
  retry_count : Int,
  now~ : @clock.Timestamp,
) -> Json {
  mooncode_event(
    session_id=mooncode_json_string(command, "session_id", default=""),
    command_id=mooncode_command_id(command),
    lane="runtime",
    kind="runtime.planner_retry_recovered",
    title="MoonCode model planner provider recovered",
    status="running",
    detail="Model `\{model_name}` returned after \{retry_count} transient provider retry attempt(s); MoonClaw is continuing the preserved planner checkpoint.",
    now~,
  )
}

///|
async fn mooncode_runtime_turn_record_model_retry_recovered(
  command : Json,
  model_name : String,
  retry_count : Int,
) -> Unit {
  let book_root = mooncode_book_root(command)
  let session_id = mooncode_json_string(command, "session_id", default="")
  if book_root == "" || session_id == "" || mooncode_command_id(command) == "" {
    return
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    mooncode_runtime_turn_model_retry_recovered_event(
      command,
      model_name,
      retry_count,
      now=@clock.epoch.now(),
    ),
  ) catch {
    _ => ()
  }
}
