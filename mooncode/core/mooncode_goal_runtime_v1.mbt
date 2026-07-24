///|
/// Pure additive runtime contract for `mooncode-goal-runtime.v1`.
pub let mooncode_goal_runtime_contract : String = "mooncode-goal-runtime.v1"

///|
/// Per-operation policy is deliberately separate from aggregate goal progress.
/// Limits here bound one potentially unsafe operation; they never settle a goal.
pub(all) struct GoalOperationPolicy {
  max_output_bytes : Int
  timeout_milliseconds : Int
} derive(Eq, Debug)

///|
pub(all) struct GoalRuntimeOperation {
  operation_id : String
  kind : String
  input : String
  policy : GoalOperationPolicy
} derive(Eq, Debug)

///|
pub(all) enum GoalRuntimePhase {
  Queued
  Running
  WaitingApproval
  RetryBackoff
  PausedNoProgress
  PausedExternal
} derive(Eq, Debug)

///|
pub(all) struct GoalCriterionEvidence {
  criterion : String
  evidence_refs : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct GoalBlockedReason {
  code : String
  detail : String
} derive(Eq, Debug)

///|
pub(all) enum GoalPlannerDecision {
  Continue(Array[GoalRuntimeOperation], String, String)
  Achieved(String, Array[GoalCriterionEvidence])
  Blocked(GoalBlockedReason, Array[String], String?)
} derive(Eq, Debug)

///|
/// Terminal outcomes are intentionally closed and exact.
pub enum GoalRuntimeOutcome {
  AchievedOutcome(String, Array[GoalCriterionEvidence])
  BlockedOutcome(GoalBlockedReason, Array[String], String?)
  CancelledOutcome(String)
} derive(Eq, Debug)

///|
pub struct GoalRuntimeState {
  contract : String
  phase : GoalRuntimePhase
  priv outcome : GoalRuntimeOutcome?
  priv handled_ids : Array[String]
  priv operation_ids : Array[String]
  priv checkpoint_ids : Array[String]
} derive(Eq, Debug)

///|
pub(all) enum GoalRuntimeEvent {
  PlannerDecision(String, GoalPlannerDecision)
  OperationAccepted(String, String)
  CheckpointAccepted(String, String)
  PhaseChanged(String, GoalRuntimePhase)
  Cancelled(String, String)
} derive(Eq, Debug)

///|
pub fn new_goal_runtime_state() -> GoalRuntimeState {
  {
    contract: mooncode_goal_runtime_contract,
    phase: Queued,
    outcome: None,
    handled_ids: [],
    operation_ids: [],
    checkpoint_ids: [],
  }
}

///|
fn string_array_contains(values : Array[String], value : String) -> Bool {
  values.any(fn(item) { item == value })
}

///|
fn copy_goal_evidence(
  evidence : Array[GoalCriterionEvidence],
) -> Array[GoalCriterionEvidence] {
  evidence.map(fn(item) {
    { criterion: item.criterion, evidence_refs: item.evidence_refs.copy() }
  })
}

///|
pub fn goal_runtime_contract(state : GoalRuntimeState) -> String {
  state.contract
}

///|
pub fn goal_runtime_phase(state : GoalRuntimeState) -> GoalRuntimePhase {
  state.phase
}

///|
pub fn goal_runtime_is_terminal(state : GoalRuntimeState) -> Bool {
  state.outcome is Some(_)
}

///|
pub fn goal_runtime_handled_count(state : GoalRuntimeState) -> Int {
  state.handled_ids.length()
}

///|
pub fn goal_runtime_operation_count(state : GoalRuntimeState) -> Int {
  state.operation_ids.length()
}

///|
pub fn goal_runtime_checkpoint_count(state : GoalRuntimeState) -> Int {
  state.checkpoint_ids.length()
}

///|
pub fn goal_runtime_outcome(state : GoalRuntimeState) -> GoalRuntimeOutcome? {
  match state.outcome {
    Some(AchievedOutcome(summary, evidence)) =>
      Some(AchievedOutcome(summary, copy_goal_evidence(evidence)))
    Some(BlockedOutcome(reason, alternatives, unblock)) =>
      Some(BlockedOutcome(reason, alternatives.copy(), unblock))
    Some(CancelledOutcome(reason)) => Some(CancelledOutcome(reason))
    None => None
  }
}

///|
fn is_canonical_nonempty(value : String) -> Bool {
  value != "" && value.trim() == value
}

///|
fn canonical_unique_strings(values : Array[String]) -> Bool {
  let seen : Array[String] = []
  for value in values {
    if !is_canonical_nonempty(value) || string_array_contains(seen, value) {
      return false
    }
    seen.push(value)
  }
  true
}

///|
/// Validate a planner decision before it can affect runtime state.
pub fn validate_goal_planner_decision(decision : GoalPlannerDecision) -> Bool {
  match decision {
    Continue(operations, expected_progress, rationale) => {
      if operations.is_empty() ||
        expected_progress.trim().is_empty() ||
        rationale.trim().is_empty() {
        return false
      }
      let ids : Array[String] = []
      for operation in operations {
        if operation.operation_id.trim().is_empty() ||
          operation.operation_id.trim().to_owned() != operation.operation_id ||
          operation.kind.trim().is_empty() ||
          operation.kind.trim() != operation.kind ||
          operation.policy.max_output_bytes <= 0 ||
          operation.policy.timeout_milliseconds <= 0 ||
          string_array_contains(ids, operation.operation_id) {
          return false
        }
        ids.push(operation.operation_id)
      }
      true
    }
    Achieved(summary, evidence) => {
      if !is_canonical_nonempty(summary) || evidence.is_empty() {
        return false
      }
      let criteria : Array[String] = []
      for item in evidence {
        if !is_canonical_nonempty(item.criterion) ||
          item.evidence_refs.is_empty() ||
          string_array_contains(criteria, item.criterion) ||
          !canonical_unique_strings(item.evidence_refs) {
          return false
        }
        criteria.push(item.criterion)
      }
      true
    }
    Blocked(reason, attempted_alternatives, required_event) => {
      if !is_canonical_nonempty(reason.code) ||
        !is_canonical_nonempty(reason.detail) ||
        attempted_alternatives.is_empty() ||
        !canonical_unique_strings(attempted_alternatives) {
        return false
      }
      match required_event {
        Some(event) => is_canonical_nonempty(event)
        None => true
      }
    }
  }
}

///|
/// Canonical public status JSON; aggregate budgets are absent by construction.
pub fn goal_runtime_status_json(state : GoalRuntimeState) -> Json {
  let outcome_name = match state.outcome {
    None => "none"
    Some(AchievedOutcome(_, _)) => "achieved"
    Some(BlockedOutcome(_, _, _)) => "blocked"
    Some(CancelledOutcome(_)) => "cancelled"
  }
  {
    "contract": state.contract,
    "phase": match state.phase {
      Queued => "queued"
      Running => "running"
      WaitingApproval => "waiting_approval"
      RetryBackoff => "retry_backoff"
      PausedNoProgress => "paused_no_progress"
      PausedExternal => "paused_external"
    },
    "terminal": state.outcome is Some(_),
    "outcome": outcome_name,
    "handled_count": state.handled_ids.length(),
    "operation_count": state.operation_ids.length(),
    "checkpoint_count": state.checkpoint_ids.length(),
  }
}

///|
/// Pure, replay-safe reducer. Counters, provider responses, and timeouts are not
/// events in this contract and therefore cannot imply settlement.
pub fn reduce_goal_runtime(
  state : GoalRuntimeState,
  event : GoalRuntimeEvent,
) -> GoalRuntimeState {
  let event_id = match event {
    PlannerDecision(id, _)
    | OperationAccepted(id, _)
    | CheckpointAccepted(id, _)
    | PhaseChanged(id, _)
    | Cancelled(id, _) => id
  }
  if event_id.trim().is_empty() ||
    event_id.trim().to_owned() != event_id ||
    string_array_contains(state.handled_ids, event_id) ||
    state.outcome is Some(_) {
    return state
  }
  if event is PlannerDecision(_, decision) &&
    !validate_goal_planner_decision(decision) {
    return state
  }
  let handled_ids = state.handled_ids.copy()
  handled_ids.push(event_id)
  let next = { ..state, handled_ids, }
  match event {
    PlannerDecision(_, Continue(operations, _, _)) => {
      let ids = next.operation_ids.copy()
      for operation in operations {
        if !string_array_contains(ids, operation.operation_id) {
          ids.push(operation.operation_id)
        }
      }
      { ..next, phase: Running, operation_ids: ids }
    }
    PlannerDecision(_, Achieved(summary, evidence)) =>
      {
        ..next,
        outcome: Some(AchievedOutcome(summary, copy_goal_evidence(evidence))),
      }
    PlannerDecision(_, Blocked(reason, alternatives, required_event)) =>
      {
        ..next,
        outcome: Some(
          BlockedOutcome(reason, alternatives.copy(), required_event),
        ),
      }
    OperationAccepted(_, operation_id) =>
      if operation_id.trim().is_empty() ||
        operation_id.trim().to_owned() != operation_id {
        state
      } else if string_array_contains(next.operation_ids, operation_id) {
        next
      } else {
        {
          ..next,
          operation_ids: {
            let ids = next.operation_ids.copy()
            ids.push(operation_id)
            ids
          },
        }
      }
    CheckpointAccepted(_, checkpoint_id) =>
      if checkpoint_id.trim().is_empty() ||
        checkpoint_id.trim().to_owned() != checkpoint_id {
        state
      } else if string_array_contains(next.checkpoint_ids, checkpoint_id) {
        next
      } else {
        {
          ..next,
          checkpoint_ids: {
            let ids = next.checkpoint_ids.copy()
            ids.push(checkpoint_id)
            ids
          },
        }
      }
    PhaseChanged(_, phase) => { ..next, phase, }
    Cancelled(_, reason) =>
      if reason.trim().is_empty() {
        state
      } else {
        { ..next, outcome: Some(CancelledOutcome(reason)) }
      }
  }
}

///|
/// Diagnostic compatibility denylist only; strict exact-allowlist enforcement
/// belongs to the adapter.
pub fn goal_runtime_rejects_aggregate_field(field : String) -> Bool {
  [
    "max_tokens", "token_budget", "max_turns", "turn_budget", "deadline", "deadline_ms",
    "wall_time_limit", "max_loc", "loc_budget", "token_limit", "turn_limit", "max_steps",
    "step_limit", "planner_max_steps", "max_continuations", "max_iterations", "iteration_limit",
    "time_budget", "max_time", "expires_at", "max_operations", "operation_limit",
    "loc_limit",
  ].any(fn(item) { item == field })
}
