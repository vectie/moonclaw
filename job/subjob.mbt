///|
pub(all) struct SubjobStepConfig {
  request_text : String
  cwd : String?
  home : String?
  include_parent_outputs : Bool
  max_depth : Int
} derive(ToJson, FromJson, Show)

///|
pub fn SubjobStepConfig::new(
  request_text~ : String,
  cwd? : String? = None,
  home? : String? = None,
  include_parent_outputs? : Bool = true,
  max_depth? : Int = 2,
) -> SubjobStepConfig {
  SubjobStepConfig::{
    request_text,
    cwd,
    home,
    include_parent_outputs,
    max_depth,
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
pub fn subjob_step_handler(
  runtime~ : RuntimeManager,
  planner~ : ProposalPlanner,
  compiler~ : ProposalCompiler,
  engine_factory~ : () -> WorkflowEngine,
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
    store.save_job_proposal(JobProposal::{
      ..proposal,
      status: JobProposalStatus::Confirmed,
      job_id: Some(compilation.definition.id),
      workflow_id: Some(compilation.workflow.id),
      last_run_id: Some(child_run.id),
      updated_at: now(),
    })
    let engine = engine_factory()
    let child_result = match
      engine.execute_run(child_run.id, now, control=context.control) {
      Ok(result) => result
      Err(error) => return Err("Subjob \{child_run.id} failed: \{error}")
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
        logs=[
          "spawned child run \{child_run.id}",
          "child family: \{compilation.family}",
        ],
      ),
    )
  })
}
