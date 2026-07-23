///|
/// Durable, pure goal-mode contracts. The daemon must build validated projections.
pub(all) enum GoalStatus {
  Active
  Complete
  Blocked
} derive(Eq, Debug)

///|
pub(all) enum GoalRunState {
  Runnable
  AwaitingApproval
  AwaitingInput
  AwaitingBudget
  Evaluating
  EvaluationBackoff
} derive(Eq, Debug)

///|
pub(all) enum RequirementState {
  Unproven
  Proven
  Contradicted
} derive(Eq, Debug)

///|
pub(all) enum Convergence {
  Converged
  Disagreed
  InsufficientEvidence
} derive(Eq, Debug)

///|
pub(all) enum ApprovalOutcome {
  Approved
  Rejected
} derive(Eq, Debug)

///|
pub(all) struct GoalBudget {
  token_limit : Int?
  turn_limit : Int?
  wall_time_limit : Int?
  tokens_used : Int
  turns_used : Int
  wall_time_used : Int
} derive(Eq, Debug)

///|
pub(all) struct GoalRequirement {
  id : String
  criterion : String
  state : RequirementState
  evidence_refs : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct BlockerIdentity {
  kind : String
  authority : String
  resource : String
  required_change : String
} derive(Eq, Debug)

///|
pub(all) struct GoalBlocker {
  identity : BlockerIdentity
  count : Int
  last_consecutive_turn : Int
  run_id : Int
} derive(Eq, Debug)

///|
pub(all) struct GoalConvergence {
  report : ConvergenceReport
  accepted_revision : Int
} derive(Eq, Debug)

///|
pub(all) struct ConvergenceReport {
  evaluation_id : String
  evaluated_revision : Int
  evidence_digest : String
  outcome : Convergence
  requirement_deltas : Array[String]
  residual_risks : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct EvaluationRequest {
  id : String
  revision : Int
  evidence_digest : String
} derive(Eq, Debug)

///|
/// ValidatedProjection is an explicit daemon-supplied snapshot. Core does not inspect journals.
pub(all) struct ValidatedProjection {
  revision : Int
  evaluation_basis_revision : Int
  journal_digest : String
  workspace_digest : String
  evaluation_digest : String
  pending_approvals : Bool
  active_or_retryable_commands : Bool
  open_claims : Bool
  command_evidence_complete_and_passing : Bool
  mutations_have_later_passing_checks : Bool
} derive(Eq, Debug)

///|
pub(all) struct CompletionProof {
  projection : ValidatedProjection
} derive(Eq, Debug)

///|
pub(all) struct Goal {
  id : String
  session_id : String
  objective : String
  status : GoalStatus
  run_state : GoalRunState
  run_id : Int
  created_at : Int
  updated_at : Int
  revision : Int
  current_goal_turn : Int
  continuation_count : Int
  budget : GoalBudget
  requirements : Array[GoalRequirement]
  blocker : GoalBlocker?
  convergence : GoalConvergence?
  active_evaluation : EvaluationRequest?
  approval_refs : Array[String]
  seen_ids : Array[String]
} derive(Eq, Debug)

///|
fn goal_status_name(status : GoalStatus) -> String {
  match status {
    Active => "active"
    Complete => "complete"
    Blocked => "blocked"
  }
}

///|
fn goal_run_state_name(state : GoalRunState) -> String {
  match state {
    Runnable => "runnable"
    AwaitingApproval => "awaiting_approval"
    AwaitingInput => "awaiting_input"
    AwaitingBudget => "awaiting_budget"
    Evaluating => "evaluating"
    EvaluationBackoff => "evaluation_backoff"
  }
}

///|
fn requirement_state_name(state : RequirementState) -> String {
  match state {
    Unproven => "unproven"
    Proven => "proven"
    Contradicted => "contested"
  }
}

///|
fn convergence_name(value : Convergence) -> String {
  match value {
    Converged => "converged"
    Disagreed => "disagreed"
    InsufficientEvidence => "insufficient_evidence"
  }
}

///|
fn remaining(limit : Int?, used : Int) -> Json {
  match limit {
    Some(value) => (value - used).max(0).to_json()
    None => Json::null()
  }
}

///|
fn budget_json(b : GoalBudget) -> Json {
  {
    "token_limit": b.token_limit,
    "turn_limit": b.turn_limit,
    "wall_time_limit": b.wall_time_limit,
    "tokens_used": b.tokens_used,
    "turns_used": b.turns_used,
    "wall_time_used": b.wall_time_used,
    "tokens_remaining": remaining(b.token_limit, b.tokens_used),
    "turns_remaining": remaining(b.turn_limit, b.turns_used),
    "wall_time_remaining": remaining(b.wall_time_limit, b.wall_time_used),
  }
}

///|
/// Deliberately excludes objective, approval/evidence refs, seen ids, and reasoning.
pub fn goal_status_json(goal : Goal) -> Json {
  let mut proven = 0
  let mut unproven = 0
  let mut contested = 0
  for requirement in goal.requirements {
    match requirement.state {
      Proven => proven += 1
      Unproven => unproven += 1
      Contradicted => contested += 1
    }
  }
  let convergence : Json = match goal.convergence {
    Some(value) => convergence_name(value.report.outcome).to_json()
    None => Json::null()
  }
  {
    "schema_version": 2,
    "goal_id": goal.id,
    "session_id": goal.session_id,
    "status": goal_status_name(goal.status),
    "run_state": goal_run_state_name(goal.run_state),
    "run_id": goal.run_id,
    "revision": goal.revision,
    "current_goal_turn": goal.current_goal_turn,
    "continuation_count": goal.continuation_count,
    "budget": budget_json(goal.budget),
    "requirements": {
      "total": goal.requirements.length(),
      "proven": proven,
      "unproven": unproven,
      "contested": contested,
    },
    "convergence": convergence,
  }
}

///|
/// Evaluation may contain objective/evidence refs, but never approval refs or seen ids.
pub fn goal_evaluation_bundle_json(goal : Goal) -> Json {
  let requirements : Array[Json] = goal.requirements.map(fn(requirement) {
    {
      "id": requirement.id,
      "criterion": requirement.criterion,
      "state": requirement_state_name(requirement.state),
      "evidence_refs": requirement.evidence_refs,
    }
  })
  let blocker : Json = match goal.blocker {
    Some(value) =>
      {
        "kind": value.identity.kind,
        "authority": value.identity.authority,
        "resource": value.identity.resource,
        "required_change": value.identity.required_change,
        "count": value.count,
        "last_consecutive_turn": value.last_consecutive_turn,
        "run_id": value.run_id,
      }
    None => Json::null()
  }
  let active_evaluation : Json = match goal.active_evaluation {
    Some(value) =>
      {
        "id": value.id,
        "revision": value.revision,
        "evidence_digest": value.evidence_digest,
      }
    None => Json::null()
  }
  let convergence : Json = match goal.convergence {
    Some(convergence) => {
      let value = convergence.report
      {
        "evaluation_id": value.evaluation_id,
        "evaluated_revision": value.evaluated_revision,
        "evidence_digest": value.evidence_digest,
        "outcome": convergence_name(value.outcome),
        "requirement_deltas": value.requirement_deltas,
        "residual_risks": value.residual_risks,
        "accepted_revision": convergence.accepted_revision,
      }
    }
    None => Json::null()
  }
  {
    "schema_version": 2,
    "goal_id": goal.id,
    "objective": goal.objective,
    "run_id": goal.run_id,
    "revision": goal.revision,
    "run_state": goal_run_state_name(goal.run_state),
    "budget": budget_json(goal.budget),
    "blocker": blocker,
    "requirements": requirements,
    "active_evaluation": active_evaluation,
    "convergence": convergence,
  }
}
