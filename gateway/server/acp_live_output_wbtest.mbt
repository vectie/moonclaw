///|
test "stdio_content_preview prefers stdout over stderr" {
  assert_true(
    stdio_content_preview({ "stdout": "hello\n", "stderr": "warn\n" })
    is Some("hello"),
  )
}

///|
test "live_acp_output_timeline_entry emits live output event with linkage" {
  let run : @acp.AcpRun = @json.from_json({
    "id": "run-1",
    "session_id": "session-1",
    "session_key": "key-1",
    "target_id": "target-1",
    "backend": "codex",
    "status": "running",
    "created_at": 10,
    "updated_at": 20,
    "request": {
      "message": "review repo",
      "metadata": {
        "linked_job_run_id": "job-run-1",
        "linked_job_node_id": "node-1",
      },
    },
    "plan": {},
  })
  let event = live_acp_output_timeline_entry(
    run,
    { "stdout": "partial output", "stderr": "" },
    30,
  ).unwrap()
  assert_eq(event.id, "run-output:run-1:14:0")
  assert_eq(event.event_type, "run.output")
  assert_eq(event.detail, "partial output")
  assert_eq(event.timestamp, 30)
  assert_true(event.status is Some("running"))
  let data = event.data.stringify()
  assert_true(data.contains("\"stdout\":\"partial output\""))
  assert_true(data.contains("\"linked_job_run_id\":\"job-run-1\""))
  assert_true(data.contains("\"live\":true"))
}
