///|
fn acp_analysis_execution_requested(mode : String?) -> Bool {
  match mode {
    Some(mode) => mode.trim().to_owned() == "acp"
    None => false
  }
}

///|
fn analysis_acp_session_id(run_id : String, step_id : String) -> String {
  "job-analysis-\{run_id}-\{step_id}"
}

///|
fn analysis_acp_session_key(run_id : String, step_id : String) -> String {
  "job.analysis:\{run_id}:\{step_id}"
}

///|
fn analysis_acp_run_id(run_id : String, step_id : String) -> String {
  "acp-\{run_id}-\{step_id}"
}

///|
fn analysis_acp_message(request : AnalysisRequest) -> String {
  let builder = StringBuilder::new()
  builder.write_string(request.system_prompt.trim().to_owned())
  builder.write_string("\n\n")
  builder.write_string(request.prompt.trim().to_owned())
  builder.to_string().trim().to_owned()
}

///|
fn analysis_acp_linkage_metadata(request : AnalysisRequest) -> Json {
  let fields : Map[String, Json] = {}
  fields["job_id"] = request.job_id.to_json()
  fields["job_run_id"] = request.run_id.to_json()
  fields["job_step_id"] = request.step_id.to_json()
  fields["execution_mode"] = "acp".to_json()
  match request.execution_target {
    Some(target) => fields["execution_target"] = target.to_json()
    None => ()
  }
  match request.step_metadata {
    Object(object) =>
      for key, value in object {
        fields[key] = value
      }
    _ => ()
  }
  Json::object(fields)
}

///|
fn acp_result_content(result : Json) -> String {
  match result {
    { "content": String(content), .. } => content
    _ => result.stringify()
  }
}

///|
fn acp_result_status(result : Json) -> String {
  match result {
    { "status": String(status), .. } => status
    _ => "completed"
  }
}

///|
fn acp_result_error(result : Json) -> String? {
  match result {
    { "stderr": String(stderr), .. } if !stderr.trim().is_blank() =>
      Some(stderr.trim().to_owned())
    { "content": String(content), .. } if !content.trim().is_blank() =>
      Some(content.trim().to_owned())
    _ => None
  }
}

///|
fn acp_result_patch_receipt(result : Json) -> Json? {
  match result {
    { "patch_receipt": receipt, .. } => Some(receipt)
    _ => None
  }
}

///|
fn acp_patch_receipt_result_decision(receipt : Json) -> String? {
  match receipt {
    Object(object) =>
      match object.get("result_decision") {
        Some(String(decision)) => Some(decision)
        _ => None
      }
    _ => None
  }
}

///|
fn current_analysis_time_ms() -> Int {
  @async.now().to_int()
}

///|
async fn run_acp_analysis_runner(
  request : AnalysisRequest,
) -> Result[AnalysisExecution, String] {
  let target_id = match request.execution_target {
    Some(target_id) if !target_id.trim().to_owned().is_blank() =>
      target_id.trim().to_owned()
    _ => return Err("ACP analysis execution requires execution_target")
  }
  let home = request.home.unwrap_or(request.cwd)
  let runtime = @acp.AcpRuntime::new(home~, cwd=request.cwd)
  let now_ms = current_analysis_time_ms()
  let session = match
    runtime.open_session(
      analysis_acp_session_id(request.run_id, request.step_id),
      target_id,
      analysis_acp_session_key(request.run_id, request.step_id),
      now_ms,
      metadata={
        "job_id": request.job_id,
        "job_run_id": request.run_id,
        "job_step_id": request.step_id,
      },
    ) {
    Ok(session) => session
    Err(error) => return Err(error)
  }
  let target = match runtime.get_target(target_id) {
    Some(target) => target
    None => return Err("Unknown ACP target: \{target_id}")
  }
  let acp_run_id = analysis_acp_run_id(request.run_id, request.step_id)
  let metadata = analysis_acp_linkage_metadata(request)
  let run_request = @acp.new_run_request(
    message=analysis_acp_message(request),
    run_id=acp_run_id,
    model?=if request.model_name == "default" {
      None
    } else {
      Some(request.model_name)
    },
    metadata~,
  )
  let launch = match @acp.prepare_launch_plan(target, session, run_request) {
    Ok(launch) => launch
    Err(error) => return Err(error)
  }
  ignore(
    runtime.start_run(
      acp_run_id,
      session,
      target,
      run_request.to_json(),
      launch.to_json(),
      now_ms,
    ),
  )
  ignore(runtime.set_session_status(session.id, "running", now_ms))
  let result = match @acp.execute_launch_plan(launch, run_request) {
    Ok(result) => result
    Err(error) => {
      let failed_at = current_analysis_time_ms()
      ignore(
        runtime.finish_run(acp_run_id, "failed", failed_at, error=Some(error)),
      )
      ignore(
        runtime.set_session_status(
          session.id,
          "failed",
          failed_at,
          last_error=Some(error),
        ),
      )
      return Err(error)
    }
  }
  let status = acp_result_status(result)
  let result_error = if status == "completed" {
    None
  } else {
    acp_result_error(result)
  }
  let finished_at = current_analysis_time_ms()
  ignore(
    runtime.finish_run(
      acp_run_id,
      status,
      finished_at,
      result=Some(result),
      error=result_error,
    ),
  )
  ignore(
    runtime.set_session_status(
      session.id,
      status,
      finished_at,
      last_error=result_error,
    ),
  )
  if status != "completed" {
    return Err(result_error.unwrap_or("ACP analysis execution failed"))
  }
  let model_name = if request.model_name == "default" {
    target.label.unwrap_or(target.id)
  } else {
    request.model_name
  }
  let execution_metadata : Map[String, Json] = {
    "job_id": request.job_id,
    "run_id": request.run_id,
    "step_id": request.step_id,
    "execution_mode": "acp",
    "execution_target": target_id,
    "acp_run_id": acp_run_id,
    "acp_session_id": session.id,
  }
  match acp_result_patch_receipt(result) {
    Some(receipt) => {
      execution_metadata["patch_receipt"] = receipt
      match acp_patch_receipt_result_decision(receipt) {
        Some(decision) =>
          execution_metadata["result_decision"] = decision.to_json()
        None => ()
      }
    }
    None => ()
  }
  Ok({
    model_name,
    content: acp_result_content(result),
    conversation_id: Some(acp_run_id),
    usage: None,
    metadata: Json::object(execution_metadata),
  })
}
