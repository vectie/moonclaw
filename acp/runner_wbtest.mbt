///|
async test "execute_launch_plan refuses host execution without sandbox grant" {
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
  inspect(
    match execute_launch_plan(plan, request) {
      Ok(_) => "unexpected execution"
      Err(error) => error
    },
    content="ACP backend execution is disabled for target codex-main: a MoonFort ExecutionSandbox grant is required",
  )
}

///|
async test "execute_launch_plan never starts a configured failing backend" {
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
    content="ACP backend execution is disabled for target codex-main: a MoonFort ExecutionSandbox grant is required",
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

///|
test "changed file parser keeps path for raw and trimmed status lines" {
  inspect(
    acp_changed_file_from_status_line(" M adapters/moonclaw/run_polling.mbt").unwrap_or(
      "",
    ),
    content="adapters/moonclaw/run_polling.mbt",
  )
  inspect(
    acp_changed_file_from_status_line("M adapters/moonclaw/run_polling.mbt").unwrap_or(
      "",
    ),
    content="adapters/moonclaw/run_polling.mbt",
  )
  inspect(
    acp_changed_file_from_status_line("?? live_autonomy_wbtest.mbt").unwrap_or(
      "",
    ),
    content="live_autonomy_wbtest.mbt",
  )
}

///|
fn acp_changed_file_from_status_line(line : String) -> String? {
  let raw = line.to_string()
  if raw.trim().to_owned().is_blank() {
    return None
  }
  let chars = raw.to_array()
  if chars.length() <= 2 {
    return None
  }
  let path_start = if chars.length() > 2 && chars[2] == ' ' {
    3
  } else if chars.length() > 1 && chars[1] == ' ' {
    2
  } else if chars.length() > 3 {
    3
  } else {
    return None
  }
  let builder = StringBuilder::new()
  for index in path_start..<chars.length() {
    builder.write_char(chars[index])
  }
  Some(builder.to_string().trim().to_owned())
}

///|
async fn acp_test_git(
  cwd : String,
  operation : @trusted_host_process.GitOperation,
) -> Unit {
  let process = @trusted_host_process.run_git(cwd, operation) catch {
    error => fail(error.to_string())
  }
  if process.status() != 0 {
    fail(process.stderr())
  }
}

///|
async fn acp_git_status(cwd : String) -> String {
  let process = @trusted_host_process.run_git(cwd, StatusShort) catch {
    _ => return ""
  }
  if process.status() == 0 {
    process.stdout().trim().to_owned()
  } else {
    ""
  }
}

///|
fn acp_json_string_field(value : Json, key : String) -> String? {
  match value {
    Object(object) =>
      match object.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn acp_json_field_with_step_metadata(value : Json, key : String) -> Json? {
  match value {
    Object(object) =>
      match object.get(key) {
        Some(value) => Some(value)
        None =>
          match object.get("step_metadata") {
            Some(nested) => acp_json_field_with_step_metadata(nested, key)
            None =>
              match object.get("metadata") {
                Some(nested) => acp_json_field_with_step_metadata(nested, key)
                None => None
              }
          }
      }
    _ => None
  }
}

///|
fn acp_json_array_field(value : Json, key : String) -> Json {
  match acp_json_field_with_step_metadata(value, key) {
    Some(value) =>
      match value {
        Array(_) => return value
        _ => ()
      }
    None => ()
  }
  match value {
    Object(object) =>
      match object.get(key) {
        Some(value) =>
          match value {
            Array(_) => value
            _ => []
          }
        _ => []
      }
    _ => []
  }
}

///|
async fn acp_test_init_repo(cwd : String) -> Unit {
  acp_test_git(cwd, Init)
  @fsx.write_to_file(
    @path.Path(cwd).join(Path("README.md")).to_string(),
    "# Test\n",
  )
  acp_test_git(cwd, AddFiles(["README.md"]))
  acp_test_git(cwd, Commit("Initial commit"))
}

///|
async fn acp_execute_fixture_launch_plan(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Result[Json, String] {
  let workspace = plan.workspace.unwrap_or(plan.cwd)
  @execution_sandbox_fixture.with_fixture_moonfort(
    workspace,
    { "sh": "/bin/sh" },
    async fn(config) {
      let command = match prepare_launch_command(plan, request) {
        Ok(command) => command
        Err(error) => return Err(error)
      }
      let approved_plan = @execution_sandbox.make_exec_plan(
        config,
        workspace,
        plan.cwd,
        command.command,
        command.args,
        120_000,
      )
      execute_launch_plan_with_approved_sandbox(
        config, approved_plan, plan, request,
      )
    },
  )
}

///|
async test "approved sandbox launch records committed git patch receipt" {
  @fsx.with_temporary_directory("acp-patch-receipt-XXXXXX", async fn(dir) {
    acp_test_init_repo(dir)
    let plan = AcpLaunchPlan::{
      backend: "codex",
      target_id: "codex-main",
      session_id: "acp-session-1",
      session_key: "session:1",
      cwd: dir,
      workspace: Some(dir),
      command: Some("sh"),
      args: [
        "-c", "printf 'patched\\n' > source.txt; git add source.txt; git -c user.name='MoonClaw Test' -c user.email='moonclaw-test@local' commit -m 'ACP patch' >/dev/null; printf done",
        "runner",
      ],
      model: Some("gpt-5"),
      env: {},
      metadata: {},
    }
    let request = new_run_request(
      message="repair",
      run_id="acp-run-1",
      cwd=dir,
      metadata={
        "criterion_id": "planbook-source-patch-loop",
        "job_run_id": "run-1",
        "required_validation_commands": ["moon check --no-render"],
      },
    )
    let result = match acp_execute_fixture_launch_plan(plan, request) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    let receipt = match result {
      { "patch_receipt": receipt, .. } => receipt
      _ => fail("missing patch receipt")
    }
    inspect(
      acp_json_string_field(receipt, "contract").unwrap_or(""),
      content="planbook.repair.patch_receipt.v1",
    )
    inspect(
      acp_json_string_field(receipt, "result_decision").unwrap_or(""),
      content="accepted",
    )
    inspect(
      acp_json_string_field(receipt, "commit_status").unwrap_or(""),
      content="committed",
    )
    inspect(
      acp_json_string_field(receipt, "commit_message").unwrap_or(""),
      content="ACP patch",
    )
    inspect(
      match acp_json_array_field(receipt, "changed_files") {
        Array(files) => files.length().to_string()
        _ => "0"
      },
      content="1",
    )
    inspect(
      acp_json_string_field(receipt, "criterion_id").unwrap_or(""),
      content="planbook-source-patch-loop",
    )
    inspect(
      match acp_json_array_field(receipt, "validation_commands") {
        Array(files) => files.length().to_string()
        _ => "0"
      },
      content="1",
    )
  })
}

///|
async test "approved sandbox launch commits repair owned files after validation" {
  @fsx.with_temporary_directory("acp-runner-owned-commit-XXXXXX", async fn(
    dir,
  ) {
    acp_test_init_repo(dir)
    @fsx.write_to_file(
      @path.Path(dir).join(Path("generated.txt")).to_string(),
      "generated\n",
    )
    acp_test_git(dir, AddFiles(["generated.txt"]))
    acp_test_git(dir, Commit("Add generated baseline"))
    let target_path = @path.Path(dir).join(Path("source.txt")).to_string()
    let plan = AcpLaunchPlan::{
      backend: "codex",
      target_id: "codex-main",
      session_id: "acp-session-1",
      session_key: "session:1",
      cwd: dir,
      workspace: Some(dir),
      command: Some("sh"),
      args: [
        "-c", "printf 'patched\\n' > source.txt; printf 'generated\\n\\n' > generated.txt; printf done",
        "runner",
      ],
      model: Some("gpt-5"),
      env: {},
      metadata: {},
    }
    let result = match
      acp_execute_fixture_launch_plan(
        plan,
        new_run_request(message="repair", run_id="acp-run-1", cwd=dir, metadata={
          "criterion_id": "planbook-source-patch-loop",
          "job_run_id": "run-1",
          "target_files": [target_path],
          "git_policy": { "commit_after_validation": true },
          "required_validation_commands": ["moon check --no-render"],
          "commit_message": "Runner owned ACP commit",
        }),
      ) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    let receipt = match result {
      { "patch_receipt": receipt, .. } => receipt
      _ => fail("missing patch receipt")
    }
    inspect(
      acp_json_string_field(receipt, "result_decision").unwrap_or(""),
      content="accepted",
    )
    inspect(
      acp_json_string_field(receipt, "commit_status").unwrap_or(""),
      content="committed",
    )
    inspect(
      acp_json_string_field(receipt, "commit_message").unwrap_or(""),
      content="Runner owned ACP commit",
    )
    inspect(
      match acp_json_array_field(receipt, "changed_files") {
        Array([String(file), ..]) => file
        _ => ""
      },
      content="source.txt",
    )
    inspect(acp_git_status(dir).contains("generated.txt"), content="false")
  })
}

///|
async test "approved sandbox launch keeps paths and blocks uncommitted patches" {
  @fsx.with_temporary_directory("acp-uncommitted-receipt-XXXXXX", async fn(
    dir,
  ) {
    acp_test_init_repo(dir)
    @fsx.make_directory(
      @path.Path(dir).join(Path("adapters")).to_string(),
      recursive=true,
    )
    let plan = AcpLaunchPlan::{
      backend: "codex",
      target_id: "codex-main",
      session_id: "acp-session-1",
      session_key: "session:1",
      cwd: dir,
      workspace: Some(dir),
      command: Some("sh"),
      args: [
        "-c", "printf 'patched\\n' > adapters/source.txt; printf done", "runner",
      ],
      model: Some("gpt-5"),
      env: {},
      metadata: {},
    }
    let result = match
      acp_execute_fixture_launch_plan(
        plan,
        new_run_request(message="repair", run_id="acp-run-1", cwd=dir, metadata={
          "step_metadata": {
            "criterion_id": "planbook-source-patch-loop",
            "required_validation_commands": ["moon check --no-render"],
          },
          "job_run_id": "run-1",
        }),
      ) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    let receipt = match result {
      { "patch_receipt": receipt, .. } => receipt
      _ => fail("missing patch receipt")
    }
    inspect(
      acp_json_string_field(receipt, "result_decision").unwrap_or(""),
      content="blocked",
    )
    inspect(
      acp_json_string_field(receipt, "commit_status").unwrap_or(""),
      content="ready_to_commit",
    )
    inspect(
      match acp_json_array_field(receipt, "changed_files") {
        Array([String(file), ..]) => file
        _ => ""
      },
      content="adapters/source.txt",
    )
    inspect(
      acp_json_string_field(receipt, "criterion_id").unwrap_or(""),
      content="planbook-source-patch-loop",
    )
  })
}

///|
async test "approved sandbox launch records no-change without fake success" {
  @fsx.with_temporary_directory("acp-no-change-receipt-XXXXXX", async fn(dir) {
    acp_test_init_repo(dir)
    let plan = AcpLaunchPlan::{
      backend: "codex",
      target_id: "codex-main",
      session_id: "acp-session-1",
      session_key: "session:1",
      cwd: dir,
      workspace: Some(dir),
      command: Some("sh"),
      args: ["-c", "printf unchanged", "runner"],
      model: Some("gpt-5"),
      env: {},
      metadata: {},
    }
    let result = match
      acp_execute_fixture_launch_plan(
        plan,
        new_run_request(message="inspect", cwd=dir),
      ) {
      Ok(result) => result
      Err(error) => fail(error)
    }
    let receipt = match result {
      { "patch_receipt": receipt, .. } => receipt
      _ => fail("missing patch receipt")
    }
    inspect(
      acp_json_string_field(receipt, "result_decision").unwrap_or(""),
      content="no_change",
    )
    inspect(
      acp_json_string_field(receipt, "commit_status").unwrap_or(""),
      content="skipped_no_change",
    )
    inspect(
      match acp_json_array_field(receipt, "changed_files") {
        Array(files) => files.length().to_string()
        _ => "1"
      },
      content="0",
    )
  })
}
