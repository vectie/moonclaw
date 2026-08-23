// Strict codec for mooncode-goal-runtime.v1.
// Runtime physical journal lane remains `event`; this codec emits logical payload objects only.

///|
let mooncode_goal_runtime_protocol_v1 = "mooncode.v1"

///|
let mooncode_goal_runtime_contract_v1 = "mooncode-goal-runtime.v1"

///|
let mooncode_goal_runtime_genesis_kind_v1 = "mooncode.goal.runtime.genesis.v1"

///|
let mooncode_goal_runtime_event_kind_v1 = "mooncode.goal.runtime.event.v1"

///|
let mooncode_goal_runtime_genesis_id_v1 = "goal-runtime-genesis-v1"

///|
priv suberror MoonCodeGoalRuntimeCodecError {
  Invalid(String)
}

///|
priv struct MoonCodeGoalRuntimeStoredCriterion {
  id : String
  criterion : String
}

///|
priv struct MoonCodeGoalRuntimeStoredGenesis {
  id : String
  session_id : String
  goal_id : String
  objective : String
  criteria : Array[MoonCodeGoalRuntimeStoredCriterion]
  semantic_digest : String
  recorded_at : Int64
}

///|
priv struct MoonCodeGoalRuntimeStoredEvent {
  id : String
  session_id : String
  goal_id : String
  event : @mooncode_core.GoalRuntimeEvent
  semantic_digest : String
  recorded_at : Int64
}

///|
fn[T] mooncode_goal_runtime_fail(
  message : String,
) -> T raise MoonCodeGoalRuntimeCodecError {
  raise Invalid(message)
}

///|
fn mooncode_goal_runtime_canonical(value : String) -> Bool {
  value != "" && value.trim() == value
}

///|
fn mooncode_goal_runtime_json_string(value : String) -> String {
  value.to_json().stringify()
}

///|
fn mooncode_goal_runtime_sha256_hex(text : String) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(text).to_fixedarray()),
  )
}

///|
fn mooncode_goal_runtime_valid_digest(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  for ch in value {
    if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
      return false
    }
  }
  true
}

///|
fn mooncode_goal_runtime_exact_object(
  json : Json,
  keys : Array[String],
  label : String,
) -> Map[String, Json] raise MoonCodeGoalRuntimeCodecError {
  guard json is Object(object) else {
    mooncode_goal_runtime_fail(label + " must be an object")
  }
  for key in keys {
    if !object.contains(key) {
      mooncode_goal_runtime_fail(label + " missing key " + key)
    }
  }
  for key, _ in object {
    if !keys.any(fn(allowed) { allowed == key }) {
      mooncode_goal_runtime_fail(label + " has unexpected key " + key)
    }
  }
  object
}

///|
fn mooncode_goal_runtime_json_field(
  object : Map[String, Json],
  key : String,
) -> Json raise MoonCodeGoalRuntimeCodecError {
  match object.get(key) {
    Some(value) => value
    None => mooncode_goal_runtime_fail("missing key " + key)
  }
}

///|
fn mooncode_goal_runtime_checked_string(
  object : Map[String, Json],
  key : String,
) -> String raise MoonCodeGoalRuntimeCodecError {
  match mooncode_goal_runtime_json_field(object, key) {
    String(value) => value
    _ => mooncode_goal_runtime_fail(key + " must be a string")
  }
}

///|
fn mooncode_goal_runtime_checked_array(
  object : Map[String, Json],
  key : String,
) -> Array[Json] raise MoonCodeGoalRuntimeCodecError {
  match mooncode_goal_runtime_json_field(object, key) {
    Array(values) => values
    _ => mooncode_goal_runtime_fail(key + " must be an array")
  }
}

///|
fn mooncode_goal_runtime_decode_string_array(
  json : Json,
) -> Array[String] raise MoonCodeGoalRuntimeCodecError {
  guard json is Array(values) else {
    mooncode_goal_runtime_fail("string array must be an array")
  }
  values.map(fn(value) raise MoonCodeGoalRuntimeCodecError {
    match value {
      String(text) => text
      _ => mooncode_goal_runtime_fail("string array item must be a string")
    }
  })
}

///|
fn mooncode_goal_runtime_decode_optional_string(
  json : Json,
) -> String? raise MoonCodeGoalRuntimeCodecError {
  match json {
    String(value) => Some(value)
    Null => None
    _ => mooncode_goal_runtime_fail("optional string must be a string or null")
  }
}

///|
fn mooncode_goal_runtime_decode_phase(
  json : Json,
) -> @mooncode_core.GoalRuntimePhase raise MoonCodeGoalRuntimeCodecError {
  match json {
    String("queued") => Queued
    String("running") => Running
    String("waiting_approval") => WaitingApproval
    String("retry_backoff") => RetryBackoff
    String("paused_no_progress") => PausedNoProgress
    String("paused_external") => PausedExternal
    _ => mooncode_goal_runtime_fail("invalid phase")
  }
}

///|
fn mooncode_goal_runtime_checked_nonnegative_int64(
  object : Map[String, Json],
  key : String,
) -> Int64 raise MoonCodeGoalRuntimeCodecError {
  let json = mooncode_goal_runtime_json_field(object, key)
  let value = match json {
    Number(_, repr=Some(raw)) =>
      @string.parse_int64(raw) catch {
        _ =>
          mooncode_goal_runtime_fail(key + " must be a full-precision integer")
      }
    Number(number, repr=None) => {
      if number.is_inf() ||
        number.is_nan() ||
        number != number.trunc() ||
        number < 0.0 ||
        number > 9007199254740991.0 {
        mooncode_goal_runtime_fail(key + " must be a full-precision integer")
      }
      number.to_int64()
    }
    _ => mooncode_goal_runtime_fail(key + " must be a full-precision integer")
  }
  if value < 0L {
    mooncode_goal_runtime_fail(key + " must be nonnegative")
  }
  value
}

///|
fn mooncode_goal_runtime_checked_positive_int(
  object : Map[String, Json],
  key : String,
) -> Int raise MoonCodeGoalRuntimeCodecError {
  let value = match mooncode_goal_runtime_json_field(object, key) {
    Number(value, ..) => value
    _ => mooncode_goal_runtime_fail(key + " must be an integer")
  }
  if value < 1.0 ||
    value > 2147483647.0 ||
    value.is_nan() ||
    value.floor() != value {
    mooncode_goal_runtime_fail(key + " must be an integer in 1..2147483647")
  }
  value.to_int()
}

///|
fn mooncode_goal_runtime_decode_policy(
  json : Json,
) -> @mooncode_core.GoalOperationPolicy raise MoonCodeGoalRuntimeCodecError {
  let object = mooncode_goal_runtime_exact_object(
    json,
    ["max_output_bytes", "timeout_milliseconds"],
    "policy",
  )
  {
    max_output_bytes: mooncode_goal_runtime_checked_positive_int(
      object, "max_output_bytes",
    ),
    timeout_milliseconds: mooncode_goal_runtime_checked_positive_int(
      object, "timeout_milliseconds",
    ),
  }
}

///|
fn mooncode_goal_runtime_decode_operation(
  json : Json,
) -> @mooncode_core.GoalRuntimeOperation raise MoonCodeGoalRuntimeCodecError {
  let object = mooncode_goal_runtime_exact_object(
    json,
    ["operation_id", "kind", "input", "policy"],
    "operation",
  )
  {
    operation_id: mooncode_goal_runtime_checked_string(object, "operation_id"),
    kind: mooncode_goal_runtime_checked_string(object, "kind"),
    input: mooncode_goal_runtime_checked_string(object, "input"),
    policy: mooncode_goal_runtime_decode_policy(
      mooncode_goal_runtime_json_field(object, "policy"),
    ),
  }
}

///|
fn mooncode_goal_runtime_decode_criterion_evidence(
  json : Json,
) -> @mooncode_core.GoalCriterionEvidence raise MoonCodeGoalRuntimeCodecError {
  let object = mooncode_goal_runtime_exact_object(
    json,
    ["criterion", "evidence_refs"],
    "criterion evidence",
  )
  {
    criterion: mooncode_goal_runtime_checked_string(object, "criterion"),
    evidence_refs: mooncode_goal_runtime_decode_string_array(
      mooncode_goal_runtime_json_field(object, "evidence_refs"),
    ),
  }
}

///|
fn mooncode_goal_runtime_decode_decision(
  json : Json,
) -> @mooncode_core.GoalPlannerDecision raise MoonCodeGoalRuntimeCodecError {
  guard json is Object(probe) else {
    mooncode_goal_runtime_fail("planner decision must be an object")
  }
  let kind = mooncode_goal_runtime_checked_string(probe, "type")
  let decision = match kind {
    "continue" => {
      let object = mooncode_goal_runtime_exact_object(
        json,
        ["type", "operations", "expected_progress", "rationale"],
        "continue decision",
      )
      let operations = mooncode_goal_runtime_checked_array(object, "operations").map(fn(
          value,
        ) raise MoonCodeGoalRuntimeCodecError {
          mooncode_goal_runtime_decode_operation(value)
        },
      )
      @mooncode_core.Continue(
        operations,
        mooncode_goal_runtime_checked_string(object, "expected_progress"),
        mooncode_goal_runtime_checked_string(object, "rationale"),
      )
    }
    "achieved" => {
      let object = mooncode_goal_runtime_exact_object(
        json,
        ["type", "summary", "evidence"],
        "achieved decision",
      )
      let evidence = mooncode_goal_runtime_checked_array(object, "evidence").map(fn(
          value,
        ) raise MoonCodeGoalRuntimeCodecError {
          mooncode_goal_runtime_decode_criterion_evidence(value)
        },
      )
      Achieved(
        mooncode_goal_runtime_checked_string(object, "summary"),
        evidence,
      )
    }
    "blocked" => {
      let object = mooncode_goal_runtime_exact_object(
        json,
        ["type", "reason", "attempted_alternatives", "required_event"],
        "blocked decision",
      )
      Blocked(
        mooncode_goal_runtime_decode_blocked_reason(
          mooncode_goal_runtime_json_field(object, "reason"),
        ),
        mooncode_goal_runtime_decode_string_array(
          mooncode_goal_runtime_json_field(object, "attempted_alternatives"),
        ),
        mooncode_goal_runtime_decode_optional_string(
          mooncode_goal_runtime_json_field(object, "required_event"),
        ),
      )
    }
    _ => mooncode_goal_runtime_fail("invalid planner decision type")
  }
  if !@mooncode_core.validate_goal_planner_decision(decision) {
    mooncode_goal_runtime_fail("invalid planner decision")
  }
  decision
}

///|
fn mooncode_goal_runtime_decode_event_payload(
  json : Json,
  event_id : String,
) -> @mooncode_core.GoalRuntimeEvent raise MoonCodeGoalRuntimeCodecError {
  guard json is Object(probe) else {
    mooncode_goal_runtime_fail("event payload must be an object")
  }
  let kind = mooncode_goal_runtime_checked_string(probe, "type")
  match kind {
    "planner_decision" => {
      let object = mooncode_goal_runtime_exact_object(
        json,
        ["type", "decision"],
        "planner decision event",
      )
      PlannerDecision(
        event_id,
        mooncode_goal_runtime_decode_decision(
          mooncode_goal_runtime_json_field(object, "decision"),
        ),
      )
    }
    "operation_accepted" => {
      let object = mooncode_goal_runtime_exact_object(
        json,
        ["type", "operation_id"],
        "operation accepted event",
      )
      OperationAccepted(
        event_id,
        mooncode_goal_runtime_checked_string(object, "operation_id"),
      )
    }
    "checkpoint_accepted" => {
      let object = mooncode_goal_runtime_exact_object(
        json,
        ["type", "checkpoint_id"],
        "checkpoint accepted event",
      )
      CheckpointAccepted(
        event_id,
        mooncode_goal_runtime_checked_string(object, "checkpoint_id"),
      )
    }
    "phase_changed" => {
      let object = mooncode_goal_runtime_exact_object(
        json,
        ["type", "phase"],
        "phase changed event",
      )
      PhaseChanged(
        event_id,
        mooncode_goal_runtime_decode_phase(
          mooncode_goal_runtime_json_field(object, "phase"),
        ),
      )
    }
    "cancelled" => {
      let object = mooncode_goal_runtime_exact_object(
        json,
        ["type", "reason"],
        "cancelled event",
      )
      Cancelled(
        event_id,
        mooncode_goal_runtime_checked_string(object, "reason"),
      )
    }
    _ => mooncode_goal_runtime_fail("invalid event payload type")
  }
}

///|
fn mooncode_goal_runtime_decode_blocked_reason(
  json : Json,
) -> @mooncode_core.GoalBlockedReason raise MoonCodeGoalRuntimeCodecError {
  let object = mooncode_goal_runtime_exact_object(
    json,
    ["code", "detail"],
    "blocked reason",
  )
  {
    code: mooncode_goal_runtime_checked_string(object, "code"),
    detail: mooncode_goal_runtime_checked_string(object, "detail"),
  }
}

///|
fn decode_mooncode_goal_runtime_genesis(
  text : String,
) -> MoonCodeGoalRuntimeStoredGenesis raise MoonCodeGoalRuntimeCodecError {
  let json = @json.parse(text) catch {
    _ => mooncode_goal_runtime_fail("malformed genesis JSON")
  }
  let object = mooncode_goal_runtime_exact_object(
    json,
    [
      "id", "kind", "protocol", "contract", "session_id", "goal_id", "objective",
      "criteria", "semantic_digest", "recorded_at",
    ],
    "genesis",
  )
  let id = mooncode_goal_runtime_checked_string(object, "id")
  let kind = mooncode_goal_runtime_checked_string(object, "kind")
  let protocol = mooncode_goal_runtime_checked_string(object, "protocol")
  let contract = mooncode_goal_runtime_checked_string(object, "contract")
  if id != mooncode_goal_runtime_genesis_id_v1 {
    mooncode_goal_runtime_fail("invalid genesis id")
  }
  if kind != mooncode_goal_runtime_genesis_kind_v1 {
    mooncode_goal_runtime_fail("invalid genesis kind")
  }
  if protocol != mooncode_goal_runtime_protocol_v1 {
    mooncode_goal_runtime_fail("invalid genesis protocol")
  }
  if contract != mooncode_goal_runtime_contract_v1 {
    mooncode_goal_runtime_fail("invalid genesis contract")
  }
  let criteria : Array[MoonCodeGoalRuntimeStoredCriterion] = []
  for item in mooncode_goal_runtime_checked_array(object, "criteria") {
    let criterion = mooncode_goal_runtime_exact_object(
      item,
      ["id", "criterion"],
      "criterion",
    )
    criteria.push({
      id: mooncode_goal_runtime_checked_string(criterion, "id"),
      criterion: mooncode_goal_runtime_checked_string(criterion, "criterion"),
    })
  }
  let supplied_digest = mooncode_goal_runtime_checked_string(
    object, "semantic_digest",
  )
  if !mooncode_goal_runtime_valid_digest(supplied_digest) {
    mooncode_goal_runtime_fail("semantic_digest must be lowercase 64 hex")
  }
  let reconstructed = new_mooncode_goal_runtime_genesis(
    mooncode_goal_runtime_checked_string(object, "session_id"),
    mooncode_goal_runtime_checked_string(object, "goal_id"),
    mooncode_goal_runtime_checked_string(object, "objective"),
    criteria,
    mooncode_goal_runtime_checked_nonnegative_int64(object, "recorded_at"),
  )
  if supplied_digest != reconstructed.semantic_digest {
    mooncode_goal_runtime_fail("semantic_digest mismatch")
  }
  if text != encode_mooncode_goal_runtime_genesis(reconstructed) {
    mooncode_goal_runtime_fail("genesis JSON must use canonical encoding")
  }
  reconstructed
}

///|
fn mooncode_goal_runtime_string_array(values : Array[String]) -> String {
  "[" + values.map(mooncode_goal_runtime_json_string).join(",") + "]"
}

///|
fn mooncode_goal_runtime_require_canonical_strings(
  values : Array[String],
  label : String,
) -> Unit raise MoonCodeGoalRuntimeCodecError {
  for value in values {
    if !mooncode_goal_runtime_canonical(value) {
      mooncode_goal_runtime_fail(
        label + " must contain canonical nonblank values",
      )
    }
  }
}

///|
fn mooncode_goal_runtime_require_unique_strings(
  values : Array[String],
  label : String,
) -> Unit raise MoonCodeGoalRuntimeCodecError {
  mooncode_goal_runtime_require_canonical_strings(values, label)
  let seen : Array[String] = []
  for value in values {
    if seen.any(fn(item) { item == value }) {
      mooncode_goal_runtime_fail(label + " must be unique")
    }
    seen.push(value)
  }
}

///|
fn mooncode_goal_runtime_phase_json(
  phase : @mooncode_core.GoalRuntimePhase,
) -> String {
  match phase {
    Queued => "\"queued\""
    Running => "\"running\""
    WaitingApproval => "\"waiting_approval\""
    RetryBackoff => "\"retry_backoff\""
    PausedNoProgress => "\"paused_no_progress\""
    PausedExternal => "\"paused_external\""
  }
}

///|
fn mooncode_goal_runtime_policy_json(
  policy : @mooncode_core.GoalOperationPolicy,
) -> String {
  "{\"max_output_bytes\":" +
  policy.max_output_bytes.to_string() +
  ",\"timeout_milliseconds\":" +
  policy.timeout_milliseconds.to_string() +
  "}"
}

///|
fn mooncode_goal_runtime_operation_json(
  operation : @mooncode_core.GoalRuntimeOperation,
) -> String {
  "{\"operation_id\":" +
  mooncode_goal_runtime_json_string(operation.operation_id) +
  ",\"kind\":" +
  mooncode_goal_runtime_json_string(operation.kind) +
  ",\"input\":" +
  mooncode_goal_runtime_json_string(operation.input) +
  ",\"policy\":" +
  mooncode_goal_runtime_policy_json(operation.policy) +
  "}"
}

///|
fn mooncode_goal_runtime_evidence_json(
  evidence : @mooncode_core.GoalCriterionEvidence,
) -> String {
  "{\"criterion\":" +
  mooncode_goal_runtime_json_string(evidence.criterion) +
  ",\"evidence_refs\":" +
  mooncode_goal_runtime_string_array(evidence.evidence_refs) +
  "}"
}

///|
fn mooncode_goal_runtime_blocked_reason_json(
  reason : @mooncode_core.GoalBlockedReason,
) -> String {
  "{\"code\":" +
  mooncode_goal_runtime_json_string(reason.code) +
  ",\"detail\":" +
  mooncode_goal_runtime_json_string(reason.detail) +
  "}"
}

///|
fn mooncode_goal_runtime_optional_string(value : String?) -> String {
  match value {
    Some(text) => mooncode_goal_runtime_json_string(text)
    None => "null"
  }
}

///|
fn mooncode_goal_runtime_decision_json(
  decision : @mooncode_core.GoalPlannerDecision,
) -> String {
  match decision {
    Continue(operations, expected_progress, rationale) =>
      "{\"type\":\"continue\",\"operations\":[" +
      operations.map(mooncode_goal_runtime_operation_json).join(",") +
      "],\"expected_progress\":" +
      mooncode_goal_runtime_json_string(expected_progress) +
      ",\"rationale\":" +
      mooncode_goal_runtime_json_string(rationale) +
      "}"
    Achieved(summary, evidence) =>
      "{\"type\":\"achieved\",\"summary\":" +
      mooncode_goal_runtime_json_string(summary) +
      ",\"evidence\":[" +
      evidence.map(mooncode_goal_runtime_evidence_json).join(",") +
      "]}"
    Blocked(reason, attempted_alternatives, required_event) =>
      "{\"type\":\"blocked\",\"reason\":" +
      mooncode_goal_runtime_blocked_reason_json(reason) +
      ",\"attempted_alternatives\":" +
      mooncode_goal_runtime_string_array(attempted_alternatives) +
      ",\"required_event\":" +
      mooncode_goal_runtime_optional_string(required_event) +
      "}"
  }
}

///|
fn mooncode_goal_runtime_event_id(
  event : @mooncode_core.GoalRuntimeEvent,
) -> String {
  match event {
    PlannerDecision(id, _) => id
    OperationAccepted(id, _) => id
    CheckpointAccepted(id, _) => id
    PhaseChanged(id, _) => id
    Cancelled(id, _) => id
  }
}

///|
fn mooncode_goal_runtime_event_json(
  event : @mooncode_core.GoalRuntimeEvent,
) -> String {
  match event {
    PlannerDecision(_, decision) =>
      "{\"type\":\"planner_decision\",\"decision\":" +
      mooncode_goal_runtime_decision_json(decision) +
      "}"
    OperationAccepted(_, operation_id) =>
      "{\"type\":\"operation_accepted\",\"operation_id\":" +
      mooncode_goal_runtime_json_string(operation_id) +
      "}"
    CheckpointAccepted(_, checkpoint_id) =>
      "{\"type\":\"checkpoint_accepted\",\"checkpoint_id\":" +
      mooncode_goal_runtime_json_string(checkpoint_id) +
      "}"
    PhaseChanged(_, phase) =>
      "{\"type\":\"phase_changed\",\"phase\":" +
      mooncode_goal_runtime_phase_json(phase) +
      "}"
    Cancelled(_, reason) =>
      "{\"type\":\"cancelled\",\"reason\":" +
      mooncode_goal_runtime_json_string(reason) +
      "}"
  }
}

///|
fn mooncode_goal_runtime_copy_policy(
  policy : @mooncode_core.GoalOperationPolicy,
) -> @mooncode_core.GoalOperationPolicy {
  {
    max_output_bytes: policy.max_output_bytes,
    timeout_milliseconds: policy.timeout_milliseconds,
  }
}

///|
fn mooncode_goal_runtime_copy_operation(
  operation : @mooncode_core.GoalRuntimeOperation,
) -> @mooncode_core.GoalRuntimeOperation {
  {
    operation_id: operation.operation_id,
    kind: operation.kind,
    input: operation.input,
    policy: mooncode_goal_runtime_copy_policy(operation.policy),
  }
}

///|
fn mooncode_goal_runtime_copy_decision(
  decision : @mooncode_core.GoalPlannerDecision,
) -> @mooncode_core.GoalPlannerDecision {
  match decision {
    Continue(operations, progress, reason) =>
      Continue(
        operations.map(mooncode_goal_runtime_copy_operation),
        progress,
        reason,
      )
    Achieved(summary, evidence) =>
      Achieved(
        summary,
        evidence.map(fn(item) {
          {
            criterion: item.criterion,
            evidence_refs: item.evidence_refs.copy(),
          }
        }),
      )
    Blocked(reason, attempted_alternatives, required_event) =>
      Blocked(
        { code: reason.code, detail: reason.detail },
        attempted_alternatives.copy(),
        required_event,
      )
  }
}

///|
fn mooncode_goal_runtime_copy_event(
  event : @mooncode_core.GoalRuntimeEvent,
) -> @mooncode_core.GoalRuntimeEvent {
  match event {
    PlannerDecision(id, decision) =>
      PlannerDecision(id, mooncode_goal_runtime_copy_decision(decision))
    OperationAccepted(id, operation_id) => OperationAccepted(id, operation_id)
    CheckpointAccepted(id, checkpoint_id) =>
      CheckpointAccepted(id, checkpoint_id)
    PhaseChanged(id, phase) => PhaseChanged(id, phase)
    Cancelled(id, reason) => Cancelled(id, reason)
  }
}

///|
fn mooncode_goal_runtime_event_semantic_basis(
  session_id : String,
  goal_id : String,
  payload : @mooncode_core.GoalRuntimeEvent,
) -> String {
  "{\"kind\":" +
  mooncode_goal_runtime_json_string(mooncode_goal_runtime_event_kind_v1) +
  ",\"protocol\":" +
  mooncode_goal_runtime_json_string(mooncode_goal_runtime_protocol_v1) +
  ",\"contract\":" +
  mooncode_goal_runtime_json_string(mooncode_goal_runtime_contract_v1) +
  ",\"session_id\":" +
  mooncode_goal_runtime_json_string(session_id) +
  ",\"goal_id\":" +
  mooncode_goal_runtime_json_string(goal_id) +
  ",\"payload\":" +
  mooncode_goal_runtime_event_json(payload) +
  "}"
}

///|
fn new_mooncode_goal_runtime_genesis(
  session_id : String,
  goal_id : String,
  objective : String,
  criteria : Array[MoonCodeGoalRuntimeStoredCriterion],
  recorded_at : Int64,
) -> MoonCodeGoalRuntimeStoredGenesis raise MoonCodeGoalRuntimeCodecError {
  let id = mooncode_goal_runtime_genesis_id_v1
  let normalized_criteria = criteria.map(fn(item) {
    { id: item.id, criterion: item.criterion }
  })
  mooncode_goal_runtime_require_canonical_strings(
    [id, session_id, goal_id, objective],
    "genesis identity",
  )
  if normalized_criteria.length() == 0 {
    mooncode_goal_runtime_fail("criteria must not be empty")
  }
  mooncode_goal_runtime_require_unique_strings(
    normalized_criteria.map(fn(item) { item.id }),
    "criterion ids",
  )
  mooncode_goal_runtime_require_unique_strings(
    normalized_criteria.map(fn(item) { item.criterion }),
    "criterion texts",
  )
  if recorded_at < 0 {
    mooncode_goal_runtime_fail("recorded_at must be nonnegative")
  }
  let semantic = "{\"protocol\":\"" +
    mooncode_goal_runtime_protocol_v1 +
    "\",\"contract\":\"" +
    mooncode_goal_runtime_contract_v1 +
    "\",\"session_id\":" +
    mooncode_goal_runtime_json_string(session_id) +
    ",\"goal_id\":" +
    mooncode_goal_runtime_json_string(goal_id) +
    ",\"objective\":" +
    mooncode_goal_runtime_json_string(objective) +
    ",\"criteria\":[" +
    normalized_criteria
    .map(fn(item) {
      "{\"id\":" +
      mooncode_goal_runtime_json_string(item.id) +
      ",\"criterion\":" +
      mooncode_goal_runtime_json_string(item.criterion) +
      "}"
    })
    .join(",") +
    "]}"
  {
    id,
    session_id,
    goal_id,
    objective,
    criteria: normalized_criteria,
    semantic_digest: mooncode_goal_runtime_sha256_hex(semantic),
    recorded_at,
  }
}

///|
fn genesis_envelope_json(value : MoonCodeGoalRuntimeStoredGenesis) -> String {
  "{\"id\":" +
  mooncode_goal_runtime_json_string(value.id) +
  ",\"kind\":\"" +
  mooncode_goal_runtime_genesis_kind_v1 +
  "\",\"protocol\":\"" +
  mooncode_goal_runtime_protocol_v1 +
  "\",\"contract\":\"" +
  mooncode_goal_runtime_contract_v1 +
  "\",\"session_id\":" +
  mooncode_goal_runtime_json_string(value.session_id) +
  ",\"goal_id\":" +
  mooncode_goal_runtime_json_string(value.goal_id) +
  ",\"objective\":" +
  mooncode_goal_runtime_json_string(value.objective) +
  ",\"criteria\":[" +
  value.criteria
  .map(fn(item) {
    "{\"id\":" +
    mooncode_goal_runtime_json_string(item.id) +
    ",\"criterion\":" +
    mooncode_goal_runtime_json_string(item.criterion) +
    "}"
  })
  .join(",") +
  "],\"semantic_digest\":\"" +
  value.semantic_digest +
  "\",\"recorded_at\":" +
  value.recorded_at.to_string() +
  "}"
}

///|
fn new_mooncode_goal_runtime_stored_event(
  session_id : String,
  goal_id : String,
  event : @mooncode_core.GoalRuntimeEvent,
  recorded_at : Int64,
) -> MoonCodeGoalRuntimeStoredEvent raise MoonCodeGoalRuntimeCodecError {
  let normalized_event = mooncode_goal_runtime_copy_event(event)
  let id = mooncode_goal_runtime_event_id(normalized_event)
  mooncode_goal_runtime_require_canonical_strings(
    [id, session_id, goal_id],
    "event identity",
  )
  match normalized_event {
    PlannerDecision(_, decision) =>
      if !@mooncode_core.validate_goal_planner_decision(decision) {
        mooncode_goal_runtime_fail("invalid planner decision")
      }
    OperationAccepted(_, operation_id) =>
      mooncode_goal_runtime_require_canonical_strings(
        [operation_id],
        "operation_id",
      )
    CheckpointAccepted(_, checkpoint_id) =>
      mooncode_goal_runtime_require_canonical_strings(
        [checkpoint_id],
        "checkpoint_id",
      )
    PhaseChanged(_, Queued) => ()
    PhaseChanged(_, Running) => ()
    PhaseChanged(_, WaitingApproval) => ()
    PhaseChanged(_, RetryBackoff) => ()
    PhaseChanged(_, PausedNoProgress) => ()
    PhaseChanged(_, PausedExternal) => ()
    Cancelled(_, reason) =>
      if reason.trim().is_empty() {
        mooncode_goal_runtime_fail("cancel reason must not be blank")
      }
  }
  if recorded_at < 0L {
    mooncode_goal_runtime_fail("recorded_at must be nonnegative")
  }
  let semantic = mooncode_goal_runtime_event_semantic_basis(
    session_id, goal_id, normalized_event,
  )
  {
    id,
    session_id,
    goal_id,
    event: normalized_event,
    semantic_digest: mooncode_goal_runtime_sha256_hex(semantic),
    recorded_at,
  }
}

///|
fn event_envelope_json(value : MoonCodeGoalRuntimeStoredEvent) -> String {
  "{\"id\":" +
  mooncode_goal_runtime_json_string(value.id) +
  ",\"kind\":" +
  mooncode_goal_runtime_json_string(mooncode_goal_runtime_event_kind_v1) +
  ",\"protocol\":\"" +
  mooncode_goal_runtime_protocol_v1 +
  "\",\"contract\":\"" +
  mooncode_goal_runtime_contract_v1 +
  "\",\"session_id\":" +
  mooncode_goal_runtime_json_string(value.session_id) +
  ",\"goal_id\":" +
  mooncode_goal_runtime_json_string(value.goal_id) +
  ",\"payload\":" +
  mooncode_goal_runtime_event_json(value.event) +
  ",\"semantic_digest\":\"" +
  value.semantic_digest +
  "\",\"recorded_at\":" +
  value.recorded_at.to_string() +
  "}"
}

///|
fn encode_mooncode_goal_runtime_genesis(
  value : MoonCodeGoalRuntimeStoredGenesis,
) -> String raise MoonCodeGoalRuntimeCodecError {
  if value.id != mooncode_goal_runtime_genesis_id_v1 {
    mooncode_goal_runtime_fail("genesis id must be exact fixed id")
  }
  if !mooncode_goal_runtime_valid_digest(value.semantic_digest) {
    mooncode_goal_runtime_fail(
      "genesis semantic_digest must be lowercase 64-hex",
    )
  }
  let normalized = new_mooncode_goal_runtime_genesis(
    value.session_id,
    value.goal_id,
    value.objective,
    value.criteria,
    value.recorded_at,
  )
  if value.semantic_digest != normalized.semantic_digest {
    mooncode_goal_runtime_fail("genesis semantic_digest mismatch")
  }
  genesis_envelope_json(normalized)
}

///|
fn decode_mooncode_goal_runtime_stored_event(
  text : String,
) -> MoonCodeGoalRuntimeStoredEvent raise MoonCodeGoalRuntimeCodecError {
  let json = @json.parse(text) catch {
    _ => mooncode_goal_runtime_fail("malformed event JSON")
  }
  let object = mooncode_goal_runtime_exact_object(
    json,
    [
      "id", "kind", "protocol", "contract", "session_id", "goal_id", "payload", "semantic_digest",
      "recorded_at",
    ],
    "event",
  )
  let id = mooncode_goal_runtime_checked_string(object, "id")
  if mooncode_goal_runtime_checked_string(object, "kind") !=
    mooncode_goal_runtime_event_kind_v1 {
    mooncode_goal_runtime_fail("invalid event kind")
  }
  if mooncode_goal_runtime_checked_string(object, "protocol") !=
    mooncode_goal_runtime_protocol_v1 {
    mooncode_goal_runtime_fail("invalid event protocol")
  }
  if mooncode_goal_runtime_checked_string(object, "contract") !=
    mooncode_goal_runtime_contract_v1 {
    mooncode_goal_runtime_fail("invalid event contract")
  }
  let session_id = mooncode_goal_runtime_checked_string(object, "session_id")
  let goal_id = mooncode_goal_runtime_checked_string(object, "goal_id")
  let supplied_digest = mooncode_goal_runtime_checked_string(
    object, "semantic_digest",
  )
  if !mooncode_goal_runtime_valid_digest(supplied_digest) {
    mooncode_goal_runtime_fail("event semantic_digest must be lowercase 64-hex")
  }
  let event = mooncode_goal_runtime_decode_event_payload(
    mooncode_goal_runtime_json_field(object, "payload"),
    id,
  )
  let recorded_at = mooncode_goal_runtime_checked_nonnegative_int64(
    object, "recorded_at",
  )
  let reconstructed = new_mooncode_goal_runtime_stored_event(
    session_id, goal_id, event, recorded_at,
  )
  if supplied_digest != reconstructed.semantic_digest {
    mooncode_goal_runtime_fail("event semantic_digest mismatch")
  }
  if text != encode_mooncode_goal_runtime_stored_event(reconstructed) {
    mooncode_goal_runtime_fail("event JSON must use canonical encoding")
  }
  reconstructed
}

///|
fn encode_mooncode_goal_runtime_stored_event(
  value : MoonCodeGoalRuntimeStoredEvent,
) -> String raise MoonCodeGoalRuntimeCodecError {
  if value.id != mooncode_goal_runtime_event_id(value.event) {
    mooncode_goal_runtime_fail("event outer id must equal embedded event id")
  }
  if !mooncode_goal_runtime_valid_digest(value.semantic_digest) {
    mooncode_goal_runtime_fail("event semantic_digest must be lowercase 64-hex")
  }
  let normalized = new_mooncode_goal_runtime_stored_event(
    value.session_id,
    value.goal_id,
    value.event,
    value.recorded_at,
  )
  if value.semantic_digest != normalized.semantic_digest {
    mooncode_goal_runtime_fail("event semantic_digest mismatch")
  }
  event_envelope_json(normalized)
}
