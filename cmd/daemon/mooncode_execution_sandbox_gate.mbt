///|
let mooncode_fixture_sandbox_configs : Map[
  String,
  @execution_sandbox.SandboxExecutorConfig,
] = Map([])

///|
let mooncode_fixture_sandbox_configs_lock : @semaphore.Semaphore = Semaphore(1)

///|
async fn mooncode_install_fixture_sandbox_config(
  book_root : String,
  config : @execution_sandbox.SandboxExecutorConfig,
) -> Unit {
  let canonical_root = @fsx.resolve(book_root)
  mooncode_fixture_sandbox_configs_lock.acquire()
  defer mooncode_fixture_sandbox_configs_lock.release()
  guard !mooncode_fixture_sandbox_configs.contains(canonical_root) else {
    fail(
      "MoonFort fixture configuration is already installed for this MoonBook",
    )
  }
  mooncode_fixture_sandbox_configs[canonical_root] = config
}

///|
async fn mooncode_remove_fixture_sandbox_config(book_root : String) -> Unit {
  let canonical_root = @fsx.resolve(book_root)
  mooncode_fixture_sandbox_configs_lock.acquire()
  defer mooncode_fixture_sandbox_configs_lock.release()
  mooncode_fixture_sandbox_configs.remove(canonical_root)
}

///|
async fn mooncode_fixture_sandbox_config(
  book_root : String,
) -> @execution_sandbox.SandboxExecutorConfig? {
  if book_root == "" {
    return None
  }
  let canonical_root = @fsx.resolve(book_root) catch { _ => return None }
  mooncode_fixture_sandbox_configs_lock.acquire()
  defer mooncode_fixture_sandbox_configs_lock.release()
  mooncode_fixture_sandbox_configs.get(canonical_root)
}

///|
async fn mooncode_execution_sandbox_config(
  tool : String,
  book_root? : String = "",
) -> Result[@execution_sandbox.SandboxExecutorConfig, Json] {
  match mooncode_fixture_sandbox_config(book_root) {
    Some(config) => return Ok(config)
    None => ()
  }
  let config = @moonfort_config.load_sandbox_executor_config() catch {
    error =>
      return Err(
        mooncode_tool_error_result(
          tool,
          message="ExecutionSandbox configuration failed closed: \{error}",
          metadata={
            "execution_sandbox_required": true,
            "execution_sandbox_configured": true,
            "execution_sandbox_policy": "fail-closed",
          },
        ),
      )
  }
  match config {
    Some(config) => Ok(config)
    None => Err(mooncode_execution_sandbox_refusal(tool))
  }
}

///|
fn mooncode_sandbox_evidence(
  execution : @execution_sandbox.SandboxExecution,
) -> Json {
  let receipt = execution.receipt
  let output_artifact : Json = match receipt.output_artifact {
    None => Json::null()
    Some(artifact) =>
      {
        "artifact_id": artifact.artifact_id,
        "run_id": artifact.run_id,
        "sha256": artifact.sha256,
        "size_bytes": artifact.size_bytes,
        "media_type": artifact.media_type,
        "expires_at_ms": artifact.expires_at_ms,
      }
  }
  {
    "approval_digest": receipt.approval_digest,
    "approval_plan_digest": execution.plan.expected_approval_digest,
    "backend": receipt.backend,
    "enforcement": receipt.enforcement,
    "cleanup_verified": receipt.cleanup_verified,
    "profile_digest": receipt.profile_digest,
    "command_digest": receipt.command_digest,
    "limit_reason": receipt.limit_reason,
    "unverified_limits": receipt.unverified_limits,
    "changed_paths": receipt.changed_paths,
    "changes": receipt.changes,
    "artifacts": receipt.artifacts,
    "output_artifact": output_artifact,
    "retention_id": receipt.retention_id,
    "requested_policy": {
      "backend": execution.plan.grant.backend,
      "enforcement_requirement": execution.plan.grant.enforcement_requirement,
      "network": execution.plan.grant.network,
      "allowed_egress": execution.plan.grant.allowed_egress,
      "allowed_commands": execution.plan.grant.allowed_commands,
      "limits": execution.plan.grant.limits,
      "working_directory": execution.plan.grant.working_directory,
    },
  }
}

///|
fn mooncode_sandbox_terminal_result(
  tool : String,
  execution : @execution_sandbox.SandboxExecution,
  expected_exit_code : Int,
  max_output_chars : Int,
  metadata : Json,
) -> Json {
  let receipt = execution.receipt
  guard receipt.status is Exited && receipt.exit_code is Some(exit_code) else {
    return mooncode_tool_error_result(
      tool,
      message="MoonFort did not return a terminal exit receipt",
      output=receipt.output,
      metadata={
        "execution_sandbox_required": true,
        "execution_sandbox_configured": true,
        "execution_sandbox_policy": "fail-closed",
        "approval_plan_digest": execution.plan.expected_approval_digest,
        "approval_id": receipt.approval_id,
        "run_id": receipt.run_id,
        "sandbox_evidence": mooncode_sandbox_evidence(execution),
      },
    )
  }
  let capped = if exit_code == expected_exit_code {
    mooncode_cap_tool_output(receipt.output, max_output_chars)
  } else {
    mooncode_cap_failed_process_output(receipt.output, max_output_chars)
  }
  guard metadata is Object(fields) else {
    return mooncode_tool_error_result(
      tool,
      message="ExecutionSandbox result metadata is invalid",
    )
  }
  fields["exit_code"] = exit_code.to_json()
  fields["status"] = exit_code.to_json()
  fields["truncated"] = mooncode_json_bool(capped, "truncated", default=false).to_json()
  fields["execution_sandbox_required"] = true.to_json()
  fields["execution_sandbox_configured"] = true.to_json()
  fields["execution_sandbox_policy"] = "grant-bound".to_json()
  fields["approval_plan_digest"] = execution.plan.expected_approval_digest.to_json()
  fields["approval_id"] = receipt.approval_id.to_json()
  fields["run_id"] = receipt.run_id.to_json()
  fields["profile_digest"] = receipt.profile_digest.to_json()
  fields["sandbox_evidence"] = mooncode_sandbox_evidence(execution)
  let output = mooncode_json_string(capped, "output", default="")
  if exit_code == expected_exit_code {
    mooncode_tool_ok_result(
      tool,
      message="\{tool} completed inside ExecutionSandbox",
      output~,
      metadata~,
    )
  } else {
    mooncode_tool_error_result(
      tool,
      message="\{tool} exited with status \{exit_code} inside ExecutionSandbox",
      output~,
      metadata~,
    )
  }
}

///|
fn mooncode_approved_sandbox_plan(
  arguments : Json,
) -> @execution_sandbox.SandboxApprovalPlan raise {
  guard arguments is { "_execution_sandbox_plan": plan, .. } else {
    fail("operator-approved ExecutionSandbox plan is required")
  }
  @json.from_json(plan) catch {
    _ => fail("operator-approved ExecutionSandbox plan is malformed")
  }
}

///|
/// Freeze the exact shell grant before MoonCode emits its human approval
/// request. The resulting JSON is journaled with that request and is the only
/// plan accepted after approval.
async fn mooncode_prepare_shell_approval_plan(
  book_root : String,
  arguments : Json,
) -> Result[@execution_sandbox.SandboxApprovalPlan, Json] {
  let cmd = mooncode_json_string(arguments, "cmd", default="")
  if cmd == "" {
    return Err(
      mooncode_tool_error_result("shell", message="cmd must be non-empty"),
    )
  }
  if mooncode_json_bool(arguments, "background", default=false) {
    return Err(
      mooncode_tool_error_result(
        "shell",
        message="background execution is not supported by the one-shot ExecutionSandbox contract",
      ),
    )
  }
  let cwd = mooncode_tool_cwd(book_root, arguments)
  if !mooncode_json_bool(cwd, "ok", default=false) {
    return Err(
      mooncode_tool_error_result(
        "shell",
        message=mooncode_json_string(cwd, "message", default="invalid cwd"),
      ),
    )
  }
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
  match mooncode_shell_boundary_error(book_root, cwd_path, cmd) {
    Some(message) => return Err(mooncode_tool_error_result("shell", message~))
    None => ()
  }
  let config = match mooncode_execution_sandbox_config("shell", book_root~) {
    Err(refusal) => return Err(refusal)
    Ok(config) => config
  }
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=30000)
  let plan = @execution_sandbox.make_sandbox_plan(
    config, book_root, cwd_path, cmd, timeout,
  ) catch {
    error =>
      return Err(
        mooncode_tool_error_result(
          "shell",
          message="Failed to prepare MoonFort approval plan: \{error}",
        ),
      )
  }
  Ok(plan)
}

///|
async fn mooncode_prepare_moon_cmd_approval_plan(
  book_root : String,
  arguments : Json,
) -> Result[@execution_sandbox.SandboxApprovalPlan, Json] {
  let command = mooncode_json_string(arguments, "command", default="")
  if !mooncode_moon_cmd_supported(command) {
    return Err(
      mooncode_tool_error_result(
        "moon_cmd",
        message="unsupported moon_cmd command: \{command}",
      ),
    )
  }
  let selector = mooncode_moon_cmd_primary_path(arguments)
  let explicit_cwd = mooncode_json_string(arguments, "cwd", default="") != ""
  let cwd = if explicit_cwd {
    mooncode_tool_cwd(book_root, arguments)
  } else {
    mooncode_moon_module_cwd_for_path(book_root, selector)
  }
  if !mooncode_json_bool(cwd, "ok", default=false) {
    return Err(
      mooncode_tool_error_result(
        "moon_cmd",
        message=mooncode_json_string(cwd, "message", default="invalid cwd"),
      ),
    )
  }
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
  let selector_root = if explicit_cwd { cwd_path } else { book_root }
  let args = mooncode_moon_cmd_args(
    arguments,
    command,
    selector_root~,
    cwd_path~,
  )
  let config = match mooncode_execution_sandbox_config("moon_cmd", book_root~) {
    Err(refusal) => return Err(refusal)
    Ok(config) => config
  }
  let plan = @execution_sandbox.make_exec_plan(
    config,
    book_root,
    cwd_path,
    "moon",
    args,
    mooncode_json_int(arguments, "timeout_ms", default=60000),
  ) catch {
    error =>
      return Err(
        mooncode_tool_error_result(
          "moon_cmd",
          message="Failed to prepare MoonFort approval plan: \{error}",
        ),
      )
  }
  Ok(plan)
}

///|
fn mooncode_execution_sandbox_refusal(tool : String) -> Json {
  mooncode_tool_error_result(
    tool,
    message="native execution refused: no configured ExecutionSandbox route is available",
    metadata={
      "execution_sandbox_required": true,
      "execution_sandbox_configured": false,
      "execution_sandbox_policy": "fail-closed",
    },
  )
}

///|
fn mooncode_patch_verification_sandbox_refusal() -> Json {
  {
    "ok": false,
    "tool": "execution_sandbox",
    "message": "post-change verification refused: no configured ExecutionSandbox route is available",
    "execution_sandbox_required": true,
    "execution_sandbox_configured": false,
    "execution_sandbox_policy": "fail-closed",
  }
}

///|
/// MoonCode process tools have a MoonFort-only implementation. Availability of
/// a particular deployment is still checked by the operator-owned config
/// loader at every call and never implies an unsandboxed fallback.
#warnings("-unused_value")
fn mooncode_execution_sandbox_route_available() -> Bool {
  true
}
