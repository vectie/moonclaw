///|
fn adaptive_subplanned_result(
  execution : AnalysisExecution,
  report_artifact_id : String,
  result_artifact_id : String,
  child_job_id : String,
  child_run_id : String,
  child_outputs : Json,
) -> Result[WorkflowStepResult, String] {
  Ok(
    WorkflowStepResult::new(
      output={
        "status": "subplanned",
        "model": execution.model_name,
        "content": execution.content,
        "conversation_id": execution.conversation_id,
        "report_artifact_id": report_artifact_id,
        "result_artifact_id": result_artifact_id,
        "usage": usage_json(execution.usage),
        "child_job_id": child_job_id,
        "child_run_id": child_run_id,
        "child_outputs": child_outputs,
      },
      summary=Some("Analysis requested and completed a child subplan"),
      metrics=result_metrics(execution),
      logs=[
        "report artifact written: \{report_artifact_id}",
        "result artifact written: \{result_artifact_id}",
        "spawned child job: \{child_job_id}",
        "spawned child run: \{child_run_id}",
      ],
    ),
  )
}

///|
async fn resolved_adaptive_envelope(
  executor : AnalysisExecutor,
  request : AnalysisRequest,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
) -> AdaptiveAnalysisEnvelope? {
  if analysis_adaptive_disabled(config) {
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
}

///|
pub async fn resolve_adaptive_analysis_result(
  runtime : RuntimeManager,
  compiler : ProposalCompiler?,
  engine_factory : (() -> WorkflowEngine)?,
  child_executor : ChildRunExecutor?,
  executor : AnalysisExecutor,
  request : AnalysisRequest,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
  completed_result : Result[WorkflowStepResult, String],
  report_artifact_id : String,
  result_artifact_id : String,
  now : () -> Int,
  next_run_id : () -> String,
) -> Result[WorkflowStepResult, String]? {
  let adaptive_envelope = resolved_adaptive_envelope(
    executor, request, context, config, execution,
  )
  let adaptive_max_depth = configured_adaptive_subplan_max_depth(
    request.cwd,
    request.home,
  ).unwrap_or(5)
  match adaptive_envelope {
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
                          adaptive_subplanned_result(
                            execution,
                            report_artifact_id,
                            result_artifact_id,
                            child_job_id,
                            child_run_id,
                            child_outputs.to_json(),
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
}
