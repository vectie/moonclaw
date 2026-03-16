///|
test "stdio_content_preview prefers stdout over stderr" {
  inspect(
    stdio_content_preview({ "stdout": "hello\n", "stderr": "warn\n" }),
    content="Some(\"hello\")",
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
  inspect(
    live_acp_output_timeline_entry(
      run,
      { "stdout": "partial output", "stderr": "" },
      30,
    )
    .unwrap()
    .to_json()
    .stringify(),
    content="{\"id\":\"run-output:run-1:14:0\",\"event_type\":\"run.output\",\"title\":\"Run output streaming\",\"detail\":\"partial output\",\"timestamp\":30,\"target_id\":\"target-1\",\"session_id\":\"session-1\",\"run_id\":\"run-1\",\"status\":\"running\",\"data\":{\"stdout_stderr\":{\"stdout\":\"partial output\",\"stderr\":\"\"},\"linkage\":{\"linked_job_run_id\":\"job-run-1\",\"linked_job_node_id\":\"node-1\"},\"live\":true}}",
  )
}
