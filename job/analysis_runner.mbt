///|

///|
fn analysis_execution_metadata(request : AnalysisRequest) -> Json {
  {
    "job_id": request.job_id,
    "run_id": request.run_id,
    "step_id": request.step_id,
    "execution_isolation": request.execution_isolation,
    "role_runtime_contract": request.role_runtime_contract,
  }
}

///|
fn provider_task_single_response_requested(request : AnalysisRequest) -> Bool {
  let provider_task_requested = provider_execution_requested(
      request.execution_mode,
    ) &&
    metadata_string_value(request.step_metadata, "extension_task_id") is Some(_)
  provider_task_requested &&
  (
    metadata_bool_with_step_metadata(
      request.step_metadata,
      "provider_force_single_response",
      false,
    ) ||
    !request.enable_tools
  )
}

///|
fn analysis_request_timeout_ms(request : AnalysisRequest) -> Int? {
  metadata_int_with_step_metadata_option(request.step_metadata, "timeout_ms")
}

///|
async fn run_single_response_analysis_runner(
  request : AnalysisRequest,
) -> Result[AnalysisExecution, String] {
  let requested_model = resolved_model_name(request)
  guard @model.load(
      home?=request.home.map(fn(home) { home }),
      cwd=request.cwd,
      name?=requested_model,
    )
    is Some(model) else {
    return Err("Model not found: \{request.model_name}")
  }
  let logger = @pino.logger("job-analysis", @pino.Transport::console())
  let mut final_content = ""
  let response = @openai.chat_with_text_deltas(
    model~,
    @openai.chat_completion(
      messages=[
        @openai.system_message(content=request.system_prompt),
        @openai.user_message(content=request.prompt),
      ],
      model=model.model_name,
      response_format=JsonObject,
      tool_choice=Disallow,
      stream=true,
      usage=@openai.usage(include_=true),
      stream_options=@openai.stream_options(include_usage=true),
    ),
    logger~,
    on_text_delta=delta => {
      let chunk = delta.to_string()
      if !chunk.is_blank() {
        final_content = final_content + chunk
      }
    },
    timeout_ms=analysis_request_timeout_ms(request),
  )
  guard !response.choices.is_empty() else {
    return Err("Analysis agent failed: empty choices")
  }
  let message = response.choices[0].message
  let content = message.content.unwrap_or("").trim().to_owned()
  let final_content = if !content.is_blank() {
    content
  } else {
    final_content.trim().to_owned()
  }
  Ok({
    model_name: model.name,
    content: final_content,
    conversation_id: None,
    usage: response.usage.map(fn(usage) { @ai.Usage::from_openai(usage) }),
    metadata: analysis_execution_metadata(request),
  })
}

///|
async fn run_local_analysis_runner(
  request : AnalysisRequest,
) -> Result[AnalysisExecution, String] {
  if provider_task_single_response_requested(request) {
    return run_single_response_analysis_runner(request)
  }
  let requested_model = resolved_model_name(request)
  guard @model.load(
      home?=request.home.map(fn(home) { home }),
      cwd=request.cwd,
      name?=requested_model,
    )
    is Some(model) else {
    return Err("Model not found: \{request.model_name}")
  }
  let logger = @pino.logger("job-analysis", @pino.Transport::console())
  let agent = @agent.new(
    model,
    logger~,
    home?=request.home.map(fn(home) { home }),
    cwd=request.cwd,
    system_message=request.system_prompt,
    user_message=request.prompt,
    web_search=request.web_search,
    request_timeout_ms=analysis_request_timeout_ms(request),
  )
  defer agent.close()
  if request.enable_tools {
    let sandbox_config = if constrain_tool_contract_for_request(request).shell {
      @moonfort_config.load_sandbox_executor_config()
    } else {
      None
    }
    configure_analysis_agent_for_request(agent, request, sandbox_config?)
  }

  let mut final_content = ""
  let delta_content = StringBuilder::new()
  let mut final_usage : @ai.Usage? = None
  let mut failed : String? = None
  let tool_journal : Array[Json] = []
  agent.event_target.add_listener(event => {
    match event.desc {
      AssistantMessageDelta(content) =>
        if !content.is_blank() {
          delta_content.write_string(content)
        }
      PreToolCall(tool_call) =>
        push_analysis_tool_journal_entry(
          tool_journal,
          analysis_tool_call_start_entry(tool_call),
        )
      PostToolCall(tool_call, result~, rendered~) =>
        push_analysis_tool_journal_entry(
          tool_journal,
          analysis_tool_call_finish_entry(tool_call, result, rendered),
        )
      AssistantMessage(usage~, tool_calls~, content) => {
        if !content.is_blank() {
          final_content = content
        }
        if usage is Some(usage) {
          final_usage = Some(usage)
        }
        ignore(tool_calls)
      }
      Failed(error) => failed = Some(error.stringify())
      _ => ()
    }
  })

  match analysis_request_timeout_ms(request) {
    Some(timeout_ms) if timeout_ms > 0 =>
      @async.with_timeout(timeout_ms, () => agent.start()) catch {
        @async.TimeoutError => {
          if failed is Some(error) {
            return Err("Analysis agent failed: \{error}")
          }
          let partial = if !final_content.is_blank() {
            final_content
          } else {
            delta_content.to_string().trim().to_owned()
          }
          if partial.is_blank() {
            return Err(
              "Analysis agent timed out before producing a final answer after \{timeout_ms}ms",
            )
          }
        }
        error => return Err("Analysis agent failed: \{error}")
      }
    _ =>
      agent.start() catch {
        error => return Err("Analysis agent failed: \{error}")
      }
  }
  if failed is Some(error) {
    return Err(error)
  }
  if final_content.is_blank() {
    let fallback = delta_content.to_string().trim().to_owned()
    if !fallback.is_blank() {
      final_content = fallback
    }
  }
  Ok({
    model_name: model.name,
    content: final_content,
    conversation_id: Some(agent.id().to_string()),
    usage: final_usage,
    metadata: analysis_execution_metadata_with_tool_journal(
      request, tool_journal,
    ),
  })
}

///|
pub async fn run_default_analysis_runner(
  request : AnalysisRequest,
) -> Result[AnalysisExecution, String] {
  if acp_analysis_execution_requested(request.execution_mode) {
    return run_acp_analysis_runner(request)
  }
  // Provider-backed execution still reuses the normal local analysis runner for
  // the actual reasoning loop; only task shaping and persistence are delegated.
  if provider_execution_requested(request.execution_mode) {
    return run_provider_task_analysis_runner(request, run_local_analysis_runner)
  }
  run_local_analysis_runner(request)
}
