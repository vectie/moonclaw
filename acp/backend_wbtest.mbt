///|
test "prepare_launch_plan builds codex defaults" {
  let target = AcpTarget::{
    id: "codex-main",
    backend: "codex",
    label: Some("Main Codex"),
    cwd: None,
    workspace: Some("/tmp/workspace"),
    command: None,
    args: [],
    model: Some("gpt-5"),
    status: "ready",
    metadata: {},
  }
  let session = AcpSession::{
    id: "acp-session-1",
    target_id: "codex-main",
    session_key: "channel:feishu:chat-1",
    status: "attached",
    cwd: None,
    workspace: None,
    created_at: 1,
    updated_at: 1,
    last_error: None,
    metadata: {},
  }
  let request = AcpRunRequest::{
    message: "Review this repo",
    run_id: Some("run-1"),
    model: None,
    cwd: None,
    idempotency_key: None,
    metadata: None,
  }
  let plan = match prepare_launch_plan(target, session, request) {
    Ok(plan) => plan
    Err(error) => fail(error)
  }
  inspect(plan.command.unwrap_or(""), content="codex")
  inspect(plan.args.join(","), content="exec")
  inspect(plan.cwd, content="/tmp/workspace")
  inspect(plan.model.unwrap_or(""), content="gpt-5")
}

///|
test "prepare_launch_plan prefers request overrides" {
  let target = AcpTarget::{
    id: "codex-main",
    backend: "codex",
    label: None,
    cwd: Some("/tmp/default"),
    workspace: Some("/tmp/workspace"),
    command: Some("codex"),
    args: ["exec", "--json"],
    model: Some("gpt-5"),
    status: "ready",
    metadata: {},
  }
  let session = AcpSession::{
    id: "acp-session-1",
    target_id: "codex-main",
    session_key: "channel:feishu:chat-1",
    status: "attached",
    cwd: Some("/tmp/session"),
    workspace: Some("/tmp/session-workspace"),
    created_at: 1,
    updated_at: 1,
    last_error: None,
    metadata: {},
  }
  let request = AcpRunRequest::{
    message: "Do work",
    run_id: None,
    model: Some("gpt-5.1"),
    cwd: Some("/tmp/request"),
    idempotency_key: Some("idem-1"),
    metadata: None,
  }
  let plan = match prepare_launch_plan(target, session, request) {
    Ok(plan) => plan
    Err(error) => fail(error)
  }
  inspect(plan.cwd, content="/tmp/request")
  inspect(plan.model.unwrap_or(""), content="gpt-5.1")
  inspect(plan.args.join(","), content="exec,--json")
}
