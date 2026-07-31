///|
/// One host-approved transport for an exact installed-pack capability.
///
/// Routes are operator configuration, never invocation input. This prevents a
/// browser or domain pack from supplying an arbitrary provider or HTTP target.
priv struct CapabilityHttpRouteV1 {
  route_id : String
  operation_ref : String
  adapter_id : String
  transport : String
  submit_url : String?
  reconcile_url : String?
  base_url : String?
  estimated_cost_micros : Int
  provider_route_ref : String?
} derive(Debug, FromJson)

///|
/// Host-owned policy loaded from MoonClaw's product home in the served
/// workspace. It is deliberately not accepted in an HTTP request.
priv struct CapabilityHttpPolicyV1 {
  contract_id : String
  catalog_ref : String
  granted_authorities : Array[String]
  reviewed_operation_refs : Array[String]
  max_attempts : Int
  timeout_ms : Int
  remaining_budget_micros : Int
  approved_provider_route_refs : Array[String]
  routes : Array[CapabilityHttpRouteV1]
} derive(Debug, FromJson)

///|
fn capability_http_policy_path(workspace : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    workspace, "moonclaw", "capability-http-policy.json",
  )
}

///|
fn capability_http_safe_reference(reference : String) -> Bool {
  !reference.is_blank() &&
  !reference.has_prefix("/") &&
  !reference.contains("\\") &&
  !reference.contains("?") &&
  !reference.contains("#") &&
  !reference.split("/").any(part => part == "" || part == "." || part == "..")
}

///|
async fn capability_http_contained_path(
  workspace : String,
  reference : String,
) -> String {
  guard capability_http_safe_reference(reference) else {
    fail("capability host reference is unsafe")
  }
  let root = @fsx.resolve(workspace)
  let path = @fsx.resolve(@pathx.join(root, reference))
  guard path == root || path.has_prefix(root + "/") else {
    fail("capability host reference resolves outside the served workspace")
  }
  path
}

///|
async fn load_capability_http_policy(
  workspace : String,
) -> CapabilityHttpPolicyV1 {
  let root = @fsx.resolve(workspace)
  let path = @fsx.resolve(capability_http_policy_path(workspace))
  guard path == root || path.has_prefix(root + "/") else {
    fail(
      "MoonClaw capability HTTP policy resolves outside the served workspace",
    )
  }
  guard @fsx.exists_as_file(path) else {
    fail(
      "MoonClaw capability HTTP policy is not configured at " +
      ".moonsuite/products/moonclaw/capability-http-policy.json",
    )
  }
  let policy : CapabilityHttpPolicyV1 = @json.from_json(
    @json.parse(@fsx.read_file(path)),
  )
  guard policy.contract_id == "moonclaw.capability-http-policy.v1" &&
    capability_http_safe_reference(policy.catalog_ref) &&
    policy.max_attempts > 0 &&
    policy.timeout_ms > 0 &&
    policy.remaining_budget_micros >= 0 else {
    fail("MoonClaw capability HTTP policy is invalid")
  }
  policy
}

///|
async fn capability_http_catalog(
  workspace : String,
  policy : CapabilityHttpPolicyV1,
) -> Json {
  let path = capability_http_contained_path(workspace, policy.catalog_ref)
  guard @fsx.exists_as_file(path) else {
    fail("configured MoonFlow capability catalog is unavailable")
  }
  @json.parse(@fsx.read_file(path))
}

///|
fn capability_http_identity(
  invocation : @packtool.CapabilityInvocationV1,
) -> Json {
  {
    "request_id": invocation.request.request_id,
    "attempt_id": invocation.request.attempt_id,
    "idempotency_key": invocation.request.idempotency_key,
    "operation_ref": invocation.request.operation,
    "adapter_id": invocation.adapter_id,
  }
}

///|
fn capability_http_json_error(
  code : Int,
  reason : String,
  error_code : String,
  message : String,
  invocation? : @packtool.CapabilityInvocationV1,
) -> HttpError {
  json_error(code, reason, {
    "error": {
      "code": error_code,
      "message": message,
      "identity": invocation.map(capability_http_identity),
    },
  })
}

///|
fn capability_http_host_allowed(host : String, port : Int) -> Bool {
  let normalized = host.trim().to_lower()
  normalized == "127.0.0.1:\{port}" || normalized == "localhost:\{port}"
}

///|
fn capability_http_request_allowed(
  headers : Map[String, String],
  port : Int,
  token : String?,
) -> Result[Unit, String] {
  guard headers.get("host") is Some(host) &&
    capability_http_host_allowed(host, port) else {
    return Err("capability requests require the exact loopback gateway host")
  }
  match headers.get("origin") {
    Some(origin) => {
      let expected = "http://" + host.trim().to_owned().to_lower()
      if origin.trim().to_lower() != expected {
        return Err(
          "cross-origin capability mutation is denied; use a same-origin host proxy",
        )
      }
    }
    None => ()
  }
  match token {
    Some(expected) =>
      if headers.get("authorization") != Some("Bearer " + expected) {
        return Err("capability gateway authorization is required")
      }
    None => ()
  }
  Ok(())
}

///|
fn capability_http_loopback_url(value : String, allow_root : Bool) -> Bool {
  let normalized = value.trim().to_owned()
  if normalized != value ||
    !normalized.has_prefix("http://") ||
    normalized.contains("@") ||
    normalized.contains("?") ||
    normalized.contains("#") ||
    normalized.contains("%") ||
    normalized.contains("\\") {
    return false
  }
  let remainder = normalized[7:]
  let slash = remainder.find("/")
  let (authority, path) = match slash {
    Some(index) => (remainder[0:index].to_owned(), remainder[index:].to_owned())
    None => (remainder.to_owned(), "")
  }
  let parts = authority.split(":").to_array()
  guard parts is [host, raw_port] &&
    (host == "127.0.0.1" || host == "localhost") &&
    !raw_port.is_blank() &&
    raw_port.iter().all(char => char.is_ascii_digit()) else {
    return false
  }
  let port = @string.parse_int(raw_port) catch { _ => return false }
  if port <= 0 || port > 65535 {
    return false
  }
  if path == "" {
    return allow_root
  }
  if !path.has_prefix("/") ||
    path.split("/").any(part => part == "." || part == "..") {
    return false
  }
  allow_root || path != "/"
}

///|
fn capability_http_provider_calls_forbidden(config : Json) -> Bool {
  match config {
    Object(fields) =>
      match fields.get("provider_calls_forbidden") {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
fn capability_http_route(
  policy : CapabilityHttpPolicyV1,
  invocation : @packtool.CapabilityInvocationV1,
) -> CapabilityHttpRouteV1 raise {
  let matches = policy.routes.filter(route => {
    route.operation_ref == invocation.request.operation &&
    route.adapter_id == invocation.adapter_id
  })
  guard matches is [route] else {
    fail("capability has no unique host-approved execution route")
  }
  guard !route.route_id.is_blank() && route.estimated_cost_micros >= 0 else {
    fail("capability execution route is invalid")
  }
  route
}

///|
async fn capability_http_post_json(
  url : String,
  body : Json,
  timeout_ms : Int,
) -> Result[Json, String] {
  let request = async fn() {
    @http.post(url, body.stringify(), headers={
      "Content-Type": "application/json; charset=utf-8",
    })
  }
  let (response, data) = @async.with_timeout(timeout_ms, request) catch {
    @async.TimeoutError => return Err("capability adapter request timed out")
    error => return Err("capability adapter request failed: \{error}")
  }
  let text = data.text()
  if response.code < 200 || response.code >= 300 {
    return Err("capability adapter returned HTTP \{response.code}")
  }
  Ok(@json.parse(text)) catch {
    error => Err("capability adapter returned invalid JSON: \{error}")
  }
}

///|
fn capability_http_uncertain_result(
  message : String,
) -> @packtool.PackToolExecutionResult {
  @packtool.PackToolExecutionResult::new(
    output={ "error_kind": "adapter-transport-uncertain" },
    status="unknown",
    summary=Some(
      "The pack adapter outcome is uncertain; reconcile the same attempt.",
    ),
    logs=[message],
  )
}

///|
fn capability_http_decode_execution_result(
  value : Json,
) -> Result[@packtool.PackToolExecutionResult, String] noraise {
  try @json.from_json(value) catch {
    error => Err("invalid pack-tool submit result: \{error}")
  } noraise {
    result => Ok(result)
  }
}

///|
fn capability_http_decode_reconciliation(
  value : Json,
) -> Result[@packtool.PackToolReconciliation, String] noraise {
  try @json.from_json(value) catch {
    error => Err("invalid pack-tool reconciliation: \{error}")
  } noraise {
    result => Ok(result)
  }
}

///|
fn capability_http_pack_executor(
  route : CapabilityHttpRouteV1,
  timeout_ms : Int,
) -> @packtool.PackToolExecutor raise {
  guard route.transport == "moonclaw.pack-tool-http.v1" &&
    route.submit_url is Some(submit_url) &&
    route.reconcile_url is Some(reconcile_url) &&
    capability_http_loopback_url(submit_url, false) &&
    capability_http_loopback_url(reconcile_url, false) else {
    fail("pack-tool HTTP route is incomplete or unsafe")
  }
  let estimated_cost_micros = route.estimated_cost_micros
  @packtool.PackToolExecutor::new(
    estimate_cost_micros=(_, _) => estimated_cost_micros,
    run=request => {
      match
        capability_http_post_json(submit_url, request.to_json(), timeout_ms) {
        Err(error) => Ok(capability_http_uncertain_result(error))
        Ok(value) =>
          match capability_http_decode_execution_result(value) {
            Ok(result) => Ok(result)
            Err(error) => Ok(capability_http_uncertain_result(error))
          }
      }
    },
    reconcile=Some(request => {
      match
        capability_http_post_json(reconcile_url, request.to_json(), timeout_ms) {
        Err(error) => Err(error)
        Ok(value) => capability_http_decode_reconciliation(value)
      }
    }),
  )
}

///|
fn capability_http_executor(
  policy : CapabilityHttpPolicyV1,
  route : CapabilityHttpRouteV1,
  invocation : @packtool.CapabilityInvocationV1,
) -> @packtool.PackToolExecutor raise {
  match route.provider_route_ref {
    Some(provider_route_ref) => {
      guard !provider_route_ref.is_blank() &&
        policy.approved_provider_route_refs.contains(provider_route_ref) else {
        fail("capability provider route is not approved by the host")
      }
      guard !capability_http_provider_calls_forbidden(invocation.config) else {
        fail("capability invocation explicitly forbids provider calls")
      }
    }
    None =>
      if route.transport == "moonclaw.agent-goal-http.v1" {
        fail("agent-goal execution requires an approved provider route")
      }
  }
  match route.transport {
    "moonclaw.pack-tool-http.v1" =>
      capability_http_pack_executor(route, policy.timeout_ms)
    "moonclaw.agent-goal-http.v1" => {
      guard route.base_url is Some(base_url) &&
        capability_http_loopback_url(base_url, true) else {
        fail("MoonClaw agent-goal route is incomplete or unsafe")
      }
      @packtool.moonclaw_agent_goal_executor(
        @packtool.moonclaw_agent_goal_http_transport(base_url),
      )
    }
    _ => fail("unsupported capability HTTP transport")
  }
}

///|
fn capability_http_policy_projection(
  policy : CapabilityHttpPolicyV1,
) -> @packtool.CapabilityInvocationPolicyV1 {
  {
    granted_authorities: policy.granted_authorities,
    reviewed_operation_refs: policy.reviewed_operation_refs,
    max_attempts: policy.max_attempts,
    timeout_ms: policy.timeout_ms,
    remaining_budget_micros: policy.remaining_budget_micros,
  }
}

///|
async fn capability_http_invocation(
  r : @httpx.RequestReader,
) -> @packtool.CapabilityInvocationV1 {
  let body = r.body.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _ =>
      raise capability_http_json_error(
        400, "BadRequest", "invalid_utf8", "Capability request body is not UTF-8",
      )
  }
  if text.length() > @protocol.MAX_PAYLOAD_BYTES {
    raise capability_http_json_error(
      413, "PayloadTooLarge", "payload_too_large", "Capability request exceeds the gateway payload ceiling",
    )
  }
  let value = @json.parse(text) catch {
    _ =>
      raise capability_http_json_error(
        400, "BadRequest", "invalid_json", "Capability request body is not valid JSON",
      )
  }
  @json.from_json(value) catch {
    _ =>
      raise capability_http_json_error(
        400, "BadRequest", "invalid_capability_invocation", "Capability request does not match moonclaw.capability-invocation.v1",
      )
  }
}

///|
async fn Gateway::capability_http_inputs(
  self : Gateway,
  r : @httpx.RequestReader,
  require_authority : Bool,
) -> (@packtool.CapabilityInvocationV1, CapabilityHttpPolicyV1, Json) {
  match capability_http_request_allowed(r.headers, self.port, self.auth.token) {
    Err(message) =>
      raise capability_http_json_error(
        403, "Forbidden", "capability_origin_denied", message,
      )
    Ok(_) => ()
  }
  let invocation = capability_http_invocation(r)
  let policy = load_capability_http_policy(self.cwd) catch {
    error =>
      raise capability_http_json_error(
        503,
        "ServiceUnavailable",
        "capability_policy_unavailable",
        "\{error}",
        invocation~,
      )
  }
  guard !require_authority ||
    policy.granted_authorities.contains(invocation.request.requested_authority) else {
    raise capability_http_json_error(
      403,
      "Forbidden",
      "capability_authority_denied",
      "Requested capability authority is not granted by the MoonClaw host",
      invocation~,
    )
  }
  let catalog = capability_http_catalog(self.cwd, policy) catch {
    error =>
      raise capability_http_json_error(
        503,
        "ServiceUnavailable",
        "capability_catalog_unavailable",
        "\{error}",
        invocation~,
      )
  }
  (invocation, policy, catalog)
}

///|
fn capability_http_approved_executor(
  policy : CapabilityHttpPolicyV1,
  invocation : @packtool.CapabilityInvocationV1,
) -> @packtool.PackToolExecutor raise {
  let route = capability_http_route(policy, invocation) catch {
    error =>
      raise capability_http_json_error(
        403,
        "Forbidden",
        "capability_route_denied",
        "\{error}",
        invocation~,
      )
  }
  capability_http_executor(policy, route, invocation) catch {
    error =>
      raise capability_http_json_error(
        403,
        "Forbidden",
        "capability_provider_route_denied",
        "\{error}",
        invocation~,
      )
  }
}

///|
async fn capability_http_write_outcome(
  w : @httpx.ResponseWriter,
  outcome : @packtool.CapabilityInvocationOutcomeV1,
) -> Unit {
  w.header().set("Content-Type", "application/json; charset=utf-8")
  w.header().set("Cache-Control", "no-store")
  w
  .header()
  .set("X-MoonClaw-Replayed", if outcome.replayed { "true" } else { "false" })
  w.write_header(200)
  // MoonFind consumes the canonical receipt directly.
  w.write(outcome.receipt.to_json().stringify())
}

///|
async fn Gateway::handle_capability_submit(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let (invocation, policy, catalog) = self.capability_http_inputs(r, true)
  let executor = capability_http_approved_executor(policy, invocation)
  let outcome = @packtool.execute_installed_capability_v1(
    workspace=self.cwd,
    catalog_json=catalog,
    invocation~,
    executor~,
    policy=capability_http_policy_projection(policy),
  ) catch {
    error =>
      raise capability_http_json_error(
        422,
        "UnprocessableEntity",
        "capability_submission_rejected",
        "\{error}",
        invocation~,
      )
  }
  capability_http_write_outcome(w, outcome)
}

///|
async fn Gateway::handle_capability_reconcile(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let (invocation, policy, catalog) = self.capability_http_inputs(r, true)
  let executor = capability_http_approved_executor(policy, invocation)
  let existing = @packtool.inspect_installed_capability_v1(
    workspace=self.cwd,
    catalog_json=catalog,
    invocation~,
  ) catch {
    error =>
      raise capability_http_json_error(
        422,
        "UnprocessableEntity",
        "capability_reconciliation_rejected",
        "\{error}",
        invocation~,
      )
  }
  guard existing is Some(_) else {
    raise capability_http_json_error(
      409,
      "Conflict",
      "capability_attempt_not_submitted",
      "Reconciliation cannot create a new capability attempt",
      invocation~,
    )
  }
  let outcome = @packtool.execute_installed_capability_v1(
    workspace=self.cwd,
    catalog_json=catalog,
    invocation~,
    executor~,
    policy=capability_http_policy_projection(policy),
  ) catch {
    error =>
      raise capability_http_json_error(
        422,
        "UnprocessableEntity",
        "capability_reconciliation_rejected",
        "\{error}",
        invocation~,
      )
  }
  capability_http_write_outcome(w, outcome)
}

///|
async fn Gateway::handle_capability_status(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let (invocation, _, catalog) = self.capability_http_inputs(r, false)
  let outcome = @packtool.inspect_installed_capability_v1(
    workspace=self.cwd,
    catalog_json=catalog,
    invocation~,
  ) catch {
    error =>
      raise capability_http_json_error(
        422,
        "UnprocessableEntity",
        "capability_status_rejected",
        "\{error}",
        invocation~,
      )
  }
  guard outcome is Some(outcome) else {
    raise capability_http_json_error(
      404,
      "NotFound",
      "capability_attempt_not_found",
      "No durable receipt exists for this exact capability attempt",
      invocation~,
    )
  }
  capability_http_write_outcome(w, outcome)
}
