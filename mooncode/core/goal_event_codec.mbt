///|
let goal_event_codec_schema_version : Int = 1

///|
priv suberror GoalEventCodecError {
  GoalEventCodecError(String)
}

///|
fn goal_event_codec_fail(message : String) -> Unit raise GoalEventCodecError {
  raise GoalEventCodecError(message)
}

///|
fn goal_event_codec_exact_object(
  json : Json,
  fields : Array[String],
  level : String,
) -> Map[String, Json] raise GoalEventCodecError {
  match json {
    Object(object) => {
      if object.length() != fields.length() {
        goal_event_codec_fail("invalid " + level + " fields")
      }
      for field in fields {
        if object.get(field) is None {
          goal_event_codec_fail("invalid " + level + " fields")
        }
      }
      object
    }
    _ => {
      goal_event_codec_fail(level + " must be an object")
      Map([])
    }
  }
}

///|
fn goal_event_codec_string(
  object : Map[String, Json],
  field : String,
) -> String raise GoalEventCodecError {
  match object.get(field) {
    Some(String(value)) => value
    _ => {
      goal_event_codec_fail("invalid " + field)
      ""
    }
  }
}

///|
fn goal_event_codec_bool(
  object : Map[String, Json],
  field : String,
) -> Bool raise GoalEventCodecError {
  match object.get(field) {
    Some(True) => true
    Some(False) => false
    _ => {
      goal_event_codec_fail("invalid " + field)
      false
    }
  }
}

///|
fn goal_event_codec_strings(
  object : Map[String, Json],
  field : String,
) -> Array[String] raise GoalEventCodecError {
  match object.get(field) {
    Some(Array(values)) =>
      values.map(value => {
        match value {
          String(text) => text
          _ => {
            goal_event_codec_fail("invalid " + field)
            ""
          }
        }
      })
    _ => {
      goal_event_codec_fail("invalid " + field)
      []
    }
  }
}

///|
fn goal_event_codec_id(
  value : String,
  field : String,
) -> String raise GoalEventCodecError {
  if value.is_empty() || value.trim() != value {
    goal_event_codec_fail("invalid " + field)
  }
  value
}

///|
fn goal_event_codec_checked_int(
  object : Map[String, Json],
  field : String,
) -> Int raise GoalEventCodecError {
  match object.get(field) {
    Some(Number(value, ..)) => {
      if value != value ||
        value.trunc() != value ||
        value < -2147483648.0 ||
        value > 2147483647.0 {
        goal_event_codec_fail("invalid " + field)
      }
      value.to_int()
    }
    _ => {
      goal_event_codec_fail("invalid " + field)
      0
    }
  }
}

///|
fn goal_event_codec_nonnegative_int(
  object : Map[String, Json],
  field : String,
) -> Int raise GoalEventCodecError {
  let value = goal_event_codec_checked_int(object, field)
  if value < 0 {
    goal_event_codec_fail("invalid " + field)
  }
  value
}

///|
fn goal_event_codec_optional_nonnegative_int(
  object : Map[String, Json],
  field : String,
) -> Int? raise GoalEventCodecError {
  match object.get(field) {
    Some(Null) => None
    Some(_) => Some(goal_event_codec_nonnegative_int(object, field))
    None => {
      goal_event_codec_fail("invalid " + field)
      None
    }
  }
}

///|
pub fn goal_event_from_json(json : Json) -> GoalEvent raise {
  let envelope = goal_event_codec_exact_object(
    json,
    ["schema_version", "kind", "event_id", "recorded_at", "payload"],
    "envelope",
  )
  if goal_event_codec_checked_int(envelope, "schema_version") !=
    goal_event_codec_schema_version {
    goal_event_codec_fail("unsupported schema_version")
  }
  let kind = goal_event_codec_string(envelope, "kind")
  if kind != "mooncode.goal.complete-requested.v1" &&
    kind != "mooncode.goal.resumed.v1" &&
    kind != "mooncode.goal.continuation-accepted.v1" &&
    kind != "mooncode.goal.evaluated.v1" &&
    kind != "mooncode.goal.evaluation-started.v1" &&
    kind != "mooncode.goal.evaluation-failed.v1" &&
    kind != "mooncode.goal.evaluation-retry-due.v1" &&
    kind != "mooncode.goal.turn-finished.v1" &&
    kind != "mooncode.goal.requirement-updated.v1" &&
    kind != "mooncode.goal.awaiting-approval.v1" &&
    kind != "mooncode.goal.approval-settled.v1" &&
    kind != "mooncode.goal.budget-usage-recorded.v1" &&
    kind != "mooncode.goal.budget-exhausted.v1" &&
    kind != "mooncode.goal.budget-extended.v1" {
    goal_event_codec_fail("unsupported goal event kind")
  }
  let event_id = goal_event_codec_id(
    goal_event_codec_string(envelope, "event_id"),
    "event_id",
  )
  let recorded_at = goal_event_codec_checked_int(envelope, "recorded_at")
  if recorded_at < 0 {
    goal_event_codec_fail("invalid recorded_at")
  }
  let payload_json = match envelope.get("payload") {
    Some(value) => value
    None => {
      goal_event_codec_fail("invalid payload")
      Json::null()
    }
  }
  if kind == "mooncode.goal.resumed.v1" {
    ignore(goal_event_codec_exact_object(payload_json, [], "payload"))
    return Resume(event_id, recorded_at)
  } else if kind == "mooncode.goal.complete-requested.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["proof"],
      "payload",
    )
    let proof_json = match payload.get("proof") {
      Some(value) => value
      None => {
        goal_event_codec_fail("invalid proof")
        Json::null()
      }
    }
    let proof_object = goal_event_codec_exact_object(
      proof_json,
      ["projection"],
      "proof",
    )
    let projection_json = match proof_object.get("projection") {
      Some(value) => value
      None => {
        goal_event_codec_fail("invalid projection")
        Json::null()
      }
    }
    let projection = goal_event_codec_exact_object(
      projection_json,
      [
        "revision", "evaluation_basis_revision", "journal_digest", "workspace_digest",
        "evaluation_digest", "pending_approvals", "active_or_retryable_commands",
        "open_claims", "command_evidence_complete_and_passing", "mutations_have_later_passing_checks",
      ],
      "projection",
    )
    let validated_projection = ValidatedProjection::{
      revision: goal_event_codec_nonnegative_int(projection, "revision"),
      evaluation_basis_revision: goal_event_codec_nonnegative_int(
        projection, "evaluation_basis_revision",
      ),
      journal_digest: goal_event_codec_id(
        goal_event_codec_string(projection, "journal_digest"),
        "journal_digest",
      ),
      workspace_digest: goal_event_codec_id(
        goal_event_codec_string(projection, "workspace_digest"),
        "workspace_digest",
      ),
      evaluation_digest: goal_event_codec_id(
        goal_event_codec_string(projection, "evaluation_digest"),
        "evaluation_digest",
      ),
      pending_approvals: goal_event_codec_bool(projection, "pending_approvals"),
      active_or_retryable_commands: goal_event_codec_bool(
        projection, "active_or_retryable_commands",
      ),
      open_claims: goal_event_codec_bool(projection, "open_claims"),
      command_evidence_complete_and_passing: goal_event_codec_bool(
        projection, "command_evidence_complete_and_passing",
      ),
      mutations_have_later_passing_checks: goal_event_codec_bool(
        projection, "mutations_have_later_passing_checks",
      ),
    }
    let proof = CompletionProof::{ projection: validated_projection }
    return CompleteRequested(event_id, recorded_at, proof)
  } else if kind == "mooncode.goal.evaluated.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["evaluation_id", "evaluated_revision", "evidence_digest", "report"],
      "payload",
    )
    let evaluation_id = goal_event_codec_id(
      goal_event_codec_string(payload, "evaluation_id"),
      "evaluation_id",
    )
    let evaluated_revision = goal_event_codec_nonnegative_int(
      payload, "evaluated_revision",
    )
    let evidence_digest = goal_event_codec_id(
      goal_event_codec_string(payload, "evidence_digest"),
      "evidence_digest",
    )
    let report_json = match payload.get("report") {
      Some(value) => value
      None => {
        goal_event_codec_fail("invalid report")
        Json::null()
      }
    }
    let report_object = goal_event_codec_exact_object(
      report_json,
      [
        "evaluation_id", "evaluated_revision", "evidence_digest", "outcome", "requirement_deltas",
        "residual_risks",
      ],
      "report",
    )
    let report_evaluation_id = goal_event_codec_id(
      goal_event_codec_string(report_object, "evaluation_id"),
      "evaluation_id",
    )
    let report_evaluated_revision = goal_event_codec_nonnegative_int(
      report_object, "evaluated_revision",
    )
    let report_evidence_digest = goal_event_codec_id(
      goal_event_codec_string(report_object, "evidence_digest"),
      "evidence_digest",
    )
    let outcome = match goal_event_codec_string(report_object, "outcome") {
      "converged" => Converged
      "disagreed" => Disagreed
      "insufficient_evidence" => InsufficientEvidence
      _ => {
        goal_event_codec_fail("invalid outcome")
        Converged
      }
    }
    let report = ConvergenceReport::{
      evaluation_id: report_evaluation_id,
      evaluated_revision: report_evaluated_revision,
      evidence_digest: report_evidence_digest,
      outcome,
      requirement_deltas: goal_event_codec_strings(
        report_object, "requirement_deltas",
      ),
      residual_risks: goal_event_codec_strings(report_object, "residual_risks"),
    }
    return Evaluated(
      event_id, recorded_at, evaluation_id, evaluated_revision, evidence_digest,
      report,
    )
  }
  if kind == "mooncode.goal.requirement-updated.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["requirement_id", "state", "evidence_refs"],
      "payload",
    )
    let requirement_id = goal_event_codec_id(
      goal_event_codec_string(payload, "requirement_id"),
      "requirement_id",
    )
    let state = match goal_event_codec_string(payload, "state") {
      "unproven" => Unproven
      "proven" => Proven
      "contested" => Contradicted
      _ => {
        goal_event_codec_fail("invalid state")
        Unproven
      }
    }
    let evidence_refs = match payload.get("evidence_refs") {
      Some(Array(values)) =>
        values.map(fn(value) raise {
          match value {
            String(text) => text
            _ => {
              goal_event_codec_fail("invalid evidence_refs")
              ""
            }
          }
        })
      _ => {
        goal_event_codec_fail("invalid evidence_refs")
        []
      }
    }
    return RequirementUpdated(
      event_id, recorded_at, requirement_id, state, evidence_refs,
    )
  }
  if kind == "mooncode.goal.awaiting-approval.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["approval_refs"],
      "payload",
    )
    return AwaitingApproval(
      event_id,
      recorded_at,
      goal_event_codec_strings(payload, "approval_refs"),
    )
  }
  if kind == "mooncode.goal.approval-settled.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["approval_refs", "outcome"],
      "payload",
    )
    let outcome = match goal_event_codec_string(payload, "outcome") {
      "approved" => Approved
      "rejected" => Rejected
      _ => {
        goal_event_codec_fail("invalid outcome")
        Approved
      }
    }
    return ApprovalSettled(
      event_id,
      recorded_at,
      goal_event_codec_strings(payload, "approval_refs"),
      outcome,
    )
  }
  if kind == "mooncode.goal.budget-usage-recorded.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["tokens_used", "turns_used", "wall_time_used"],
      "payload",
    )
    return BudgetUsageRecorded(
      event_id,
      recorded_at,
      goal_event_codec_nonnegative_int(payload, "tokens_used"),
      goal_event_codec_nonnegative_int(payload, "turns_used"),
      goal_event_codec_nonnegative_int(payload, "wall_time_used"),
    )
  }
  if kind == "mooncode.goal.budget-exhausted.v1" {
    ignore(goal_event_codec_exact_object(payload_json, [], "payload"))
    return BudgetExhausted(event_id, recorded_at)
  }
  if kind == "mooncode.goal.budget-extended.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["token_limit", "turn_limit", "wall_time_limit"],
      "payload",
    )
    return BudgetExtended(
      event_id,
      recorded_at,
      goal_event_codec_optional_nonnegative_int(payload, "token_limit"),
      goal_event_codec_optional_nonnegative_int(payload, "turn_limit"),
      goal_event_codec_optional_nonnegative_int(payload, "wall_time_limit"),
    )
  }
  if kind == "mooncode.goal.evaluation-started.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["evaluation_id", "evidence_digest"],
      "payload",
    )
    return EvaluationStarted(
      event_id,
      recorded_at,
      goal_event_codec_id(
        goal_event_codec_string(payload, "evaluation_id"),
        "evaluation_id",
      ),
      goal_event_codec_id(
        goal_event_codec_string(payload, "evidence_digest"),
        "evidence_digest",
      ),
    )
  }
  if kind == "mooncode.goal.evaluation-failed.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      [
        "evaluation_id", "run_id", "basis_revision", "evidence_digest", "attempt",
        "category", "next_retry_at",
      ],
      "payload",
    )
    return EvaluationFailed(
      event_id,
      recorded_at,
      goal_event_codec_id(
        goal_event_codec_string(payload, "evaluation_id"),
        "evaluation_id",
      ),
      goal_event_codec_nonnegative_int(payload, "run_id"),
      goal_event_codec_nonnegative_int(payload, "basis_revision"),
      goal_event_codec_id(
        goal_event_codec_string(payload, "evidence_digest"),
        "evidence_digest",
      ),
      goal_event_codec_nonnegative_int(payload, "attempt"),
      goal_event_codec_id(
        goal_event_codec_string(payload, "category"),
        "category",
      ),
      goal_event_codec_nonnegative_int(payload, "next_retry_at"),
    )
  }
  if kind == "mooncode.goal.evaluation-retry-due.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["evaluation_id", "run_id", "attempt"],
      "payload",
    )
    return EvaluationRetryDue(
      event_id,
      recorded_at,
      goal_event_codec_id(
        goal_event_codec_string(payload, "evaluation_id"),
        "evaluation_id",
      ),
      goal_event_codec_nonnegative_int(payload, "run_id"),
      goal_event_codec_nonnegative_int(payload, "attempt"),
    )
  }
  if kind == "mooncode.goal.turn-finished.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["run_id", "turn", "blocker", "made_progress"],
      "payload",
    )
    let run_id = goal_event_codec_checked_int(payload, "run_id")
    let turn = goal_event_codec_checked_int(payload, "turn")
    if run_id < 0 {
      goal_event_codec_fail("invalid run_id")
    }
    if turn < 0 {
      goal_event_codec_fail("invalid turn")
    }
    let blocker = match payload.get("blocker") {
      Some(Null) => None
      Some(value) => {
        let object = goal_event_codec_exact_object(
          value,
          ["kind", "authority", "resource", "required_change"],
          "blocker",
        )
        Some({
          kind: goal_event_codec_string(object, "kind"),
          authority: goal_event_codec_string(object, "authority"),
          resource: goal_event_codec_string(object, "resource"),
          required_change: goal_event_codec_string(object, "required_change"),
        })
      }
      None => {
        goal_event_codec_fail("invalid blocker")
        None
      }
    }
    let made_progress = match payload.get("made_progress") {
      Some(True) => true
      Some(False) => false
      _ => {
        goal_event_codec_fail("invalid made_progress")
        false
      }
    }
    TurnFinished(event_id, recorded_at, run_id, turn, blocker, made_progress)
  } else if kind == "mooncode.goal.continuation-accepted.v1" {
    let payload = goal_event_codec_exact_object(
      payload_json,
      ["run_id", "continuation_count"],
      "payload",
    )
    let run_id = goal_event_codec_checked_int(payload, "run_id")
    let continuation_count = goal_event_codec_checked_int(
      payload, "continuation_count",
    )
    if run_id < 0 {
      goal_event_codec_fail("invalid run_id")
    }
    if continuation_count < 0 {
      goal_event_codec_fail("invalid continuation_count")
    }
    ContinuationAccepted(event_id, recorded_at, run_id, continuation_count)
  } else {
    goal_event_codec_fail("unsupported goal event kind")
    ContinuationAccepted("", 0, 0, 0)
  }
}

///|
pub fn decode_goal_event_v1(json : Json) -> Result[GoalEvent, String] {
  Ok(goal_event_from_json(json)) catch {
    GoalEventCodecError(message) => Err(message)
    _ => Err("invalid goal event")
  }
}

///|
pub fn goal_event_created_kind() -> String {
  "mooncode.goal.created.v1"
}

///|
pub fn goal_event_kind(event : GoalEvent) -> String {
  match event {
    ContinuationAccepted(_, _, _, _) => "mooncode.goal.continuation-accepted.v1"
    TurnFinished(_, _, _, _, _, _) => "mooncode.goal.turn-finished.v1"
    RequirementUpdated(_, _, _, _, _) => "mooncode.goal.requirement-updated.v1"
    AwaitingApproval(_, _, _) => "mooncode.goal.awaiting-approval.v1"
    ApprovalSettled(_, _, _, _) => "mooncode.goal.approval-settled.v1"
    BudgetUsageRecorded(_, _, _, _, _) =>
      "mooncode.goal.budget-usage-recorded.v1"
    BudgetExhausted(_, _) => "mooncode.goal.budget-exhausted.v1"
    BudgetExtended(_, _, _, _, _) => "mooncode.goal.budget-extended.v1"
    EvaluationStarted(_, _, _, _) => "mooncode.goal.evaluation-started.v1"
    Evaluated(_, _, _, _, _, _) => "mooncode.goal.evaluated.v1"
    EvaluationFailed(_, _, _, _, _, _, _, _, _) =>
      "mooncode.goal.evaluation-failed.v1"
    EvaluationRetryDue(_, _, _, _, _) => "mooncode.goal.evaluation-retry-due.v1"
    CompleteRequested(_, _, _) => "mooncode.goal.complete-requested.v1"
    Resume(_, _) => "mooncode.goal.resumed.v1"
  }
}

///|
pub fn goal_event_id(event : GoalEvent) -> String {
  match event {
    ContinuationAccepted(id, _, _, _) => id
    TurnFinished(id, _, _, _, _, _) => id
    RequirementUpdated(id, _, _, _, _) => id
    AwaitingApproval(id, _, _) => id
    ApprovalSettled(id, _, _, _) => id
    BudgetUsageRecorded(id, _, _, _, _) => id
    BudgetExhausted(id, _) => id
    BudgetExtended(id, _, _, _, _) => id
    EvaluationStarted(id, _, _, _) => id
    Evaluated(id, _, _, _, _, _) => id
    EvaluationFailed(id, _, _, _, _, _, _, _, _) => id
    EvaluationRetryDue(id, _, _, _, _) => id
    CompleteRequested(id, _, _) => id
    Resume(id, _) => id
  }
}

///|
pub fn goal_event_recorded_at(event : GoalEvent) -> Int {
  match event {
    ContinuationAccepted(_, now, _, _) => now
    TurnFinished(_, now, _, _, _, _) => now
    RequirementUpdated(_, now, _, _, _) => now
    AwaitingApproval(_, now, _) => now
    ApprovalSettled(_, now, _, _) => now
    BudgetUsageRecorded(_, now, _, _, _) => now
    BudgetExhausted(_, now) => now
    BudgetExtended(_, now, _, _, _) => now
    EvaluationStarted(_, now, _, _) => now
    Evaluated(_, now, _, _, _, _) => now
    EvaluationFailed(_, now, _, _, _, _, _, _, _) => now
    EvaluationRetryDue(_, now, _, _, _) => now
    CompleteRequested(_, now, _) => now
    Resume(_, now) => now
  }
}

///|
fn strings_json(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
fn int_option_json(value : Int?) -> Json {
  match value {
    Some(value) => Json::number(value.to_double())
    None => Json::null()
  }
}

///|
fn blocker_json(value : BlockerIdentity) -> Json {
  {
    "kind": value.kind,
    "authority": value.authority,
    "resource": value.resource,
    "required_change": value.required_change,
  }
}

///|
fn blocker_option_json(value : BlockerIdentity?) -> Json {
  match value {
    Some(value) => blocker_json(value)
    None => Json::null()
  }
}

///|
fn requirement_state_json(value : RequirementState) -> Json {
  Json::string(
    match value {
      Unproven => "unproven"
      Proven => "proven"
      Contradicted => "contested"
    },
  )
}

///|
fn approval_outcome_json(value : ApprovalOutcome) -> Json {
  Json::string(
    match value {
      Approved => "approved"
      Rejected => "rejected"
    },
  )
}

///|
fn convergence_json(value : Convergence) -> Json {
  Json::string(
    match value {
      Converged => "converged"
      Disagreed => "disagreed"
      InsufficientEvidence => "insufficient_evidence"
    },
  )
}

///|
fn convergence_report_json(value : ConvergenceReport) -> Json {
  {
    "evaluation_id": value.evaluation_id,
    "evaluated_revision": value.evaluated_revision,
    "evidence_digest": value.evidence_digest,
    "outcome": convergence_json(value.outcome),
    "requirement_deltas": strings_json(value.requirement_deltas),
    "residual_risks": strings_json(value.residual_risks),
  }
}

///|
fn validated_projection_json(value : ValidatedProjection) -> Json {
  {
    "revision": value.revision,
    "evaluation_basis_revision": value.evaluation_basis_revision,
    "journal_digest": value.journal_digest,
    "workspace_digest": value.workspace_digest,
    "evaluation_digest": value.evaluation_digest,
    "pending_approvals": value.pending_approvals,
    "active_or_retryable_commands": value.active_or_retryable_commands,
    "open_claims": value.open_claims,
    "command_evidence_complete_and_passing": value.command_evidence_complete_and_passing,
    "mutations_have_later_passing_checks": value.mutations_have_later_passing_checks,
  }
}

///|
fn completion_proof_json(value : CompletionProof) -> Json {
  { "projection": validated_projection_json(value.projection) }
}

///|
/// Deterministically encodes the complete versioned GoalEvent envelope.
pub fn goal_event_to_json(event : GoalEvent) -> Json {
  let payload : Json = match event {
    ContinuationAccepted(_, _, run_id, continuation_count) =>
      { "run_id": run_id, "continuation_count": continuation_count }
    TurnFinished(_, _, run_id, turn, blocker, made_progress) =>
      {
        "run_id": run_id,
        "turn": turn,
        "blocker": blocker_option_json(blocker),
        "made_progress": made_progress,
      }
    RequirementUpdated(_, _, requirement_id, state, evidence_refs) =>
      {
        "requirement_id": requirement_id,
        "state": requirement_state_json(state),
        "evidence_refs": strings_json(evidence_refs),
      }
    AwaitingApproval(_, _, approval_refs) =>
      { "approval_refs": strings_json(approval_refs) }
    ApprovalSettled(_, _, approval_refs, outcome) =>
      {
        "approval_refs": strings_json(approval_refs),
        "outcome": approval_outcome_json(outcome),
      }
    BudgetUsageRecorded(_, _, tokens_used, turns_used, wall_time_used) =>
      {
        "tokens_used": tokens_used,
        "turns_used": turns_used,
        "wall_time_used": wall_time_used,
      }
    BudgetExhausted(_, _) => {}
    BudgetExtended(_, _, token_limit, turn_limit, wall_time_limit) =>
      {
        "token_limit": int_option_json(token_limit),
        "turn_limit": int_option_json(turn_limit),
        "wall_time_limit": int_option_json(wall_time_limit),
      }
    EvaluationStarted(_, _, evaluation_id, evidence_digest) =>
      { "evaluation_id": evaluation_id, "evidence_digest": evidence_digest }
    Evaluated(_, _, evaluation_id, evaluated_revision, evidence_digest, report) =>
      {
        "evaluation_id": evaluation_id,
        "evaluated_revision": evaluated_revision,
        "evidence_digest": evidence_digest,
        "report": convergence_report_json(report),
      }
    EvaluationFailed(
      _,
      _,
      evaluation_id,
      run_id,
      basis_revision,
      evidence_digest,
      attempt,
      category,
      next_retry_at
    ) =>
      {
        "evaluation_id": evaluation_id,
        "run_id": run_id,
        "basis_revision": basis_revision,
        "evidence_digest": evidence_digest,
        "attempt": attempt,
        "category": category,
        "next_retry_at": next_retry_at,
      }
    EvaluationRetryDue(_, _, evaluation_id, run_id, attempt) =>
      { "evaluation_id": evaluation_id, "run_id": run_id, "attempt": attempt }
    CompleteRequested(_, _, proof) => { "proof": completion_proof_json(proof) }
    Resume(_, _) => {}
  }
  {
    "schema_version": goal_event_codec_schema_version,
    "kind": goal_event_kind(event),
    "event_id": goal_event_id(event),
    "recorded_at": goal_event_recorded_at(event),
    "payload": payload,
  }
}
