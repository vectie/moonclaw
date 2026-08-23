///|
pub struct AcpLaunchCommand {
  command : String
  args : Array[String]
  env : Map[String, String]
} derive(ToJson, FromJson, Debug)

///|
fn launch_arguments(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Array[String] {
  let args = plan.args.map(fn(arg) { arg })
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
  let env = Map([])
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
pub fn process_output_summary(
  stdout : String,
  stderr : String,
  status : Int,
) -> String {
  let stdout = stdout.trim().to_owned()
  let stderr = stderr.trim().to_owned()
  if !stdout.is_blank() {
    stdout
  } else if !stderr.is_blank() {
    stderr
  } else {
    "Codex backend exited with status \{status}"
  }
}

///|
pub fn prepare_launch_command(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Result[AcpLaunchCommand, String] {
  let command = match plan.command {
    Some(command) => command
    None =>
      return Err(
        "ACP launch plan is missing a command for backend \{plan.backend}",
      )
  }
  Ok({
    command,
    args: launch_arguments(plan, request),
    env: launch_env(plan, request),
  })
}

///|
#warnings("-unused_async")
pub async fn execute_launch_plan(
  plan : AcpLaunchPlan,
  request : AcpRunRequest,
) -> Result[Json, String] {
  ignore(request)
  Err(
    "ACP backend execution is disabled for target \{plan.target_id}: a MoonFort ExecutionSandbox grant is required",
  )
}
