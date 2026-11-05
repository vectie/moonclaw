///|
fn mooncode_runtime_operation_id(
  command_id : String,
  step : Int32,
  index : Int32,
) -> String {
  "\{command_id}:\{step}:\{index}"
}

///|
fn mooncode_runtime_operation_record(
  events : Array[Json],
  operation_id : String,
  kind : String,
) -> Json? {
  for event in events.rev() {
    if mooncode_json_string(event, "operation_id", default="") == operation_id &&
      mooncode_json_string(event, "operation_state", default="") == kind &&
      ["moonclaw-native-runtime-continuation", "moonclaw-native-tool-exec"].contains(
        mooncode_json_string(event, "source", default=""),
      ) {
      return Some(mooncode_runtime_unproject_journal_event(event))
    }
  }
  None
}

///|
fn mooncode_runtime_checkpoint_with_intent(
  checkpoint : Json,
  operation_id : String,
  call : Json,
) -> Json {
  checkpoint
  |> mooncode_json_object_with_field("operation_id", Json(operation_id))
  |> mooncode_json_object_with_field("operation_state", "started")
  |> mooncode_json_object_with_field(
    "call_digest",
    Json(mooncode_sha256_hex(call.stringify())),
  )
}

///|
fn mooncode_runtime_operation_recovery(
  events : Array[Json],
  session_id : String,
  book_root : String,
  command_id : String,
  operation_id : String,
  call : Json,
  now~ : @clock.Timestamp,
) -> Json? raise {
  match mooncode_runtime_operation_record(events, operation_id, "completed") {
    Some(record) if mooncode_json_string(record, "call_digest", default="") ==
      mooncode_sha256_hex(call.stringify()) => {
      let compact = mooncode_json_object_field_or_empty(record, "execution")
      let execution = mooncode_json_object_with_field(
        compact,
        "result",
        mooncode_json_object_field_or_empty(record, "tool_result"),
      )
      return Some(mooncode_json_object_with_field(execution, "event", record))
    }
    Some(_) =>
      raise InvalidJournal(
        "operation identity was reused with a different tool call",
      )
    None => ()
  }
  guard mooncode_runtime_operation_record(events, operation_id, "started")
    is Some(intent) else {
    return None
  }
  if mooncode_json_string(intent, "call_digest", default="") !=
    mooncode_sha256_hex(call.stringify()) {
    raise InvalidJournal("operation intent differs from the resumed call")
  }
  // Repeating a local observation is safe. An uncommitted effect is not a
  // failure receipt: let the same agent inspect the workspace/backend first.
  let tool = mooncode_json_string(call, "tool", default="")
  if mooncode_runtime_tool_policy(call).replay {
    return None
  }
  let result = mooncode_tool_error_result(
    tool,
    message="Execution was interrupted after its durable intent and has no committed result. Reconcile the actual workspace or backend receipt before retrying the effect.",
    metadata={
      "outcome_unknown": true,
      "operation_id": operation_id,
      "tool_call": call,
    },
  )
  Some(
    mooncode_tool_execution(
      session_id,
      book_root,
      command_id,
      tool,
      mooncode_json_object_field_or_empty(call, "arguments"),
      result,
      now~,
    ),
  )
}

///|
fn mooncode_runtime_operation_finished(
  operation_id : String,
  call : Json,
  execution : Json,
  step~ : Int32,
  index~ : Int32,
) -> Json {
  let compact : Map[String, Json] = Map([])
  if execution is Object(fields) {
    for key, value in fields {
      if key != "result" && key != "event" {
        compact[key] = value
      }
    }
  }
  let event = mooncode_json_object_field_or_empty(execution, "event")
    |> mooncode_json_object_with_field(
      "id",
      Json("moonclaw-operation-" + operation_id),
    )
    |> mooncode_json_object_with_field("operation_id", Json(operation_id))
    |> mooncode_json_object_with_field("planner_step", Json(step + 1))
    |> mooncode_json_object_with_field(
      "tool_call_id",
      Json(mooncode_runtime_turn_tool_call_id(call, step=step + 1, index~)),
    )
    |> mooncode_json_object_with_field("operation_state", "completed")
    |> mooncode_json_object_with_field(
      "call_digest",
      Json(mooncode_sha256_hex(call.stringify())),
    )
    |> mooncode_json_object_with_field("execution", Json::object(compact))
  mooncode_json_object_with_field(execution, "event", event)
}
