///|
/// Generic execution request passed from MoonClaw to a pack-owned executor.
pub(all) struct PackToolExecutionRequest {
  binding : ToolBinding
  config : Json
  initial_input : Json?
  outputs : Map[String, Json]
  request_id : String
  attempt_id : String
  idempotency_key : String
  operation_ref : String
  run_id : String
  step_id : String
  evidence_path : String
  attempt : Int
  estimated_cost_micros : Int
} derive(Debug, ToJson, FromJson)

///|
/// Generic result returned by a pack-owned executor.
pub(all) struct PackToolExecutionResult {
  status : String
  output : Json
  summary : String?
  metrics : Json
  logs : Array[String]
  output_artifacts : Array[String]
  external_job_id : String
  compensable : Bool
} derive(Debug, ToJson, FromJson)

///|
pub fn PackToolExecutionResult::new(
  output~ : Json,
  status? : String = "succeeded",
  summary? : String? = None,
  metrics? : Json = Json::empty_object(),
  logs? : Array[String] = [],
  output_artifacts? : Array[String] = [],
  external_job_id? : String = "",
  compensable? : Bool = false,
) -> PackToolExecutionResult {
  {
    status,
    output,
    summary,
    metrics,
    logs,
    output_artifacts,
    external_job_id,
    compensable,
  }
}

///|
/// Result of asking a pack-owned adapter to reconcile a previously submitted
/// idempotency key. A terminal success must carry the original tool result.
pub(all) struct PackToolReconciliation {
  status : String
  result : PackToolExecutionResult?
  error_kind : String
} derive(Debug, ToJson, FromJson)

///|
/// Opaque pack execution boundary supplied by the host.
pub struct PackToolExecutor {
  estimate_cost_micros : (ToolBinding, Json) -> Int
  run : async (PackToolExecutionRequest) -> Result[
    PackToolExecutionResult,
    String,
  ]
  reconcile : (async (PackToolExecutionRequest) -> Result[
    PackToolReconciliation,
    String,
  ])?
  cancel : (async (PackToolExecutionRequest) -> Result[
    PackToolReconciliation,
    String,
  ])?
}

///|
pub fn PackToolExecutor::new(
  run~ : async (PackToolExecutionRequest) -> Result[
    PackToolExecutionResult,
    String,
  ],
  estimate_cost_micros? : (ToolBinding, Json) -> Int = (_, _) => 0,
  reconcile? : (async (PackToolExecutionRequest) -> Result[
    PackToolReconciliation,
    String,
  ])? = None,
  cancel? : (async (PackToolExecutionRequest) -> Result[
    PackToolReconciliation,
    String,
  ])? = None,
) -> PackToolExecutor {
  { estimate_cost_micros, run, reconcile, cancel }
}

///|
fn pack_tool_evidence_path(
  binding : ToolBinding,
  run_id : String,
  step_id : String,
) -> String {
  match binding.evidence_outputs.get(0) {
    Some(prefix) => "\{prefix}/\{run_id}/\{step_id}.json"
    None => ""
  }
}

///|
fn pack_tool_step_request(
  context : @job.WorkflowStepContext,
  executor : PackToolExecutor,
) -> Result[PackToolExecutionRequest, String] {
  guard context.step.config
    is {
      "contract": String(contract),
      "pack_id": String(pack_id),
      "product_id": String(product_id),
      "tool": tool,
      "config": config,
      ..
    } else {
    return Err("invalid compiled pack tool step config")
  }
  if contract != "moonsuite.pack-tool-step.v1" {
    return Err("unsupported compiled pack tool step contract")
  }
  let binding : ToolBinding = @json.from_json(tool) catch {
    error => return Err("invalid compiled pack tool binding: \{error}")
  }
  if binding.pack_id != pack_id || binding.product_id != product_id {
    return Err("compiled pack tool ownership does not match its binding")
  }
  let estimated_cost_micros = (executor.estimate_cost_micros)(binding, config)
  Ok({
    binding,
    config,
    initial_input: context.initial_input,
    outputs: context.outputs,
    request_id: "\{context.run.id}/\{context.step.id}",
    attempt_id: "\{context.run.id}/\{context.step.id}/\{context.run.attempt}",
    idempotency_key: "\{context.run.id}/\{context.step.id}/\{context.run.attempt}",
    operation_ref: "\{binding.product_id}/\{binding.tool_id}",
    run_id: context.run.id,
    step_id: context.step.id,
    evidence_path: pack_tool_evidence_path(
      binding,
      context.run.id,
      context.step.id,
    ),
    attempt: context.run.attempt,
    estimated_cost_micros,
  })
}

///|
/// Build the generic MoonClaw handler used by compiled MoonPack tool steps.
pub fn pack_tool_step_handler(
  executor : PackToolExecutor,
  policy : InvocationPolicy,
) -> @job.WorkflowStepHandler {
  @job.WorkflowStepHandler::new(kind="moonsuite.pack.tool", run=async fn(
    context,
  ) {
    let request = match pack_tool_step_request(context, executor) {
      Ok(request) => request
      Err(error) => return Err(error)
    }
    let decision = authorize(
      request.binding,
      {
        tool_id: request.binding.tool_id,
        input_schema_id: request.binding.input_schema_id,
        output_schema_id: request.binding.output_schema_id,
        evidence_path: request.evidence_path,
        attempt: request.attempt,
        estimated_cost_micros: request.estimated_cost_micros,
      },
      policy,
    )
    if !decision.allowed {
      return Err("pack tool invocation denied: " + decision.issues.join("; "))
    }
    match (executor.run)(request) {
      Ok(result) =>
        Ok(
          @job.WorkflowStepResult::new(
            output=result.output,
            summary=result.summary,
            metrics=result.metrics,
            logs=result.logs,
          ),
        )
      Err(error) => Err(error)
    }
  })
}
