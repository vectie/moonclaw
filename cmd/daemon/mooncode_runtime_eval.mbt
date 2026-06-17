///|
async fn mooncode_runtime_turn_eval_results(
  session_id : String,
  book_root : String,
  command : Json,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let native_eval = mooncode_native_eval_harness_report(session_id, now~)
  let record : Json = {
    "kind": "mooncode-session-record",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command_log_count": 1,
    "event_log_count": 0,
    "package_result_log_count": 0,
  }
  let report = mooncode_eval_report_payload(
    session_id,
    None,
    Some(record),
    Some(native_eval),
    now~,
  )
  let manifest = mooncode_runtime_turn_eval_manifest(
    session_id,
    book_root,
    command,
    report,
    now~,
  )
  let relative = mooncode_runtime_turn_eval_manifest_relative_path(session_id)
  mooncode_runtime_turn_write_json_manifest(book_root, relative, manifest)
  [
    {
      "kind": "mooncode-eval-result",
      "protocol": mooncode_protocol_version(),
      "event": "eval_report.manifest",
      "accepted": mooncode_json_bool(report, "ok", default=false),
      "session_id": session_id,
      "book_root": book_root,
      "command_id": mooncode_command_id(command),
      "manifest_path": relative,
      "absolute_manifest_path": @pathx.join(book_root, relative),
      "native_eval_report": report,
      "manifest": manifest,
      "created_at": now,
      "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
      "owner": mooncode_runtime_turn_eval_owner(),
    },
  ]
}

///|
fn mooncode_runtime_turn_eval_manifest(
  session_id : String,
  book_root : String,
  command : Json,
  report : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let relative = mooncode_runtime_turn_eval_manifest_relative_path(session_id)
  {
    "kind": "mooncode-eval-report",
    "protocol": mooncode_protocol_version(),
    "status": if mooncode_json_bool(report, "ok", default=false) {
      "accepted"
    } else {
      "failed"
    },
    "session_id": session_id,
    "book_root": book_root,
    "command_id": mooncode_command_id(command),
    "manifest_path": relative,
    "absolute_manifest_path": @pathx.join(book_root, relative),
    "native_eval_evidence_ready": mooncode_json_bool(
      report,
      "ok",
      default=false,
    ),
    "native_eval_source": mooncode_json_string(report, "source", default=""),
    "native_eval_endpoint": "/v1/mooncode/sessions/\{session_id}/eval-report?book_root=<path>",
    "native_eval_ingest_method": "moonclaw-runtime-turn",
    "native_eval_ingest_endpoint": "/v1/mooncode/sessions/\{session_id}/runtime-turn?book_root=<path>",
    "native_eval_report": report,
    "last_command_packet": mooncode_json_object_field_or_empty(
      command, "packet",
    ),
    "recorded_at": now,
    "owner": mooncode_runtime_turn_eval_owner(),
  }
}

///|
fn mooncode_runtime_turn_eval_manifest_relative_path(
  session_id : String,
) -> String {
  "wiki/reviews/mooncode/\{mooncode_safe_session_id(session_id)}/eval-report.json"
}

///|
fn mooncode_runtime_turn_eval_event(
  session_id : String,
  command_id : String,
  command : Json,
  eval_result : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let accepted = mooncode_json_bool(eval_result, "accepted", default=false)
  let manifest = mooncode_json_object_field_or_empty(eval_result, "manifest")
  let path = mooncode_json_string(eval_result, "manifest_path", default="")
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-eval-report-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": mooncode_book_root(command),
    "command_id": command_id,
    "lane": "review",
    "kind": "eval_report.manifest",
    "event": "eval_report.manifest",
    "title": "MoonCode eval report",
    "status": if accepted {
      "accepted"
    } else {
      "failed"
    },
    "detail": if accepted {
      "MoonClaw native runtime-turn wrote eval report proof at \{path}."
    } else {
      "MoonClaw native runtime-turn eval proof failed; see \{path}."
    },
    "path": path,
    "manifest_path": path,
    "eval_result": eval_result,
    "eval_report_manifest": manifest,
    "command": "run_eval",
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_eval_owner() -> Json {
  {
    "ui": "moondesk",
    "runtime": "moonclaw",
    "artifact": "moonbook",
    "review": "moonbook",
    "extractable_component": "mooncode",
  }
}
