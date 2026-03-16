///|
fn launch_arguments(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Array[String] {
  let args = plan.args
  if !request.message.trim().is_blank() {
    args.push(request.message)
  }
  args
}

///|
fn launch_env(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Map[String, String] {
  let env = {}
  match plan.env {
    Object(entries) =>
      for key, value in entries {
        match value {
          String(text) => env[key] = text
          Null => ()
          _ => env[key] = value.stringify()
        }
      }
    _ => ()
  }
  env["ACP_MESSAGE"] = request.message
  env
}

///|
fn codex_output_summary(process : @spawn.CompletedProcess) -> String {
  let stdout = process.stdout.trim().to_string()
  let stderr = process.stderr.trim().to_string()
  if !stdout.is_blank() {
    stdout
  } else if !stderr.is_blank() {
    stderr
  } else {
    "Codex backend exited with status \{process.status}"
  }
}

///|
pub async fn execute_launch_plan(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Result[Json, String] {
  let command = match plan.command {
    Some(command) => command
    None =>
      return Err(
        "ACP launch plan is missing a command for backend \{plan.backend}",
      )
  }
  if plan.backend == "codex" &&
    command == "codex" &&
    !@codex.credentials_exist() {
    return Err(
      "Codex credentials are not available. Authenticate first with the Codex OAuth flow.",
    )
  }
  let arguments = launch_arguments(plan, request)
  let env = launch_env(plan, request)
  let process = @spawn.spawn(
    command,
    arguments.map(fn(arg) { arg }),
    cwd=plan.cwd,
    env~,
  ) catch {
    error => return Err("Failed to start ACP backend: \{error}")
  }
  let result : Json = {
    "backend": plan.backend,
    "target_id": plan.target_id,
    "session_id": plan.session_id,
    "session_key": plan.session_key,
    "cwd": plan.cwd,
    "workspace": plan.workspace,
    "command": command,
    "args": arguments,
    "status": if process.status == 0 {
      "completed"
    } else {
      "failed"
    },
    "exit_status": process.status,
    "stdout": process.stdout,
    "stderr": process.stderr,
    "elapsed_ms": process.elapsed,
    "content": codex_output_summary(process),
  }
  if process.status == 0 {
    Ok(result)
  } else {
    Err(codex_output_summary(process))
  }
}
