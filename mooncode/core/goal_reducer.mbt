///|
pub(all) enum GoalEvent {
  ContinuationAccepted(String, Int, Int, Int)
  TurnFinished(String, Int, Int, Int, BlockerIdentity?, Bool)
  RequirementUpdated(String, Int, String, RequirementState, Array[String])
  AwaitingApproval(String, Int, Array[String])
  ApprovalSettled(String, Int, Array[String], ApprovalOutcome)
  BudgetUsageRecorded(String, Int, Int, Int, Int)
  BudgetExhausted(String, Int)
  BudgetExtended(String, Int, Int?, Int?, Int?)
  EvaluationStarted(String, Int, String, String)
  Evaluated(String, Int, String, Int, String, ConvergenceReport)
  EvaluationFailed(String, Int, Int, String, Int)
  CompleteRequested(String, Int, CompletionProof)
  Resume(String, Int)
} derive(Eq, Debug)

///|
fn valid_limit(limit : Int?) -> Bool {
  match limit {
    Some(value) => value >= 0
    None => true
  }
}

///|
fn nonempty(value : String) -> Bool {
  !value.trim().is_empty()
}

///|
fn limit_covers_usage(limit : Int?, usage : Int) -> Bool {
  match limit {
    Some(value) => value >= usage
    None => true
  }
}

///|
fn valid_budget(budget : GoalBudget) -> Bool {
  budget.tokens_used >= 0 &&
  budget.turns_used >= 0 &&
  budget.wall_time_used >= 0 &&
  valid_limit(budget.token_limit) &&
  valid_limit(budget.turn_limit) &&
  valid_limit(budget.wall_time_limit) &&
  limit_covers_usage(budget.token_limit, budget.tokens_used) &&
  limit_covers_usage(budget.turn_limit, budget.turns_used) &&
  limit_covers_usage(budget.wall_time_limit, budget.wall_time_used)
}

///|
/// Raising constructor prevents contradictory initial state and copies caller arrays.
pub fn new_goal(
  id : String,
  session_id : String,
  objective : String,
  now : Int,
  budget : GoalBudget,
  requirements : Array[GoalRequirement],
) -> Goal raise {
  let clean_id = id.trim().to_owned()
  let clean_session_id = session_id.trim().to_owned()
  let clean_objective = objective.trim().to_owned()
  if clean_id.is_empty() ||
    clean_session_id.is_empty() ||
    clean_objective.is_empty() ||
    !valid_budget(budget) ||
    requirements.is_empty() {
    raise Failure::Failure("invalid goal")
  }
  let copied : Array[GoalRequirement] = []
  let ids : Array[String] = []
  for requirement in requirements {
    let requirement_id = requirement.id.trim().to_owned()
    let criterion = requirement.criterion.trim().to_owned()
    if requirement_id.is_empty() ||
      criterion.is_empty() ||
      ids.contains(requirement_id) {
      raise Failure::Failure("invalid requirement")
    }
    ids.push(requirement_id)
    copied.push({
      ..requirement,
      id: requirement_id,
      criterion,
      evidence_refs: requirement.evidence_refs.copy(),
    })
  }
  {
    id: clean_id,
    session_id: clean_session_id,
    objective: clean_objective,
    status: Active,
    run_state: if goal_budget_exhausted(budget) {
      AwaitingBudget
    } else {
      Runnable
    },
    run_id: 0,
    created_at: now,
    updated_at: now,
    revision: 0,
    current_goal_turn: 0,
    continuation_count: 0,
    budget,
    requirements: copied,
    blocker: None,
    convergence: None,
    active_evaluation: None,
    approval_refs: [],
    seen_ids: [],
  }
}

///|
pub fn goal_budget_exhausted(budget : GoalBudget) -> Bool {
  match budget.token_limit {
    Some(limit) if budget.tokens_used >= limit => true
    _ =>
      match budget.turn_limit {
        Some(limit) if budget.turns_used >= limit => true
        _ =>
          match budget.wall_time_limit {
            Some(limit) => budget.wall_time_used >= limit
            None => false
          }
      }
  }
}

///|
fn event_identity(event : GoalEvent) -> (String, Int) {
  match event {
    ContinuationAccepted(id, now, _, _) => (id, now)
    TurnFinished(id, now, _, _, _, _) => (id, now)
    RequirementUpdated(id, now, _, _, _) => (id, now)
    AwaitingApproval(id, now, _) => (id, now)
    ApprovalSettled(id, now, _, _) => (id, now)
    BudgetUsageRecorded(id, now, _, _, _) => (id, now)
    BudgetExhausted(id, now) => (id, now)
    BudgetExtended(id, now, _, _, _) => (id, now)
    EvaluationStarted(id, now, _, _) => (id, now)
    Evaluated(id, now, _, _, _, _) => (id, now)
    EvaluationFailed(id, now, _, _, _) => (id, now)
    CompleteRequested(id, now, _) => (id, now)
    Resume(id, now) => (id, now)
  }
}

///|
fn accepted(goal : Goal, id : String, now : Int) -> Goal {
  let seen = goal.seen_ids.copy()
  seen.push(id.trim().to_owned())
  { ..goal, seen_ids: seen, revision: goal.revision + 1, updated_at: now }
}

///|
fn runnable(goal : Goal) -> Bool {
  goal.status == Active && goal.run_state == Runnable
}

///|
fn canonical_refs(refs : Array[String]) -> Array[String]? {
  let result : Array[String] = []
  for raw_ref in refs {
    let value = raw_ref.trim().to_owned()
    if value.is_empty() || result.contains(value) {
      return None
    }
    result.push(value)
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}

///|
fn same_refs(left : Array[String], right : Array[String]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for item in left {
    if !right.contains(item) {
      return false
    }
  }
  true
}

///|
fn canonical_blocker(identity : BlockerIdentity) -> BlockerIdentity? {
  let kind = identity.kind.trim().to_owned()
  let authority = identity.authority.trim().to_owned()
  let resource = identity.resource.trim().to_owned()
  let required_change = identity.required_change.trim().to_owned()
  if kind.is_empty() ||
    authority.is_empty() ||
    resource.is_empty() ||
    required_change.is_empty() {
    None
  } else {
    Some({ kind, authority, resource, required_change })
  }
}

///|
fn apply_blocker(
  goal : Goal,
  identity : BlockerIdentity,
  meaningful_progress : Bool,
) -> Goal {
  let previous = if meaningful_progress { None } else { goal.blocker }
  match previous {
    Some(blocker) if blocker.identity == identity &&
      blocker.run_id == goal.run_id &&
      blocker.last_consecutive_turn + 1 == goal.current_goal_turn => {
      let next_count = blocker.count + 1
      {
        ..goal,
        blocker: Some({
          identity,
          count: next_count,
          last_consecutive_turn: goal.current_goal_turn,
          run_id: goal.run_id,
        }),
        status: if next_count == 3 {
          Blocked
        } else {
          goal.status
        },
        run_state: if next_count == 3 {
          AwaitingInput
        } else {
          goal.run_state
        },
      }
    }
    _ =>
      {
        ..goal,
        blocker: Some({
          identity,
          count: 1,
          last_consecutive_turn: goal.current_goal_turn,
          run_id: goal.run_id,
        }),
      }
  }
}

///|
/// Projection values are accepted only after daemon validation at the constructor boundary.
fn projection_ready(goal : Goal, proof : CompletionProof) -> Bool {
  let projection = proof.projection
  projection.revision == goal.revision &&
  nonempty(projection.journal_digest) &&
  nonempty(projection.workspace_digest) &&
  nonempty(projection.evaluation_digest) &&
  !projection.pending_approvals &&
  !projection.active_or_retryable_commands &&
  !projection.open_claims &&
  projection.command_evidence_complete_and_passing &&
  projection.mutations_have_later_passing_checks &&
  (match goal.convergence {
    Some(convergence) => {
      let report = convergence.report
      convergence.accepted_revision == goal.revision &&
      report.outcome == Converged &&
      report.evaluated_revision == projection.evaluation_basis_revision &&
      report.evidence_digest == projection.evaluation_digest
    }
    None => false
  }) &&
  goal.requirements.all(fn(requirement) {
    requirement.state == Proven && !requirement.evidence_refs.is_empty()
  })
}

///|
pub fn reduce_goal(goal : Goal, event : GoalEvent) -> Goal {
  let (raw_id, now) = event_identity(event)
  let id = raw_id.trim().to_owned()
  if id.is_empty() || goal.seen_ids.contains(id) || goal.status == Complete {
    goal
  } else if goal.status == Blocked {
    match event {
      CompleteRequested(_, _, _)
      | ContinuationAccepted(_, _, _, _)
      | TurnFinished(_, _, _, _, _, _)
      | RequirementUpdated(_, _, _, _, _)
      | AwaitingApproval(_, _, _)
      | ApprovalSettled(_, _, _, _)
      | BudgetUsageRecorded(_, _, _, _, _)
      | BudgetExhausted(_, _)
      | BudgetExtended(_, _, _, _, _)
      | EvaluationStarted(_, _, _, _)
      | Evaluated(_, _, _, _, _, _)
      | EvaluationFailed(_, _, _, _, _) => goal
      Resume(_, _) => {
        let next = accepted(goal, id, now)
        {
          ..next,
          status: Active,
          run_state: Runnable,
          run_id: goal.run_id + 1,
          blocker: None,
        }
      }
    }
  } else {
    match event {
      ContinuationAccepted(_, _, expected_run_id, expected_ordinal) =>
        if runnable(goal) &&
          expected_run_id == goal.run_id &&
          expected_ordinal == goal.continuation_count {
          let next = accepted(goal, id, now)
          { ..next, continuation_count: goal.continuation_count + 1 }
        } else {
          goal
        }
      TurnFinished(
        _,
        _,
        expected_run_id,
        expected_turn_ordinal,
        blocker,
        meaningful_progress
      ) =>
        if runnable(goal) &&
          expected_run_id == goal.run_id &&
          expected_turn_ordinal == goal.current_goal_turn {
          let next = accepted(goal, id, now)
          let advanced = {
            ..next,
            current_goal_turn: goal.current_goal_turn + 1,
            blocker: if meaningful_progress {
              None
            } else {
              goal.blocker
            },
          }
          if meaningful_progress {
            advanced
          } else {
            match blocker {
              Some(identity) =>
                match canonical_blocker(identity) {
                  Some(clean) => apply_blocker(advanced, clean, false)
                  None => goal
                }
              None => { ..advanced, blocker: None }
            }
          }
        } else {
          goal
        }
      RequirementUpdated(_, _, requirement_id, state, evidence_refs) =>
        if runnable(goal) {
          let clean_id = requirement_id.trim().to_owned()
          if clean_id.is_empty() ||
            !goal.requirements.any(fn(item) { item.id == clean_id }) {
            goal
          } else {
            let requirements = goal.requirements.map(fn(item) {
              if item.id == clean_id {
                { ..item, state, evidence_refs: evidence_refs.copy() }
              } else {
                item
              }
            })
            let next = accepted(goal, id, now)
            { ..next, requirements, }
          }
        } else {
          goal
        }
      AwaitingApproval(_, _, refs) =>
        if runnable(goal) {
          match canonical_refs(refs) {
            Some(clean) => {
              let next = accepted(goal, id, now)
              { ..next, run_state: AwaitingApproval, approval_refs: clean }
            }
            None => goal
          }
        } else {
          goal
        }
      ApprovalSettled(_, _, refs, outcome) =>
        if goal.run_state == AwaitingApproval {
          match canonical_refs(refs) {
            Some(clean) =>
              if same_refs(clean, goal.approval_refs) {
                let next = accepted(goal, id, now)
                match outcome {
                  Approved => { ..next, run_state: Runnable, approval_refs: [] }
                  Rejected =>
                    { ..next, run_state: AwaitingInput, approval_refs: [] }
                }
              } else {
                goal
              }
            None => goal
          }
        } else {
          goal
        }
      BudgetUsageRecorded(_, _, tokens, turns, wall) =>
        if runnable(goal) &&
          tokens >= goal.budget.tokens_used &&
          turns >= goal.budget.turns_used &&
          wall >= goal.budget.wall_time_used {
          let budget = {
            ..goal.budget,
            tokens_used: tokens,
            turns_used: turns,
            wall_time_used: wall,
          }
          let next = accepted(goal, id, now)
          {
            ..next,
            budget,
            run_state: if goal_budget_exhausted(budget) {
              AwaitingBudget
            } else {
              Runnable
            },
          }
        } else {
          goal
        }
      BudgetExhausted(_, _) =>
        if runnable(goal) && goal_budget_exhausted(goal.budget) {
          let next = accepted(goal, id, now)
          { ..next, run_state: AwaitingBudget }
        } else {
          goal
        }
      BudgetExtended(_, _, tokens, turns, wall) =>
        if goal.run_state == AwaitingBudget &&
          valid_limit(tokens) &&
          valid_limit(turns) &&
          valid_limit(wall) &&
          limit_covers_usage(tokens, goal.budget.tokens_used) &&
          limit_covers_usage(turns, goal.budget.turns_used) &&
          limit_covers_usage(wall, goal.budget.wall_time_used) {
          let budget = {
            ..goal.budget,
            token_limit: tokens,
            turn_limit: turns,
            wall_time_limit: wall,
          }
          if goal_budget_exhausted(budget) {
            goal
          } else {
            let next = accepted(goal, id, now)
            { ..next, budget, run_state: Runnable }
          }
        } else {
          goal
        }
      EvaluationStarted(_, _, evaluation_id, digest) =>
        if runnable(goal) && nonempty(evaluation_id) && nonempty(digest) {
          let next = accepted(goal, id, now)
          {
            ..next,
            run_state: Evaluating,
            active_evaluation: Some({
              id: evaluation_id.trim().to_owned(),
              revision: goal.revision,
              evidence_digest: digest.trim().to_owned(),
            }),
          }
        } else {
          goal
        }
      Evaluated(_, _, evaluation_id, revision, digest, report) =>
        if goal.run_state == Evaluating {
          match goal.active_evaluation {
            Some(request) =>
              if request.id == evaluation_id.trim().to_owned() &&
                request.revision == revision &&
                request.evidence_digest == digest.trim().to_owned() &&
                report.evaluation_id == request.id &&
                report.evaluated_revision == request.revision &&
                report.evidence_digest == request.evidence_digest {
                let next = accepted(goal, id, now)
                {
                  ..next,
                  run_state: Runnable,
                  active_evaluation: None,
                  convergence: Some({ report, accepted_revision: next.revision }),
                }
              } else {
                goal
              }
            None => goal
          }
        } else {
          goal
        }
      EvaluationFailed(_, _, attempt, category, next_retry_at) =>
        if goal.run_state == Evaluating &&
          attempt >= 0 &&
          nonempty(category) &&
          next_retry_at >= now {
          let next = accepted(goal, id, now)
          { ..next, run_state: EvaluationBackoff, active_evaluation: None }
        } else {
          goal
        }
      CompleteRequested(_, _, proof) =>
        if runnable(goal) && projection_ready(goal, proof) {
          let next = accepted(goal, id, now)
          { ..next, status: Complete }
        } else {
          goal
        }
      Resume(_, _) =>
        if goal.run_state == AwaitingInput ||
          goal.run_state == EvaluationBackoff {
          let next = accepted(goal, id, now)
          { ..next, run_state: Runnable }
        } else {
          goal
        }
    }
  }
}
