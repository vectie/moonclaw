///|
/// Worker ownership is the command captured by spawn, not the latest message or
/// service stop in the child session. Read only that linked session's journal.
async fn mooncode_worker_result_projection(record : Json) -> Json {
  let child_session_id = mooncode_json_string(
    record,
    "child_session_id",
    default="",
  )
  let child_book_root = mooncode_json_string(
    record,
    "child_book_root",
    default="",
  )
  let child_command_id = mooncode_json_string(
    record,
    "child_command_id",
    default="",
  )
  let service_id = mooncode_json_string(record, "service_id", default="")
  let journal = mooncode_read_session_journal(child_book_root, child_session_id)
  let service_events = mooncode_journal_entries(
    journal,
    mooncode_journal_event(),
  ).filter(event => {
    let kind = mooncode_json_string(event, "kind", default="")
    kind == "runtime.service_started" ||
    kind == "runtime.service_finished" ||
    kind == "runtime.service_failed"
  })
  let service = mooncode_runtime_service_state_payload(
    child_session_id,
    child_book_root,
    service_events,
    service_id~,
  )
  // Approval resume may start a new service id; lifecycle liveness is session
  // scoped, while terminal outcome and all returned content remain command scoped.
  let current_service = mooncode_runtime_service_state_payload(
    child_session_id,
    child_book_root,
    service_events,
    service_id="",
  )
  let mut receipt_record = Json::object({})
  let mut checkpoint_record = Json::object({})
  let mut failure_record = Json::object({})
  let mut command_started = false
  let result_records : Array[Json] = []
  for entry in journal {
    let payload = mooncode_json_object_field_or_empty(entry, "payload")
    if child_command_id == "" ||
      mooncode_json_string(payload, "session_id", default="") !=
      child_session_id ||
      mooncode_json_string(payload, "command_id", default="") !=
      child_command_id {
      continue
    }
    let kind = mooncode_json_string(entry, "record_kind", default="")
    if kind == mooncode_journal_runtime_receipt() {
      receipt_record = entry
    } else if kind == mooncode_journal_event() {
      let event_kind = mooncode_json_string(payload, "kind", default="")
      if event_kind == "runtime.turn_started" {
        command_started = true
        checkpoint_record = Json::object({})
      } else if event_kind == mooncode_runtime_continuation_kind() {
        checkpoint_record = entry
      }
      let tool = mooncode_json_string(payload, "tool", default="")
      let tool_result = mooncode_json_object_field_or_empty(
        payload, "tool_result",
      )
      if mooncode_json_bool(tool_result, "is_error", default=false) {
        failure_record = entry
      }
      let event_name = mooncode_json_string(payload, "event", default="")
      if (
          (event_name == "tool_result" && (tool == "write" || tool == "edit")) ||
          (event_name == "patch_applied" && tool == "apply_patch")
        ) &&
        mooncode_json_bool(tool_result, "ok", default=false) &&
        !mooncode_json_bool(tool_result, "is_error", default=false) {
        result_records.push(entry)
      }
    } else if kind == mooncode_journal_book_result() ||
      kind == mooncode_journal_package_result() {
      result_records.push(entry)
    }
  }
  let receipt = mooncode_json_object_field_or_empty(receipt_record, "payload")
  let receipt_status = mooncode_json_string(receipt, "status", default="")
  let terminal = receipt_status == "runtime-completed" ||
    receipt_status == "runtime-failed" ||
    receipt_status == "runtime-cancelled"
  let successful = receipt_status == "runtime-completed"
  let checkpoint = mooncode_json_object_field_or_empty(
    checkpoint_record, "payload",
  )
  let checkpoint_state = mooncode_json_string(checkpoint, "state", default="")
  let service_status = mooncode_json_string(
    current_service,
    "status",
    default="idle",
  )
  let status = if successful {
    "done"
  } else if receipt_status == "runtime-failed" {
    "failed"
  } else if receipt_status == "runtime-cancelled" {
    "cancelled"
  } else if checkpoint_state == "awaiting-approval" {
    "waiting"
  } else if mooncode_json_string(checkpoint, "status", default="") == "paused" {
    "paused"
  } else if service_status == "waiting" {
    "waiting"
  } else if service_status == "failed" || service_status == "cancelled" {
    "interrupted"
  } else if service_status == "running" &&
    (command_started || receipt_status == "runtime-claimed") {
    "running"
  } else if receipt_status == "runtime-claimed" || command_started {
    "pending"
  } else {
    "queued"
  }
  let pending : Json = if terminal {
    Json::object({})
  } else {
    let approval = mooncode_json_object_field_or_empty(checkpoint, "approval")
    {
      "state": if checkpoint_state != "" {
        checkpoint_state
      } else {
        status
      },
      "target_command_id": child_command_id,
      "approval_id": mooncode_json_string(checkpoint, "approval_id", default=""),
      "tool_call_id": mooncode_json_string(approval, "tool_call_id", default=""),
      "reason": mooncode_json_string(checkpoint, "reason", default=""),
      "checkpoint_reference": mooncode_worker_journal_reference(
        record, checkpoint_record,
      ),
    }
  }
  let answer = if successful {
    mooncode_worker_receipt_answer(receipt)
  } else {
    ""
  }
  let capped = mooncode_cap_tool_output(answer, 16000)
  let result_references : Array[Json] = []
  let artifact_references : Array[Json] = []
  let seen_artifacts : Map[String, Bool] = Map([])
  let mut results_truncated = false
  let mut artifacts_truncated = false
  if terminal {
    for entry in result_records {
      let source = mooncode_worker_journal_reference(record, entry)
      let payload = mooncode_json_object_field_or_empty(entry, "payload")
      if result_references.length() < 32 {
        result_references.push({
          "source": source,
          "result_id": mooncode_json_string(payload, "result_id", default=""),
          "path": mooncode_worker_artifact_path(
            mooncode_json_string(
              payload,
              "result_path",
              default=mooncode_json_string(payload, "path", default=""),
            ),
          ),
        })
      } else {
        results_truncated = true
      }
      let paths : Array[String] = []
      if mooncode_json_string(entry, "record_kind", default="") ==
        mooncode_journal_book_result() {
        paths.push(mooncode_json_string(payload, "result_path", default=""))
        let book_result = mooncode_json_object_field_or_empty(
          payload, "book_result",
        )
        for artifact in mooncode_json_array_items(book_result, "artifacts") {
          if artifact is String(path) {
            paths.push(path)
          }
        }
      } else if mooncode_json_string(entry, "record_kind", default="") ==
        mooncode_journal_package_result() {
        for
          path in mooncode_runtime_turn_book_result_artifacts(
            [payload],
            result_path="",
          ) {
          paths.push(path)
        }
      } else {
        paths.push(mooncode_json_string(payload, "path", default=""))
        for path in mooncode_json_array_items(payload, "changed_paths") {
          if path is String(path) {
            paths.push(path)
          }
        }
      }
      for path in paths {
        let normalized = mooncode_worker_artifact_path(path)
        // References do not grant filesystem access, and may only describe a
        // relative path in the linked child. Never dereference their contents.
        if normalized == "" || seen_artifacts.contains(normalized) {
          continue
        }
        seen_artifacts[normalized] = true
        if artifact_references.length() < 64 {
          artifact_references.push({
            "child_session_id": child_session_id,
            "child_book_root": child_book_root,
            "child_command_id": child_command_id,
            "path": normalized,
            "source": source,
            "access": "reference-only",
          })
        } else {
          artifacts_truncated = true
        }
      }
    }
  }
  {
    "worker_id": mooncode_json_string(record, "worker_id", default=""),
    "child_session_id": child_session_id,
    "child_book_root": child_book_root,
    "child_command_id": child_command_id,
    "service_id": service_id,
    "status": status,
    "running": status == "running",
    "terminal": terminal,
    "successful": successful,
    "terminal_evidence": if terminal {
      mooncode_worker_terminal_evidence(record, receipt_record, failure_record)
    } else {
      Json::object({})
    },
    "service_status": mooncode_json_string(service, "status", default="idle"),
    "service_running": mooncode_json_bool(service, "running", default=false),
    "current_service_status": service_status,
    "service_evidence": mooncode_json_object_field_or_empty(
      service, "latest_event",
    ),
    "pending": pending,
    "result": {
      "answer": mooncode_json_string(capped, "output", default=""),
      "answer_truncated": mooncode_json_bool(capped, "truncated", default=false),
      "receipt_reference": if terminal {
        mooncode_worker_journal_reference(record, receipt_record)
      } else {
        Json::object({})
      },
      "result_references": Json::array(result_references),
      "result_references_truncated": results_truncated,
      "artifact_references": Json::array(artifact_references),
      "artifact_references_truncated": artifacts_truncated,
      "artifact_access": "reference-only",
    },
  }
}

///|
fn mooncode_worker_journal_reference(link : Json, entry : Json) -> Json {
  let record_id = mooncode_json_string(entry, "record_id", default="")
  if record_id == "" {
    return Json::object({})
  }
  {
    "session_id": mooncode_json_string(link, "child_session_id", default=""),
    "book_root": mooncode_json_string(link, "child_book_root", default=""),
    "command_id": mooncode_json_string(link, "child_command_id", default=""),
    "record_kind": mooncode_json_string(entry, "record_kind", default=""),
    "record_id": record_id,
    "sequence": mooncode_json_string(entry, "sequence", default=""),
    "claim_id": mooncode_json_string(
      mooncode_json_object_field_or_empty(entry, "payload"),
      "claim_id",
      default="",
    ),
  }
}

///|
fn mooncode_worker_receipt_answer(receipt : Json) -> String {
  let execution = mooncode_json_object_field_or_empty(receipt, "execution")
  let mut answer = ""
  for result in mooncode_json_array_items(execution, "tool_results") {
    if mooncode_json_string(result, "tool", default="") != "finish" ||
      !mooncode_json_bool(result, "accepted", default=false) {
      continue
    }
    // Native receipts retain tool executions with a nested result. Older
    // compact receipts may retain the direct finish payload instead.
    let nested = mooncode_json_object_field_or_empty(result, "result")
    let tool_result = if nested is Object(fields) && fields.length() > 0 {
      nested
    } else {
      result
    }
    if mooncode_json_bool(tool_result, "is_error", default=false) {
      continue
    }
    let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
    answer = mooncode_json_string(
      metadata,
      "answer",
      default=mooncode_json_string(tool_result, "output", default=""),
    )
  }
  answer
}

///|
fn mooncode_worker_artifact_path(path : String) -> String {
  let normalized = @pathx.normalize(path)
  if path == "" ||
    normalized == "." ||
    normalized == ".." ||
    normalized.has_prefix("../") ||
    @pathx.is_absolute(normalized) {
    ""
  } else {
    normalized
  }
}

///|
fn mooncode_worker_terminal_evidence(
  link : Json,
  receipt_record : Json,
  failure_record : Json,
) -> Json {
  let receipt = mooncode_json_object_field_or_empty(receipt_record, "payload")
  let failure = mooncode_json_object_field_or_empty(failure_record, "payload")
  let failed_tool = mooncode_json_object_field_or_empty(failure, "tool_result")
  let failure_reason = mooncode_json_string(failed_tool, "message", default="")
  let use_failure = mooncode_json_string(receipt, "status", default="") ==
    "runtime-failed" &&
    failure_reason != ""
  let reason = if use_failure {
    failure_reason
  } else {
    mooncode_json_string(receipt, "message", default="")
  }
  let capped = mooncode_cap_tool_output(reason, 2000)
  let evidence = mooncode_json_object_with_field(
    mooncode_runtime_receipt_compact(receipt),
    "reference",
    mooncode_worker_journal_reference(link, receipt_record),
  )
  let evidence = mooncode_json_object_with_field(
    evidence,
    "reason",
    mooncode_json_string(capped, "output", default="").to_json(),
  )
  let evidence = mooncode_json_object_with_field(
    evidence,
    "reason_truncated",
    mooncode_json_bool(capped, "truncated", default=false).to_json(),
  )
  mooncode_json_object_with_field(
    evidence,
    "reason_reference",
    mooncode_worker_journal_reference(
      link,
      if use_failure {
        failure_record
      } else {
        receipt_record
      },
    ),
  )
}
