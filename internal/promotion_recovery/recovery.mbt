///|
priv struct MoonDeskRecoveryRequest {
  protocol_version : Int32
  instance_id : String
  workspace_id : String
  retention_id : String
  pending_attempt_id : String
  request_id : String
} derive(Eq, ToJson, @json.FromJson)

///|
priv struct MoonFortRecoveryResponse {
  protocol_version : Int32
  retention_id : String
  workspace_id : String
  profile_digest : String
  approval_digest : String
  command_digest : String
  destination_path : String
  reviewed_state_digest : String
  desired_state_digest : String
  observed_state_digest : String
  outcome : String
  error : MoonFortPromotionError?
} derive(Eq, ToJson, @json.FromJson)

///|
fn recovery_safe_id(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 128 &&
  value.all(c => {
    c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-' || c == '_'
  })
}

///|
fn moondesk_recovery_parse_request(
  value : Json,
) -> MoonDeskRecoveryRequest raise {
  guard value is Object(fields) && fields.length() == 6 else {
    fail("Recovery request must contain only opaque identifiers")
  }
  let request : MoonDeskRecoveryRequest = @json.from_json(value)
  guard request.protocol_version == 1 &&
    [
      request.instance_id,
      request.workspace_id,
      request.retention_id,
      request.pending_attempt_id,
      request.request_id,
    ].all(recovery_safe_id) else {
    fail("Invalid recovery request")
  }
  request
}

///|
async fn moondesk_recovery_pending(
  path : String,
  request : MoonDeskRecoveryRequest,
  discover_attempt~ : Bool = false,
) -> MoonDeskPromotionRequest {
  guard @fs.kind(path, follow_symlink=false) is Regular &&
    @fs.realpath(path) == path else {
    fail("Exact pending attempt is unavailable")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard file.kind() is Regular && size >= 0L && size <= 131_072L else {
    fail("Exact pending attempt is unavailable")
  }
  let bytes = @buffer.Buffer(size_hint=2_048)
  for ;; {
    guard file.read_some(max_len=(131_073 - bytes.length()).min(4_096))
      is Some(chunk) else {
      break
    }
    guard bytes.length() + chunk.length() <= 131_072 else {
      fail("Exact pending attempt exceeds its bound")
    }
    bytes.write_bytes(chunk)
  }
  guard file.size() == size &&
    bytes.length().to_int64() == size &&
    @fs.kind(path, follow_symlink=false) is Regular &&
    @fs.realpath(path) == path else {
    fail("Pending attempt changed during inspection")
  }
  let value = @json.parse(@encoding/utf8.decode(bytes.to_bytes()))
  guard value is { "pending_attempt": true, "request": stored, .. } else {
    fail("Only unresolved pending attempts can be inspected")
  }
  let pending = moondesk_promotion_parse_request(stored)
  guard pending.instance_id == request.instance_id &&
    pending.workspace_id == request.workspace_id &&
    pending.retention_id == request.retention_id &&
    (discover_attempt || pending.request_id == request.pending_attempt_id) else {
    fail("The pending return attempt has changed")
  }
  pending
}

///|
/// Return a nonsecret navigation reference only when the stored pending
/// selection exactly matches the authenticated host's original selection.
/// This never inspects the destination or changes the checkpoint.
pub async fn pending_reference(selection : Json) -> Json? {
  let selected = moondesk_promotion_parse_request(selection)
  guard @moonfort_config.load_promotion_adapter_config() is Some(config) else {
    return None
  }
  let request : MoonDeskRecoveryRequest = {
    protocol_version: 1,
    instance_id: selected.instance_id,
    workspace_id: selected.workspace_id,
    retention_id: selected.retention_id,
    pending_attempt_id: selected.request_id,
    request_id: "reference-only",
  }
  let path = moondesk_promotion_identity_path(
    config.receipt_root,
    selected.instance_id,
    selected.workspace_id,
    selected.retention_id,
  )
  guard @fs.kind(path + ".lock", follow_symlink=false) is Regular &&
    @fs.realpath(path + ".lock") == path + ".lock" else {
    return None
  }
  let lock = @fs.open(path + ".lock", mode=ReadOnly)
  defer lock.close()
  guard lock.try_lock(Shared) else { return None }
  defer lock.unlock()
  let pending = moondesk_recovery_pending(path, request, discover_attempt=true)
  guard pending.approval_digest == selected.approval_digest &&
    pending.command_digest == selected.command_digest &&
    pending.items == selected.items else {
    return None
  }
  Some({
    "instance_id": pending.instance_id,
    "workspace_id": pending.workspace_id,
    "retention_id": pending.retention_id,
    "pending_attempt_id": pending.request_id,
    "inspection_endpoint": "/v1/execution-sandbox/promotion-recovery",
    "read_only": true,
  })
}

///|
fn moondesk_recovery_validate(
  pending : MoonDeskPromotionRequest,
  response : MoonFortRecoveryResponse,
) -> Unit raise {
  let bound = response.workspace_id == pending.workspace_id &&
    response.approval_digest == pending.approval_digest &&
    response.command_digest == pending.command_digest &&
    response.destination_path == pending.items[0].destination_relative &&
    moondesk_promotion_safe_digest(response.profile_digest) &&
    moondesk_promotion_safe_digest(response.reviewed_state_digest) &&
    moondesk_promotion_safe_digest(response.desired_state_digest)
  let observed = moondesk_promotion_safe_digest(response.observed_state_digest)
  let code = response.error.map(error => error.code).unwrap_or("")
  let unbound_refusal = response.workspace_id == "" &&
    response.profile_digest == "" &&
    response.approval_digest == "" &&
    response.command_digest == "" &&
    response.destination_path == "" &&
    response.reviewed_state_digest == "" &&
    response.desired_state_digest == "" &&
    response.observed_state_digest == ""
  let valid = match response.outcome {
    "desired-applied" =>
      bound &&
      observed &&
      code == "" &&
      response.observed_state_digest == response.desired_state_digest
    "reviewed-prestate" =>
      bound &&
      observed &&
      code == "" &&
      response.observed_state_digest == response.reviewed_state_digest &&
      response.observed_state_digest != response.desired_state_digest
    "diverged" =>
      bound &&
      observed &&
      code == "" &&
      response.observed_state_digest != response.reviewed_state_digest &&
      response.observed_state_digest != response.desired_state_digest
    "manual-recovery" =>
      bound &&
      response.observed_state_digest == "" &&
      code == "root-mapping-unproven"
    "unavailable" =>
      (
        bound &&
        response.observed_state_digest == "" &&
        code == "destination-unavailable"
      ) ||
      (unbound_refusal && code == "inspection-unavailable")
    _ => false
  }
  guard response.protocol_version == 4 &&
    response.retention_id == pending.retention_id &&
    valid else {
    fail("Recovery inspection did not match the exact pending return")
  }
}

///|
fn moondesk_recovery_public(
  request : MoonDeskRecoveryRequest,
  pending : MoonDeskPromotionRequest,
  response : MoonFortRecoveryResponse,
  observed_at_ms : Int64,
) -> Json {
  {
    "protocol_version": 1,
    "instance_id": request.instance_id,
    "workspace_id": request.workspace_id,
    "retention_id": request.retention_id,
    "pending_attempt_id": request.pending_attempt_id,
    "request_id": request.request_id,
    "destination_relative": pending.items[0].destination_relative,
    "approval_digest": pending.approval_digest,
    "command_digest": pending.command_digest,
    "outcome": response.outcome,
    "reviewed_state_digest": response.reviewed_state_digest,
    "desired_state_digest": response.desired_state_digest,
    "observed_state_digest": response.observed_state_digest,
    "observed_at_ms": observed_at_ms,
    "pending_attempt": true,
    "retry_allowed": false,
    "historical_success_confirmed": false,
    "error_code": response.error.map(error => error.code).unwrap_or(""),
  }
}

///|
async fn moondesk_recovery_inspect(
  request : MoonDeskRecoveryRequest,
  receipt_root : String,
  invoke : async (String) -> MoonFortRecoveryResponse,
) -> Json {
  let path = moondesk_promotion_identity_path(
    receipt_root,
    request.instance_id,
    request.workspace_id,
    request.retention_id,
  )
  // Existing lock only: read-only inspection creates no receipt or lock file.
  guard @fs.kind(path + ".lock", follow_symlink=false) is Regular &&
    @fs.realpath(path + ".lock") == path + ".lock" else {
    fail("Pending return lock is unavailable")
  }
  let lock = @fs.open(path + ".lock", mode=ReadOnly)
  defer lock.close()
  guard lock.try_lock(Shared) else { fail("Return attempt is still active") }
  defer lock.unlock()
  let pending = moondesk_recovery_pending(path, request)
  let response = invoke(pending.retention_id)
  moondesk_recovery_validate(pending, response)
  guard pending == moondesk_recovery_pending(path, request) else {
    fail("Pending return changed during inspection")
  }
  moondesk_recovery_public(request, pending, response, @async.now())
}

///|
async fn read_moondesk_recovery(
  request : MoonDeskRecoveryRequest,
  route : @moondesk_sandbox_config.Config,
) -> Json {
  guard request.instance_id == route.instance_id &&
    request.workspace_id == route.workspace_id else {
    fail("Recovery request does not match the configured instance")
  }
  guard @moonfort_config.load_recovery_inspection_config() is Some(config) &&
    @moonfort_config.load_promotion_adapter_config() is Some(promotion) &&
    config.receipt_root == promotion.receipt_root &&
    config.executor_config_path == promotion.executor_config_path else {
    fail(
      "Recovery inspector does not match the trusted promotion configuration",
    )
  }
  let client = @execution_sandbox_adapter.RecoveryInspectionClient::new(
    config.inspector_path,
    config.inspector_args,
    config.executor_config_path,
    config.receipt_root,
  )
  moondesk_recovery_inspect(request, config.receipt_root, async fn(
    retention_id,
  ) {
    let body : Json = { "protocol_version": 4, "retention_id": retention_id }
    let process = client.inspect(body.stringify())
    guard process.status == 0 else { fail("Recovery inspector failed") }
    @json.from_json(@json.parse(process.stdout))
  })
}
