///|
async test "ACP UI timeline orders newest entries first" {
  let dir = "/tmp/moonclaw-acp-ui-events"
  @fsx.make_directory(dir, recursive=true)
  @fsx.write_to_file(
    @path.Path(dir).join(@path.Path("moonclaw.json")).to_string(),
    ({ "acp": { "targets": { "codex-main": { "backend": "codex" } } } } : Json).stringify(),
  )
  let runtime = AcpRuntime::new(home=dir, cwd=dir)
  let session = match
    runtime.open_session("acp-session-1", "codex-main", "session:1", 100) {
    Ok(session) => session
    Err(error) => fail(error)
  }
  let target = runtime.get_target("codex-main").unwrap()
  ignore(
    runtime.start_run(
      "acp-run-1",
      session,
      target,
      { "message": "hello" },
      { "command": "codex" },
      120,
    ),
  )
  let timeline = build_acp_ui_timeline(runtime)
  inspect(timeline.length(), content="2")
  inspect(timeline[0].id, content="run:acp-run-1")
  inspect(timeline[1].id, content="session:acp-session-1")
}
