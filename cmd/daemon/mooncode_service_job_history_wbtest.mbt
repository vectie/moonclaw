///|
test "Code job history keeps separate durable runs and terminal reasons" {
  let events : Array[Json] = [
    {
      "id": "start-1",
      "kind": "runtime.service_started",
      "service_id": "service",
      "created_at": "2026-09-26T00:00:00Z",
    },
    {
      "id": "finish-1",
      "kind": "runtime.service_finished",
      "service_id": "service",
      "status": "waiting",
      "stopped_by": "approval",
      "ran_turn_count": 1,
      "created_at": "2026-09-26T00:01:00Z",
    },
    {
      "id": "start-2",
      "kind": "runtime.service_started",
      "service_id": "service",
      "created_at": "2026-09-26T00:02:00Z",
    },
    {
      "id": "fail-2",
      "kind": "runtime.service_failed",
      "service_id": "service",
      "status": "failed",
      "detail": "executor unavailable",
      "created_at": "2026-09-26T00:03:00Z",
    },
    {
      "id": "start-3",
      "kind": "runtime.service_started",
      "service_id": "service",
      "created_at": "2026-09-26T00:04:00Z",
    },
  ]
  let history = mooncode_service_job_history_projection(
    "session", events, false,
  )
  let jobs = mooncode_json_array_items(history, "jobs")
  assert_eq(jobs.length(), 3)
  assert_eq(mooncode_json_string(jobs[0], "run_id", default=""), "start-3")
  assert_eq(mooncode_json_string(jobs[0], "status", default=""), "interrupted")
  assert_eq(mooncode_json_string(jobs[1], "status", default=""), "failed")
  assert_eq(mooncode_json_string(jobs[2], "status", default=""), "waiting")
  assert_eq(mooncode_json_string(jobs[2], "stopped_by", default=""), "approval")
  assert_eq(mooncode_json_int(jobs[2], "ran_turn_count", default=0), 1)
  let live = mooncode_service_job_history_projection("session", events, true)
  assert_eq(
    mooncode_json_string(
      mooncode_json_array_items(live, "jobs")[0],
      "status",
      default="",
    ),
    "running",
  )
  assert_eq(mooncode_job_detail_preview("🛠️ 汉字"), "🛠️ 汉字")
}
