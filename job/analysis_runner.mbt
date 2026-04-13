///|
async fn run_local_analysis_runner(
  request : AnalysisRequest,
) -> Result[AnalysisExecution, String] {
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
    configure_analysis_agent_for_request(agent, request)
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
      "execution_isolation": request.execution_isolation,
      "role_runtime_contract": request.role_runtime_contract,
    },
  })
}

///|
pub async fn run_default_analysis_runner(
  request : AnalysisRequest,
) -> Result[AnalysisExecution, String] {
  if provider_execution_requested(request.execution_mode) {
    return run_provider_task_analysis_runner(request, run_local_analysis_runner)
  }
  run_local_analysis_runner(request)
}
