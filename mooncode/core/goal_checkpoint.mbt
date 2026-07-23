///|
/// Controller-owned comparison contract, version 2.
pub let goal_checkpoint_contract_version : Int = 2

///|
pub(all) struct CheckpointProducerIdentity {
  producer_id : String
  producer_version : String
  contract_version : Int
} derive(Eq, Debug)

///|
pub(all) struct CheckpointIdentity {
  checkpoint_id : String
  comparison_epoch : Int
  checkpoint_key : String
  parent_checkpoint_id : String?
} derive(Eq, Debug)

///|
/// A required stable identifier and its controller-issued specification digest.
pub(all) struct ComparisonRequirementDefinition {
  requirement_id : String
  spec_digest : String
} derive(Eq, Debug)

///|
pub(all) struct ComparisonOutputDefinition {
  output_id : String
  spec_digest : String
} derive(Eq, Debug)

///|
pub(all) struct ComparisonCheckDefinition {
  check_id : String
  spec_digest : String
} derive(Eq, Debug)

///|
/// Versioned, controller-owned basis and acceptance policy.
pub(all) struct ComparisonBasis {
  version : Int
  basis_digest : String
  policy_digest : String
  comparison_epoch : Int
  checkpoint_key : String
  required_requirements : Array[ComparisonRequirementDefinition]
  required_outputs : Array[ComparisonOutputDefinition]
  required_checks : Array[ComparisonCheckDefinition]
} derive(Eq, Debug)

///|
/// Evidence identity is local; comparisons use role/spec/content_digest.
pub(all) struct CheckpointEvidenceRecord {
  evidence_id : String
  role : String
  spec_digest : String
  content_digest : String
  evidence_ref : String
} derive(Eq, Debug)

///|
pub(all) struct CheckpointRequirementEvidence {
  requirement_id : String
  spec_digest : String
  state : RequirementState
  evidence_refs : Array[String]
} derive(Eq, Debug)

///|
/// `content_digest` is source identity and is soft after acceptance.
pub(all) struct CheckpointOutputManifest {
  output_id : String
  spec_digest : String
  content_digest : String
  api_digest : String
  artifact_digest : String
  evidence_refs : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct CheckpointRemainingWork {
  work_id : String
  requirement_id : String
  description_digest : String
} derive(Eq, Debug)

///|
pub(all) struct CheckpointBlocker {
  blocker_id : String
  kind : String
  evidence_ref : String
  digest : String
} derive(Eq, Debug)

///|
pub(all) struct CheckpointVerificationCheck {
  check_id : String
  spec_digest : String
  passed : Bool
  result_digest : String
  evidence_refs : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct CheckpointVerificationManifest {
  checks : Array[CheckpointVerificationCheck]
} derive(Eq, Debug)

///|
pub(all) struct CheckpointBudget {
  token_limit : Int?
  turn_limit : Int?
  wall_time_limit : Int?
  tokens_used : Int
  turns_used : Int
  wall_time_used : Int
} derive(Eq, Debug)

///|
pub(all) struct GoalCheckpointSnapshot {
  contract_version : Int
  producer : CheckpointProducerIdentity
  identity : CheckpointIdentity
  basis : ComparisonBasis
  goal_id : String
  objective_digest : String
  base_workspace_digest : String
  requirements : Array[CheckpointRequirementEvidence]
  evidence : Array[CheckpointEvidenceRecord]
  outputs : Array[CheckpointOutputManifest]
  remaining_work : Array[CheckpointRemainingWork]
  blockers : Array[CheckpointBlocker]
  verification : CheckpointVerificationManifest
  budget : CheckpointBudget
} derive(Eq, Debug)

///|
pub(all) enum CheckpointComparisonOutcome {
  Exact
  FunctionallyEquivalent
  Disagreed
  InsufficientEvidence
} derive(Eq, Debug)

///|
/// Evaluator-owned, per-side completeness/acceptance result.
pub(all) enum CheckpointAcceptanceOutcome {
  Accepted
  Rejected
  InsufficientEvidence
} derive(Eq, Debug)

///|
pub(all) enum CheckpointDeltaKind {
  StaleBasis
  MissingRequirement
  RequirementStateMismatch
  RequirementEvidenceMissing
  MissingOutput
  OutputEvidenceMissing
  OutputContentMismatch
  OutputApiMismatch
  OutputArtifactMismatch
  MissingVerificationCheck
  VerificationResultMismatch
  MissingEvidenceRecord
  EvidenceSemanticMismatch
  InvalidIdentifier
  DuplicateIdentifier
  InvalidDigest
  RemainingWorkMismatch
  BlockerMismatch
  MissingSequenceSide
  Regression
} derive(Eq, Debug)

///|
pub(all) struct CheckpointDelta {
  kind : CheckpointDeltaKind
  subject_id : String
  left_digest : String
  right_digest : String
} derive(Eq, Debug)

///|
pub(all) struct CheckpointComparisonReport {
  contract_version : Int
  left_checkpoint_id : String
  right_checkpoint_id : String
  agreement_outcome : CheckpointComparisonOutcome
  outcome : CheckpointComparisonOutcome
  left_acceptance : CheckpointAcceptanceOutcome
  right_acceptance : CheckpointAcceptanceOutcome
  same_basis : Bool
  deltas : Array[CheckpointDelta]
  regression : Bool
} derive(Eq, Debug)

///|
fn delta(
  kind : CheckpointDeltaKind,
  id : String,
  left : String,
  right : String,
) -> CheckpointDelta {
  { kind, subject_id: id, left_digest: left, right_digest: right }
}

///|
fn evidence(
  s : GoalCheckpointSnapshot,
  id : String,
) -> CheckpointEvidenceRecord? {
  for e in s.evidence {
    if e.evidence_id == id {
      return Some(e)
    }
  }
  None
}

///|
// Evidence comparison must remain structural: delimiter-joined keys can collide when
// role or digest values themselves contain the chosen delimiter.
fn evidence_semantics(
  s : GoalCheckpointSnapshot,
  ids : Array[String],
) -> Array[(String, String, String)]? {
  if ids.length() == 0 {
    return None
  }
  let triples : Array[(String, String, String)] = []
  let seen_ids : Array[String] = []
  for id in ids {
    if id.trim().length() == 0 || seen_ids.contains(id) {
      return None
    }
    seen_ids.push(id)
    match evidence(s, id) {
      None => return None
      Some(e) => triples.push((e.role, e.spec_digest, e.content_digest))
    }
  }
  triples.sort()
  Some(triples)
}

///|
fn req(
  s : GoalCheckpointSnapshot,
  id : String,
) -> CheckpointRequirementEvidence? {
  for x in s.requirements {
    if x.requirement_id == id {
      return Some(x)
    }
  }
  None
}

///|
fn output(s : GoalCheckpointSnapshot, id : String) -> CheckpointOutputManifest? {
  for x in s.outputs {
    if x.output_id == id {
      return Some(x)
    }
  }
  None
}

///|
fn check(
  s : GoalCheckpointSnapshot,
  id : String,
) -> CheckpointVerificationCheck? {
  for x in s.verification.checks {
    if x.check_id == id {
      return Some(x)
    }
  }
  None
}

///|
fn basis_is_minimally_valid(basis : ComparisonBasis) -> Bool {
  if basis.version != goal_checkpoint_contract_version ||
    basis.basis_digest.trim().is_empty() ||
    basis.policy_digest.trim().is_empty() ||
    basis.checkpoint_key.trim().is_empty() ||
    basis.comparison_epoch < 0 ||
    basis.required_requirements.is_empty() ||
    basis.required_checks.is_empty() {
    return false
  }
  for definition in basis.required_requirements {
    if definition.requirement_id.trim().is_empty() ||
      definition.spec_digest.trim().is_empty() {
      return false
    }
  }
  for definition in basis.required_outputs {
    if definition.output_id.trim().is_empty() ||
      definition.spec_digest.trim().is_empty() {
      return false
    }
  }
  for definition in basis.required_checks {
    if definition.check_id.trim().is_empty() ||
      definition.spec_digest.trim().is_empty() {
      return false
    }
  }
  true
}

///|
fn basis_matches(a : ComparisonBasis, b : ComparisonBasis) -> Bool {
  basis_is_minimally_valid(a) &&
  basis_is_minimally_valid(b) &&
  a.basis_digest == b.basis_digest &&
  a.policy_digest == b.policy_digest &&
  a.comparison_epoch == b.comparison_epoch &&
  a.checkpoint_key == b.checkpoint_key &&
  a.required_requirements == b.required_requirements &&
  a.required_outputs == b.required_outputs &&
  a.required_checks == b.required_checks
}

///|

///|
fn checkpoint_acceptance(
  s : GoalCheckpointSnapshot,
) -> CheckpointAcceptanceOutcome {
  if s.contract_version != goal_checkpoint_contract_version ||
    s.producer.contract_version != goal_checkpoint_contract_version ||
    checkpoint_text_blank(s.producer.producer_id) ||
    checkpoint_text_blank(s.producer.producer_version) ||
    checkpoint_text_blank(s.identity.checkpoint_id) ||
    checkpoint_text_blank(s.goal_id) ||
    checkpoint_text_blank(s.objective_digest) ||
    checkpoint_text_blank(s.base_workspace_digest) ||
    !basis_is_minimally_valid(s.basis) ||
    s.identity.comparison_epoch != s.basis.comparison_epoch ||
    s.identity.checkpoint_key != s.basis.checkpoint_key {
    return InsufficientEvidence
  }
  for d in s.basis.required_requirements {
    match req(s, d.requirement_id) {
      Some(x) if x.spec_digest == d.spec_digest && x.state == Proven =>
        if evidence_semantics(s, x.evidence_refs) is None {
          return InsufficientEvidence
        }
      Some(_) => return Rejected
      None => return InsufficientEvidence
    }
  }
  for d in s.basis.required_outputs {
    match output(s, d.output_id) {
      Some(x) if x.spec_digest == d.spec_digest =>
        if evidence_semantics(s, x.evidence_refs) is None {
          return InsufficientEvidence
        }
      Some(_) => return Rejected
      None => return InsufficientEvidence
    }
  }
  for d in s.basis.required_checks {
    match check(s, d.check_id) {
      Some(x) if x.spec_digest == d.spec_digest && x.passed =>
        if evidence_semantics(s, x.evidence_refs) is None {
          return InsufficientEvidence
        }
      Some(_) => return Rejected
      None => return InsufficientEvidence
    }
  }
  Accepted
}

///|
fn checkpoint_text_blank(value : String) -> Bool {
  value.trim().is_empty()
}

///|
fn checkpoint_subject_matches(
  a : GoalCheckpointSnapshot,
  b : GoalCheckpointSnapshot,
) -> Bool {
  !checkpoint_text_blank(a.goal_id) &&
  !checkpoint_text_blank(b.goal_id) &&
  a.goal_id.trim() == b.goal_id.trim() &&
  !checkpoint_text_blank(a.objective_digest) &&
  !checkpoint_text_blank(b.objective_digest) &&
  a.objective_digest.trim() == b.objective_digest.trim() &&
  !checkpoint_text_blank(a.base_workspace_digest) &&
  !checkpoint_text_blank(b.base_workspace_digest) &&
  a.base_workspace_digest.trim() == b.base_workspace_digest.trim()
}

///|
pub fn compare_goal_checkpoints(
  left : GoalCheckpointSnapshot,
  right : GoalCheckpointSnapshot,
) -> CheckpointComparisonReport {
  let ds : Array[CheckpointDelta] = []
  let same_basis = basis_matches(left.basis, right.basis) &&
    checkpoint_subject_matches(left, right)
  let la = checkpoint_acceptance(left)
  let ra = checkpoint_acceptance(right)
  if !same_basis {
    ds.push(
      delta(
        StaleBasis,
        "basis",
        left.basis.basis_digest,
        right.basis.basis_digest,
      ),
    )
  }
  let mut hard = false
  let mut soft = false
  if same_basis {
    for d in left.basis.required_requirements {
      match (req(left, d.requirement_id), req(right, d.requirement_id)) {
        (Some(a), Some(b)) => {
          if a.state != b.state {
            hard = true
            ds.push(
              delta(
                RequirementStateMismatch,
                d.requirement_id,
                requirement_state_name(a.state),
                requirement_state_name(b.state),
              ),
            )
          }
          if evidence_semantics(left, a.evidence_refs) !=
            evidence_semantics(right, b.evidence_refs) {
            hard = true
            ds.push(
              delta(EvidenceSemanticMismatch, d.requirement_id, "left", "right"),
            )
          }
        }
        _ => {
          hard = true
          ds.push(delta(MissingRequirement, d.requirement_id, "", ""))
        }
      }
    }
    for d in left.basis.required_outputs {
      match (output(left, d.output_id), output(right, d.output_id)) {
        (Some(a), Some(b)) => {
          if a.api_digest != b.api_digest {
            hard = true
            ds.push(
              delta(OutputApiMismatch, d.output_id, a.api_digest, b.api_digest),
            )
          }
          if a.artifact_digest != b.artifact_digest {
            hard = true
            ds.push(
              delta(
                OutputArtifactMismatch,
                d.output_id,
                a.artifact_digest,
                b.artifact_digest,
              ),
            )
          }
          if evidence_semantics(left, a.evidence_refs) !=
            evidence_semantics(right, b.evidence_refs) {
            hard = true
            ds.push(
              delta(EvidenceSemanticMismatch, d.output_id, "left", "right"),
            )
          }
          if a.content_digest != b.content_digest {
            soft = true
            ds.push(
              delta(
                OutputContentMismatch,
                d.output_id,
                a.content_digest,
                b.content_digest,
              ),
            )
          }
        }
        _ => {
          hard = true
          ds.push(delta(MissingOutput, d.output_id, "", ""))
        }
      }
    }
    for d in left.basis.required_checks {
      match (check(left, d.check_id), check(right, d.check_id)) {
        (Some(a), Some(b)) => {
          if a.passed != b.passed || a.result_digest != b.result_digest {
            hard = true
            ds.push(
              delta(
                VerificationResultMismatch,
                d.check_id,
                a.result_digest,
                b.result_digest,
              ),
            )
          }
          if evidence_semantics(left, a.evidence_refs) !=
            evidence_semantics(right, b.evidence_refs) {
            hard = true
            ds.push(
              delta(EvidenceSemanticMismatch, d.check_id, "left", "right"),
            )
          }
        }
        _ => {
          hard = true
          ds.push(delta(MissingVerificationCheck, d.check_id, "", ""))
        }
      }
    }
  }
  let agreement = if !same_basis {
    CheckpointComparisonOutcome::InsufficientEvidence
  } else if hard {
    Disagreed
  } else if soft {
    FunctionallyEquivalent
  } else {
    Exact
  }
  let outcome = if !same_basis || la != Accepted || ra != Accepted {
    CheckpointComparisonOutcome::InsufficientEvidence
  } else if hard {
    Disagreed
  } else if soft {
    FunctionallyEquivalent
  } else {
    Exact
  }
  {
    contract_version: goal_checkpoint_contract_version,
    left_checkpoint_id: left.identity.checkpoint_id,
    right_checkpoint_id: right.identity.checkpoint_id,
    agreement_outcome: agreement,
    outcome,
    left_acceptance: la,
    right_acceptance: ra,
    same_basis,
    deltas: ds,
    regression: false,
  }
}

///|
fn duplicate_key(
  xs : Array[GoalCheckpointSnapshot],
  epoch : Int,
  key : String,
) -> Bool {
  let mut n = 0
  for x in xs {
    if x.identity.comparison_epoch == epoch && x.identity.checkpoint_key == key {
      n = n + 1
    }
  }
  n > 1
}

///|
fn by_key(
  xs : Array[GoalCheckpointSnapshot],
  epoch : Int,
  key : String,
) -> GoalCheckpointSnapshot? {
  for x in xs {
    if x.identity.comparison_epoch == epoch && x.identity.checkpoint_key == key {
      return Some(x)
    }
  }
  None
}

///|
/// Aligns only controller-issued epoch/key pairs; duplicate keys are ambiguous.
fn sequence_keys(
  left : Array[GoalCheckpointSnapshot],
  right : Array[GoalCheckpointSnapshot],
) -> Array[(Int, String)] {
  let keys : Array[(Int, String)] = []
  for checkpoint in left {
    let key = (
      checkpoint.identity.comparison_epoch,
      checkpoint.identity.checkpoint_key,
    )
    if !keys.contains(key) {
      keys.push(key)
    }
  }
  for checkpoint in right {
    let key = (
      checkpoint.identity.comparison_epoch,
      checkpoint.identity.checkpoint_key,
    )
    if !keys.contains(key) {
      keys.push(key)
    }
  }
  keys.sort()
  keys
}

///|
pub fn compare_goal_checkpoint_sequences(
  left : Array[GoalCheckpointSnapshot],
  right : Array[GoalCheckpointSnapshot],
) -> Array[CheckpointComparisonReport] {
  let reports = []
  let mut previously_accepted = false
  for pair in sequence_keys(left, right) {
    let (epoch, key) = pair
    let left_checkpoint = by_key(left, epoch, key)
    let right_checkpoint = by_key(right, epoch, key)
    if duplicate_key(left, epoch, key) || duplicate_key(right, epoch, key) {
      let base_report = match (left_checkpoint, right_checkpoint) {
        (Some(l), _) => compare_goal_checkpoints(l, l)
        (_, Some(r)) => compare_goal_checkpoints(r, r)
        _ => continue
      }
      let deltas = base_report.deltas.copy()
      deltas.push(delta(DuplicateIdentifier, key, "duplicate", "duplicate"))
      reports.push({
        ..base_report,
        outcome: InsufficientEvidence,
        agreement_outcome: InsufficientEvidence,
        deltas,
      })
      continue
    }
    match (left_checkpoint, right_checkpoint) {
      (Some(l), Some(r)) => {
        let base_report = compare_goal_checkpoints(l, r)
        let report = if previously_accepted && base_report.outcome == Disagreed {
          let deltas = base_report.deltas.copy()
          deltas.push(delta(Regression, key, "converged", "disagreed"))
          { ..base_report, regression: true, deltas }
        } else {
          base_report
        }
        if report.outcome == Exact || report.outcome == FunctionallyEquivalent {
          previously_accepted = true
        }
        reports.push(report)
      }
      (Some(l), None) =>
        reports.push({
          contract_version: goal_checkpoint_contract_version,
          left_checkpoint_id: l.identity.checkpoint_id,
          right_checkpoint_id: "",
          agreement_outcome: InsufficientEvidence,
          outcome: InsufficientEvidence,
          left_acceptance: checkpoint_acceptance(l),
          right_acceptance: CheckpointAcceptanceOutcome::InsufficientEvidence,
          same_basis: false,
          deltas: [
            delta(MissingSequenceSide, key, l.identity.checkpoint_id, ""),
          ],
          regression: false,
        })
      (None, Some(r)) =>
        reports.push({
          contract_version: goal_checkpoint_contract_version,
          left_checkpoint_id: "",
          right_checkpoint_id: r.identity.checkpoint_id,
          agreement_outcome: InsufficientEvidence,
          outcome: InsufficientEvidence,
          left_acceptance: CheckpointAcceptanceOutcome::InsufficientEvidence,
          right_acceptance: checkpoint_acceptance(r),
          same_basis: false,
          deltas: [
            delta(MissingSequenceSide, key, "", r.identity.checkpoint_id),
          ],
          regression: false,
        })
      _ => ()
    }
  }
  reports
}
