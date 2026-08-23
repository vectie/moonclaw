///|
/// Adapter port for MoonClaw's existing native goal runtime. Implementations
/// must call that runtime; this port is not a scheduler or an agent loop.
pub struct AgentGoalRuntimeTransport {
  submit : async (Json) -> Result[Json, String]
  reconcile : async (Json) -> Result[Json, String]
  cancel : async (Json) -> Result[Json, String]
}

///|
pub fn AgentGoalRuntimeTransport::new(
  submit~ : async (Json) -> Result[Json, String],
  reconcile~ : async (Json) -> Result[Json, String],
  cancel~ : async (Json) -> Result[Json, String],
) -> AgentGoalRuntimeTransport {
  { submit, reconcile, cancel }
}

///|
fn agent_goal_string(
  fields : Map[String, Json],
  key : String,
  default? : String = "",
) -> String {
  match fields.get(key) {
    Some(String(value)) => value
    _ => default
  }
}

///|
fn agent_goal_int(
  fields : Map[String, Json],
  key : String,
  default~ : Int,
) -> Int {
  match fields.get(key) {
    Some(Number(value, ..)) => value.to_int()
    _ => default
  }
}

///|
fn agent_goal_bool(
  fields : Map[String, Json],
  key : String,
  default~ : Bool,
) -> Bool {
  match fields.get(key) {
    Some(True) => true
    Some(False) => false
    _ => default
  }
}

///|
fn agent_goal_object(
  fields : Map[String, Json],
  key : String,
) -> Map[String, Json] {
  match fields.get(key) {
    Some(Object(value)) => value
    _ => Map([])
  }
}

///|
fn agent_goal_array(fields : Map[String, Json], key : String) -> Array[Json] {
  match fields.get(key) {
    Some(Array(value)) => value
    _ => []
  }
}

///|
fn agent_goal_exact_fields(
  fields : Map[String, Json],
  allowed : Array[String],
  required : Array[String],
  subject : String,
) -> Unit raise {
  for key, _ in fields.iter2() {
    if !allowed.contains(key) {
      fail("\{subject} contains unsupported field: \{key}")
    }
  }
  for key in required {
    if fields.get(key) is None {
      fail("\{subject} is missing field: \{key}")
    }
  }
}

///|
fn agent_goal_canonical(value : String) -> Bool {
  value != "" && value == value.trim().to_owned() && value.length() <= 20000
}

///|
fn agent_goal_identifier(value : String) -> Bool {
  agent_goal_canonical(value) &&
  value.length() <= 128 &&
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
fn agent_goal_command_id(idempotency_key : String) -> String {
  "moonflow-" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(idempotency_key)))[0:32].to_owned()
}

///|
fn agent_goal_model_selector(model : String) -> String {
  if model == "gpt-5.6-sol" {
    "codex/gpt-5.6-sol"
  } else {
    model
  }
}

///|
fn agent_goal_prompt(
  role : String,
  objective : String,
  criteria : Array[Json],
  instructions : Array[Json],
) -> String raise {
  let criterion_lines : Array[String] = []
  for criterion in criteria {
    guard criterion is Object(fields) else {
      fail("agent goal criterion must be an object")
    }
    agent_goal_exact_fields(
      fields,
      ["id", "criterion"],
      ["id", "criterion"],
      "agent goal criterion",
    )
    let id = agent_goal_string(fields, "id")
    let text = agent_goal_string(fields, "criterion")
    if !agent_goal_identifier(id) || !agent_goal_canonical(text) {
      fail("agent goal criterion is invalid")
    }
    criterion_lines.push("- [\{id}] \{text}")
  }
  if criterion_lines.is_empty() {
    fail("agent goal requires at least one criterion")
  }
  let instruction_lines : Array[String] = []
  for instruction in instructions {
    guard instruction is String(text) && agent_goal_canonical(text) else {
      fail("agent goal profile instruction is invalid")
    }
    instruction_lines.push("- " + text)
  }
  let role_section = "Runtime role: " + role
  let objective_section = "Objective:\n" + objective
  let criteria_section = "Completion criteria:\n" + criterion_lines.join("\n")
  let instructions_section = if instruction_lines.is_empty() {
    ""
  } else {
    "\nRole instructions:\n" + instruction_lines.join("\n")
  }
  role_section +
  "\n\n" +
  objective_section +
  "\n\n" +
  criteria_section +
  instructions_section +
  "\n\nUse the existing goal runtime. Settle it only with finish.goal_runtime and evidence references covering every criterion. Runtime success is not human acceptance."
}

///|
fn agent_goal_normalized_action(
  request : PackToolExecutionRequest,
  action : String,
) -> Json raise {
  guard request.initial_input is Some(Object(input)) else {
    fail("agent goal executor requires an object input")
  }
  agent_goal_exact_fields(
    input,
    [
      "contract_id", "session_id", "goal_id", "workspace_root", "objective", "criteria",
      "role", "profile", "config",
    ],
    [
      "contract_id", "session_id", "goal_id", "workspace_root", "objective", "criteria",
      "role", "profile", "config",
    ],
    "agent goal request",
  )
  if agent_goal_string(input, "contract_id") !=
    "moonclaw.agent-goal-execution-request.v1" {
    fail("unsupported agent goal request contract")
  }
  let session_id = agent_goal_string(input, "session_id")
  let goal_id = agent_goal_string(input, "goal_id")
  let workspace_root = agent_goal_string(input, "workspace_root")
  let objective = agent_goal_string(input, "objective")
  let role = agent_goal_string(input, "role")
  if !agent_goal_identifier(session_id) ||
    !agent_goal_identifier(goal_id) ||
    !agent_goal_identifier(role) ||
    !agent_goal_canonical(workspace_root) ||
    !agent_goal_canonical(objective) {
    fail("agent goal identity or objective is invalid")
  }
  let criteria = agent_goal_array(input, "criteria")
  let profile = agent_goal_object(input, "profile")
  let config = agent_goal_object(input, "config")
  agent_goal_exact_fields(
    profile,
    ["model", "instructions", "web_search"],
    [],
    "agent goal profile",
  )
  agent_goal_exact_fields(
    config,
    [
      "planner_max_steps", "planner_timeout_ms", "max_turns", "live_wait_ms", "poll_ms",
    ],
    [],
    "agent goal config",
  )
  let model = agent_goal_string(profile, "model", default="gpt-5.6-sol")
  if !agent_goal_canonical(model) {
    fail("agent goal model is invalid")
  }
  let instructions = agent_goal_array(profile, "instructions")
  let command_id = agent_goal_command_id(request.idempotency_key)
  let prompt = agent_goal_prompt(role, objective, criteria, instructions)
  let planner_max_steps = agent_goal_int(config, "planner_max_steps", default=0)
  let planner_timeout_ms = agent_goal_int(
    config,
    "planner_timeout_ms",
    default=60000,
  )
  let max_turns = agent_goal_int(config, "max_turns", default=1)
  let live_wait_ms = agent_goal_int(config, "live_wait_ms", default=5000)
  let poll_ms = agent_goal_int(config, "poll_ms", default=250)
  if planner_max_steps < 0 ||
    planner_max_steps > 1000 ||
    planner_timeout_ms < 1000 ||
    planner_timeout_ms > 120000 ||
    max_turns < 1 ||
    max_turns > 100 ||
    live_wait_ms < 0 ||
    live_wait_ms > 30000 ||
    poll_ms < 25 ||
    poll_ms > 2000 {
    fail("agent goal local execution config is outside bounds")
  }
  let journal_ref = ".moonsuite/products/moonclaw/mooncode/sessions/" +
    session_id +
    "/journal.jsonl"
  let goal_runtime_ref = "/v1/code/sessions/" +
    session_id +
    "/goal-runtime?book_root=<encoded-workspace>"
  {
    "contract_id": "moonclaw.agent-goal-runtime-action.v1",
    "action": action,
    "operation_ref": "moonclaw/agent.goal.execute@0.1.5",
    "session_id": session_id,
    "goal_id": goal_id,
    "workspace_root": workspace_root,
    "command_id": command_id,
    "role": role,
    "model": model,
    "native_model_selector": agent_goal_model_selector(model),
    "goal_runtime_ref": goal_runtime_ref,
    "journal_ref": journal_ref,
    "receipt_ref": request.evidence_path,
    "command": {
      "protocol": "mooncode.v1",
      "session_id": session_id,
      "book_root": workspace_root,
      "command": "prompt",
      "model": agent_goal_model_selector(model),
      "text": prompt,
      "web_search": agent_goal_bool(profile, "web_search", default=false),
      "packet": { "command_id": command_id },
      "payload": {
        "planner_max_steps": planner_max_steps,
        "planner_timeout_ms": planner_timeout_ms,
        "role": role,
        "profile_model": model,
      },
    },
    "goal_runtime": {
      "protocol": "mooncode.v1",
      "contract": "mooncode-goal-runtime.v1",
      "session_id": session_id,
      "goal_id": goal_id,
      "objective": objective,
      "criteria": Json::array(criteria),
    },
    "service": {
      "book_root": workspace_root,
      "service_id": "moonflow-agent-goal-" + command_id,
      "consumer_id": "moonflow-agent-goal-" + command_id,
      "max_turns": max_turns,
      "live_wait_ms": live_wait_ms,
      "poll_ms": poll_ms,
    },
    "cancel": {
      "protocol": "mooncode.v1",
      "session_id": session_id,
      "book_root": workspace_root,
      "command": "cancel",
      "model": agent_goal_model_selector(model),
      "text": "Cancel the exact MoonFlow agent-goal attempt.",
      "packet": { "command_id": "cancel-" + command_id },
      "payload": { "target_command_id": command_id },
    },
  }
}

///|
fn agent_goal_collect_evidence_refs(value : Json, refs : Array[String]) -> Unit {
  match value {
    Object(fields) =>
      for key, item in fields.iter2() {
        if key == "evidence_refs" {
          match item {
            Array(values) =>
              for candidate in values {
                match candidate {
                  String(reference) =>
                    if !refs.contains(reference) {
                      refs.push(reference)
                    }
                  _ => ()
                }
              }
            _ => ()
          }
        }
        agent_goal_collect_evidence_refs(item, refs)
      }
    Array(items) =>
      for item in items {
        agent_goal_collect_evidence_refs(item, refs)
      }
    _ => ()
  }
}

///|
async fn agent_goal_artifact_evidence(
  workspace_root : String,
  journal_ref : String,
) -> Array[Json] {
  let refs : Array[String] = []
  if @pack.safe_artifact_path(journal_ref) {
    refs.push(journal_ref)
  }
  let journal_path = @pathx.join(workspace_root, journal_ref)
  if @fsx.exists_as_file(journal_path) {
    for line in @fsx.read_file(journal_path).split("\n") {
      if !line.trim().is_empty() {
        let value = @json.parse(line) catch { _ => Json::null() }
        agent_goal_collect_evidence_refs(value, refs)
      }
    }
  }
  let evidence : Array[Json] = []
  for reference in refs {
    if @pack.safe_artifact_path(reference) {
      let path = @pathx.join(workspace_root, reference)
      if @fsx.exists_as_file(path) {
        evidence.push({
          "ref": reference,
          "digest": "sha256:" +
          @crypto.bytes_to_hex_string(
            @crypto.sha256(@fs.read_file(path).binary()),
          ),
        })
      }
    }
  }
  evidence
}

///|
fn agent_goal_observation_fields(value : Json) -> Map[String, Json] raise {
  guard value is Object(fields) else {
    fail("agent goal runtime observation must be an object")
  }
  if agent_goal_string(fields, "contract_id") !=
    "moonclaw.agent-goal-runtime-observation.v1" {
    fail("unsupported agent goal runtime observation")
  }
  fields
}

///|
async fn agent_goal_execution_result(
  action : Json,
  observation : Json,
) -> PackToolExecutionResult {
  guard action is Object(action_fields) else {
    fail("normalized agent goal action must be an object")
  }
  let observed = agent_goal_observation_fields(observation)
  let execution_status = agent_goal_string(
    observed,
    "execution_status",
    default="unknown",
  )
  if !["submitted", "running", "succeeded", "failed", "cancelled", "unknown"].contains(
      execution_status,
    ) {
    fail("agent goal runtime returned unsupported execution status")
  }
  let goal_outcome = agent_goal_string(
    observed,
    "goal_outcome",
    default="unknown",
  )
  if !["none", "achieved", "blocked", "cancelled", "unknown"].contains(
      goal_outcome,
    ) {
    fail("agent goal runtime returned unsupported goal outcome")
  }
  let workspace_root = agent_goal_string(action_fields, "workspace_root")
  let journal_ref = agent_goal_string(action_fields, "journal_ref")
  let receipt_ref = agent_goal_string(action_fields, "receipt_ref")
  let artifact_evidence = agent_goal_artifact_evidence(
    workspace_root, journal_ref,
  )
  let evidence_refs = artifact_evidence.map(item => {
    guard item is Object(fields) else { "" }
    agent_goal_string(fields, "ref")
  })
  let output : Json = {
    "contract_id": "moonclaw.agent-goal-execution-receipt.v1",
    "operation_ref": "moonclaw/agent.goal.execute@0.1.5",
    "execution_status": execution_status,
    "goal_outcome": goal_outcome,
    "acceptance_status": "review-required",
    "session_id": agent_goal_string(action_fields, "session_id"),
    "goal_id": agent_goal_string(action_fields, "goal_id"),
    "command_id": agent_goal_string(action_fields, "command_id"),
    "service_id": agent_goal_string(observed, "service_id"),
    "role": agent_goal_string(action_fields, "role"),
    "model": agent_goal_string(action_fields, "model"),
    "goal_runtime_ref": agent_goal_string(action_fields, "goal_runtime_ref"),
    "journal_ref": journal_ref,
    "receipt_ref": receipt_ref,
    "evidence_refs": Json::array(evidence_refs.map(value => value.to_json())),
    "artifact_evidence": Json::array(artifact_evidence),
    "message": agent_goal_string(observed, "message"),
  }
  if receipt_ref != "" {
    let path = @pathx.join(workspace_root, receipt_ref)
    @fsx.make_directory(
      @pathx.dirname(path).to_owned(),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(path, output.stringify(indent=2) + "\n", create=0o600)
  }
  let output_artifacts : Array[String] = []
  if receipt_ref != "" {
    output_artifacts.push(receipt_ref)
  }
  if @pack.safe_artifact_path(journal_ref) &&
    @fsx.exists_as_file(@pathx.join(workspace_root, journal_ref)) {
    output_artifacts.push(journal_ref)
  }
  PackToolExecutionResult::new(
    output~,
    status=execution_status,
    summary=Some(agent_goal_string(observed, "message")),
    output_artifacts~,
    external_job_id=agent_goal_string(observed, "service_id"),
  )
}

///|
/// Construct the pack executor for the canonical agent-goal capability.
pub fn moonclaw_agent_goal_executor(
  transport : AgentGoalRuntimeTransport,
) -> PackToolExecutor {
  PackToolExecutor::new(
    run=request => {
      let action = agent_goal_normalized_action(request, "submit")
      match (transport.submit)(action) {
        Ok(observation) => Ok(agent_goal_execution_result(action, observation))
        Err(error) => Err(error)
      }
    },
    reconcile=Some(request => {
      let action = agent_goal_normalized_action(request, "reconcile")
      match (transport.reconcile)(action) {
        Ok(observation) => {
          let result = agent_goal_execution_result(action, observation)
          Ok({ status: result.status, result: Some(result), error_kind: "" })
        }
        Err(error) => Err(error)
      }
    }),
    cancel=Some(request => {
      let action = agent_goal_normalized_action(request, "cancel")
      match (transport.cancel)(action) {
        Ok(observation) => {
          let result = agent_goal_execution_result(action, observation)
          Ok({ status: result.status, result: Some(result), error_kind: "" })
        }
        Err(error) => Err(error)
      }
    }),
  )
}

///|
fn agent_goal_base_url(value : String) -> String raise {
  let trimmed = value.trim().to_owned()
  if trimmed == "" || trimmed != value {
    fail("MoonClaw daemon base URL is invalid")
  }
  if trimmed.has_suffix("/") {
    trimmed[0:trimmed.length() - 1].to_owned()
  } else {
    trimmed
  }
}

///|
async fn agent_goal_http_get(url : String) -> Result[Json, String] {
  let (response, data) = @http.get(url) catch {
    error => return Err("MoonClaw daemon GET failed: \{error}")
  }
  let body = data.text()
  if response.code < 200 || response.code >= 300 {
    return Err("MoonClaw daemon GET returned HTTP \{response.code}: \{body}")
  }
  Ok(@json.parse(body)) catch {
    error => Err("MoonClaw daemon GET returned invalid JSON: \{error}")
  }
}

///|
async fn agent_goal_http_post(
  url : String,
  body : Json,
) -> Result[Json, String] {
  let (response, data) = @http.post(url, body.stringify(), headers={
    "Content-Type": "application/json",
  }) catch {
    error => return Err("MoonClaw daemon POST failed: \{error}")
  }
  let text = data.text()
  if response.code < 200 || response.code >= 300 {
    return Err("MoonClaw daemon POST returned HTTP \{response.code}: \{text}")
  }
  Ok(@json.parse(text)) catch {
    error => Err("MoonClaw daemon POST returned invalid JSON: \{error}")
  }
}

///|
async fn agent_goal_http_put(url : String, body : Json) -> Result[Json, String] {
  let (response, data) = @http.put(url, body.stringify(), headers={
    "Content-Type": "application/json",
  }) catch {
    error => return Err("MoonClaw daemon PUT failed: \{error}")
  }
  let text = data.text()
  if response.code < 200 || response.code >= 300 {
    return Err("MoonClaw daemon PUT returned HTTP \{response.code}: \{text}")
  }
  Ok(@json.parse(text)) catch {
    error => Err("MoonClaw daemon PUT returned invalid JSON: \{error}")
  }
}

///|
fn agent_goal_action_endpoint(
  base_url : String,
  fields : Map[String, Json],
  suffix : String,
) -> String {
  let session = @mooncode_core.native_endpoint_component(
    agent_goal_string(fields, "session_id"),
  )
  let root = @mooncode_core.native_endpoint_component(
    agent_goal_string(fields, "workspace_root"),
  )
  "\{base_url}/v1/code/sessions/\{session}/\{suffix}?book_root=\{root}"
}

///|
fn agent_goal_http_observation(
  goal_response : Json,
  service_id? : String = "",
  message? : String = "",
) -> Json {
  let (terminal, phase, outcome) = match goal_response {
    Object(fields) => {
      let status = agent_goal_object(fields, "status")
      (
        agent_goal_bool(status, "terminal", default=false),
        agent_goal_string(status, "phase", default="queued"),
        agent_goal_string(status, "outcome", default="none"),
      )
    }
    _ => (false, "queued", "unknown")
  }
  let execution_status = if terminal {
    match outcome {
      "achieved" => "succeeded"
      "blocked" => "failed"
      "cancelled" => "cancelled"
      _ => "unknown"
    }
  } else {
    match phase {
      "queued" => "submitted"
      _ => "running"
    }
  }
  {
    "contract_id": "moonclaw.agent-goal-runtime-observation.v1",
    "execution_status": execution_status,
    "goal_outcome": outcome,
    "service_id": service_id,
    "message": if message == "" {
      "MoonClaw projected the existing durable goal runtime."
    } else {
      message
    },
  }
}

///|
/// Real transport that wraps the already-running MoonClaw daemon. No runtime,
/// queue, lease or retry loop is created by this adapter.
pub fn moonclaw_agent_goal_http_transport(
  daemon_base_url : String,
) -> AgentGoalRuntimeTransport raise {
  let base_url = agent_goal_base_url(daemon_base_url)
  AgentGoalRuntimeTransport::new(
    submit=action => {
      guard action is Object(fields) else {
        return Err("normalized agent goal action is invalid")
      }
      let session = @mooncode_core.native_endpoint_component(
        agent_goal_string(fields, "session_id"),
      )
      let command_url = "\{base_url}/v1/code/sessions/\{session}/commands"
      let goal_url = agent_goal_action_endpoint(
        base_url, fields, "goal-runtime",
      )
      let service_url = agent_goal_action_endpoint(
        base_url, fields, "runtime-service",
      )
      match
        agent_goal_http_post(
          command_url,
          fields.get("command").unwrap_or(Json::empty_object()),
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      let goal = match
        agent_goal_http_put(
          goal_url,
          fields.get("goal_runtime").unwrap_or(Json::empty_object()),
        ) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let service = match
        agent_goal_http_post(
          service_url,
          fields.get("service").unwrap_or(Json::empty_object()),
        ) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let service_id = match service {
        Object(service_fields) =>
          agent_goal_string(service_fields, "service_id")
        _ => ""
      }
      Ok(
        agent_goal_http_observation(
          goal,
          service_id~,
          message="MoonClaw durably submitted the goal to its existing runtime service.",
        ),
      )
    },
    reconcile=action => {
      guard action is Object(fields) else {
        return Err("normalized agent goal action is invalid")
      }
      match
        agent_goal_http_get(
          agent_goal_action_endpoint(base_url, fields, "goal-runtime"),
        ) {
        Ok(goal) => Ok(agent_goal_http_observation(goal))
        Err(error) => Err(error)
      }
    },
    cancel=action => {
      guard action is Object(fields) else {
        return Err("normalized agent goal action is invalid")
      }
      let session = @mooncode_core.native_endpoint_component(
        agent_goal_string(fields, "session_id"),
      )
      match
        agent_goal_http_post(
          "\{base_url}/v1/code/sessions/\{session}/turns",
          fields.get("cancel").unwrap_or(Json::empty_object()),
        ) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match
        agent_goal_http_get(
          agent_goal_action_endpoint(base_url, fields, "goal-runtime"),
        ) {
        Ok(goal) =>
          Ok(
            agent_goal_http_observation(
              goal,
              message="MoonClaw recorded exact-target cancellation in the existing session journal.",
            ),
          )
        Err(error) => Err(error)
      }
    },
  )
}

///|
/// Probe the live daemon surface used to issue expiring adapter health.
pub async fn probe_moonclaw_agent_goal_http(
  daemon_base_url : String,
) -> Result[Json, String] {
  let base_url = agent_goal_base_url(daemon_base_url)
  let health = match agent_goal_http_get(base_url + "/v1/health") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let capabilities = match
    agent_goal_http_get(base_url + "/v1/code/capabilities") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  guard capabilities is Object(fields) &&
    agent_goal_bool(fields, "native_runtime_ready", default=false) &&
    agent_goal_string(fields, "runtime_owner") == "moonclaw" &&
    agent_goal_string(fields, "goal_runtime_endpoint").contains("/goal-runtime") else {
    return Err(
      "MoonClaw daemon does not expose the required native goal runtime",
    )
  }
  Ok({
    "contract_id": "moonclaw.agent-goal-health-evidence.v1",
    "operation_ref": "moonclaw/agent.goal.execute@0.1.5",
    "daemon_health": health,
    "native_capabilities": capabilities,
  })
}
