///|
async test "resolve_robot_target_config reads generic target from moonclaw config" {
  @fsx.with_temporary_directory("gateway-robot-config-XXXXXX", dir => {
    let home_config_dir = @path.Path(dir)
      .join(@path.Path(".moonclaw"))
      .to_string()
    @fsx.make_directory(home_config_dir, recursive=true)
    let config_path = @path.Path(home_config_dir)
      .join(@path.Path("moonclaw.json"))
      .to_string()
    let config : Json = Json::object({
      "robots": Json::object({
        "targets": Json::object({
          "robot-main": Json::object({
            "command": "/bin/sh".to_json(),
            "args": [
              "-c", "cat >/dev/null; printf '{\"status\":\"completed\"}'",
            ].to_json(),
            "cwd": "/tmp/robot-bridge".to_json(),
            "env": Json::object({ "ROBOT_DDS_DOMAIN": "17".to_json() }),
          }),
        }),
      }),
    })
    @fsx.write_to_file(config_path, config.stringify())

    let target = match
      resolve_robot_target_config(dir, "/tmp/no-project", "robot-main") {
      Ok(target) => target
      Err(error) => fail(error)
    }
    inspect(target.command, content="/bin/sh")
    inspect(target.args.length(), content="2")
    inspect(target.cwd.unwrap_or(""), content="/tmp/robot-bridge")
    inspect(target.env.get("ROBOT_DDS_DOMAIN").unwrap_or(""), content="17")
  })
}

///|
async test "analysis executor refuses robot bridge without sandbox grant" {
  @fsx.with_temporary_directory("gateway-robot-exec-XXXXXX", dir => {
    let home_config_dir = @path.Path(dir)
      .join(@path.Path(".moonclaw"))
      .to_string()
    @fsx.make_directory(home_config_dir, recursive=true)
    let config_path = @path.Path(home_config_dir)
      .join(@path.Path("moonclaw.json"))
      .to_string()
    let config : Json = Json::object({
      "robots": Json::object({
        "targets": Json::object({
          "robot-main": Json::object({
            "command": "/bin/sh".to_json(),
            "args": [
              "-c", "cat >/dev/null; printf '{\"status\":\"completed\",\"content\":\"Robot waved at the operator.\",\"metadata\":{\"action\":\"wave\"}}'",
            ].to_json(),
          }),
        }),
      }),
    })
    @fsx.write_to_file(config_path, config.stringify())

    inspect(
      match
        execute_robot_bridge_analysis(dir, "/tmp/no-project", @job.AnalysisRequest::{
          job_id: "job.robot",
          run_id: "run.robot",
          step_id: "step.robot",
          source_prompt: "Ask the robot to wave.",
          prompt: "Ask the robot to wave.",
          model_name: "default",
          cwd: dir,
          home: Some(dir),
          execution_mode: Some("robot.dds"),
          execution_target: Some("robot-main"),
          system_prompt: "Use the robot bridge.",
          preferred_skills: [],
          enable_tools: false,
          web_search: false,
          tool_contract: @job.AnalysisToolContract::new(
            shell=false,
            file_write=false,
            patch_edit=false,
          ),
          step_metadata: {},
          execution_isolation: None,
          role_runtime_contract: None,
        }) {
        Ok(_) => "unexpected execution"
        Err(error) => error
      },
      content="robot.dds robot bridge execution is disabled for target robot-main: a MoonFort ExecutionSandbox grant is required",
    )
  })
}

///|
async test "analysis executor still accepts robot.e1 as compatibility alias" {
  @fsx.with_temporary_directory("gateway-robot-e1-alias-XXXXXX", dir => {
    let home_config_dir = @path.Path(dir)
      .join(@path.Path(".moonclaw"))
      .to_string()
    @fsx.make_directory(home_config_dir, recursive=true)
    let config_path = @path.Path(home_config_dir)
      .join(@path.Path("moonclaw.json"))
      .to_string()
    let config : Json = Json::object({
      "robots": Json::object({
        "e1": Json::object({
          "targets": Json::object({
            "e1-main": Json::object({
              "command": "/bin/sh".to_json(),
              "args": [
                "-c", "cat >/dev/null; printf '{\"status\":\"completed\",\"content\":\"Compatibility alias works.\"}'",
              ].to_json(),
            }),
          }),
        }),
      }),
    })
    @fsx.write_to_file(config_path, config.stringify())

    let execution = match
      execute_robot_bridge_analysis(dir, "/tmp/no-project", @job.AnalysisRequest::{
        job_id: "job.robot",
        run_id: "run.robot",
        step_id: "step.robot",
        source_prompt: "Ask the robot to wave.",
        prompt: "Ask the robot to wave.",
        model_name: "default",
        cwd: dir,
        home: Some(dir),
        execution_mode: Some("robot.e1"),
        execution_target: Some("e1-main"),
        system_prompt: "Use the robot bridge.",
        preferred_skills: [],
        enable_tools: false,
        web_search: false,
        tool_contract: @job.AnalysisToolContract::new(
          shell=false,
          file_write=false,
          patch_edit=false,
        ),
        step_metadata: {},
        execution_isolation: None,
        role_runtime_contract: None,
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }
    inspect(execution.model_name, content="robot.e1:e1-main")
    inspect(execution.content, content="Compatibility alias works.")
  })
}

///|
async test "analysis executor forwards structured metadata to robot bridge" {
  @fsx.with_temporary_directory("gateway-robot-metadata-XXXXXX", dir => {
    let home_config_dir = @path.Path(dir)
      .join(@path.Path(".moonclaw"))
      .to_string()
    @fsx.make_directory(home_config_dir, recursive=true)
    let config_path = @path.Path(home_config_dir)
      .join(@path.Path("moonclaw.json"))
      .to_string()
    let config : Json = Json::object({
      "robots": Json::object({
        "targets": Json::object({
          "robot-main": Json::object({
            "command": "python3".to_json(),
            "args": [
              "-c", "import json,sys; payload=json.load(sys.stdin); print(json.dumps({'status':'completed','content':'ok','metadata':payload.get('metadata', {})}))",
            ].to_json(),
          }),
        }),
      }),
    })
    @fsx.write_to_file(config_path, config.stringify())

    let execution = match
      execute_robot_bridge_analysis(dir, "/tmp/no-project", @job.AnalysisRequest::{
        job_id: "job.robot",
        run_id: "run.robot",
        step_id: "step.robot",
        source_prompt: "Wave at the operator.",
        prompt: "Wave at the operator.",
        model_name: "default",
        cwd: dir,
        home: Some(dir),
        execution_mode: Some("robot.dds"),
        execution_target: Some("robot-main"),
        system_prompt: "Use the robot bridge.",
        preferred_skills: [],
        enable_tools: false,
        web_search: false,
        tool_contract: @job.AnalysisToolContract::new(
          shell=false,
          file_write=false,
          patch_edit=false,
        ),
        step_metadata: {
          "robot_action": "wave",
          "robot_params": { "arm": "right" },
          "robot_safety_class": "high_level_motion",
        },
        execution_isolation: None,
        role_runtime_contract: None,
      }) {
      Ok(execution) => execution
      Err(error) => fail(error)
    }
    let rendered = execution.metadata.stringify()
    inspect(rendered.contains("\"robot_action\":\"wave\""), content="true")
    inspect(
      rendered.contains("\"robot_safety_class\":\"high_level_motion\""),
      content="true",
    )
    inspect(rendered.contains("\"arm\":\"right\""), content="true")
  })
}
