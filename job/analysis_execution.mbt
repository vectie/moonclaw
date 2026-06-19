///|
pub(all) struct PersistedAnalysisExecution {
  execution : AnalysisExecution
  result_payload : Json
  report_artifact_id : String
  result_artifact_id : String
  completed_result : Result[WorkflowStepResult, String]
}

///|
fn analysis_execution_isolation_metadata(
  execution : AnalysisExecution,
) -> Json? {
  match execution.metadata {
    { "execution_isolation": value, .. } => Some(value)
    _ => None
  }
}

///|
pub async fn execute_analysis_request(
  executor : AnalysisExecutor,
  request : AnalysisRequest,
  policy : AnalysisPolicy,
  step_id : String,
) -> Result[AnalysisExecution, String] {
  let execution = match policy.timeout_ms {
    Some(timeout_ms) =>
      @async.with_timeout(timeout_ms, () => (executor.run)(request)) catch {
        @async.TimeoutError =>
          if analysis_best_effort_on_timeout(request) {
            Ok(
              best_effort_timeout_analysis_execution(
                request, step_id, timeout_ms,
              ),
            )
          } else {
            return Err(
              "\{timeout_error_message(step_id, timeout_ms)} (tool journal: \{analysis_tool_journal_path(request)})",
            )
          }
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
  if policy_budget_exceeded(execution, policy) is Some(error) {
    return Err(error)
  }
  Ok(execution)
}

///|
fn analysis_best_effort_on_timeout(request : AnalysisRequest) -> Bool {
  metadata_bool_with_step_metadata(
    request.step_metadata,
    "best_effort_on_timeout",
    false,
  )
}

///|
fn best_effort_timeout_analysis_execution(
  request : AnalysisRequest,
  step_id : String,
  timeout_ms : Int,
) -> AnalysisExecution {
  let message = "\{timeout_error_message(step_id, timeout_ms)}; continuing because `best_effort_on_timeout` is enabled. Inspect workspace artifacts and blockers for the bounded result."
  {
    model_name: request.model_name,
    content: message,
    conversation_id: None,
    usage: None,
    metadata: {
      "job_id": request.job_id,
      "run_id": request.run_id,
      "step_id": request.step_id,
      "best_effort_on_timeout": true,
      "timeout_ms": timeout_ms,
      "tool_call_journal_path": analysis_tool_journal_path(request),
    },
  }
}

///|
pub async fn persist_analysis_execution(
  store : SystemStore,
  artifacts : ArtifactStore,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
  now : () -> Int,
) -> PersistedAnalysisExecution {
  let execution_isolation = analysis_execution_isolation_metadata(execution)
  let step_key = safe_step_file_segment(context.step.id)
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
        "execution_isolation": execution_isolation,
      },
      scope=config.artifacts.scope,
      append_only=config.artifacts.append_only,
    ),
    "\{context.run.id}:\{step_key}:report:\{now()}",
    now(),
  )
  let result_payload = structured_analysis_result_payload(
    context.step.id,
    config,
    execution,
  )
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
        "execution_isolation": execution_isolation,
      },
      scope=config.artifacts.scope,
      append_only=config.artifacts.append_only,
    ),
    "\{context.run.id}:\{step_key}:result:\{now()}",
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
        "execution_isolation": execution_isolation,
      },
      summary=Some("Analysis completed"),
      metrics=result_metrics(execution),
      logs=[
        "report artifact written: \{report_artifact.id}",
        "result artifact written: \{result_artifact.id}",
        ..analysis_tool_journal_logs(execution.metadata),
      ],
    ),
  )
  {
    execution,
    result_payload,
    report_artifact_id: report_artifact.id,
    result_artifact_id: result_artifact.id,
    completed_result,
  }
}
