///|
pub struct RuntimeContextResult {
  cwd : String
  home : String?
  run_id : String?
  job_id : String?
  step_id : String?
  model_name : String?
  execution_mode : String?
  execution_target : String?
  workspace_dir : String?
  execution_isolation : Json?
  enabled_tools : Array[String]
} derive(ToJson, FromJson)

///|
pub fn RuntimeContextResult::new(
  cwd~ : String,
  home? : String? = None,
  run_id? : String? = None,
  job_id? : String? = None,
  step_id? : String? = None,
  model_name? : String? = None,
  execution_mode? : String? = None,
  execution_target? : String? = None,
  workspace_dir? : String? = None,
  execution_isolation? : Json? = None,
  enabled_tools? : Array[String] = [],
) -> RuntimeContextResult {
  RuntimeContextResult::{
    cwd,
    home,
    run_id,
    job_id,
    step_id,
    model_name,
    execution_mode,
    execution_target,
    workspace_dir,
    execution_isolation,
    enabled_tools,
  }
}

///|
pub impl Show for RuntimeContextResult with output(
  result : RuntimeContextResult,
  logger : &Logger,
) -> Unit {
  let lines = ["CWD: \{result.cwd}"]
  if result.home is Some(home) && !home.is_blank() {
    lines.push("Home: \{home}")
  }
  if result.job_id is Some(job_id) && !job_id.is_blank() {
    lines.push("Job: \{job_id}")
  }
  if result.run_id is Some(run_id) && !run_id.is_blank() {
    lines.push("Run: \{run_id}")
  }
  if result.step_id is Some(step_id) && !step_id.is_blank() {
    lines.push("Step: \{step_id}")
  }
  if result.model_name is Some(model_name) && !model_name.is_blank() {
    lines.push("Model: \{model_name}")
  }
  if result.execution_mode is Some(mode) && !mode.is_blank() {
    lines.push("Execution mode: \{mode}")
  }
  if result.execution_target is Some(target) && !target.is_blank() {
    lines.push("Execution target: \{target}")
  }
  if result.workspace_dir is Some(workspace_dir) && !workspace_dir.is_blank() {
    lines.push("Workspace: \{workspace_dir}")
  }
  if !result.enabled_tools.is_empty() {
    let enabled = result.enabled_tools.join(", ")
    lines.push("Enabled tools: \{enabled}")
  }
  logger.write_string(lines.join("\n"))
}

///|
pub fn new(context : RuntimeContextResult) -> @tool.Tool[RuntimeContextResult] {
  @tool.new(
    name="runtime_context",
    description="Return the current MoonClaw runtime context for this analysis step, including run identity, cwd, execution target, isolation, and enabled tools.",
    schema={ "type": "object", "properties": {}, "required": [] },
    @tool.ToolFn(fn(_args) -> @tool.ToolResult[RuntimeContextResult] noraise {
      @tool.ok(context)
    }),
  )
}
