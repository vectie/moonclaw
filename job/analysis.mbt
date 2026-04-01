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
  let starter_attachment_artifacts_prompt = match context.initial_input {
    Some(input) => render_starter_attachment_artifacts_prompt(input)
    None => ""
  }
  let sections = [
    config.prompt,
    preferred_skills_prompt(config.preferred_skills),
    skills_prompt,
    memory_prompt,
    step_metadata_prompt,
    starter_attachment_artifacts_prompt,
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
fn starter_attachment_artifact_priority(artifact_id : String) -> Int {
  if artifact_id.has_suffix("-summary") {
    0
  } else if artifact_id.has_suffix("-text") {
    1
  } else {
    2
  }
}

///|
fn render_starter_attachment_artifacts_prompt(input : Json) -> String {
  let digest_lines : Array[String] = []
  match input {
    { "starter_attachment_digest_excerpt": String(text), .. } => {
      let trimmed = text.trim().to_string()
      if !trimmed.is_blank() {
        digest_lines.push("Starter attachment digest excerpt:")
        digest_lines.push(trimmed)
      }
    }
    _ => ()
  }
  match input {
    { "starter_attachment_digest_path": String(path), .. } =>
      digest_lines.push("Aggregate starter attachment digest path: \{path}")
    _ => ()
  }
  match input {
    { "starter_attachment_digest_artifact_id": String(artifact_id), .. } =>
      digest_lines.push(
        "Aggregate starter attachment digest artifact: \{artifact_id}",
      )
    _ => ()
  }
  let digest_prompt = digest_lines.join("\n")
  let rendered : Array[String] = []
  match input {
    { "starter_attachment_artifacts": Array(entries), .. } =>
      for entry in entries {
        match entry {
          {
            "id": String(id),
            "filename": filename,
            "artifact_ids": Array(artifact_ids),
            ..
          } => {
            let name = match filename {
              String(name) => name
              _ => id
            }
            let ids = artifact_ids
              .map(fn(value) {
                match value {
                  String(id) => id
                  _ => ""
                }
              })
              .filter(fn(id) { !id.is_blank() })
            if !ids.is_empty() {
              let ids = ids.copy()
              ids.sort_by(fn(left, right) {
                starter_attachment_artifact_priority(left).compare(
                  starter_attachment_artifact_priority(right),
                )
              })
              let joined_ids = ids.join(", ")
              rendered.push("- \{name}: \{joined_ids}")
            }
          }
          { "kind": String(kind), "artifact_id": String(artifact_id), .. } =>
            rendered.push("- \{kind}: \{artifact_id}")
          _ => ()
        }
      }
    _ => ()
  }
  if rendered.is_empty() {
    digest_prompt
  } else {
    let sections = [
      "Starter attachment artifacts:",
      "Prefer `starter_attachment_digest_excerpt` first when present as the immediate compact starter-document overview.",
      "Prefer `starter_attachment_digest_path` first when present as the directly readable aggregate starter-document overview.",
      "Use `starter_attachment_digest_artifact_id` next when artifact-oriented tooling is available.",
      "Prefer `starter_attachment.summary` artifact ids first when available; use the full extracted text artifacts only when you need more detail.",
      "Prefer these durable artifact references before falling back to raw workspace paths.",
      rendered.join("\n"),
    ]
    let sections = if digest_prompt.is_blank() {
      sections
    } else {
      [digest_prompt, ..sections]
    }
    sections.join("\n")
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
    let adaptive_result = resolve_adaptive_analysis_result(
      runtime,
      compiler,
      engine_factory,
      child_executor,
      executor,
      request,
      context,
      config,
      execution,
      completed_result,
      report_artifact.id,
      result_artifact.id,
      now,
      next_run_id,
    )
    match adaptive_result {
      Some(result) => result
      None => completed_result
    }
  })
}
