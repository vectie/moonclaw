///|
priv struct RobotBridgeSandboxLaunch {
  execution_mode : String
  target_id : String
  target : RobotBridgeTargetConfig
  workspace : String
  working_directory : String
  capability : String
  args : Array[String]
}

///|
fn robot_bridge_request_json(request : @job.AnalysisRequest) -> Json {
  {
    "kind": "job.analysis",
    "job_id": request.job_id,
    "run_id": request.run_id,
    "step_id": request.step_id,
    "prompt": request.prompt,
    "system_prompt": request.system_prompt,
    "model_name": request.model_name,
    "cwd": request.cwd,
    "home": request.home,
    "execution_mode": request.execution_mode,
    "execution_target": request.execution_target,
    "preferred_skills": request.preferred_skills,
    "enable_tools": request.enable_tools,
    "web_search": request.web_search,
    "metadata": request.step_metadata,
  }
}

///|
async fn prepare_robot_bridge_sandbox_launch(
  home : String,
  cwd : String,
  request : @job.AnalysisRequest,
) -> Result[RobotBridgeSandboxLaunch, String] {
  let execution_mode = robot_bridge_execution_mode(request.execution_mode).unwrap_or(
    "robot.dds",
  )
  let target_id = match request.execution_target {
    Some(target_id) if !target_id.trim().to_owned().is_blank() =>
      target_id.trim().to_owned()
    _ =>
      return Err(
        "\{execution_mode} analysis execution requires execution_target",
      )
  }
  let target = match resolve_robot_target_config(home, cwd, target_id) {
    Ok(target) => target
    Err(error) => return Err(error)
  }
  guard target.env.is_empty() else {
    return Err(
      "\{execution_mode} sandbox execution refuses target environment variables until the MoonFort grant contract binds them",
    )
  }
  let args = target.args.copy()
  args.push(robot_bridge_request_json(request).stringify())
  Ok({
    execution_mode,
    target_id,
    target,
    workspace: request.cwd,
    working_directory: target.cwd.unwrap_or(request.cwd),
    capability: target.command,
    args,
  })
}

///|
fn robot_bridge_response_content(response : Json, fallback : String) -> String {
  match response {
    { "content": String(content), .. } if !content.trim().is_blank() =>
      content.trim().to_owned()
    { "message": String(content), .. } if !content.trim().is_blank() =>
      content.trim().to_owned()
    { "summary": String(content), .. } if !content.trim().is_blank() =>
      content.trim().to_owned()
    _ => fallback
  }
}

///|
fn robot_bridge_response_error(response : Json) -> String? {
  match response {
    { "error": String(error), .. } if !error.trim().is_blank() =>
      Some(error.trim().to_owned())
    { "message": String(error), "status": String(status), .. } if status
      .trim()
      .to_owned() ==
      "failed" &&
      !error.trim().is_blank() => Some(error.trim().to_owned())
    { "status": String(status), .. } if status.trim().to_owned() == "failed" =>
      Some("robot bridge reported failure")
    _ => None
  }
}

///|
fn robot_bridge_sandbox_metadata(
  response : Json,
  launch : RobotBridgeSandboxLaunch,
  receipt : @execution_sandbox.MoonFortReceipt,
) -> Json {
  let bridge_metadata = match response {
    { "metadata": Object(metadata), .. } => Json::object(metadata)
    _ => ({} : Json)
  }
  {
    "execution_mode": launch.execution_mode,
    "execution_target": launch.target_id,
    "bridge_capability": launch.capability,
    "bridge_args": launch.target.args,
    "bridge_cwd": launch.working_directory,
    "bridge_metadata": bridge_metadata,
    "sandbox": {
      "approval_id": receipt.approval_id,
      "approval_digest": receipt.approval_digest,
      "backend": receipt.backend,
      "enforcement": receipt.enforcement,
      "cleanup_verified": receipt.cleanup_verified,
      "profile_digest": receipt.profile_digest,
    },
  }
}

///|
/// Consume a pre-approved typed MoonFort plan for one robot bridge request.
/// The request payload is an exact final argument in the approved plan; target
/// executables and environment variables cannot be selected after approval.
#warnings("-unused_value")
async fn execute_robot_bridge_analysis_with_approved_sandbox(
  config : @execution_sandbox.SandboxExecutorConfig,
  approved_plan : @execution_sandbox.SandboxApprovalPlan,
  home : String,
  cwd : String,
  request : @job.AnalysisRequest,
) -> Result[@job.AnalysisExecution, String] {
  let launch = match prepare_robot_bridge_sandbox_launch(home, cwd, request) {
    Ok(launch) => launch
    Err(error) => return Err(error)
  }
  let execution = @execution_sandbox.run_approved_exec(
    config,
    launch.workspace,
    launch.working_directory,
    launch.capability,
    launch.args,
    approved_plan,
  ) catch {
    error =>
      return Err(
        "MoonFort \{launch.execution_mode} execution failed closed: \{error}",
      )
  }
  let receipt = execution.receipt
  guard receipt.status is Exited && receipt.exit_code is Some(status) else {
    return Err("MoonFort robot bridge omitted a terminal exit status")
  }
  guard !receipt.output_truncated else {
    return Err("MoonFort robot bridge output is incomplete")
  }
  if status != 0 {
    return Err(@acp.process_output_summary(receipt.output, "", status))
  }
  let output = receipt.output.trim().to_owned()
  let response : Json = if output.is_blank() {
    ({} : Json)
  } else {
    @json.parse(output) catch {
      _ =>
        return Ok({
          model_name: "\{launch.execution_mode}:\{launch.target_id}",
          content: output,
          conversation_id: None,
          usage: None,
          metadata: robot_bridge_sandbox_metadata({}, launch, receipt),
        })
    }
  }
  match robot_bridge_response_error(response) {
    Some(error) => return Err(error)
    None => ()
  }
  Ok({
    model_name: "\{launch.execution_mode}:\{launch.target_id}",
    content: robot_bridge_response_content(response, output),
    conversation_id: None,
    usage: None,
    metadata: robot_bridge_sandbox_metadata(response, launch, receipt),
  })
}
