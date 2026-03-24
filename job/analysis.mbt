///|
pub(all) struct AnalysisPolicy {
  timeout_ms : Int?
  max_total_tokens : Int?
  skip_if_artifact_exists : Bool
} derive(ToJson, FromJson, Show)

///|
pub fn AnalysisPolicy::new(
  timeout_ms? : Int? = None,
  max_total_tokens? : Int? = None,
  skip_if_artifact_exists? : Bool = false,
) -> AnalysisPolicy {
  AnalysisPolicy::{ timeout_ms, max_total_tokens, skip_if_artifact_exists }
}

///|
pub(all) struct AnalysisArtifactConfig {
  report_artifact_type : String
  result_artifact_type : String
  logical_key : String?
  report_file_name : String?
  result_file_name : String?
  scope : Array[String]
  append_only : Bool
} derive(ToJson, FromJson, Show)

///|
pub fn AnalysisArtifactConfig::new(
  report_artifact_type? : String = "analysis.report",
  result_artifact_type? : String = "analysis.result",
  logical_key? : String? = None,
  report_file_name? : String? = None,
  result_file_name? : String? = None,
  scope? : Array[String] = [],
  append_only? : Bool = true,
) -> AnalysisArtifactConfig {
  AnalysisArtifactConfig::{
    report_artifact_type,
    result_artifact_type,
    logical_key,
    report_file_name,
    result_file_name,
    scope,
    append_only,
  }
}

///|
pub(all) struct AnalysisStepConfig {
  prompt : String
  model : String?
  cwd : String?
  home : String?
  workspace : String?
  execution_mode : String?
  execution_target : String?
  system_prompt : String?
  preferred_skills : Array[String]
  enable_tools : Bool
  web_search : Bool
  policy : AnalysisPolicy
  artifacts : AnalysisArtifactConfig
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub fn AnalysisStepConfig::new(
  prompt~ : String,
  model? : String? = None,
  cwd? : String? = None,
  home? : String? = None,
  workspace? : String? = None,
  execution_mode? : String? = None,
  execution_target? : String? = None,
  system_prompt? : String? = None,
  preferred_skills? : Array[String] = [],
  enable_tools? : Bool = true,
  web_search? : Bool = false,
  policy? : AnalysisPolicy = AnalysisPolicy::new(),
  artifacts? : AnalysisArtifactConfig = AnalysisArtifactConfig::new(),
  metadata? : Json = {},
) -> AnalysisStepConfig {
  AnalysisStepConfig::{
    prompt,
    model,
    cwd,
    home,
    workspace,
    execution_mode,
    execution_target,
    system_prompt,
    preferred_skills,
    enable_tools,
    web_search,
    policy,
    artifacts,
    metadata,
  }
}

///|
pub(all) struct AnalysisRequest {
  job_id : String
  run_id : String
  step_id : String
  prompt : String
  model_name : String
  cwd : String
  home : String?
  execution_mode : String?
  execution_target : String?
  system_prompt : String
  preferred_skills : Array[String]
  enable_tools : Bool
  web_search : Bool
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AnalysisExecution {
  model_name : String
  content : String
  conversation_id : String?
  usage : @ai.Usage?
  metadata : Json
} derive(Show)

///|
pub(all) struct AnalysisExecutor {
  run : async (AnalysisRequest) -> Result[AnalysisExecution, String]
}

///|
pub fn AnalysisExecutor::new(
  run~ : async (AnalysisRequest) -> Result[AnalysisExecution, String],
) -> AnalysisExecutor {
  AnalysisExecutor::{ run, }
}

///|
fn default_analysis_system_prompt() -> String {
  [
    @prompt.prelude, "You are executing a job workflow analysis step.", "Produce a concise, grounded report using the provided context.",
  ].join("\n\n")
}

///|
pub fn analysis_system_prompt(config : AnalysisStepConfig) -> String {
  config.system_prompt.unwrap_or(default_analysis_system_prompt())
}

///|
fn requested_model_name_or_none(name : String) -> String? {
  let trimmed = name.trim().to_string()
  if trimmed.is_blank() || trimmed == "default" {
    None
  } else {
    Some(trimmed)
  }
}

///|
fn setup_analysis_agent(agent : @agent.Agent, cwd : String) -> Unit {
  let file_manager = @file.manager(cwd~)
  let todo_list = @todo.new(uuid=agent.uuid, cwd=agent.cwd)
  agent.add_tools([
    @execute_command.new(cwd).to_agent_tool(),
    @list_files.new(file_manager).to_agent_tool(),
    @read_file.new(file_manager).to_agent_tool(),
    @todo.new_tool(todo_list).to_agent_tool(),
    @search_files.new(agent.cwd).to_agent_tool(),
  ])
  if agent.model.supports_apply_patch {
    agent.add_tool(@apply_patch.new(agent.cwd))
  } else {
    agent.add_tool(@write_to_file.new(agent.cwd))
  }
}

///|
fn preferred_skills_prompt(preferred_skills : Array[String]) -> String {
  if preferred_skills.is_empty() {
    ""
  } else {
    let names = preferred_skills.join(", ")
    "Prefer these skills if relevant: \{names}"
  }
}

///|
fn skill_file_candidates(
  cwd : String,
  home : String?,
  skill : String,
) -> Array[String] {
  let candidates : Array[String] = [
    cwd
    |> @pathx.join("skills")
    |> @pathx.join(skill)
    |> @pathx.join("SKILL.md"),
    cwd
    |> @pathx.join("skills")
    |> @pathx.join(skill)
    |> @pathx.join("skill.md"),
    cwd
    |> @pathx.join(".moonclaw")
    |> @pathx.join("skills")
    |> @pathx.join(skill)
    |> @pathx.join("SKILL.md"),
  ]
  match home {
    Some(home) =>
      candidates.push(
        home
        |> @pathx.join(".moonclaw")
        |> @pathx.join("skills")
        |> @pathx.join(skill)
        |> @pathx.join("SKILL.md"),
      )
    None => ()
  }
  candidates
}

///|
async fn load_skill_instruction_text(
  cwd : String,
  home : String?,
  skill : String,
) -> String? {
  for candidate in skill_file_candidates(cwd, home, skill) {
    let exists = @fsx.exists(candidate) catch { _ => false }
    if exists {
      let content = @fsx.read_file(candidate) catch { _ => continue }
      return Some(content)
    }
  }
  None
}

///|
async fn loaded_skills_prompt(
  cwd : String,
  home : String?,
  preferred_skills : Array[String],
) -> String {
  let loaded : Array[String] = []
  for skill in preferred_skills {
    match load_skill_instruction_text(cwd, home, skill) {
      Some(content) => loaded.push(["Skill `\{skill}`", content].join("\n\n"))
      None => ()
    }
  }
  if loaded.is_empty() {
    ""
  } else {
    ["Loaded skill instructions:", loaded.join("\n\n---\n\n")].join("\n\n")
  }
}

///|
fn build_analysis_prompt(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  skills_prompt : String,
  memory_prompt : String,
) -> String {
  let sections = [
    config.prompt,
    preferred_skills_prompt(config.preferred_skills),
    skills_prompt,
    memory_prompt,
    "Job id: \{context.run.job_id}",
    "Run id: \{context.run.id}",
    "Step id: \{context.step.id}",
  ]
  let sections = match context.initial_input {
    Some(input) => [..sections, "Initial input:\n\{input.stringify()}"]
    None => sections
  }
  let sections = if context.outputs.is_empty() {
    sections
  } else {
    let rendered : Array[String] = []
    for step_id, output in context.outputs {
      rendered.push("[\{step_id}] \{output.stringify()}")
    }
    let rendered_text = rendered.join("\n")
    [..sections, "Previous step outputs:\n\{rendered_text}"]
  }
  sections.filter(fn(section) { !section.is_blank() }).join("\n\n")
}

///|
fn analysis_memory_query(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> MemoryQuery {
  let workspace = match config.workspace {
    Some(workspace) => Some(workspace)
    None =>
      match context.run.workspace_dir {
        Some(workspace_dir) => Some(workspace_dir)
        None => config.cwd
      }
  }
  MemoryQuery::new(
    workspace~,
    scope=config.artifacts.scope.get(0),
    status=Some(MemoryStatus::Active),
  )
}

///|
fn analysis_working_directory(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> String {
  context.run.workspace_dir.unwrap_or(config.cwd.unwrap_or("."))
}

///|
fn analysis_memory_search_text(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> String {
  let sections = [config.prompt]
  let sections = match context.initial_input {
    Some(input) => [..sections, input.stringify()]
    None => sections
  }
  if context.outputs.is_empty() {
    sections.join("\n")
  } else {
    let rendered : Array[String] = []
    for step_id, output in context.outputs {
      rendered.push("[\{step_id}] \{output.stringify()}")
    }
    [..sections, rendered.join("\n")].join("\n")
  }
}

///|
fn analysis_memory_prompt(
  store : SystemStore,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> String {
  let memories = MemoryService::new(store~)
  let query = analysis_memory_query(context, config)
  let hits = memories.search(
    analysis_memory_search_text(context, config),
    query~,
    max_hits=4,
  )
  if !hits.is_empty() {
    return render_memory_hits_prompt(
      hits,
      header="Relevant long-term memory for this step",
    )
  }
  let fallback = memories.list(query~)
  fallback.sort_by(fn(left, right) { right.updated_at.compare(left.updated_at) })
  let fallback = if fallback.length() > 4 {
    fallback[:4].to_array()
  } else {
    fallback
  }
  render_memory_records_prompt(
    fallback,
    header="Relevant long-term memory for this step",
  )
}

///|
pub async fn build_analysis_request(
  store : SystemStore,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> AnalysisRequest {
  let working_directory = analysis_working_directory(context, config)
  let skills_prompt = loaded_skills_prompt(
    working_directory,
    config.home,
    config.preferred_skills,
  )
  let memory_prompt = analysis_memory_prompt(store, context, config)
  AnalysisRequest::{
    job_id: context.run.job_id,
    run_id: context.run.id,
    step_id: context.step.id,
    prompt: build_analysis_prompt(context, config, skills_prompt, memory_prompt),
    model_name: config.model.unwrap_or("default"),
    cwd: working_directory,
    home: config.home,
    execution_mode: config.execution_mode,
    execution_target: config.execution_target,
    system_prompt: analysis_system_prompt(config),
    preferred_skills: config.preferred_skills,
    enable_tools: config.enable_tools,
    web_search: config.web_search,
  }
}

///|
fn find_existing_analysis_artifact(
  artifacts : ArtifactStore,
  run : JobRun,
  config : AnalysisStepConfig,
) -> ArtifactRecord? {
  let logical_key = config.artifacts.logical_key
  let matches = artifacts.list(
    query=ArtifactQuery::new(
      job_id=Some(run.job_id),
      artifact_type=Some(config.artifacts.report_artifact_type),
      logical_key~,
      status=Some(ArtifactStatus::Active),
    ),
  )
  if matches.is_empty() {
    None
  } else {
    Some(matches[0])
  }
}

///|
fn usage_json(usage : @ai.Usage?) -> Json? {
  usage.map(fn(usage) {
    {
      "input_tokens": usage.input_tokens,
      "output_tokens": usage.output_tokens,
      "total_tokens": usage.total_tokens,
      "cache_read_tokens": usage.cache_read_tokens,
    }
  })
}

///|
fn result_metrics(execution : AnalysisExecution) -> Json {
  match execution.usage {
    Some(usage) =>
      {
        "input_tokens": usage.input_tokens,
        "output_tokens": usage.output_tokens,
        "total_tokens": usage.total_tokens,
      }
    None => {}
  }
}

///|
fn policy_budget_exceeded(
  execution : AnalysisExecution,
  policy : AnalysisPolicy,
) -> String? {
  match (policy.max_total_tokens, execution.usage) {
    (Some(max_total_tokens), Some(usage)) if usage.total_tokens >
      max_total_tokens =>
      Some(
        "Analysis exceeded token budget: \{usage.total_tokens} > \{max_total_tokens}",
      )
    _ => None
  }
}

///|
fn timeout_error_message(step_id : String, timeout_ms : Int) -> String {
  "Analysis step \{step_id} timed out after \{timeout_ms}ms"
}

///|
pub fn default_analysis_executor() -> AnalysisExecutor {
  AnalysisExecutor::new(run=async fn(request) {
    let requested_model = requested_model_name_or_none(request.model_name)
    guard @model.load(
        home?=request.home.map(fn(home) { home[:] }),
        cwd=request.cwd[:],
        name?=requested_model,
      )
      is Some(model) else {
      return Err("Model not found: \{request.model_name}")
    }
    let logger = @pino.logger("job-analysis", @pino.Transport::console())
    let agent = @agent.new(
      model,
      logger~,
      home?=request.home.map(fn(home) { home[:] }),
      cwd=request.cwd[:],
      system_message=request.system_prompt,
      user_message=request.prompt,
      web_search=request.web_search,
    )
    defer agent.close()
    if request.enable_tools {
      setup_analysis_agent(agent, request.cwd)
    }

    let mut final_content = ""
    let mut final_usage : @ai.Usage? = None
    let mut failed : String? = None
    agent.event_target.add_listener(event => {
      match event.desc {
        @event.AssistantMessage(usage~, tool_calls~, content) => {
          if !content.is_blank() {
            final_content = content
          }
          if usage is Some(usage) {
            final_usage = Some(usage)
          }
          ignore(tool_calls)
        }
        @event.Failed(error) => failed = Some(error.stringify())
        _ => ()
      }
    })

    agent.start() catch {
      error => return Err("Analysis agent failed: \{error}")
    }
    if failed is Some(error) {
      return Err(error)
    }
    Ok(AnalysisExecution::{
      model_name: model.name,
      content: final_content,
      conversation_id: Some(agent.id().to_string()),
      usage: final_usage,
      metadata: {
        "job_id": request.job_id,
        "run_id": request.run_id,
        "step_id": request.step_id,
      },
    })
  })
}

///|
pub fn analysis_step_handler(
  runtime~ : RuntimeManager,
  executor? : AnalysisExecutor = default_analysis_executor(),
  now? : () -> Int = fn() { @async.now().to_int() },
  kind? : String = "job.analysis",
) -> WorkflowStepHandler {
  let store = runtime.store()
  let artifacts = ArtifactStore::new(store~)
  WorkflowStepHandler::new(kind~, run=async fn(context) {
    let config : AnalysisStepConfig = @json.from_json(context.step.config) catch {
      error => return Err("Invalid analysis step config: \{error}")
    }
    if config.policy.skip_if_artifact_exists &&
      find_existing_analysis_artifact(artifacts, context.run, config)
      is Some(existing) {
      return Ok(
        WorkflowStepResult::new(
          output={ "status": "skipped", "report_artifact_id": existing.id },
          summary=Some("Skipped existing analysis artifact"),
          logs=["existing artifact reused: \{existing.id}"],
        ),
      )
    }

    let request = build_analysis_request(store, context, config)

    let execution = match config.policy.timeout_ms {
      Some(timeout_ms) =>
        @async.with_timeout(timeout_ms, () => (executor.run)(request)) catch {
          @async.TimeoutError =>
            return Err(timeout_error_message(context.step.id, timeout_ms))
          error => return Err("Analysis execution failed: \{error}")
        }
      None =>
        (executor.run)(request) catch {
          error => return Err("Analysis execution failed: \{error}")
        }
    }
    let execution = match execution {
      Ok(execution) => execution
      Err(error) => return Err(error)
    }
    if policy_budget_exceeded(execution, config.policy) is Some(error) {
      return Err(error)
    }

    let report_artifact = artifacts.write(
      ArtifactWriteRequest::new(
        run_id=context.run.id,
        job_id=context.run.job_id,
        artifact_type=config.artifacts.report_artifact_type,
        logical_key=config.artifacts.logical_key,
        content=execution.content,
        content_type="text/markdown",
        file_name=config.artifacts.report_file_name,
        metadata={
          "step_id": context.step.id,
          "model": execution.model_name,
          "conversation_id": execution.conversation_id,
          "preferred_skills": config.preferred_skills,
          "config_metadata": config.metadata,
        },
        scope=config.artifacts.scope,
        append_only=config.artifacts.append_only,
      ),
      "\{context.run.id}:\{context.step.id}:report:\{now()}",
      now(),
    )
    let result_payload : Json = {
      "step_id": context.step.id,
      "model": execution.model_name,
      "content": execution.content,
      "conversation_id": execution.conversation_id,
      "usage": usage_json(execution.usage),
      "metadata": execution.metadata,
    }
    let result_artifact = artifacts.write(
      ArtifactWriteRequest::new(
        run_id=context.run.id,
        job_id=context.run.job_id,
        artifact_type=config.artifacts.result_artifact_type,
        logical_key=config.artifacts.logical_key,
        content=result_payload.stringify(),
        content_type="application/json",
        file_name=config.artifacts.result_file_name,
        metadata={
          "step_id": context.step.id,
          "report_artifact_id": report_artifact.id,
          "config_metadata": config.metadata,
        },
        scope=config.artifacts.scope,
        append_only=config.artifacts.append_only,
      ),
      "\{context.run.id}:\{context.step.id}:result:\{now()}",
      now(),
    )

    Ok(
      WorkflowStepResult::new(
        output={
          "status": "completed",
          "model": execution.model_name,
          "content": execution.content,
          "conversation_id": execution.conversation_id,
          "report_artifact_id": report_artifact.id,
          "result_artifact_id": result_artifact.id,
          "usage": usage_json(execution.usage),
        },
        summary=Some("Analysis completed"),
        metrics=result_metrics(execution),
        logs=[
          "report artifact written: \{report_artifact.id}",
          "result artifact written: \{result_artifact.id}",
        ],
      ),
    )
  })
}
