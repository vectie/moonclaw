///|
async test "ACP runtime loads codex targets from config and persists sessions" {
  let dir = "/tmp/moonclaw-acp-runtime"
  let config_path = preferred_config_path(dir)
  @fsx.make_directory(dir, recursive=true)
  @fsx.make_directory(
    @moonsuite.product_home(dir, "moonclaw").state_path,
    recursive=true,
  )
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
async test "ACP runtime prefers product config and persists state in product home" {
  @fsx.with_temporary_directory("moonclaw-acp-runtime-product-XXXXXX", dir => {
    let home = dir + "/books/acp-book"
    @fsx.make_directory(home, recursive=true)
    let product_config = @moonsuite.product_artifact_for_workspace_root(
      home, "moonclaw", "moonclaw.json",
    )
    @fsx.make_directory(
      @moonsuite.product_home_for_workspace_root(home, "moonclaw").state_path,
      recursive=true,
    )
    @fsx.write_to_file(
      @path.Path(home).join(Path("moonclaw.json")).to_string(),
      (
        { "acp": { "targets": { "legacy-main": { "backend": "codex" } } } } :
        Json).stringify(),
    )
    @fsx.write_to_file(
      product_config,
      (
        { "acp": { "targets": { "product-main": { "backend": "codex" } } } } :
        Json).stringify(),
    )

    let runtime = AcpRuntime::new(home~, cwd=home)
    let targets = runtime.list_targets()
    inspect(targets.length(), content="1")
    inspect(targets[0].id, content="product-main")
    ignore(
      runtime.open_session("acp-session-1", "product-main", "session:1", 100),
    )
    inspect(
      @fsx.exists(
        @moonsuite.product_artifact_for_workspace_root(
          home, "moonclaw", "acp_sessions.json",
        ),
      ),
      content="true",
    )
    inspect(
      @fsx.exists(
        @path.Path(home)
        .join(Path(".moonsuite"))
        .join(Path("products"))
        .to_string(),
      ),
      content="false",
    )
  })
}

///|
async test "ACP runtime reuses existing target/session-key binding" {
  let dir = "/tmp/moonclaw-acp-runtime-reuse"
  @fsx.make_directory(dir, recursive=true)
  @fsx.make_directory(
    @moonsuite.product_home(dir, "moonclaw").state_path,
    recursive=true,
  )
  @fsx.write_to_file(
    preferred_config_path(dir),
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

///|
async test "ACP runtime lists and deletes sessions for a bound session key" {
  let dir = "/tmp/moonclaw-acp-runtime-list"
  @fsx.make_directory(dir, recursive=true)
  @fsx.make_directory(
    @moonsuite.product_home(dir, "moonclaw").state_path,
    recursive=true,
  )
  @fsx.write_to_file(
    preferred_config_path(dir),
    (
      {
        "acp": {
          "targets": {
            "codex-main": { "backend": "codex" },
            "codex-alt": { "backend": "codex" },
          },
        },
      } : Json).stringify(),
  )
  let runtime = AcpRuntime::new(home=dir, cwd=dir)
  ignore(runtime.open_session("acp-session-1", "codex-main", "session:1", 100))
  ignore(runtime.open_session("acp-session-2", "codex-alt", "session:1", 200))
  let sessions = runtime.list_sessions_for_key("session:1")
  inspect(sessions.length(), content="2")
  inspect(sessions[0].id, content="acp-session-2")
  let removed = runtime.delete_session("acp-session-1")
  inspect(
    removed.map(fn(session) { session.id }).unwrap_or(""),
    content="acp-session-1",
  )
  inspect(runtime.list_sessions_for_key("session:1").length(), content="1")
}

///|
async test "ACP runtime persists run lifecycle" {
  let dir = "/tmp/moonclaw-acp-runtime-runs"
  @fsx.make_directory(dir, recursive=true)
  @fsx.make_directory(
    @moonsuite.product_home(dir, "moonclaw").state_path,
    recursive=true,
  )
  @fsx.write_to_file(
    preferred_config_path(dir),
    ({ "acp": { "targets": { "codex-main": { "backend": "codex" } } } } : Json).stringify(),
  )
  let runtime = AcpRuntime::new(home=dir, cwd=dir)
  let session = match
    runtime.open_session("acp-session-1", "codex-main", "session:1", 100) {
    Ok(session) => session
    Err(error) => fail(error)
  }
  let target = runtime.get_target("codex-main").unwrap()
  let run = runtime.start_run(
    "acp-run-1",
    session,
    target,
    { "message": "hello" },
    { "command": "codex" },
    120,
  )
  inspect(run.status, content="running")
  let finished = match
    runtime.finish_run(
      "acp-run-1",
      "completed",
      180,
      result=Some(({ "content": "done" } : Json)),
    ) {
    Ok(run) => run
    Err(error) => fail(error)
  }
  inspect(finished.status, content="completed")
  let reloaded = AcpRuntime::new(home=dir, cwd=dir)
  inspect(reloaded.list_runs().length(), content="1")
  inspect(
    reloaded.get_run("acp-run-1").map(fn(run) { run.status }).unwrap_or(""),
    content="completed",
  )
}
