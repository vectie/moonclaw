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
  source_prompt : String
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
  tool_contract : AnalysisToolContract
  step_metadata : Json
  execution_isolation : Json?
  role_runtime_contract : RoleRuntimeContract?
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
fn requested_model_name_or_none(name : String) -> String? {
  let trimmed = name.trim().to_string()
  if trimmed.is_blank() || trimmed == "default" {
    None
  } else {
    Some(trimmed)
  }
}

///|
async fn resolved_model_name(request : AnalysisRequest) -> String? {
  match requested_model_name_or_none(request.model_name) {
    Some(requested) => Some(requested)
    None => configured_primary_model(request.cwd, request.home)
  }
}

///|
pub async fn build_analysis_request(
  store : SystemStore,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> AnalysisRequest {
  compose_job_analysis_request(store, context, config)
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
  AnalysisExecutor::new(run=run_default_analysis_runner)
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

    let execution = execute_analysis_request(
      executor,
      request,
      config.policy,
      context.step.id,
    )
    let execution = match execution {
      Ok(execution) => execution
      Err(error) => return Err(error)
    }

    let persisted = persist_analysis_execution(
      store, artifacts, context, config, execution, now,
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
      persisted.execution,
      persisted.completed_result,
      persisted.report_artifact_id,
      persisted.result_artifact_id,
      now,
      next_run_id,
    )
    match adaptive_result {
      Some(result) => result
      None => persisted.completed_result
    }
  })
}
