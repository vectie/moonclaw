///|
async test "execute_launch_plan runs configured codex command" {
  let plan = AcpLaunchPlan::{
    backend: "codex",
    target_id: "codex-main",
    session_id: "acp-session-1",
    session_key: "channel:feishu:chat-1",
    cwd: "/tmp",
    workspace: Some("/tmp"),
    command: Some("sh"),
    args: ["-c", "printf '%s|%s' \"$ACP_SESSION_ID\" \"$1\"", "runner"],
    model: Some("gpt-5"),
    env: { "ACP_SESSION_ID": "acp-session-1", "ACP_BACKEND": "codex" },
    metadata: {},
  }
  let request = new_run_request(message="review-this", cwd="/tmp")
  let result = match execute_launch_plan(plan, request) {
    Ok(result) => result
    Err(error) => fail(error)
  }
  inspect(
    match result {
      { "status": String(status), .. } => status
      _ => ""
    },
    content="completed",
  )
  inspect(
    match result {
      { "content": String(content), .. } => content
      _ => ""
    },
    content="acp-session-1|review-this",
  )
}

///|
async test "execute_launch_plan reports backend failure" {
  let plan = AcpLaunchPlan::{
    backend: "codex",
    target_id: "codex-main",
    session_id: "acp-session-1",
    session_key: "channel:feishu:chat-1",
    cwd: "/tmp",
    workspace: None,
    command: Some("sh"),
    args: ["-c", "echo backend-failed 1>&2; exit 7"],
    model: None,
    env: {},
    metadata: {},
  }
  let request = new_run_request(message="ignored")
  inspect(
    match execute_launch_plan(plan, request) {
      Ok(_) => "ok"
      Err(error) => error
    },
    content="backend-failed",
  )
}

///|
test "prepare_launch_command does not mutate stored plan args" {
  let plan = AcpLaunchPlan::{
    backend: "codex",
    target_id: "codex-main",
    session_id: "acp-session-1",
    session_key: "channel:feishu:chat-1",
    cwd: "/tmp",
    workspace: Some("/tmp"),
    command: Some("codex"),
    args: ["exec"],
    model: Some("gpt-5"),
    env: {},
    metadata: {},
  }
  let first = match
    prepare_launch_command(plan, new_run_request(message="first prompt")) {
    Ok(command) => command
    Err(error) => fail(error)
  }
  let second = match
    prepare_launch_command(plan, new_run_request(message="second prompt")) {
    Ok(command) => command
    Err(error) => fail(error)
  }
  inspect(first.args.join("|"), content="exec|first prompt")
  inspect(second.args.join("|"), content="exec|second prompt")
  inspect(plan.args.join("|"), content="exec")
}
