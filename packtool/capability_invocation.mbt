///|
/// Minimal wire projection of `moonflow.capability-catalog.v1`. MoonClaw does
/// not compile this catalog; it verifies the selected operation again at the
/// point where an installed pack is invoked.
priv struct CapabilityCatalogProductV1 {
  product_id : String
  pack_id : String
  pack_version : String
} derive(FromJson)

///|
priv struct CapabilityCatalogOperationV1 {
  operation_ref : String
  product_id : String
  pack_id : String
  pack_version : String
  tool_id : String
  adapter_id : String
  protocol : String
  authority : String
  input_schema_ref : String
  output_schema_ref : String
  claim_ceiling : String
  idempotent : Bool
  review_required : Bool
  supports_cancel : Bool
  supports_reconcile : Bool
  health_checked_at : String
  health_valid_until : String
  health_evidence_ref : String
  health_evidence_digest : String
} derive(FromJson)

///|
// Decoded for wire compatibility; producer diagnostics are not interpreted at
// the invocation boundary.
#warnings("-unused_field")
priv struct CapabilityCatalogIssueV1 {
  code : String
  subject : String
  detail : String
  suggestions : Array[String]
} derive(FromJson)

///|
priv struct CapabilityCatalogWireV1 {
  contract_id : String
  catalog_id : String
  compiled_at : String
  conformant : Bool
  products : Array[CapabilityCatalogProductV1]
  operations : Array[CapabilityCatalogOperationV1]
  issues : Array[CapabilityCatalogIssueV1]
} derive(FromJson)

///|
/// MoonFlow's durable adapter request, retained here as a wire-compatible
/// boundary so MoonClaw does not depend on or duplicate MoonFlow's engine.
pub(all) struct MoonFlowAdapterRequestV2 {
  request_id : String
  run_id : String
  book_id : String
  work_item_id : String
  declaration_id : String
  attempt_id : String
  idempotency_key : String
  product_id : String
  operation : String
  requested_authority : String
  acceptance_criteria : Array[String]
  input_contracts : Array[String]
  output_contracts : Array[String]
  required_claim : String
  input_digest : String
  input_artifacts : Array[String]
  timeout_ms : Int
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Host command for one already-selected MoonFlow capability. `config` and
/// `input` remain opaque to MoonClaw and are interpreted only by the pack-owned
/// executor.
pub(all) struct CapabilityInvocationV1 {
  contract_id : String
  adapter_id : String
  evaluated_at : String
  recorded_at : String
  attempt : Int
  request : MoonFlowAdapterRequestV2
  config : Json
  input : Json
} derive(Debug, ToJson, FromJson)

///|
/// Per-invocation policy. Review identities are canonical operation refs, not
/// unversioned tool names.
pub(all) struct CapabilityInvocationPolicyV1 {
  granted_authorities : Array[String]
  reviewed_operation_refs : Array[String]
  max_attempts : Int
  timeout_ms : Int
  remaining_budget_micros : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
priv struct InstalledPackCapabilityV1 {
  manifest : @pack.MoonPackManifest
  operation : CapabilityCatalogOperationV1
  binding : ToolBinding
}

///|
/// Durable receipt. Its common result fields intentionally match MoonFlow's
/// `AdapterResult`, so the same JSON object can be passed to
/// `reconcile-attempt`. Additional fields preserve capability and health
/// identity for audit/restart recovery.
pub(all) struct CapabilityInvocationReceiptV1 {
  contract_id : String
  result_id : String
  request_id : String
  attempt_id : String
  idempotency_key : String
  product_id : String
  external_job_id : String
  status : String
  output_digest : String
  output_artifacts : Array[String]
  error_kind : String
  compensable : Bool
  recorded_at : String
  catalog_id : String
  pack_id : String
  pack_version : String
  adapter_id : String
  operation_ref : String
  input_schema_ref : String
  output_schema_ref : String
  requested_authority : String
  input_digest : String
  health_evidence_ref : String
  health_evidence_digest : String
  output : Json?
  summary : String?
  metrics : Json
  logs : Array[String]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct CapabilityInvocationOutcomeV1 {
  receipt_ref : String
  receipt : CapabilityInvocationReceiptV1
  replayed : Bool
} derive(Debug, ToJson, FromJson)

///|
fn capability_safe_identifier(value : String) -> Bool {
  !value.is_blank() &&
  value.length() <= 160 &&
  value
  .iter()
  .all(char => {
    char.is_ascii_alphabetic() ||
    char.is_ascii_digit() ||
    char == '-' ||
    char == '_' ||
    char == '.'
  })
}

///|
fn capability_semver(value : String) -> Bool {
  let parts = value.split(".").to_array()
  parts.length() == 3 &&
  parts.all(part => {
    !part.is_empty() &&
    part.iter().all(char => char.is_ascii_digit()) &&
    (part == "0" || !part.has_prefix("0"))
  })
}

///|
fn capability_timestamp(value : String) -> Bool {
  value.length() == 20 &&
  value[4] == '-' &&
  value[7] == '-' &&
  value[10] == 'T' &&
  value[13] == ':' &&
  value[16] == ':' &&
  value[19] == 'Z' &&
  value
  .iter()
  .all(char => {
    char.is_ascii_digit() ||
    char == '-' ||
    char == 'T' ||
    char == ':' ||
    char == 'Z'
  })
}

///|
fn capability_digest(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:]
  .iter()
  .all(char => char.is_ascii_digit() || (char >= 'a' && char <= 'f'))
}

///|
fn capability_claim_rank(claim : String) -> Int? {
  match claim {
    "observation" => Some(0)
    "research-evidence" => Some(1)
    "execution-result" => Some(2)
    "accepted-knowledge" => Some(3)
    "digital-artifact" => Some(4)
    "simulation-evidence" => Some(5)
    "scenario-qualified" => Some(6)
    "calibrated-digital-twin" => Some(7)
    "hardware-in-loop-qualified" => Some(8)
    "engineering-unit-qualified" => Some(9)
    "physical-readiness" => Some(10)
    "physical-effect-claim" => Some(11)
    _ => None
  }
}

///|
fn canonical_authority(authority : @pack.AuthorityClass) -> String {
  match authority {
    Observe => "observe"
    CognitiveMaintenance => "cognitive-maintenance"
    SandboxExecution => "sandbox-execution"
    WorkspaceMutation => "workspace-mutation"
    ExternalEffect => "external-effect"
    PhysicalEffect => "physical-effect"
  }
}

///|
fn canonical_operation_ref(
  product_id : String,
  tool_id : String,
  pack_version : String,
) -> String {
  "\{product_id}/\{tool_id}@\{pack_version}"
}

///|
fn canonical_schema_ref(
  product_id : String,
  schema : @pack.ContractRef,
) -> String {
  "\{product_id}/\{schema.id}@\{schema.version}"
}

///|
fn unique_manifest_schema(
  manifest : @pack.MoonPackManifest,
  schema_id : String,
) -> @pack.ContractRef raise {
  let schemas = manifest.schemas.filter(schema => schema.id == schema_id)
  guard schemas is [schema] else {
    fail(
      "capability schema is missing or ambiguous in active pack: " + schema_id,
    )
  }
  guard capability_safe_identifier(schema.id) &&
    capability_semver(schema.version) else {
    fail("active pack contains a non-canonical schema identity: " + schema_id)
  }
  schema
}

///|
fn unique_manifest_tool(
  manifest : @pack.MoonPackManifest,
  tool_id : String,
) -> @pack.ToolDeclaration raise {
  let tools = manifest.tools.filter(tool => tool.id == tool_id)
  guard tools is [tool] else {
    fail("capability tool is missing or ambiguous in active pack: " + tool_id)
  }
  tool
}

///|
fn sha256_digest(bytes : Bytes) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
async fn contained_artifact_path(
  workspace : String,
  reference : String,
  purpose : String,
) -> String {
  if !@pack.safe_artifact_path(reference) {
    fail("capability \{purpose} must be workspace-relative: \{reference}")
  }
  let root = @fsx.resolve(workspace)
  let path = @fsx.resolve(@pathx.join(root, reference))
  if path != root && !path.has_prefix(root + "/") {
    fail("capability \{purpose} resolves outside workspace: \{reference}")
  }
  path
}

///|
async fn verify_health_evidence(
  workspace : String,
  operation : CapabilityCatalogOperationV1,
) -> Unit {
  if !capability_digest(operation.health_evidence_digest) {
    fail("capability health evidence digest is not canonical sha256")
  }
  let path = contained_artifact_path(
    workspace,
    operation.health_evidence_ref,
    "health evidence",
  )
  if !@fsx.exists_as_file(path) {
    fail(
      "capability health evidence is missing: " + operation.health_evidence_ref,
    )
  }
  let bytes = @fs.read_file(path).binary()
  if sha256_digest(bytes) != operation.health_evidence_digest {
    fail("capability health evidence digest does not match verified bytes")
  }
}

///|
async fn declared_artifact_digest(
  workspace : String,
  artifacts : Array[String],
) -> String {
  let identities : Array[String] = []
  for artifact in artifacts {
    let path = contained_artifact_path(workspace, artifact, "artifact")
    if !@fsx.exists_as_file(path) {
      fail("declared capability artifact is missing: " + artifact)
    }
    let digest = sha256_digest(@fs.read_file(path).binary())
    identities.push("\{artifact}|\{digest}")
  }
  sha256_digest(@utf8.encode(identities.join("\n")))
}

///|
fn decode_capability_catalog(value : Json) -> CapabilityCatalogWireV1 raise {
  let catalog : CapabilityCatalogWireV1 = @json.from_json(value)
  ignore(catalog.conformant)
  ignore(catalog.issues)
  if catalog.contract_id != "moonflow.capability-catalog.v1" {
    fail("unsupported capability catalog contract")
  }
  if !capability_safe_identifier(catalog.catalog_id) ||
    !capability_timestamp(catalog.compiled_at) {
    fail("capability catalog identity or compilation time is invalid")
  }
  catalog
}

///|
fn selected_catalog_operation(
  catalog : CapabilityCatalogWireV1,
  operation_ref : String,
) -> CapabilityCatalogOperationV1 raise {
  let operations = catalog.operations.filter(operation => {
    operation.operation_ref == operation_ref
  })
  guard operations is [operation] else {
    fail("capability operation is absent or ambiguous: " + operation_ref)
  }
  operation
}

///|
/// Resolve and independently verify one catalog operation against the active,
/// receipt-verified installed pack and the bytes of its expiring health proof.
async fn load_installed_capability_v1(
  workspace~ : String,
  catalog_json~ : Json,
  operation_ref~ : String,
  evaluated_at~ : String,
) -> InstalledPackCapabilityV1 {
  if !capability_timestamp(evaluated_at) {
    fail("capability evaluation time must be canonical UTC")
  }
  let catalog = decode_capability_catalog(catalog_json)
  if catalog.compiled_at > evaluated_at {
    fail("capability catalog was compiled after the evaluation time")
  }
  let operation = selected_catalog_operation(catalog, operation_ref)
  if !capability_safe_identifier(operation.product_id) ||
    !capability_safe_identifier(operation.pack_id) ||
    !capability_safe_identifier(operation.tool_id) ||
    !capability_safe_identifier(operation.adapter_id) ||
    !capability_semver(operation.pack_version) {
    fail("capability operation contains a non-canonical identity")
  }
  if operation.protocol != "moonflow.adapter.v2" ||
    !operation.supports_reconcile {
    fail("capability requires a reconcilable moonflow.adapter.v2 declaration")
  }
  if !capability_timestamp(operation.health_checked_at) ||
    !capability_timestamp(operation.health_valid_until) ||
    operation.health_checked_at > evaluated_at ||
    operation.health_valid_until < evaluated_at {
    fail("capability health attestation is invalid or expired")
  }
  if operation.operation_ref !=
    canonical_operation_ref(
      operation.product_id,
      operation.tool_id,
      operation.pack_version,
    ) {
    fail("capability operation reference is not canonical")
  }
  guard catalog.products.any(product => {
    product.product_id == operation.product_id &&
    product.pack_id == operation.pack_id &&
    product.pack_version == operation.pack_version
  }) else {
    fail("capability operation has no matching installed-product projection")
  }
  guard @installer.active_pack(workspace, operation.pack_id) is Some(pointer) else {
    fail("capability pack is not active: " + operation.pack_id)
  }
  let verification = @installer.verify_installed(
    workspace,
    pointer.pack_id,
    pointer.version,
  )
  if !verification.ok {
    fail(
      "active capability pack verification failed: " +
      verification.issues.join("; "),
    )
  }
  guard @installer.active_manifest(workspace, operation.pack_id)
    is Some(manifest) else {
    fail("active capability manifest is unavailable")
  }
  require_active_pack(pointer, manifest, operation.pack_id)
  if manifest.product_id != operation.product_id ||
    manifest.version != operation.pack_version {
    fail("capability catalog does not match the active pack identity")
  }
  let tool = unique_manifest_tool(manifest, operation.tool_id)
  if tool.owner_product != manifest.product_id {
    fail("active capability tool owner does not match its product")
  }
  let input_schema = unique_manifest_schema(manifest, tool.input_schema_id)
  let output_schema = unique_manifest_schema(manifest, tool.output_schema_id)
  if operation.input_schema_ref !=
    canonical_schema_ref(manifest.product_id, input_schema) ||
    operation.output_schema_ref !=
    canonical_schema_ref(manifest.product_id, output_schema) {
    fail("capability schema references do not match the active pack")
  }
  if operation.authority != canonical_authority(tool.authority) ||
    operation.idempotent != tool.idempotent ||
    operation.review_required != tool.review_required {
    fail("capability policy fields drift from the active pack manifest")
  }
  verify_health_evidence(workspace, operation)
  ignore(installed_pack_receipt(pointer))
  {
    manifest,
    operation,
    binding: {
      pack_id: manifest.id,
      product_id: manifest.product_id,
      tool_id: tool.id,
      input_schema_id: tool.input_schema_id,
      output_schema_id: tool.output_schema_id,
      authority: tool.authority,
      idempotent: tool.idempotent,
      evidence_outputs: tool.evidence_outputs,
      review_required: tool.review_required,
    },
  }
}

///|
fn capability_request_issues(
  installed : InstalledPackCapabilityV1,
  invocation : CapabilityInvocationV1,
  policy : CapabilityInvocationPolicyV1,
  estimated_cost_micros : Int,
) -> Array[String] {
  let issues : Array[String] = []
  let request = invocation.request
  for
    required in [
      (request.request_id, "request_id"),
      (request.run_id, "run_id"),
      (request.work_item_id, "work_item_id"),
      (request.attempt_id, "attempt_id"),
      (request.idempotency_key, "idempotency_key"),
      (request.product_id, "product_id"),
      (request.operation, "operation"),
      (request.requested_authority, "requested_authority"),
      (request.input_digest, "input_digest"),
      (request.created_at, "created_at"),
    ] {
    if required.0.trim().is_empty() {
      issues.push("capability invocation requires " + required.1)
    }
  }
  if invocation.contract_id != "moonclaw.capability-invocation.v1" {
    issues.push("unsupported MoonClaw capability invocation contract")
  }
  if invocation.adapter_id != installed.operation.adapter_id {
    issues.push("selected adapter does not match capability catalog")
  }
  if request.product_id != installed.operation.product_id ||
    request.operation != installed.operation.operation_ref {
    issues.push("request product or operation does not match capability")
  }
  if request.input_contracts != [installed.operation.input_schema_ref] ||
    request.output_contracts != [installed.operation.output_schema_ref] {
    issues.push("request schemas do not exactly match capability schemas")
  }
  if request.requested_authority != installed.operation.authority {
    issues.push("request authority does not exactly match capability authority")
  }
  match
    (
      capability_claim_rank(request.required_claim),
      capability_claim_rank(installed.operation.claim_ceiling),
    ) {
    (Some(required), Some(ceiling)) =>
      if required > ceiling {
        issues.push("required claim exceeds capability claim ceiling")
      }
    (None, _) => issues.push("capability request uses an unsupported claim")
    (_, None) =>
      issues.push("capability catalog uses an unsupported claim ceiling")
  }
  if !policy.granted_authorities.contains(request.requested_authority) {
    issues.push("capability authority is not granted")
  }
  if installed.binding.review_required &&
    !policy.reviewed_operation_refs.contains(installed.operation.operation_ref) {
    issues.push("capability requires an exact versioned review receipt")
  }
  if invocation.attempt < 1 || invocation.attempt > policy.max_attempts {
    issues.push("capability attempt is outside retry policy")
  }
  if invocation.attempt > 1 && !installed.binding.idempotent {
    issues.push("non-idempotent capability cannot be retried")
  }
  if request.timeout_ms <= 0 ||
    policy.timeout_ms <= 0 ||
    request.timeout_ms > policy.timeout_ms {
    issues.push("capability timeout exceeds host policy")
  }
  if estimated_cost_micros < 0 ||
    estimated_cost_micros > policy.remaining_budget_micros {
    issues.push("capability invocation exceeds remaining cost budget")
  }
  if !capability_digest(request.input_digest) {
    issues.push("capability input digest must be canonical sha256")
  }
  if !capability_timestamp(request.created_at) ||
    request.created_at > invocation.evaluated_at {
    issues.push("capability request time is invalid or in the future")
  }
  issues
}

///|
fn capability_receipt_ref(idempotency_key : String) -> String {
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(idempotency_key)),
  )
  ".moonsuite/products/moonclaw/capability-invocations/\{digest}/result.json"
}

///|
async fn write_capability_receipt(
  path : String,
  receipt : CapabilityInvocationReceiptV1,
) -> Unit {
  let temporary = path + ".tmp"
  @fsx.write_to_file(
    temporary,
    receipt.to_json().stringify(indent=2) + "\n",
    create=0o600,
  )
  @fsx.atomic_rename(temporary, path)
}

///|
async fn existing_capability_receipt(
  path : String,
) -> CapabilityInvocationReceiptV1? {
  if !@fsx.exists_as_file(path) {
    return None
  }
  Some(@json.from_json(@json.parse(@fsx.read_file(path)))) catch {
    error => fail("durable capability receipt is invalid: \{error}")
  }
}

///|
/// Read one durable capability receipt without submitting, retrying, or
/// reconciling the adapter. The invocation is still verified against the
/// installed pack and catalog before the receipt identity is accepted.
pub async fn inspect_installed_capability_v1(
  workspace~ : String,
  catalog_json~ : Json,
  invocation~ : CapabilityInvocationV1,
) -> CapabilityInvocationOutcomeV1? {
  if !capability_timestamp(invocation.evaluated_at) ||
    !capability_timestamp(invocation.recorded_at) {
    fail("capability inspection timestamps must be canonical UTC")
  }
  let installed = load_installed_capability_v1(
    workspace~,
    catalog_json~,
    operation_ref=invocation.request.operation,
    evaluated_at=invocation.evaluated_at,
  )
  let receipt_ref = capability_receipt_ref(invocation.request.idempotency_key)
  let receipt_path = @pathx.join(workspace, receipt_ref)
  if !@fsx.exists_as_file(receipt_path) {
    return None
  }
  let lock_file = @fs.open(
    receipt_path + ".lock",
    mode=WriteOnly,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock_file.close()
  @fsx.lock_file(lock_file)
  guard existing_capability_receipt(receipt_path) is Some(receipt) else {
    return None
  }
  require_same_capability_attempt(receipt, installed, invocation)
  Some({ receipt_ref, receipt, replayed: true })
}

///|
fn require_same_capability_attempt(
  receipt : CapabilityInvocationReceiptV1,
  installed : InstalledPackCapabilityV1,
  invocation : CapabilityInvocationV1,
) -> Unit raise {
  let request = invocation.request
  if receipt.request_id != request.request_id ||
    receipt.attempt_id != request.attempt_id ||
    receipt.idempotency_key != request.idempotency_key ||
    receipt.product_id != request.product_id ||
    receipt.adapter_id != invocation.adapter_id ||
    receipt.operation_ref != request.operation ||
    receipt.input_schema_ref != installed.operation.input_schema_ref ||
    receipt.output_schema_ref != installed.operation.output_schema_ref ||
    receipt.input_digest != request.input_digest {
    fail("idempotency key conflicts with a different capability attempt")
  }
}

///|
fn receipt_for_status(
  catalog_id : String,
  installed : InstalledPackCapabilityV1,
  invocation : CapabilityInvocationV1,
  status : String,
  result? : PackToolExecutionResult,
  error_kind? : String = "",
) -> CapabilityInvocationReceiptV1 {
  let request = invocation.request
  let suffix = status.replace(old="_", new="-")
  let result_id = "result-\{request.attempt_id}-\{suffix}"
  {
    contract_id: "moonclaw.capability-invocation-receipt.v1",
    result_id,
    request_id: request.request_id,
    attempt_id: request.attempt_id,
    idempotency_key: request.idempotency_key,
    product_id: request.product_id,
    external_job_id: result.map(value => value.external_job_id).unwrap_or(""),
    status,
    output_digest: "",
    output_artifacts: result.map(value => value.output_artifacts).unwrap_or([]),
    error_kind,
    compensable: result.map(value => value.compensable).unwrap_or(false),
    recorded_at: invocation.recorded_at,
    catalog_id,
    pack_id: installed.manifest.id,
    pack_version: installed.manifest.version,
    adapter_id: invocation.adapter_id,
    operation_ref: installed.operation.operation_ref,
    input_schema_ref: installed.operation.input_schema_ref,
    output_schema_ref: installed.operation.output_schema_ref,
    requested_authority: request.requested_authority,
    input_digest: request.input_digest,
    health_evidence_ref: installed.operation.health_evidence_ref,
    health_evidence_digest: installed.operation.health_evidence_digest,
    output: result.map(value => value.output),
    summary: match result {
      Some(value) => value.summary
      None => None
    },
    metrics: result.map(value => value.metrics).unwrap_or(Json::empty_object()),
    logs: result.map(value => value.logs).unwrap_or([]),
  }
}

///|
fn output_artifact_issues(
  installed : InstalledPackCapabilityV1,
  artifacts : Array[String],
) -> Array[String] {
  let issues : Array[String] = []
  for artifact in artifacts {
    if !@pack.safe_artifact_path(artifact) {
      issues.push("output artifact is not workspace-relative: " + artifact)
      continue
    }
    if !installed.binding.evidence_outputs.any(prefix => {
        artifact == prefix || artifact.has_prefix(prefix + "/")
      }) {
      issues.push(
        "output artifact is outside declared evidence outputs: " + artifact,
      )
    }
  }
  issues
}

///|
async fn finalize_capability_result(
  workspace : String,
  catalog_id : String,
  installed : InstalledPackCapabilityV1,
  invocation : CapabilityInvocationV1,
  result : PackToolExecutionResult,
) -> CapabilityInvocationReceiptV1 {
  let issues = output_artifact_issues(installed, result.output_artifacts)
  if !issues.is_empty() {
    let sanitized = { ..result, output_artifacts: [] }
    return receipt_for_status(
      catalog_id,
      installed,
      invocation,
      "failed",
      result=sanitized,
      error_kind="invalid-output-evidence:" + issues.join("; "),
    )
  }
  match result.status {
    "submitted" | "running" | "unknown" | "failed" | "cancelled" =>
      receipt_for_status(
        catalog_id,
        installed,
        invocation,
        result.status,
        result~,
      )
    "succeeded" => {
      let output_digest = if result.output_artifacts.is_empty() {
        sha256_digest(@utf8.encode(result.output.stringify()))
      } else {
        declared_artifact_digest(workspace, result.output_artifacts)
      }
      {
        ..receipt_for_status(
          catalog_id,
          installed,
          invocation,
          "succeeded",
          result~,
        ),
        output_digest,
      }
    }
    status =>
      receipt_for_status(
        catalog_id,
        installed,
        invocation,
        "failed",
        error_kind="unsupported-adapter-result-status:" + status,
      )
  }
}

///|
async fn reconcile_capability_attempt(
  workspace : String,
  receipt_path : String,
  catalog_id : String,
  installed : InstalledPackCapabilityV1,
  invocation : CapabilityInvocationV1,
  request : PackToolExecutionRequest,
  executor : PackToolExecutor,
) -> CapabilityInvocationReceiptV1 {
  guard executor.reconcile is Some(reconcile) else {
    let receipt = receipt_for_status(
      catalog_id,
      installed,
      invocation,
      "unknown",
      error_kind="adapter-reconciliation-unavailable",
    )
    write_capability_receipt(receipt_path, receipt)
    return receipt
  }
  let reconciliation = reconcile(request) catch {
    error => Err("adapter reconciliation raised: \{error}")
  }
  let receipt = capability_receipt_from_reconciliation(
    workspace, catalog_id, installed, invocation, reconciliation,
  )
  write_capability_receipt(receipt_path, receipt)
  receipt
}

///|
async fn capability_receipt_from_reconciliation(
  workspace : String,
  catalog_id : String,
  installed : InstalledPackCapabilityV1,
  invocation : CapabilityInvocationV1,
  reconciliation : Result[PackToolReconciliation, String],
) -> CapabilityInvocationReceiptV1 {
  match reconciliation {
    Err(_) =>
      receipt_for_status(
        catalog_id,
        installed,
        invocation,
        "unknown",
        error_kind="adapter-reconciliation-error",
      )
    Ok(reconciled) =>
      match reconciled.status {
        "submitted" | "running" | "unknown" =>
          receipt_for_status(
            catalog_id,
            installed,
            invocation,
            reconciled.status,
            error_kind=reconciled.error_kind,
          )
        "failed" | "cancelled" =>
          match reconciled.result {
            Some(result) =>
              receipt_for_status(
                catalog_id,
                installed,
                invocation,
                reconciled.status,
                result~,
                error_kind=reconciled.error_kind,
              )
            None =>
              receipt_for_status(
                catalog_id,
                installed,
                invocation,
                reconciled.status,
                error_kind=reconciled.error_kind,
              )
          }
        "succeeded" =>
          match reconciled.result {
            Some(result) =>
              finalize_capability_result(
                workspace, catalog_id, installed, invocation, result,
              )
            None =>
              receipt_for_status(
                catalog_id,
                installed,
                invocation,
                "unknown",
                error_kind="reconciled-success-missing-result",
              )
          }
        status =>
          receipt_for_status(
            catalog_id,
            installed,
            invocation,
            "unknown",
            error_kind="unsupported-reconciliation-status:" + status,
          )
      }
  }
}

///|
fn capability_execution_request(
  installed : InstalledPackCapabilityV1,
  invocation : CapabilityInvocationV1,
  estimated_cost_micros : Int,
) -> PackToolExecutionRequest {
  let evidence_path = match installed.binding.evidence_outputs.get(0) {
    Some(prefix) =>
      prefix +
      "/" +
      @crypto.bytes_to_hex_string(
        @crypto.sha256(@utf8.encode(invocation.request.idempotency_key)),
      ) +
      ".json"
    None => ""
  }
  {
    binding: installed.binding,
    config: invocation.config,
    initial_input: Some(invocation.input),
    outputs: Map([]),
    request_id: invocation.request.request_id,
    attempt_id: invocation.request.attempt_id,
    idempotency_key: invocation.request.idempotency_key,
    operation_ref: invocation.request.operation,
    run_id: invocation.request.run_id,
    step_id: invocation.request.work_item_id,
    evidence_path,
    attempt: invocation.attempt,
    estimated_cost_micros,
  }
}

///|
/// Execute or reconcile one exact installed capability. The per-idempotency-key
/// lock and submitted checkpoint make restart recovery fail closed: a repeated
/// call never reruns an uncertain effect and instead asks the pack-owned
/// adapter to reconcile it.
pub async fn execute_installed_capability_v1(
  workspace~ : String,
  catalog_json~ : Json,
  invocation~ : CapabilityInvocationV1,
  executor~ : PackToolExecutor,
  policy~ : CapabilityInvocationPolicyV1,
) -> CapabilityInvocationOutcomeV1 {
  if !capability_timestamp(invocation.evaluated_at) ||
    !capability_timestamp(invocation.recorded_at) {
    fail("capability invocation timestamps must be canonical UTC")
  }
  let catalog = decode_capability_catalog(catalog_json)
  let installed = load_installed_capability_v1(
    workspace~,
    catalog_json~,
    operation_ref=invocation.request.operation,
    evaluated_at=invocation.evaluated_at,
  )
  let estimated_cost_micros = (executor.estimate_cost_micros)(
    installed.binding,
    invocation.config,
  )
  let issues = capability_request_issues(
    installed, invocation, policy, estimated_cost_micros,
  )
  if !issues.is_empty() {
    fail("capability invocation denied: " + issues.join("; "))
  }
  let verified_input_digest = declared_artifact_digest(
    workspace,
    invocation.request.input_artifacts,
  )
  if verified_input_digest != invocation.request.input_digest {
    fail("capability input digest does not match declared artifact bytes")
  }
  let receipt_ref = capability_receipt_ref(invocation.request.idempotency_key)
  let receipt_path = @pathx.join(workspace, receipt_ref)
  let receipt_dir = @pathx.dirname(receipt_path).to_owned()
  @fsx.make_directory(receipt_dir, recursive=true, exists_ok=true)
  let lock_file = @fs.open(
    receipt_path + ".lock",
    mode=WriteOnly,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock_file.close()
  @fsx.lock_file(lock_file)
  let execution_request = capability_execution_request(
    installed, invocation, estimated_cost_micros,
  )
  match existing_capability_receipt(receipt_path) {
    Some(receipt) => {
      require_same_capability_attempt(receipt, installed, invocation)
      if receipt.status == "succeeded" ||
        receipt.status == "failed" ||
        receipt.status == "cancelled" {
        return { receipt_ref, receipt, replayed: true }
      }
      let reconciled = reconcile_capability_attempt(
        workspace,
        receipt_path,
        catalog.catalog_id,
        installed,
        invocation,
        execution_request,
        executor,
      )
      return { receipt_ref, receipt: reconciled, replayed: true }
    }
    None => ()
  }
  let submitted = receipt_for_status(
    catalog.catalog_id,
    installed,
    invocation,
    "submitted",
  )
  write_capability_receipt(receipt_path, submitted)
  let execution = (executor.run)(execution_request) catch {
    error => Err("pack executor raised: \{error}")
  }
  let receipt = match execution {
    Ok(result) =>
      finalize_capability_result(
        workspace,
        catalog.catalog_id,
        installed,
        invocation,
        result,
      )
    Err(_) =>
      receipt_for_status(
        catalog.catalog_id,
        installed,
        invocation,
        "failed",
        error_kind="adapter-execution-error",
      )
  }
  write_capability_receipt(receipt_path, receipt)
  { receipt_ref, receipt, replayed: false }
}

///|
/// Cancel one previously submitted exact capability attempt. Cancellation is
/// delegated to the same pack-owned adapter and updates the same durable
/// idempotency receipt; it does not create a second attempt or runtime.
pub async fn cancel_installed_capability_v1(
  workspace~ : String,
  catalog_json~ : Json,
  invocation~ : CapabilityInvocationV1,
  executor~ : PackToolExecutor,
  policy~ : CapabilityInvocationPolicyV1,
) -> CapabilityInvocationOutcomeV1 {
  if !capability_timestamp(invocation.evaluated_at) ||
    !capability_timestamp(invocation.recorded_at) {
    fail("capability cancellation timestamps must be canonical UTC")
  }
  let catalog = decode_capability_catalog(catalog_json)
  let installed = load_installed_capability_v1(
    workspace~,
    catalog_json~,
    operation_ref=invocation.request.operation,
    evaluated_at=invocation.evaluated_at,
  )
  if !installed.operation.supports_cancel {
    fail("capability adapter does not support cancellation")
  }
  guard executor.cancel is Some(cancel) else {
    fail("capability executor has no cancellation implementation")
  }
  let estimated_cost_micros = (executor.estimate_cost_micros)(
    installed.binding,
    invocation.config,
  )
  let issues = capability_request_issues(
    installed, invocation, policy, estimated_cost_micros,
  )
  if !issues.is_empty() {
    fail("capability cancellation denied: " + issues.join("; "))
  }
  let verified_input_digest = declared_artifact_digest(
    workspace,
    invocation.request.input_artifacts,
  )
  if verified_input_digest != invocation.request.input_digest {
    fail("capability input digest does not match declared artifact bytes")
  }
  let receipt_ref = capability_receipt_ref(invocation.request.idempotency_key)
  let receipt_path = @pathx.join(workspace, receipt_ref)
  let lock_file = @fs.open(
    receipt_path + ".lock",
    mode=WriteOnly,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock_file.close()
  @fsx.lock_file(lock_file)
  guard existing_capability_receipt(receipt_path) is Some(existing) else {
    fail("capability cancellation requires a durable submitted receipt")
  }
  require_same_capability_attempt(existing, installed, invocation)
  if existing.status == "succeeded" ||
    existing.status == "failed" ||
    existing.status == "cancelled" {
    return { receipt_ref, receipt: existing, replayed: true }
  }
  let request = capability_execution_request(
    installed, invocation, estimated_cost_micros,
  )
  let reconciliation = cancel(request) catch {
    error => Err("adapter cancellation raised: \{error}")
  }
  let receipt = capability_receipt_from_reconciliation(
    workspace,
    catalog.catalog_id,
    installed,
    invocation,
    reconciliation,
  )
  write_capability_receipt(receipt_path, receipt)
  { receipt_ref, receipt, replayed: false }
}
