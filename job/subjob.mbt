///|
pub(all) struct SubjobStepConfig {
  request_text : String
  cwd : String?
  home : String?
  child_profile : String?
  execution_mode : String?
  execution_target : String?
  include_parent_outputs : Bool
  max_depth : Int
} derive(ToJson, FromJson, Show)

///|
pub fn SubjobStepConfig::new(
  request_text~ : String,
  cwd? : String? = None,
  home? : String? = None,
  child_profile? : String? = None,
  execution_mode? : String? = None,
  execution_target? : String? = None,
  include_parent_outputs? : Bool = true,
  max_depth? : Int = 2,
) -> SubjobStepConfig {
  SubjobStepConfig::{
    request_text,
    cwd,
    home,
    child_profile,
    execution_mode,
    execution_target,
    include_parent_outputs,
    max_depth,
  }
}

///|
fn proposal_with_execution_override(
  proposal : JobProposal,
  execution_mode : String?,
  execution_target : String?,
) -> JobProposal {
  let trimmed_mode = execution_mode.map(fn(mode) { mode.trim().to_string() })
  let trimmed_target = execution_target.map(fn(target) {
    target.trim().to_string()
  })
  if trimmed_mode.unwrap_or("").is_blank() &&
    trimmed_target.unwrap_or("").is_blank() {
    return proposal
  }
  let base_metadata = match proposal.profile_metadata {
    Object(obj) => obj
    _ => {}
  }
  let execution_metadata = match base_metadata.get("execution") {
    Some(Object(obj)) => obj
    _ => {}
  }
  let merged_execution_metadata : Map[String, Json] = {}
  for key, value in execution_metadata {
    merged_execution_metadata.set(key, value)
  }
  match trimmed_mode {
    Some(mode) if !mode.is_blank() =>
      merged_execution_metadata.set("mode", mode.to_json())
    _ => ()
  }
  match trimmed_target {
    Some(target) if !target.is_blank() =>
      merged_execution_metadata.set("target", target.to_json())
    _ => ()
  }
  let merged_profile_metadata : Map[String, Json] = {}
  for key, value in base_metadata {
    merged_profile_metadata.set(key, value)
  }
  merged_profile_metadata.set(
    "execution",
    Json::object(merged_execution_metadata),
  )
  JobProposal::{
    ..proposal,
    profile_metadata: Json::object(merged_profile_metadata),
  }
}

///|
fn render_parent_outputs(outputs : Map[String, Json]) -> String {
  if outputs.is_empty() {
    return ""
  }
  let rendered : Array[String] = []
  for step_id, output in outputs {
    rendered.push("[\{step_id}] \{output.stringify()}")
  }
  rendered.join("\n")
}

///|
fn compiled_subjob_request(
  context : WorkflowStepContext,
  config : SubjobStepConfig,
) -> String {
  if !config.include_parent_outputs || context.outputs.is_empty() {
    config.request_text
  } else {
    [
      config.request_text,
      "Parent workflow outputs:",
      render_parent_outputs(context.outputs),
    ].join("\n\n")
  }
}

///|
pub(all) struct ProposalPlanner {
  run : async (String, String, String?) -> JobProposal
}

///|
pub fn ProposalPlanner::new(
  run~ : async (String, String, String?) -> JobProposal,
) -> ProposalPlanner {
  ProposalPlanner::{ run, }
}

///|
pub(all) struct ProposalCompiler {
  run : (JobProposal, Int, String, String) -> ProposalCompilation
}

///|
pub fn ProposalCompiler::new(
  run~ : (JobProposal, Int, String, String) -> ProposalCompilation,
) -> ProposalCompiler {
  ProposalCompiler::{ run, }
}

///|
pub(all) struct ChildRunExecutionRequest {
  parent_context : WorkflowStepContext
  child_run : JobRun
  compilation : ProposalCompilation
  config : SubjobStepConfig
  control : WorkflowExecutionControl
}

///|
pub(all) struct ChildRunExecutionResult {
  outputs : Map[String, Json]
}

///|
pub(all) struct ChildRunExecutor {
  run : async (ChildRunExecutionRequest) -> Result[
    ChildRunExecutionResult?,
    String,
  ]
}

///|
pub fn ChildRunExecutor::new(
  run~ : async (ChildRunExecutionRequest) -> Result[
    ChildRunExecutionResult?,
    String,
  ],
) -> ChildRunExecutor {
  ChildRunExecutor::{ run, }
}

///|
async fn execute_child_run_locally(
  child_run : JobRun,
  engine_factory : () -> WorkflowEngine,
  now : () -> Int,
  control : WorkflowExecutionControl,
) -> Result[ChildRunExecutionResult, String] {
  let engine = engine_factory()
  let child_result = match engine.execute_run(child_run.id, now, control~) {
    Ok(result) => result
    Err(error) => return Err("Subjob \{child_run.id} failed: \{error}")
  }
  Ok(ChildRunExecutionResult::{ outputs: child_result.outputs })
}

///|
pub fn subjob_step_handler(
  runtime~ : RuntimeManager,
  planner~ : ProposalPlanner,
  compiler~ : ProposalCompiler,
  engine_factory~ : () -> WorkflowEngine,
  child_executor? : ChildRunExecutor? = None,
  now? : () -> Int = fn() { @async.now().to_int() },
  next_run_id? : () -> String = fn() { "run.\{now()}" },
  kind? : String = "job.delegate",
) -> WorkflowStepHandler {
  let store = runtime.store()
  WorkflowStepHandler::new(kind~, run=async fn(context) {
    let config : SubjobStepConfig = @json.from_json(context.step.config) catch {
      error => return Err("Invalid subjob step config: \{error}")
    }
    guard context.run.depth < config.max_depth else {
      return Err(
        "Subjob depth limit reached: \{context.run.depth} >= \{config.max_depth}",
      )
    }
    let cwd = context.run.workspace_dir.unwrap_or(config.cwd.unwrap_or("."))
    let home = config.home
    let request_text = compiled_subjob_request(context, config)
    let proposal = (planner.run)(request_text, cwd, home)
    let proposal = apply_named_job_profile(
      proposal,
      cwd,
      home.unwrap_or(cwd),
      cwd,
      config.child_profile,
    )
    let proposal = proposal_with_execution_override(
      proposal,
      config.execution_mode,
      config.execution_target,
    )
    let compilation = (compiler.run)(proposal, now(), cwd, home.unwrap_or("."))
    store.save_job_proposal(JobProposal::{
      ..proposal,
      status: JobProposalStatus::Confirmed,
      job_id: Some(compilation.definition.id),
      workflow_id: Some(compilation.workflow.id),
      updated_at: now(),
    })
    runtime.register_definition(compilation.definition)
    runtime.register_workflow(compilation.workflow)
    for binding in compilation.bindings {
      store.save_chat_binding(binding)
    }
    let child_run = match
      runtime.trigger_definition(
        next_run_id(),
        compilation.definition.id,
        TriggerSource::Custom("subjob"),
        now(),
        parent_run_id=Some(context.run.id),
        parent_step_id=Some(context.step.id),
        depth=context.run.depth + 1,
      ) {
      Ok(run) => run
      Err(error) => return Err(error)
    }
    record_controller_child_run(
      store,
      context.run,
      context.step,
      compilation.definition.id,
      child_run.id,
      compilation.family,
      now(),
    )
    store.save_job_proposal(JobProposal::{
      ..proposal,
      status: JobProposalStatus::Confirmed,
      job_id: Some(compilation.definition.id),
      workflow_id: Some(compilation.workflow.id),
      last_run_id: Some(child_run.id),
      updated_at: now(),
    })
    let child_request = ChildRunExecutionRequest::{
      parent_context: context,
      child_run,
      compilation,
      config,
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
    let logs = [
      "spawned child run \{child_run.id}",
      "child family: \{compilation.family}",
    ]
    match config.execution_mode {
      Some(mode) if !mode.trim().to_string().is_blank() =>
        logs.push("child execution mode: \{mode}")
      _ => ()
    }
    match config.execution_target {
      Some(target) if !target.trim().to_string().is_blank() =>
        logs.push("child execution target: \{target}")
      _ => ()
    }
    Ok(
      WorkflowStepResult::new(
        output={
          "status": "completed",
          "child_job_id": compilation.definition.id,
          "child_run_id": child_run.id,
          "child_family": compilation.family,
          "child_outputs": child_result.outputs,
        },
        summary=Some(
          "Subjob \{compilation.definition.id} completed as \{compilation.family}",
        ),
        logs~,
      ),
    )
  })
}
