///|
#warnings("-20-27")
struct RobotBridgeTargetConfig {
  command : String
  args : Array[String]
  cwd : String?
  env : Map[String, String]
} derive(ToJson, FromJson, Show)

///|
async fn robot_bridge_config_json(home : String, cwd : String) -> Json? {
  let project_path = @path.Path(cwd)
    .join(Path(".moonclaw"))
    .join(Path("moonclaw.json"))
    .to_string()
  let home_root_path = @path.Path(home).join(Path("moonclaw.json")).to_string()
  let user_path = @path.Path(home)
    .join(Path(".moonclaw"))
    .join(Path("moonclaw.json"))
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
      let trimmed = mode.trim().to_owned()
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
          let result : Map[String, String] = Map([])
          for key, entry in entries {
            match entry {
              String(text) => result[key] = text
              _ => ()
            }
          }
          Some(result)
        }
        (_, Some(Object(entries))) => {
          let result : Map[String, String] = Map([])
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
    Some(command) if !command.trim().to_owned().is_blank() => command
    _ => return Err("Robot bridge target config is missing command")
  }
  let args = json_string_array_field(value, "args", "args").unwrap_or([])
  let cwd = match
    (
      json_string_field(value, "cwd", "cwd"),
      json_string_field(value, "working_directory", "workingDirectory"),
    ) {
    (Some(cwd), _) if !cwd.trim().to_owned().is_blank() => Some(cwd)
    (_, Some(cwd)) if !cwd.trim().to_owned().is_blank() => Some(cwd)
    _ => None
  }
  let env = json_string_map_field(value, "env", "env").unwrap_or({})
  Ok({ command, args, cwd, env })
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
// Retained as a white-box contract helper for legacy configuration migration.
#warnings("-unused_value")
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
// Retained as a white-box assertion of the fail-closed MoonFort boundary.
#warnings("-unused_value")
fn execute_robot_bridge_analysis(
  home : String,
  cwd : String,
  request : @job.AnalysisRequest,
) -> Result[@job.AnalysisExecution, String] {
  let execution_mode = robot_bridge_execution_mode(request.execution_mode).unwrap_or(
    "robot.dds",
  )
  let target_id = match request.execution_target {
    Some(target_id) if !target_id.trim().to_owned().is_blank() => target_id
    _ =>
      return Err(
        "\{execution_mode} analysis execution requires execution_target",
      )
  }
  ignore(home)
  ignore(cwd)
  Err(
    "\{execution_mode} robot bridge execution is disabled for target \{target_id}: a MoonFort ExecutionSandbox grant is required",
  )
}
