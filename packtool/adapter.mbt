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
