///|
async fn Daemon::mooncode_eval_report(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
  let book_root = mooncode_request_book_root(r)
  let record = if book_root == "" {
    None
  } else {
    self.mooncode_session_record(session_id, book_root)
  }
  let report = mooncode_eval_report_payload(
    session_id,
    self.mooncode_sessions.get(session_id),
    record,
    Some(mooncode_native_eval_harness_report(session_id, now=self.clock.now())),
    now=self.clock.now(),
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(report.stringify(indent=2))
}

///|
fn mooncode_eval_report_payload(
  session_id : String,
  binding : MoonCodeSessionBinding?,
  record : Json?,
  native_eval : Json?,
  now~ : @clock.Timestamp,
) -> Json {
  let record_value = record.unwrap_or(Json::object({}))
  let command_count = match binding {
    Some(binding) => binding.command_count
    None => mooncode_json_int(record_value, "command_log_count", default=0)
  }
  let event_count = mooncode_json_int(
    record_value,
    "event_log_count",
    default=0,
  )
  let package_result_count = mooncode_json_int(
    record_value,
    "package_result_log_count",
    default=0,
  )
  let record_ready = mooncode_json_string(record_value, "kind", default="") ==
    "mooncode-session-record"
  let eval_status = mooncode_eval_harness_status(native_eval)
  let native_harnesses = mooncode_eval_harnesses_or_empty(native_eval)
  let harness_status = if eval_status == "passed" {
    "accepted"
  } else if command_count > 0 {
    "partial"
  } else {
    "pending"
  }
  {
    "kind": "mooncode-native-eval-report",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "ok": eval_status == "passed",
    "book_root": mooncode_json_string(record_value, "book_root", default=""),
    "source": if record_ready && binding is None {
      "moonclaw-native-sidecar"
    } else if binding is Some(_) {
      "moonclaw-native-live-binding"
    } else {
      "moonclaw-native-runtime"
    },
    "status": if eval_status == "passed" {
      "accepted"
    } else if command_count > 0 {
      "partial"
    } else {
      "pending"
    },
    "generated_at": now,
    "required_harnesses": ["tool_harness", "file_edit"],
    "passed_count": if eval_status == "passed" {
      native_harnesses.length()
    } else {
      0
    },
    "failed_count": if eval_status == "passed" {
      0
    } else {
      native_harnesses.length()
    },
    "evidence": [
      if native_harnesses.length() > 0 {
        "MoonClaw native eval harness status: \{eval_status}"
      } else {
        "MoonClaw native eval harness has not run."
      },
    ],
    "harnesses": [
      {
        "id": "native-command-ingest",
        "status": if command_count > 0 {
          "passed"
        } else {
          "pending"
        },
        "evidence": "MoonClaw accepted \{command_count} native MoonCode command(s) for this session.",
      },
      {
        "id": "durable-sidecar-replay",
        "status": if record_ready {
          "passed"
        } else {
          "pending"
        },
        "evidence": "MoonClaw replayed \{event_count} event(s) and \{package_result_count} package result(s) from the selected book's native sidecar.",
      },
      {
        "id": "tool-loop-execution",
        "status": harness_status,
        "evidence": if native_harnesses.length() > 0 {
          "MoonClaw ran \{native_harnesses.length()} native MoonCode tool/file-edit harness(es); status=\{eval_status}."
        } else {
          "MoonClaw has not published native MoonCode tool/file-edit harness evidence yet."
        },
      },
    ],
    "native_eval": native_eval.unwrap_or(Json::object({})),
    "binding": match binding {
      Some(binding) => binding.to_json()
      None => Json::object({})
    },
    "session_record": record_value,
  }
}
