///|
/// A run starts with a durable service event and settles with a durable
/// finish/failure event. An unmatched start after restart is interrupted.
fn mooncode_job_detail_preview(detail : String) -> String {
  let out = StringBuilder()
  let mut count = 0
  for ch in detail {
    if count >= 400 {
      break
    }
    out.write_char(ch)
    count += 1
  }
  out.to_string()
}

///|
fn mooncode_service_job_history_projection(
  session_id : String,
  events : Array[Json],
  live_running : Bool,
) -> Json {
  let jobs : Array[Json] = []
  let mut active = -1
  for ordinal, event in events {
    let kind = mooncode_json_string(event, "kind", default="")
    let service_id = mooncode_json_string(event, "service_id", default="")
    let created_at = mooncode_json_string(event, "created_at", default="")
    if kind == "runtime.service_started" {
      if active >= 0 {
        jobs[active] = mooncode_json_object_with_field(
          jobs[active],
          "status",
          "interrupted".to_json(),
        )
      }
      let event_id = mooncode_json_string(event, "id", default="")
      jobs.push({
        "run_id": if event_id == "" {
          "service-run-\{ordinal}"
        } else {
          event_id
        },
        "service_id": service_id,
        "status": "running",
        "started_at": created_at,
        "finished_at": "",
        "ran_turn_count": 0,
        "failed_turn_count": 0,
        "stopped_by": "",
        "detail": "",
      })
      active = jobs.length() - 1
    } else if kind == "runtime.service_finished" ||
      kind == "runtime.service_failed" {
      let target = if active >= 0 &&
        mooncode_json_string(jobs[active], "service_id", default="") ==
        service_id {
        active
      } else {
        jobs.push({
          "run_id": mooncode_json_string(
            event,
            "id",
            default="service-run-\{ordinal}",
          ),
          "service_id": service_id,
          "status": "interrupted",
          "started_at": "",
          "finished_at": "",
          "ran_turn_count": 0,
          "failed_turn_count": 0,
          "stopped_by": "",
          "detail": "",
        })
        jobs.length() - 1
      }
      let status = if kind == "runtime.service_failed" {
        "failed"
      } else {
        mooncode_json_string(event, "status", default="unknown")
      }
      let detail = mooncode_json_string(event, "detail", default="")
      jobs[target] = jobs[target]
        |> mooncode_json_object_with_field("status", status.to_json())
        |> mooncode_json_object_with_field("finished_at", created_at.to_json())
        |> mooncode_json_object_with_field(
          "ran_turn_count",
          mooncode_json_int(event, "ran_turn_count", default=0).to_json(),
        )
        |> mooncode_json_object_with_field(
          "failed_turn_count",
          mooncode_json_int(event, "failed_turn_count", default=0).to_json(),
        )
        |> mooncode_json_object_with_field(
          "stopped_by",
          mooncode_json_string(event, "stopped_by", default="").to_json(),
        )
        |> mooncode_json_object_with_field(
          "detail",
          mooncode_job_detail_preview(detail).to_json(),
        )
      active = -1
    }
  }
  if active >= 0 && !live_running {
    jobs[active] = mooncode_json_object_with_field(
      jobs[active],
      "status",
      "interrupted".to_json(),
    )
  }
  let recent : Array[Json] = []
  let mut index = jobs.length() - 1
  while index >= 0 && recent.length() < 50 {
    recent.push(jobs[index])
    index -= 1
  }
  {
    "kind": "mooncode-job-history.v1",
    "owner": "moonclaw",
    "session_id": session_id,
    "job_count": jobs.length(),
    "truncated": jobs.length() > recent.length(),
    "jobs": Json::array(recent),
  }
}

///|
async fn Daemon::mooncode_runtime_service_job_history(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
  let book_root = mooncode_request_book_root(r)
  guard self.mooncode_session_record(session_id, book_root) is Some(_) else {
    raise json_error(404, "Not Found", {
      "error": { "code": -1, "message": "MoonCode session not found" },
    })
  }
  let live_running = match self.mooncode_sessions.get(session_id) {
    Some(binding) if binding.book_root == book_root =>
      binding.runtime_service_running
    _ => false
  }
  let history = mooncode_service_job_history_projection(
    session_id,
    self.mooncode_runtime_service_events(session_id, book_root),
    live_running,
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(history.stringify())
}
