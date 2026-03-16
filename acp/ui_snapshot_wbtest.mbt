///|
async test "ACP UI snapshot includes target session and run hierarchy" {
  let dir = "/tmp/moonclaw-acp-ui-snapshot"
  @fsx.make_directory(dir, recursive=true)
  @fsx.write_to_file(
    @path.Path(dir).join(@path.Path("moonclaw.json")).to_string(),
    (
      {
        "acp": {
          "targets": {
            "codex-main": {
              "backend": "codex",
              "label": "Main Codex",
              "cwd": "/tmp/workspace",
              "workspace": "/tmp/workspace",
            },
          },
        },
      } : Json).stringify(),
  )
  let runtime = AcpRuntime::new(home=dir, cwd=dir)
  let session = match
    runtime.open_session("acp-session-1", "codex-main", "session:1", 100, metadata={
      "linked_job_run_id": "job-run-1",
      "linked_job_id": "job-1",
    }) {
    Ok(session) => session
    Err(error) => fail(error)
  }
  let target = runtime.get_target("codex-main").unwrap()
  ignore(
    runtime.start_run(
      "acp-run-1",
      session,
      target,
      {
        "message": "Review repo",
        "metadata": {
          "linked_job_run_id": "job-run-1",
          "linked_job_id": "job-1",
        },
      },
      { "command": "codex" },
      120,
    ),
  )
  ignore(
    runtime.finish_run(
      "acp-run-1",
      "completed",
      180,
      result=Some(
        (
          {
            "content": "repo reviewed",
            "stdout": "repo reviewed",
            "stderr": "",
            "exit_status": 0,
          } : Json),
      ),
    ),
  )
  let snapshot = build_acp_ui_snapshot(runtime)
  inspect(snapshot.targets.length(), content="1")
  inspect(snapshot.sessions.length(), content="1")
  inspect(snapshot.runs.length(), content="1")
  inspect(snapshot.nodes.length(), content="3")
  inspect(
    snapshot.nodes[1].parent_id.unwrap_or(""),
    content="target:codex-main",
  )
  inspect(
    snapshot.nodes[2].parent_id.unwrap_or(""),
    content="session:acp-session-1",
  )
  inspect(snapshot.nodes[2].summary.unwrap_or(""), content="repo reviewed")
  inspect(
    snapshot.nodes[1].metadata.stringify(),
    content="{\"session_key\":\"session:1\",\"target_label\":[\"Main Codex\"],\"last_error\":null,\"linkage\":{\"linked_job_run_id\":\"job-run-1\",\"linked_job_id\":\"job-1\"}}",
  )
  inspect(snapshot.timeline[0].event_type, content="run.completed")
}
