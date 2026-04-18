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
fn adaptive_subplan_policy_metadata(step_metadata : Json) -> Json {
  let policy : Map[String, Json] = {}
  match metadata_int_with_step_metadata_option(step_metadata, "timeout_ms") {
    Some(value) => policy.set("timeout_ms", value.to_json())
    None => ()
  }
  match
    metadata_int_with_step_metadata_option(step_metadata, "max_total_tokens") {
    Some(value) => policy.set("max_total_tokens", value.to_json())
    None => ()
  }
  match waiting_for_input_disabled_from_metadata(step_metadata) {
    Some(value) => policy.set("disable_waiting_for_input", value.to_json())
    None => ()
  }
  match best_effort_on_missing_input_from_metadata(step_metadata) {
    Some(value) => policy.set("best_effort_on_missing_input", value.to_json())
    None => ()
  }
  Json::object(policy)
}

///|
fn adaptive_subplan_proposal(
  proposal_id : String,
  title : String,
  request_text : String,
  summary : String,
  steps : Array[AdaptiveSubstepPayload],
  policy_metadata : Json,
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
      metadata: merge_json_metadata(
        subtask_execution_isolation_metadata(
          step_id,
          step.title,
          step.prompt,
          step.kind,
        ),
        policy_metadata,
      ),
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
    profile_metadata: policy_metadata,
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
  request : AnalysisRequest,
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
  let policy_metadata = adaptive_subplan_policy_metadata(request.step_metadata)
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
    policy_metadata,
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
