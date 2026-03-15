///|
async test "ACP runtime loads codex targets from config and persists sessions" {
  let dir = "/tmp/moonclaw-acp-runtime"
  let config_path = @path.Path(dir)
    .join(@path.Path("moonclaw.json"))
    .to_string()
  @fsx.make_directory(dir, recursive=true)
  @fsx.write_to_file(
    config_path,
    (
      {
        "acp": {
          "targets": {
            "codex-main": {
              "backend": "codex",
              "label": "Main Codex",
              "cwd": "/tmp/project",
              "workspace": "/tmp/project",
              "command": "codex",
              "args": ["exec"],
              "model": "gpt-5",
            },
          },
        },
      } : Json).stringify(),
  )

  let runtime = AcpRuntime::new(home=dir, cwd=dir)
  let targets = runtime.list_targets()
  inspect(targets.length(), content="1")
  inspect(targets[0].backend, content="codex")
  inspect(targets[0].status, content="ready")

  let session = match
    runtime.open_session(
      "acp-session-1",
      "codex-main",
      "channel:feishu:chat-1",
      100,
      metadata={ "channel": "feishu" },
    ) {
    Ok(session) => session
    Err(error) => fail(error)
  }
  inspect(session.target_id, content="codex-main")
  inspect(session.status, content="attached")

  let reloaded = AcpRuntime::new(home=dir, cwd=dir)
  inspect(reloaded.list_sessions().length(), content="1")
  inspect(
    reloaded
    .get_session("acp-session-1")
    .map(fn(session) { session.session_key })
    .unwrap_or(""),
    content="channel:feishu:chat-1",
  )
}

///|
async test "ACP runtime reuses existing target/session-key binding" {
  let dir = "/tmp/moonclaw-acp-runtime-reuse"
  @fsx.make_directory(dir, recursive=true)
  @fsx.write_to_file(
    @path.Path(dir).join(@path.Path("moonclaw.json")).to_string(),
    ({ "acp": { "targets": { "codex-main": { "backend": "codex" } } } } : Json).stringify(),
  )
  let runtime = AcpRuntime::new(home=dir, cwd=dir)
  ignore(runtime.open_session("acp-session-1", "codex-main", "session:1", 100))
  let reused = match
    runtime.open_session("acp-session-2", "codex-main", "session:1", 200) {
    Ok(session) => session
    Err(error) => fail(error)
  }
  inspect(reused.id, content="acp-session-1")
  inspect(reused.updated_at, content="200")
}
