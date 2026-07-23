///|
/// A policy-free tool binding projected from the shared pack contract.
pub(all) struct ToolBinding {
  pack_id : String
  product_id : String
  tool_id : String
  input_schema_id : String
  output_schema_id : String
  authority : @pack.AuthorityClass
  idempotent : Bool
  evidence_outputs : Array[String]
  review_required : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct InvocationRequest {
  tool_id : String
  input_schema_id : String
  output_schema_id : String
  evidence_path : String
  attempt : Int
  estimated_cost_micros : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct InvocationPolicy {
  granted_authorities : Array[@pack.AuthorityClass]
  reviewed_tool_ids : Array[String]
  max_attempts : Int
  timeout_ms : Int
  remaining_budget_micros : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct InvocationDecision {
  allowed : Bool
  issues : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn bindings(
  projection : @host.HostActivationProjection,
) -> Array[ToolBinding] raise {
  if projection.contract != "moonsuite.pack-host-activation.v1" {
    fail("unsupported pack host projection")
  }
  projection.tools.map(tool => {
    if tool.owner_product != projection.product_id {
      fail("tool owner does not match projected product: " + tool.id)
    }
    {
      pack_id: projection.pack_id,
      product_id: projection.product_id,
      tool_id: tool.id,
      input_schema_id: tool.input_schema_id,
      output_schema_id: tool.output_schema_id,
      authority: tool.authority,
      idempotent: tool.idempotent,
      evidence_outputs: tool.evidence_outputs,
      review_required: tool.review_required,
    }
  })
}

///|
pub fn resolve(
  projected : Array[ToolBinding],
  tool_id : String,
) -> ToolBinding? {
  for binding in projected {
    if binding.tool_id == tool_id {
      return Some(binding)
    }
  }
  None
}

///|
/// Authorizes one concrete call. Installation authority is only a ceiling;
/// review, schema, evidence, retry, timeout, and cost checks happen per call.
pub fn authorize(
  binding : ToolBinding,
  request : InvocationRequest,
  policy : InvocationPolicy,
) -> InvocationDecision {
  let issues : Array[String] = []
  if request.tool_id != binding.tool_id {
    issues.push("tool id does not match binding")
  }
  if request.input_schema_id != binding.input_schema_id ||
    request.output_schema_id != binding.output_schema_id {
    issues.push("invocation schema does not match binding")
  }
  if !policy.granted_authorities.contains(binding.authority) {
    issues.push("tool authority is not granted")
  }
  if binding.review_required &&
    !policy.reviewed_tool_ids.contains(binding.tool_id) {
    issues.push("tool requires a review receipt")
  }
  if request.attempt < 1 || request.attempt > policy.max_attempts {
    issues.push("attempt is outside the retry policy")
  }
  if request.attempt > 1 && !binding.idempotent {
    issues.push("non-idempotent tool cannot be retried")
  }
  if policy.timeout_ms <= 0 {
    issues.push("positive timeout is required")
  }
  if request.estimated_cost_micros < 0 ||
    request.estimated_cost_micros > policy.remaining_budget_micros {
    issues.push("invocation exceeds the remaining cost budget")
  }
  if binding.evidence_outputs.is_empty() {
    if !request.evidence_path.is_blank() {
      issues.push(
        "tool without evidence outputs cannot declare an evidence path",
      )
    }
  } else if !binding.evidence_outputs.any(prefix => {
      request.evidence_path == prefix ||
      request.evidence_path.has_prefix(prefix + "/")
    }) {
    issues.push("evidence path is outside the declared outputs")
  }
  { allowed: issues.is_empty(), issues }
}
