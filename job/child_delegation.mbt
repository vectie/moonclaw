///|
/// A child runtime may produce evidence, a draft, or a reviewable result. It
/// can never delegate final acceptance or publication authority.
pub(all) enum DelegationClaimCeilingV1 {
  EvidenceOnly
  Draft
  Reviewable
} derive(Debug, Eq)

///|
pub fn DelegationClaimCeilingV1::id(self : DelegationClaimCeilingV1) -> String {
  match self {
    EvidenceOnly => "evidence-only"
    Draft => "draft"
    Reviewable => "reviewable"
  }
}

///|
fn delegation_claim_ceiling_from_id(
  value : String,
) -> DelegationClaimCeilingV1 raise {
  match value {
    "evidence-only" => EvidenceOnly
    "draft" => Draft
    "reviewable" => Reviewable
    _ => fail("unsupported child delegation claim ceiling")
  }
}

///|
fn delegation_claim_rank(value : DelegationClaimCeilingV1) -> Int {
  match value {
    EvidenceOnly => 0
    Draft => 1
    Reviewable => 2
  }
}

///|
pub struct ChildDelegationV1 {
  reference : @capability.DelegationRefV1
  parent_run_id : String
  child_run_id : String
  parent_principal : @capability.PrincipalRefV1
  child_principal : @capability.PrincipalRefV1
  allowed_operations : ReadOnlyArray[@capability.OperationRef]
  artifact_prefixes : ReadOnlyArray[String]
  claim_ceiling : DelegationClaimCeilingV1
  budget : @capability.HandoverBudgetCeilingsV1
  authority : @capability.AuthorityDecisionRefV1
  issued_at : String
  expires_at : String
  parent_delegation : @capability.DelegationRefV1?
} derive(Debug, Eq)

///|
pub fn ChildDelegationV1::reference(
  self : ChildDelegationV1,
) -> @capability.DelegationRefV1 {
  self.reference
}

///|
pub fn ChildDelegationV1::allowed_operations(
  self : ChildDelegationV1,
) -> ReadOnlyArray[@capability.OperationRef] {
  self.allowed_operations
}

///|
pub fn ChildDelegationV1::artifact_prefixes(
  self : ChildDelegationV1,
) -> ReadOnlyArray[String] {
  self.artifact_prefixes
}

///|
pub fn ChildDelegationV1::claim_ceiling(
  self : ChildDelegationV1,
) -> DelegationClaimCeilingV1 {
  self.claim_ceiling
}

///|
pub fn ChildDelegationV1::budget(
  self : ChildDelegationV1,
) -> @capability.HandoverBudgetCeilingsV1 {
  self.budget
}

///|
pub fn ChildDelegationV1::expires_at(self : ChildDelegationV1) -> String {
  self.expires_at
}

///|
priv struct ChildDelegationPayloadWireV1 {
  contract_id : String
  delegation_id : String
  parent_run_id : String
  child_run_id : String
  parent_principal : Json
  child_principal : Json
  allowed_operations : Array[Json]
  artifact_prefixes : Array[String]
  claim_ceiling : String
  max_cost_micro_usd : Int64?
  max_runtime_ms : Int64?
  max_tokens : Int64?
  max_artifacts : Int?
  authority : Json
  issued_at : String
  expires_at : String
  parent_delegation : Json?
} derive(ToJson, FromJson)

///|
priv struct ChildDelegationWireV1 {
  payload : Json
  delegation_ref : Json
} derive(ToJson, FromJson)

///|
fn child_runtime_ref_is_canonical(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 512 &&
  value
  .iter()
  .all(char => {
    char.is_ascii_alphabetic() ||
    char.is_ascii_digit() ||
    char == '.' ||
    char == '-' ||
    char == '_' ||
    char == ':' ||
    char == '/' ||
    char == '@'
  })
}

///|
fn child_delegation_payload_v1(
  delegation_id : String,
  parent_run_id : String,
  child_run_id : String,
  parent_principal : @capability.PrincipalRefV1,
  child_principal : @capability.PrincipalRefV1,
  allowed_operations : Array[@capability.OperationRef],
  artifact_prefixes : Array[String],
  claim_ceiling : DelegationClaimCeilingV1,
  budget : @capability.HandoverBudgetCeilingsV1,
  authority : @capability.AuthorityDecisionRefV1,
  issued_at : String,
  expires_at : String,
  parent_delegation : @capability.DelegationRefV1?,
) -> ChildDelegationPayloadWireV1 {
  {
    contract_id: "moonclaw.child-delegation.v1",
    delegation_id,
    parent_run_id,
    child_run_id,
    parent_principal: @capability.encode_principal_ref_v1(parent_principal),
    child_principal: @capability.encode_principal_ref_v1(child_principal),
    allowed_operations: allowed_operations.map(operation => {
      @capability.encode_operation_ref_v1(operation)
    }),
    artifact_prefixes,
    claim_ceiling: claim_ceiling.id(),
    max_cost_micro_usd: budget.max_cost_micro_usd(),
    max_runtime_ms: budget.max_runtime_ms(),
    max_tokens: budget.max_tokens(),
    max_artifacts: budget.max_artifacts(),
    authority: @capability.encode_authority_decision_ref_v1(authority),
    issued_at,
    expires_at,
    parent_delegation: parent_delegation.map(reference => {
      @capability.encode_delegation_ref_v1(reference)
    }),
  }
}

///|
fn validate_child_delegation_scope_v1(
  delegation_id : String,
  parent_run_id : String,
  child_run_id : String,
  parent_principal : @capability.PrincipalRefV1,
  child_principal : @capability.PrincipalRefV1,
  allowed_operations : Array[@capability.OperationRef],
  artifact_prefixes : Array[String],
  authority : @capability.AuthorityDecisionRefV1,
  issued_at : String,
  expires_at : String,
) -> Unit raise {
  guard @capability.identifier_component_is_canonical(delegation_id) &&
    child_runtime_ref_is_canonical(parent_run_id) &&
    child_runtime_ref_is_canonical(child_run_id) &&
    parent_run_id != child_run_id &&
    parent_principal != child_principal &&
    child_principal.kind() == Agent &&
    parent_principal.kind() != Human &&
    !allowed_operations.is_empty() &&
    !artifact_prefixes.is_empty() &&
    @capability.wire_timestamp_is_canonical(issued_at) &&
    @capability.wire_timestamp_is_canonical(expires_at) &&
    issued_at < expires_at else {
    fail("child delegation identity, scope, or lifetime is invalid")
  }
  guard authority.is_fresh_for(child_principal, issued_at) &&
    authority.expires_at() >= expires_at else {
    fail(
      "child delegation requires receiver-bound authority for its full lifetime",
    )
  }
  let operation_ids : Array[String] = []
  for operation in allowed_operations {
    let id = operation.format()
    guard !operation_ids.contains(id) else {
      fail("child delegation contains a duplicate operation")
    }
    operation_ids.push(id)
  }
  let prefixes : Array[String] = []
  for prefix in artifact_prefixes {
    guard @capability.evidence_artifact_ref_is_canonical(prefix) &&
      !prefix.contains("*") &&
      !prefixes.contains(prefix) else {
      fail("child delegation artifact prefixes must be unique exact paths")
    }
    prefixes.push(prefix)
  }
}

///|
/// Metered consumption presented at the exact authorization boundary. A
/// budgeted dimension must carry both prior and requested usage; omitting that
/// evidence fails closed rather than turning a ceiling into documentation.
pub struct ChildDelegationConsumptionV1 {
  accumulated_cost_micro_usd : Int64?
  requested_cost_micro_usd : Int64?
  accumulated_runtime_ms : Int64?
  requested_runtime_ms : Int64?
  accumulated_tokens : Int64?
  requested_tokens : Int64?
  accumulated_artifacts : Int?
  requested_artifacts : Int?
  evidence : @capability.ContentAddressedEvidenceRefV1
} derive(Debug, Eq)

///|
pub fn child_delegation_consumption_v1(
  accumulated_cost_micro_usd? : Int64,
  requested_cost_micro_usd? : Int64,
  accumulated_runtime_ms? : Int64,
  requested_runtime_ms? : Int64,
  accumulated_tokens? : Int64,
  requested_tokens? : Int64,
  accumulated_artifacts? : Int,
  requested_artifacts? : Int,
  evidence : @capability.ContentAddressedEvidenceRefV1,
) -> ChildDelegationConsumptionV1 raise {
  let i64_values = [
    accumulated_cost_micro_usd, requested_cost_micro_usd, accumulated_runtime_ms,
    requested_runtime_ms, accumulated_tokens, requested_tokens,
  ]
  let int_values = [accumulated_artifacts, requested_artifacts]
  guard !i64_values.any(value => value is Some(amount) && amount < 0L) &&
    !int_values.any(value => value is Some(amount) && amount < 0) else {
    fail("child delegation consumption cannot be negative")
  }
  {
    accumulated_cost_micro_usd,
    requested_cost_micro_usd,
    accumulated_runtime_ms,
    requested_runtime_ms,
    accumulated_tokens,
    requested_tokens,
    accumulated_artifacts,
    requested_artifacts,
    evidence,
  }
}

///|
fn i64_consumption_within_ceiling(
  ceiling : Int64?,
  accumulated : Int64?,
  requested : Int64?,
) -> Bool {
  match (ceiling, accumulated, requested) {
    (Some(limit), Some(before), Some(next)) =>
      before >= 0L && next >= 0L && before <= limit && next <= limit - before
    (None, None, None) => true
    _ => false
  }
}

///|
fn int_consumption_within_ceiling(
  ceiling : Int?,
  accumulated : Int?,
  requested : Int?,
) -> Bool {
  match (ceiling, accumulated, requested) {
    (Some(limit), Some(before), Some(next)) =>
      before >= 0 && next >= 0 && before <= limit && next <= limit - before
    (None, None, None) => true
    _ => false
  }
}

///|
fn build_child_delegation_v1(
  delegation_id : String,
  parent_run_id : String,
  child_run_id : String,
  parent_principal : @capability.PrincipalRefV1,
  child_principal : @capability.PrincipalRefV1,
  allowed_operations : Array[@capability.OperationRef],
  artifact_prefixes : Array[String],
  claim_ceiling : DelegationClaimCeilingV1,
  budget : @capability.HandoverBudgetCeilingsV1,
  authority : @capability.AuthorityDecisionRefV1,
  issued_at : String,
  expires_at : String,
  parent_delegation : @capability.DelegationRefV1?,
) -> ChildDelegationV1 raise {
  validate_child_delegation_scope_v1(
    delegation_id, parent_run_id, child_run_id, parent_principal, child_principal,
    allowed_operations, artifact_prefixes, authority, issued_at, expires_at,
  )
  let payload = child_delegation_payload_v1(
    delegation_id, parent_run_id, child_run_id, parent_principal, child_principal,
    allowed_operations, artifact_prefixes, claim_ceiling, budget, authority, issued_at,
    expires_at, parent_delegation,
  )
  let digest = @capability.sha256_digest_ref_v1(
    @encoding/utf8.encode(@json.to_json(payload).stringify()),
  )
  let reference = @capability.delegation_ref_v1(
    delegation_id,
    parent_principal,
    child_principal,
    digest.text(),
    parent_digest?=parent_delegation.map(value => value.digest().text()),
  )
  {
    reference,
    parent_run_id,
    child_run_id,
    parent_principal,
    child_principal,
    allowed_operations: ReadOnlyArray::from_array(allowed_operations),
    artifact_prefixes: ReadOnlyArray::from_array(artifact_prefixes),
    claim_ceiling,
    budget,
    authority,
    issued_at,
    expires_at,
    parent_delegation,
  }
}

///|
pub fn issue_child_delegation_v1(
  delegation_id : String,
  parent_run_id : String,
  child_run_id : String,
  parent_principal : @capability.PrincipalRefV1,
  child_principal : @capability.PrincipalRefV1,
  allowed_operations : Array[@capability.OperationRef],
  artifact_prefixes : Array[String],
  claim_ceiling : DelegationClaimCeilingV1,
  budget : @capability.HandoverBudgetCeilingsV1,
  authority : @capability.AuthorityDecisionRefV1,
  issued_at : String,
  expires_at : String,
) -> ChildDelegationV1 raise {
  build_child_delegation_v1(
    delegation_id,
    parent_run_id,
    child_run_id,
    parent_principal,
    child_principal,
    allowed_operations,
    artifact_prefixes,
    claim_ceiling,
    budget,
    authority,
    issued_at,
    expires_at,
    None,
  )
}

///|
fn optional_i64_is_narrower(child : Int64?, parent : Int64?) -> Bool {
  match (child, parent) {
    (None, _) => true
    (Some(_), None) => false
    (Some(child_value), Some(parent_value)) => child_value <= parent_value
  }
}

///|
fn optional_int_is_narrower(child : Int?, parent : Int?) -> Bool {
  match (child, parent) {
    (None, _) => true
    (Some(_), None) => false
    (Some(child_value), Some(parent_value)) => child_value <= parent_value
  }
}

///|
fn child_prefix_is_within(child : String, parent : String) -> Bool {
  child == parent || child.has_prefix(parent + "/")
}

///|
/// Produces a strictly bounded child of an existing runtime-local delegation.
/// It does not schedule work or grant any cross-product authority.
pub fn narrow_child_delegation_v1(
  parent : ChildDelegationV1,
  delegation_id : String,
  child_run_id : String,
  child_principal : @capability.PrincipalRefV1,
  allowed_operations : Array[@capability.OperationRef],
  artifact_prefixes : Array[String],
  claim_ceiling : DelegationClaimCeilingV1,
  budget : @capability.HandoverBudgetCeilingsV1,
  authority : @capability.AuthorityDecisionRefV1,
  issued_at : String,
  expires_at : String,
) -> ChildDelegationV1 raise {
  guard issued_at >= parent.issued_at &&
    expires_at <= parent.expires_at &&
    delegation_claim_rank(claim_ceiling) <=
    delegation_claim_rank(parent.claim_ceiling) &&
    allowed_operations.all(operation => {
      parent.allowed_operations.contains(operation)
    }) &&
    artifact_prefixes.all(prefix => {
      parent.artifact_prefixes.any(parent_prefix => {
        child_prefix_is_within(prefix, parent_prefix)
      })
    }) &&
    optional_i64_is_narrower(
      budget.max_cost_micro_usd(),
      parent.budget.max_cost_micro_usd(),
    ) &&
    optional_i64_is_narrower(
      budget.max_runtime_ms(),
      parent.budget.max_runtime_ms(),
    ) &&
    optional_i64_is_narrower(budget.max_tokens(), parent.budget.max_tokens()) &&
    optional_int_is_narrower(
      budget.max_artifacts(),
      parent.budget.max_artifacts(),
    ) else {
    fail("child delegation must be a subset of its parent")
  }
  build_child_delegation_v1(
    delegation_id,
    parent.child_run_id,
    child_run_id,
    parent.child_principal,
    child_principal,
    allowed_operations,
    artifact_prefixes,
    claim_ceiling,
    budget,
    authority,
    issued_at,
    expires_at,
    Some(parent.reference),
  )
}

///|
pub struct ChildDelegationUseReceiptV1 {
  delegation_ref : @capability.DelegationRefV1
  child_run_id : String
  operation : @capability.OperationRef
  artifact_refs : ReadOnlyArray[String]
  requested_claim : DelegationClaimCeilingV1
  consumption : ChildDelegationConsumptionV1
  evaluated_at : String
  receipt_digest : @capability.DigestRefV1
} derive(Debug, Eq)

///|
pub fn authorize_child_delegation_use_v1(
  delegation : ChildDelegationV1,
  child_principal : @capability.PrincipalRefV1,
  child_run_id : String,
  operation : @capability.OperationRef,
  artifact_refs : Array[String],
  requested_claim : DelegationClaimCeilingV1,
  consumption : ChildDelegationConsumptionV1,
  evaluated_at : String,
) -> Result[ChildDelegationUseReceiptV1, String] {
  guard child_principal == delegation.child_principal &&
    child_run_id == delegation.child_run_id &&
    @capability.wire_timestamp_is_canonical(evaluated_at) &&
    delegation.issued_at <= evaluated_at &&
    evaluated_at < delegation.expires_at &&
    delegation.allowed_operations.contains(operation) &&
    delegation_claim_rank(requested_claim) <=
    delegation_claim_rank(delegation.claim_ceiling) &&
    artifact_refs.all(reference => {
      @capability.evidence_artifact_ref_is_canonical(reference) &&
      delegation.artifact_prefixes.any(prefix => {
        child_prefix_is_within(reference, prefix)
      })
    }) &&
    i64_consumption_within_ceiling(
      delegation.budget.max_cost_micro_usd(),
      consumption.accumulated_cost_micro_usd,
      consumption.requested_cost_micro_usd,
    ) &&
    i64_consumption_within_ceiling(
      delegation.budget.max_runtime_ms(),
      consumption.accumulated_runtime_ms,
      consumption.requested_runtime_ms,
    ) &&
    i64_consumption_within_ceiling(
      delegation.budget.max_tokens(),
      consumption.accumulated_tokens,
      consumption.requested_tokens,
    ) &&
    int_consumption_within_ceiling(
      delegation.budget.max_artifacts(),
      consumption.accumulated_artifacts,
      consumption.requested_artifacts,
    ) &&
    consumption.requested_artifacts == Some(artifact_refs.length()) else {
    return Err("child operation exceeds delegation scope or lifetime")
  }
  let digest = @capability.sha256_digest_ref_v1(
    @encoding/utf8.encode(
      "\{delegation.reference.digest().text()}|\{child_run_id}|\{operation.format()}|\{artifact_refs.join(",")}|\{requested_claim.id()}|\{Repr(consumption.accumulated_cost_micro_usd)}|\{Repr(consumption.requested_cost_micro_usd)}|\{Repr(consumption.accumulated_runtime_ms)}|\{Repr(consumption.requested_runtime_ms)}|\{Repr(consumption.accumulated_tokens)}|\{Repr(consumption.requested_tokens)}|\{Repr(consumption.accumulated_artifacts)}|\{Repr(consumption.requested_artifacts)}|\{consumption.evidence.evidence_digest()}|\{evaluated_at}",
    ),
  )
  Ok({
    delegation_ref: delegation.reference,
    child_run_id,
    operation,
    artifact_refs: ReadOnlyArray::from_array(artifact_refs),
    requested_claim,
    consumption,
    evaluated_at,
    receipt_digest: digest,
  })
}

///|
/// Durable JSON evidence for the exact authorization consumed at the child
/// provider boundary.
pub fn encode_child_delegation_use_receipt_v1(
  receipt : ChildDelegationUseReceiptV1,
) -> Json {
  {
    "contract_id": "moonclaw.child-delegation-use-receipt.v1",
    "delegation_ref": @capability.encode_delegation_ref_v1(
      receipt.delegation_ref,
    ),
    "child_run_id": receipt.child_run_id,
    "operation": @capability.encode_operation_ref_v1(receipt.operation),
    "artifact_refs": receipt.artifact_refs.iter().to_array(),
    "requested_claim": receipt.requested_claim.id(),
    "consumption": {
      "accumulated_cost_micro_usd": receipt.consumption.accumulated_cost_micro_usd,
      "requested_cost_micro_usd": receipt.consumption.requested_cost_micro_usd,
      "accumulated_runtime_ms": receipt.consumption.accumulated_runtime_ms,
      "requested_runtime_ms": receipt.consumption.requested_runtime_ms,
      "accumulated_tokens": receipt.consumption.accumulated_tokens,
      "requested_tokens": receipt.consumption.requested_tokens,
      "accumulated_artifacts": receipt.consumption.accumulated_artifacts,
      "requested_artifacts": receipt.consumption.requested_artifacts,
      "evidence": receipt.consumption.evidence.to_json(),
    },
    "evaluated_at": receipt.evaluated_at,
    "receipt_digest": receipt.receipt_digest.text(),
  }
}

///|
/// Existing `job.delegate` child request plus the exact delegation-use receipt
/// that authorizes this runtime child. This is an adapter around MoonClaw's
/// established child-run path, not a second scheduler or agent runtime.
pub struct GovernedChildRunExecutionRequestV1 {
  request : ChildRunExecutionRequest
  delegation : ChildDelegationV1
  authorization : ChildDelegationUseReceiptV1
}

///|
pub fn GovernedChildRunExecutionRequestV1::request(
  self : GovernedChildRunExecutionRequestV1,
) -> ChildRunExecutionRequest {
  self.request
}

///|
pub fn GovernedChildRunExecutionRequestV1::authorization(
  self : GovernedChildRunExecutionRequestV1,
) -> ChildDelegationUseReceiptV1 {
  self.authorization
}

///|
/// Bind a real MoonClaw child execution request to its scoped delegation before
/// a host executor invokes it. Parent/child run identities must match exactly.
pub fn bind_child_run_execution_request_v1(
  request : ChildRunExecutionRequest,
  delegation : ChildDelegationV1,
  child_principal : @capability.PrincipalRefV1,
  operation : @capability.OperationRef,
  artifact_refs : Array[String],
  requested_claim : DelegationClaimCeilingV1,
  consumption : ChildDelegationConsumptionV1,
  evaluated_at : String,
) -> Result[GovernedChildRunExecutionRequestV1, String] {
  guard request.parent_context.run.id == delegation.parent_run_id &&
    request.child_run.id == delegation.child_run_id else {
    return Err("child execution request lineage does not match delegation")
  }
  match
    authorize_child_delegation_use_v1(
      delegation,
      child_principal,
      request.child_run.id,
      operation,
      artifact_refs,
      requested_claim,
      consumption,
      evaluated_at,
    ) {
    Ok(authorization) => Ok({ request, delegation, authorization })
    Err(reason) => Err(reason)
  }
}

///|
pub fn encode_child_delegation_v1(delegation : ChildDelegationV1) -> Json {
  let payload = child_delegation_payload_v1(
    delegation.reference.delegation_id(),
    delegation.parent_run_id,
    delegation.child_run_id,
    delegation.parent_principal,
    delegation.child_principal,
    delegation.allowed_operations.iter().to_array(),
    delegation.artifact_prefixes.iter().to_array(),
    delegation.claim_ceiling,
    delegation.budget,
    delegation.authority,
    delegation.issued_at,
    delegation.expires_at,
    delegation.parent_delegation,
  )
  ChildDelegationWireV1::{
    payload: @json.to_json(payload),
    delegation_ref: @capability.encode_delegation_ref_v1(delegation.reference),
  }
  |> @json.to_json
}

///|
/// Restores a delegation only after recomputing its content-addressed identity.
pub fn decode_child_delegation_v1(value : Json) -> ChildDelegationV1 raise {
  let wire : ChildDelegationWireV1 = @json.from_json(value)
  let payload : ChildDelegationPayloadWireV1 = @json.from_json(wire.payload)
  guard payload.contract_id == "moonclaw.child-delegation.v1" else {
    fail("unsupported child delegation contract")
  }
  let parent_delegation = payload.parent_delegation.map(value => {
    @capability.decode_delegation_ref_v1(value)
  })
  let rebuilt = build_child_delegation_v1(
    payload.delegation_id,
    payload.parent_run_id,
    payload.child_run_id,
    @capability.decode_principal_ref_v1(payload.parent_principal),
    @capability.decode_principal_ref_v1(payload.child_principal),
    payload.allowed_operations.map(value => {
      @capability.decode_operation_ref_v1(value)
    }),
    payload.artifact_prefixes,
    delegation_claim_ceiling_from_id(payload.claim_ceiling),
    @capability.handover_budget_ceilings_v1(
      max_cost_micro_usd?=payload.max_cost_micro_usd,
      max_runtime_ms?=payload.max_runtime_ms,
      max_tokens?=payload.max_tokens,
      max_artifacts?=payload.max_artifacts,
    ),
    @capability.decode_authority_decision_ref_v1(payload.authority),
    payload.issued_at,
    payload.expires_at,
    parent_delegation,
  )
  let encoded_reference = @capability.decode_delegation_ref_v1(
    wire.delegation_ref,
  )
  guard rebuilt.reference == encoded_reference else {
    fail("child delegation content digest mismatch")
  }
  rebuilt
}
