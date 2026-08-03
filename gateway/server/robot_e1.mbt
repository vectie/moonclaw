///|
struct RobotBridgeTargetConfig {
  command : String
  args : Array[String]
  cwd : String?
  env : Map[String, String]
} derive(ToJson, FromJson, Show)

///|
async fn robot_bridge_config_json(home : String, cwd : String) -> Json? {
  let project_path = @path.Path(cwd)
    .join(@path.Path(".moonclaw"))
    .join(@path.Path("moonclaw.json"))
    .to_string()
  let home_root_path = @path.Path(home)
    .join(@path.Path("moonclaw.json"))
    .to_string()
  let user_path = @path.Path(home)
    .join(@path.Path(".moonclaw"))
    .join(@path.Path("moonclaw.json"))
    .to_string()
  let home_root_json = if @fsx.exists(home_root_path) {
    let text = @fsx.read_file(home_root_path) catch { _ => return None }
    Some(@json.parse(text) catch { _ => return None })
  } else {
    None
  }
  let user_json = if @fsx.exists(user_path) {
    let text = @fsx.read_file(user_path) catch { _ => return home_root_json }
    Some(@json.parse(text) catch { _ => return home_root_json })
  } else {
    home_root_json
  }
  let project_json = if @fsx.exists(project_path) {
    let text = @fsx.read_file(project_path) catch { _ => return user_json }
    Some(@json.parse(text) catch { _ => return user_json })
  } else {
    None
  }
  match project_json {
    Some(json) => Some(json)
    None => user_json
  }
}

///|
fn robot_bridge_execution_mode(mode : String?) -> String? {
  match mode {
    Some(mode) => {
      let trimmed = mode.trim().to_string()
      if trimmed == "robot.dds" || trimmed == "robot.e1" {
        Some(trimmed)
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn robot_bridge_execution_requested(mode : String?) -> Bool {
  robot_bridge_execution_mode(mode) is Some(_)
}

///|
fn robots_json_root(config : Json) -> Json? {
  match config {
    Object(root) =>
      match root.get("robots") {
        Some(Object(robots)) => Some(Json::object(robots))
        _ => None
      }
    _ => None
  }
}

///|
fn json_string_array_field(
  value : Json,
  snake : String,
  camel : String,
) -> Array[String]? {
  match value {
    Object(obj) =>
      match (obj.get(snake), obj.get(camel)) {
        (Some(Array(values)), _) => {
          let strings : Array[String] = []
          for item in values {
            match item {
              String(text) => strings.push(text)
              _ => ()
            }
          }
          Some(strings)
        }
        (_, Some(Array(values))) => {
          let strings : Array[String] = []
          for item in values {
            match item {
              String(text) => strings.push(text)
              _ => ()
            }
          }
          Some(strings)
        }
        _ => None
      }
    _ => None
  }
}

///|
fn json_string_map_field(
  value : Json,
  snake : String,
  camel : String,
) -> Map[String, String]? {
  match value {
    Object(obj) =>
      match (obj.get(snake), obj.get(camel)) {
        (Some(Object(entries)), _) => {
          let result : Map[String, String] = {}
          for key, entry in entries {
            match entry {
              String(text) => result[key] = text
              _ => ()
            }
          }
          Some(result)
        }
        (_, Some(Object(entries))) => {
          let result : Map[String, String] = {}
          for key, entry in entries {
            match entry {
              String(text) => result[key] = text
              _ => ()
            }
          }
          Some(result)
        }
        _ => None
      }
    _ => None
  }
}

///|
fn robot_target_config_from_json(
  value : Json,
) -> Result[RobotBridgeTargetConfig, String] {
  let command = match json_string_field(value, "command", "command") {
    Some(command) if !command.trim().to_string().is_blank() => command
    _ => return Err("Robot bridge target config is missing command")
  }
  let args = json_string_array_field(value, "args", "args").unwrap_or([])
  let cwd = match
    (
      json_string_field(value, "cwd", "cwd"),
      json_string_field(value, "working_directory", "workingDirectory"),
    ) {
    (Some(cwd), _) if !cwd.trim().to_string().is_blank() => Some(cwd)
    (_, Some(cwd)) if !cwd.trim().to_string().is_blank() => Some(cwd)
    _ => None
  }
  let env = json_string_map_field(value, "env", "env").unwrap_or({})
  Ok(RobotBridgeTargetConfig::{ command, args, cwd, env })
}

///|
fn generic_robot_target_from_root(root : Json, target_id : String) -> Json? {
  match root {
    Object(robots) =>
      match robots.get("targets") {
        Some(Object(targets)) => targets.get(target_id)
        _ => None
      }
    _ => None
  }
}

///|
fn legacy_e1_target_from_root(root : Json, target_id : String) -> Json? {
  match root {
    Object(robots) =>
      match robots.get("e1") {
        Some(Object(e1)) =>
          match e1.get("targets") {
            Some(Object(targets)) => targets.get(target_id)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
async fn resolve_robot_target_config(
  home : String,
  cwd : String,
  target_id : String,
) -> Result[RobotBridgeTargetConfig, String] {
  let config = match robot_bridge_config_json(home, cwd) {
    Some(config) => config
    None => return Err("Missing moonclaw.json configuration for robot bridge")
  }
  let robots = match robots_json_root(config) {
    Some(robots) => robots
    None => return Err("Missing robots configuration")
  }
  let target = match generic_robot_target_from_root(robots, target_id) {
    Some(target) => target
    None =>
      match legacy_e1_target_from_root(robots, target_id) {
        Some(target) => target
        None => return Err("Unknown robot target: \{target_id}")
      }
  }
  robot_target_config_from_json(target)
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
fn robot_bridge_response_content(response : Json, fallback : String) -> String {
  match response {
    { "content": String(content), .. } if !content.trim().to_string().is_blank() =>
      content.trim().to_string()
    { "message": String(content), .. } if !content.trim().to_string().is_blank() =>
      content.trim().to_string()
    { "summary": String(content), .. } if !content.trim().to_string().is_blank() =>
      content.trim().to_string()
    _ => fallback
  }
}

///|
fn robot_bridge_response_metadata(
  response : Json,
  execution_mode : String,
  target_id : String,
  target : RobotBridgeTargetConfig,
  cwd : String,
) -> Json {
  let bridge_metadata = match response {
    { "metadata": Object(metadata), .. } => Json::object(metadata)
    _ => ({} : Json)
  }
  Json::object({
    "execution_mode": execution_mode,
    "execution_target": target_id,
    "bridge_command": target.command,
    "bridge_args": target.args,
    "bridge_cwd": cwd,
    "bridge_metadata": bridge_metadata,
  })
}

///|
fn robot_bridge_error(response : Json) -> String? {
  match response {
    { "error": String(error), .. } if !error.trim().to_string().is_blank() =>
      Some(error.trim().to_string())
    { "message": String(error), "status": String(status), .. } if status
      .trim()
      .to_string() ==
      "failed" &&
      !error.trim().to_string().is_blank() => Some(error.trim().to_string())
    { "status": String(status), .. } if status.trim().to_string() == "failed" =>
      Some("robot bridge reported failure")
    _ => None
  }
}

///|
async fn execute_robot_bridge_analysis(
  home : String,
  cwd : String,
  request : @job.AnalysisRequest,
) -> Result[@job.AnalysisExecution, String] {
  let execution_mode = robot_bridge_execution_mode(request.execution_mode).unwrap_or(
    "robot.dds",
  )
  let target_id = match request.execution_target {
    Some(target_id) if !target_id.trim().to_string().is_blank() => target_id
    _ =>
      return Err(
        "\{execution_mode} analysis execution requires execution_target",
      )
  }
  let target = match resolve_robot_target_config(home, cwd, target_id) {
    Ok(target) => target
    Err(error) => return Err(error)
  }
  let bridge_cwd = target.cwd.unwrap_or(request.cwd)
  let env = target.env
  env["MOONCLAW_ROBOT_EXECUTION_MODE"] = execution_mode
  env["MOONCLAW_ROBOT_TARGET_ID"] = target_id
  env["MOONCLAW_JOB_ID"] = request.job_id
  env["MOONCLAW_RUN_ID"] = request.run_id
  env["MOONCLAW_STEP_ID"] = request.step_id
  let process = @spawn.spawn(
    target.command[:],
    target.args.map(fn(arg) { arg[:] }),
    stdin=robot_bridge_request_json(request).stringify(indent=2),
    cwd=bridge_cwd[:],
    env~,
  ) catch {
    error => return Err("Failed to start robot bridge: \{error}")
  }
  if process.status != 0 {
    return Err(
      @acp.process_output_summary(
        process.stdout,
        process.stderr,
        process.status,
      ),
    )
  }
  let stdout = process.stdout.trim().to_string()
  let response : Json = if stdout.is_blank() {
    ({} : Json)
  } else {
    @json.parse(stdout) catch {
      _ =>
        return Ok(@job.AnalysisExecution::{
          model_name: "\{execution_mode}:\{target_id}",
          content: stdout,
          conversation_id: None,
          usage: None,
          metadata: robot_bridge_response_metadata(
            {},
            execution_mode,
            target_id,
            target,
            bridge_cwd,
          ),
        })
    }
  }
  match robot_bridge_error(response) {
    Some(error) => return Err(error)
    None => ()
  }
  Ok(@job.AnalysisExecution::{
    model_name: "\{execution_mode}:\{target_id}",
    content: robot_bridge_response_content(response, stdout),
    conversation_id: None,
    usage: None,
    metadata: robot_bridge_response_metadata(
      response, execution_mode, target_id, target, bridge_cwd,
    ),
  })
}

///|
async fn Gateway::execute_analysis_via_robot_e1(
  self : Gateway,
  request : @job.AnalysisRequest,
) -> Result[@job.AnalysisExecution, String] {
  execute_robot_bridge_analysis(self.home, self.cwd, request)
}
