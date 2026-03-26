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
async fn adaptive_followup_envelope(
  executor : AnalysisExecutor,
  request : AnalysisRequest,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
) -> AdaptiveAnalysisEnvelope? {
  let preferred_skills = ["analysis-adaptation"]
  let skills_prompt = loaded_skills_prompt(
    request.cwd,
    request.home,
    preferred_skills,
  )
  let base_followup = AnalysisRequest::{
    ..request,
    prompt: [
      adaptive_decision_prompt(context, config, execution),
      skills_prompt,
    ]
    .filter(fn(section) { !section.is_blank() })
    .join("\n\n"),
    system_prompt: adaptive_decision_system_prompt(),
    enable_tools: false,
    web_search: false,
    preferred_skills,
  }
  let followup_execution = (executor.run)(base_followup) catch {
    _ => return None
  }
  match followup_execution {
    Ok(result) =>
      match parse_adaptive_analysis_envelope(result.content) {
        Some(envelope) => Some(envelope)
        None => {
          let repair_followup = AnalysisRequest::{
            ..base_followup,
            prompt: [
              base_followup.prompt,
              "The previous judgment did not follow the required JSON schema.",
              "Return strict JSON only with one of these verdicts: completed, needs_input, needs_subplan.",
              "Previous judgment output:",
              result.content,
            ].join("\n\n"),
          }
          let repair_execution = (executor.run)(repair_followup) catch {
            _ => return None
          }
          match repair_execution {
            Ok(repair_result) =>
              parse_adaptive_analysis_envelope(repair_result.content)
            Err(_) => None
          }
        }
      }
    Err(_) => None
  }
}

///|
async fn adaptive_subplan_fill_envelope(
  executor : AnalysisExecutor,
  request : AnalysisRequest,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
  envelope : AdaptiveAnalysisEnvelope,
) -> AdaptiveAnalysisEnvelope? {
  let preferred_skills = ["analysis-adaptation"]
  let skills_prompt = loaded_skills_prompt(
    request.cwd,
    request.home,
    preferred_skills,
  )
  let followup = AnalysisRequest::{
    ..request,
    prompt: [
      adaptive_subplan_fill_prompt(context, config, execution, envelope),
      skills_prompt,
    ]
    .filter(fn(section) { !section.is_blank() })
    .join("\n\n"),
    system_prompt: adaptive_subplan_fill_system_prompt(),
    enable_tools: false,
    web_search: false,
    preferred_skills,
  }
  let followup_execution = (executor.run)(followup) catch { _ => return None }
  match followup_execution {
    Ok(result) =>
      match parse_adaptive_analysis_envelope(result.content) {
        Some(expanded) if !adaptive_substeps(expanded).is_empty() =>
          Some(expanded)
        _ => None
      }
    Err(_) => None
  }
}

///|
async fn adaptive_missing_inputs_fill_envelope(
  executor : AnalysisExecutor,
  request : AnalysisRequest,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
  envelope : AdaptiveAnalysisEnvelope,
) -> AdaptiveAnalysisEnvelope? {
  let preferred_skills = ["analysis-adaptation"]
  let skills_prompt = loaded_skills_prompt(
    request.cwd,
    request.home,
    preferred_skills,
  )
  let followup = AnalysisRequest::{
    ..request,
    prompt: [
      adaptive_missing_inputs_fill_prompt(context, config, execution, envelope),
      skills_prompt,
    ]
    .filter(fn(section) { !section.is_blank() })
    .join("\n\n"),
    system_prompt: adaptive_missing_inputs_fill_system_prompt(),
    enable_tools: false,
    web_search: false,
    preferred_skills,
  }
  let followup_execution = (executor.run)(followup) catch { _ => return None }
  match followup_execution {
    Ok(result) =>
      match parse_adaptive_analysis_envelope(result.content) {
        Some(expanded) if expanded.missing_inputs is Some([..]) =>
          Some(expanded)
        _ => None
      }
    Err(_) => None
  }
}

///|
fn adaptive_subplan_title(
  config : AnalysisStepConfig,
  context : WorkflowStepContext,
  envelope : AdaptiveAnalysisEnvelope,
) -> String {
  match config.metadata {
    { "proposal_step_title": String(title), .. } if !title.trim().is_blank() =>
      title
    _ => envelope.summary.unwrap_or("Subplan for \{context.step.id}")
  }
}

///|
fn adaptive_subplan_summary(envelope : AdaptiveAnalysisEnvelope) -> String {
  envelope.summary.unwrap_or(
    "Auto-generated subplan from adaptive analysis verdict.",
  )
}

///|
fn adaptive_subplan_proposal(
  proposal_id : String,
  title : String,
  request_text : String,
  summary : String,
  steps : Array[AdaptiveSubstepPayload],
  now_ms : Int,
) -> JobProposal {
  let proposal_steps : Array[JobProposalStep] = []
  let mut index = 0
  for step in steps {
    let step_id = "step_\{index + 1}"
    proposal_steps.push(JobProposalStep::{
      id: step_id,
      title: step.title.trim().to_string(),
      prompt: step.prompt.trim().to_string(),
      kind: step.kind.unwrap_or("job.analysis"),
      metadata: {},
      child_profile: None,
      execution_mode: None,
      execution_target: None,
      include_parent_outputs: None,
      max_depth: None,
    })
    index += 1
  }
  JobProposal::{
    id: proposal_id,
    title,
    request_text,
    summary,
    revision_history: [],
    suggested_family: Some("generic"),
    profile_id: None,
    profile_role: None,
    profile_metadata: {},
    status: JobProposalStatus::Draft,
    steps: proposal_steps,
    tags: ["job", "adaptive-subplan"],
    channel_id: None,
    account_id: None,
    recipient: None,
    thread_id: None,
    presented_message_id: None,
    job_id: None,
    workflow_id: None,
    last_run_id: None,
    created_at: now_ms,
    updated_at: now_ms,
  }
}

///|
async fn execute_analysis_subplan(
  runtime : RuntimeManager,
  compiler : ProposalCompiler,
  engine_factory : () -> WorkflowEngine,
  child_executor : ChildRunExecutor?,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  envelope : AdaptiveAnalysisEnvelope,
  now : () -> Int,
  next_run_id : () -> String,
  max_depth : Int,
) -> Result[(String, String, Map[String, Json]), String] {
  let steps = adaptive_substeps(envelope)
  if steps.is_empty() {
    let detail = envelope.summary.unwrap_or(
      "Adaptive subplan requested but no substeps were provided.",
    )
    return Err("Analysis requires input: \{detail}")
  }
  guard context.run.depth < max_depth else {
    return Err(
      "Adaptive subplan depth limit reached: \{context.run.depth} >= \{max_depth}",
    )
  }
  let cwd = context.run.workspace_dir.unwrap_or(config.cwd.unwrap_or("."))
  let home = config.home.unwrap_or(".")
  let proposal = adaptive_subplan_proposal(
    human_readable_proposal_id(
      adaptive_subplan_title(config, context, envelope),
      now(),
      next_run_id(),
    ),
    adaptive_subplan_title(config, context, envelope),
    config.prompt,
    adaptive_subplan_summary(envelope),
    steps,
    now(),
  )
  let compilation = (compiler.run)(proposal, now(), cwd, home)
  runtime
  .store()
  .save_job_proposal(JobProposal::{
    ..proposal,
    status: JobProposalStatus::Confirmed,
    job_id: Some(compilation.definition.id),
    workflow_id: Some(compilation.workflow.id),
    updated_at: now(),
  })
  runtime.register_definition(compilation.definition)
  runtime.register_workflow(compilation.workflow)
  for binding in compilation.bindings {
    runtime.store().save_chat_binding(binding)
  }
  let child_run = match
    runtime.trigger_definition(
      next_run_id(),
      compilation.definition.id,
      TriggerSource::Custom("analysis-subplan"),
      now(),
      parent_run_id=Some(context.run.id),
      parent_step_id=Some(context.step.id),
      depth=context.run.depth + 1,
    ) {
    Ok(run) => run
    Err(error) => return Err(error)
  }
  let child_request = ChildRunExecutionRequest::{
    parent_context: context,
    child_run,
    compilation,
    config: SubjobStepConfig::new(
      request_text=config.prompt,
      cwd=Some(cwd),
      home=Some(home),
      include_parent_outputs=true,
      max_depth~,
    ),
    control: context.control,
  }
  let child_result = match child_executor {
    Some(executor) =>
      match (executor.run)(child_request) {
        Ok(Some(result)) => result
        Ok(None) =>
          match
            execute_child_run_locally(
              child_run,
              engine_factory,
              now,
              context.control,
            ) {
            Ok(result) => result
            Err(error) => return Err(error)
          }
        Err(error) => return Err(error)
      }
    None =>
      match
        execute_child_run_locally(
          child_run,
          engine_factory,
          now,
          context.control,
        ) {
        Ok(result) => result
        Err(error) => return Err(error)
      }
  }
  Ok((compilation.definition.id, child_run.id, child_result.outputs))
}

///|
fn default_analysis_system_prompt() -> String {
  [
    @prompt.prelude, "You are executing a job workflow analysis step.", "Produce a concise, grounded report using the provided context.",
    "If the step cannot be completed because key inputs are missing, you may return JSON only: {\"verdict\":\"needs_input\",\"summary\":string,\"missing_inputs\":string[]}.",
    "If the step is too broad and should be decomposed before useful execution, you may return JSON only: {\"verdict\":\"needs_subplan\",\"summary\":string,\"suggested_substeps\":[{\"title\":string,\"prompt\":string,\"kind\":string?}]}.",
    "Use normal prose output when you can complete the step directly.",
  ].join("\n\n")
}

///|
pub fn analysis_system_prompt(config : AnalysisStepConfig) -> String {
  config.system_prompt.unwrap_or(default_analysis_system_prompt())
}

///|
fn analysis_adaptive_disabled(config : AnalysisStepConfig) -> Bool {
  metadata_bool_with_step_metadata(config.metadata, "disable_adaptive", false)
}

///|
fn metadata_with_step_metadata(metadata : Json, key : String) -> Json? {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(value) => Some(value)
        None =>
          match obj.get("step_metadata") {
            Some(nested) => metadata_with_step_metadata(nested, key)
            None => None
          }
      }
    _ => None
  }
}

///|
fn metadata_bool_with_step_metadata(
  metadata : Json,
  key : String,
  fallback : Bool,
) -> Bool {
  match metadata_with_step_metadata(metadata, key) {
    Some(True) => true
    Some(False) => false
    _ => fallback
  }
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
fn configured_primary_model_from_json(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("agents") {
        Some(Object(agents)) =>
          match agents.get("defaults") {
            Some(Object(defaults)) =>
              match defaults.get("model") {
                Some(Object(model)) =>
                  match model.get("primary") {
                    Some(String(primary)) if !primary.trim().is_empty() =>
                      Some(primary.trim().to_string())
                    _ => None
                  }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn moonclaw_config_path_candidates(
  cwd : String,
  home : String?,
) -> Array[String] {
  let paths : Array[String] = [
    cwd |> @pathx.join("moonclaw.json"),
    cwd |> @pathx.join(".moonclaw") |> @pathx.join("moonclaw.json"),
  ]
  match home {
    Some(home) => {
      paths.push(home |> @pathx.join("moonclaw.json"))
      paths.push(
        home |> @pathx.join(".moonclaw") |> @pathx.join("moonclaw.json"),
      )
    }
    None => ()
  }
  paths
}

///|
async fn configured_primary_model(cwd : String, home : String?) -> String? {
  for path in moonclaw_config_path_candidates(cwd, home) {
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    if configured_primary_model_from_json(Some(json)) is Some(primary) {
      return Some(primary)
    }
  }
  None
}

///|
fn configured_adaptive_subplan_max_depth_from_json(json : Json?) -> Int? {
  match json {
    Some(Object(root)) =>
      match root.get("jobs") {
        Some(Object(jobs)) =>
          match jobs.get("analysis") {
            Some(Object(analysis)) =>
              match analysis.get("adaptive") {
                Some(Object(adaptive)) =>
                  match adaptive.get("max_depth") {
                    Some(Number(value, ..)) => Some(value.to_int())
                    _ => None
                  }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
async fn configured_adaptive_subplan_max_depth(
  cwd : String,
  home : String?,
) -> Int? {
  for path in moonclaw_config_path_candidates(cwd, home) {
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    if configured_adaptive_subplan_max_depth_from_json(Some(json))
      is Some(max_depth) {
      return Some(max_depth)
    }
  }
  None
}

///|
async fn resolved_model_name(request : AnalysisRequest) -> String? {
  match requested_model_name_or_none(request.model_name) {
    Some(requested) => Some(requested)
    None => configured_primary_model(request.cwd, request.home)
  }
}

///|
fn setup_analysis_agent(
  agent : @agent.Agent,
  cwd : String,
  web_search? : Bool = false,
) -> Unit {
  let file_manager = @file.manager(cwd~)
  let todo_list = @todo.new(uuid=agent.uuid, cwd=agent.cwd)
  agent.add_tools([
    @execute_command.new(cwd).to_agent_tool(),
    @list_files.new(file_manager).to_agent_tool(),
    @read_file.new(file_manager).to_agent_tool(),
    @todo.new_tool(todo_list).to_agent_tool(),
    @search_files.new(agent.cwd).to_agent_tool(),
  ])
  if web_search {
    agent.add_tool(@web_search.new())
  }
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
fn workspace_output_slug(text : String) -> String {
  let buf = StringBuilder::new()
  let mut chars_written = 0
  let mut last_dash = true
  for c in text.to_lower().to_array() {
    let normalized = match c {
      'a'..='z' => Some(c)
      '0'..='9' => Some(c)
      _ => None
    }
    match normalized {
      Some(c) => {
        if chars_written >= 32 {
          break
        }
        buf.write_char(c)
        chars_written += 1
        last_dash = false
      }
      None =>
        if !last_dash && chars_written < 32 {
          buf.write_char('-')
          chars_written += 1
          last_dash = true
        }
    }
  }
  let slug = buf.to_string().trim(chars="-").to_string()
  if slug.is_blank() {
    "step"
  } else {
    slug
  }
}

///|
fn workspace_report_file_name(step_id : String, step_title : String) -> String {
  "step-\{step_id}-\{workspace_output_slug(step_title)}.md"
}

///|
fn workspace_result_file_name(step_id : String, step_title : String) -> String {
  "step-\{step_id}-\{workspace_output_slug(step_title)}.json"
}

///|
fn run_workflow_steps(
  store : SystemStore,
  run : JobRun,
) -> Array[WorkflowStepDefinition] {
  let definition = match store.get_definition(run.job_id) {
    Some(definition) => definition
    None => return []
  }
  let workflow_id = match definition.workflow_id {
    Some(workflow_id) => workflow_id
    None => return []
  }
  match store.get_workflow(workflow_id) {
    Some(workflow) => workflow.steps
    None => []
  }
}

///|
fn is_final_workflow_step(
  store : SystemStore,
  run : JobRun,
  step_id : String,
) -> Bool {
  let steps = run_workflow_steps(store, run)
  if steps.is_empty() {
    false
  } else {
    steps[steps.length() - 1].id == step_id
  }
}

///|
async fn materialize_analysis_outputs_to_workspace(
  store : SystemStore,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  result_payload : Json,
  report_content : String,
) -> Unit {
  let workspace_dir = match context.run.workspace_dir {
    Some(workspace_dir) if !workspace_dir.trim().to_string().is_blank() =>
      workspace_dir
    _ => return
  }
  let outputs_dir = workspace_dir |> @pathx.join("outputs")
  @fsx.make_directory(outputs_dir, recursive=true) catch {
    _ => return
  }
  let report_file = outputs_dir
    |> @pathx.join(
      config.artifacts.report_file_name.unwrap_or(
        workspace_report_file_name(context.step.id, context.step.id),
      ),
    )
  let result_file = outputs_dir
    |> @pathx.join(
      config.artifacts.result_file_name.unwrap_or(
        workspace_result_file_name(context.step.id, context.step.id),
      ),
    )
  @fsx.write_to_file(report_file, report_content) catch {
    _ => ()
  }
  @fsx.write_to_file(result_file, result_payload.stringify()) catch {
    _ => ()
  }
  match config.artifacts.report_file_name {
    Some(file_name) if !file_name.trim().to_string().is_blank() =>
      @fsx.write_to_file(
        workspace_dir |> @pathx.join(file_name),
        report_content,
      ) catch {
        _ => ()
      }
    _ => ()
  }
  match config.artifacts.result_file_name {
    Some(file_name) if !file_name.trim().to_string().is_blank() =>
      @fsx.write_to_file(
        workspace_dir |> @pathx.join(file_name),
        result_payload.stringify(),
      ) catch {
        _ => ()
      }
    _ => ()
  }
  if is_final_workflow_step(store, context.run, context.step.id) {
    let skip_primary = metadata_bool_with_step_metadata(
      config.metadata,
      "skip_primary_workspace_output",
      false,
    )
    if skip_primary {
      return
    }
    @fsx.write_to_file(
      workspace_dir |> @pathx.join("report.md"),
      report_content,
    ) catch {
      _ => ()
    }
    @fsx.write_to_file(
      workspace_dir |> @pathx.join("result.json"),
      result_payload.stringify(),
    ) catch {
      _ => ()
    }
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
pub async fn loaded_skills_prompt(
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
  let resume_prompt = match
    resume_instruction_from_input(context.initial_input) {
    Some(trimmed) =>
      [
        "Resume instruction from user:\n\{trimmed}",
        "Treat the resume instruction as authoritative operator guidance. Interpret it directly and adapt your approach accordingly. If it authorizes assumptions, best-effort estimation, or proceeding without further user input, follow that guidance and make clearly labeled assumptions unless completion would require inventing core facts.",
      ].join("\n\n")
    None => ""
  }
  let step_metadata_prompt = match config.metadata {
    { "step_metadata": metadata, .. } =>
      "Step metadata:\n\{metadata.stringify()}"
    _ => ""
  }
  let sections = [
    config.prompt,
    preferred_skills_prompt(config.preferred_skills),
    skills_prompt,
    memory_prompt,
    step_metadata_prompt,
    resume_prompt,
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
fn resume_instruction_from_input(input : Json?) -> String? {
  match input {
    Some({ "resume_content": String(text), .. }) => {
      let trimmed = text.trim().to_string()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    Some({ "resume_input": nested, .. }) => resume_instruction_from_json(nested)
    Some(json) => resume_instruction_from_json(json)
    None => None
  }
}

///|
fn should_preserve_first_pass_on_empty_subplan(
  context : WorkflowStepContext,
  execution : AnalysisExecution,
) -> Bool {
  match
    (
      resume_instruction_from_input(context.initial_input),
      parse_adaptive_analysis_envelope(execution.content),
    ) {
    (Some(_), None) if !execution.content.trim().to_string().is_blank() => true
    _ => false
  }
}

///|
fn resume_instruction_from_json(input : Json) -> String? {
  match input {
    { "resume_content": String(text), .. } => {
      let trimmed = text.trim().to_string()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    { "resume_input": nested, .. } => resume_instruction_from_json(nested)
    _ => resume_instruction_from_serialized_json(input.stringify())
  }
}

///|
fn resume_instruction_from_serialized_json(text : String) -> String? {
  let marker = "\"resume_content\":\""
  match text.find(marker) {
    Some(start) => {
      let remainder = text[start + marker.length():].to_string()
      match remainder.find("\"") {
        Some(end) => {
          let extracted = remainder[:end].to_string().trim().to_string()
          if extracted.is_blank() {
            None
          } else {
            Some(extracted)
          }
        }
        None => None
      }
    }
    None => None
  }
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
    let requested_model = resolved_model_name(request)
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
      setup_analysis_agent(agent, request.cwd, web_search=request.web_search)
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
  compiler? : ProposalCompiler? = None,
  engine_factory? : (() -> WorkflowEngine)? = None,
  child_executor? : ChildRunExecutor? = None,
  now? : () -> Int = fn() { @async.now().to_int() },
  next_run_id? : () -> String = fn() { "run.\{now()}" },
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
    materialize_analysis_outputs_to_workspace(
      store,
      context,
      config,
      result_payload,
      execution.content,
    )
    let completed_result = Ok(
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
    let adaptive_envelope = if analysis_adaptive_disabled(config) {
      None
    } else {
      match parse_adaptive_analysis_envelope(execution.content) {
        Some(envelope) => Some(envelope)
        None =>
          adaptive_followup_envelope(
            executor, request, context, config, execution,
          )
      }
    }
    let adaptive_max_depth = configured_adaptive_subplan_max_depth(
      request.cwd,
      request.home,
    ).unwrap_or(5)
    let adaptive_result : Result[WorkflowStepResult, String]? = match
      adaptive_envelope {
      Some(envelope) => {
        let verdict = envelope.verdict.trim().to_string().to_lower()
        match verdict {
          "completed" => None
          "needs_input" => {
            let envelope = match envelope.missing_inputs {
              Some([..]) => envelope
              _ =>
                adaptive_missing_inputs_fill_envelope(
                  executor, request, context, config, execution, envelope,
                ).unwrap_or(envelope)
            }
            Some(
              Err(
                "Analysis requires input: \{adaptive_missing_inputs_line(envelope)}",
              ),
            )
          }
          "needs_subplan" => {
            let envelope = match adaptive_substeps(envelope) {
              [] =>
                adaptive_subplan_fill_envelope(
                  executor, request, context, config, execution, envelope,
                ).unwrap_or(envelope)
              _ => envelope
            }
            let substeps = adaptive_substeps(envelope)
            if substeps.is_empty() {
              if should_preserve_first_pass_on_empty_subplan(context, execution) {
                Some(completed_result)
              } else {
                let detail = envelope.summary.unwrap_or(
                  "Adaptive subplan requested but no substeps were provided.",
                )
                Some(Err("Analysis requires input: \{detail}"))
              }
            } else {
              match compiler {
                None =>
                  Some(
                    Err(
                      "Adaptive subplanning requested but no compiler is configured",
                    ),
                  )
                Some(compiler) =>
                  match engine_factory {
                    None =>
                      Some(
                        Err(
                          "Adaptive subplanning requested but no workflow engine factory is configured",
                        ),
                      )
                    Some(engine_factory) =>
                      match
                        execute_analysis_subplan(
                          runtime, compiler, engine_factory, child_executor, context,
                          config, envelope, now, next_run_id, adaptive_max_depth,
                        ) {
                        Err(error) => Some(Err(error))
                        Ok((child_job_id, child_run_id, child_outputs)) =>
                          Some(
                            Ok(
                              WorkflowStepResult::new(
                                output={
                                  "status": "subplanned",
                                  "model": execution.model_name,
                                  "content": execution.content,
                                  "conversation_id": execution.conversation_id,
                                  "report_artifact_id": report_artifact.id,
                                  "result_artifact_id": result_artifact.id,
                                  "usage": usage_json(execution.usage),
                                  "child_job_id": child_job_id,
                                  "child_run_id": child_run_id,
                                  "child_outputs": child_outputs,
                                },
                                summary=Some(
                                  "Analysis requested and completed a child subplan",
                                ),
                                metrics=result_metrics(execution),
                                logs=[
                                  "report artifact written: \{report_artifact.id}",
                                  "result artifact written: \{result_artifact.id}",
                                  "spawned child job: \{child_job_id}",
                                  "spawned child run: \{child_run_id}",
                                ],
                              ),
                            ),
                          )
                      }
                  }
              }
            }
          }
          _ => None
        }
      }
      None => None
    }
    match adaptive_result {
      Some(result) => result
      None => completed_result
    }
  })
}
