///|
pub struct BrowserWorker {
  scope : BrowserSessionScope
  mut status : BrowserSessionStatus
  mut remaining_actions : Int
  receipts : Array[BrowserActionReceipt]
}

///|
pub struct BrowserWorkerSnapshot {
  scope : BrowserSessionScope
  status : BrowserSessionStatus
  remaining_actions : Int
  receipts : Array[BrowserActionReceipt]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn BrowserWorker::new(
  scope : BrowserSessionScope,
  action_budget? : Int = 100,
) -> BrowserWorker {
  {
    scope,
    status: Ready,
    remaining_actions: if action_budget < 0 { 0 } else { action_budget },
    receipts: [],
  }
}

///|
pub fn BrowserWorker::restore(snapshot : BrowserWorkerSnapshot) -> BrowserWorker {
  {
    scope: snapshot.scope,
    status: snapshot.status,
    remaining_actions: snapshot.remaining_actions,
    receipts: snapshot.receipts.copy(),
  }
}

///|
pub fn BrowserWorker::snapshot(self : BrowserWorker) -> BrowserWorkerSnapshot {
  {
    scope: self.scope,
    status: self.status,
    remaining_actions: self.remaining_actions,
    receipts: self.receipts.copy(),
  }
}

///|
pub fn BrowserWorker::scope(self : BrowserWorker) -> BrowserSessionScope {
  self.scope
}

///|
pub fn BrowserWorker::status(self : BrowserWorker) -> BrowserSessionStatus {
  self.status
}

///|
pub fn BrowserWorker::remaining_actions(self : BrowserWorker) -> Int {
  self.remaining_actions
}

///|
pub fn BrowserWorker::receipts(self : BrowserWorker) -> Array[BrowserActionReceipt] {
  self.receipts.copy()
}

///|
pub fn BrowserWorker::begin_agent_operation(self : BrowserWorker) -> Bool {
  match self.status {
    Ready | Paused => {
      self.status = AgentOperating
      true
    }
    _ => false
  }
}

///|
pub fn BrowserWorker::pause(self : BrowserWorker) -> Bool {
  match self.status {
    AgentOperating | Ready => {
      self.status = Paused
      true
    }
    _ => false
  }
}

///|
pub fn BrowserWorker::take_over(self : BrowserWorker) -> Bool {
  match self.status {
    Stopped => false
    _ => {
      self.status = UserControl
      true
    }
  }
}

///|
pub fn BrowserWorker::return_to_agent(self : BrowserWorker) -> Bool {
  if self.status is UserControl {
    self.status = Paused
    true
  } else {
    false
  }
}

///|
pub fn BrowserWorker::stop(self : BrowserWorker) -> Bool {
  if self.status is Stopped {
    false
  } else {
    self.status = Stopped
    true
  }
}

///|
fn BrowserWorker::receipt_for_action(
  self : BrowserWorker,
  action_id : String,
) -> BrowserActionReceipt? {
  for receipt in self.receipts {
    if receipt.action_id == action_id {
      return Some(receipt)
    }
  }
  None
}

///|
fn BrowserWorker::scope_issue(
  self : BrowserWorker,
  action : BrowserAction,
) -> String? {
  if action.session_id != self.scope.session_id {
    Some("session-mismatch")
  } else if action.code_revision != self.scope.code_revision {
    Some("code-revision-mismatch")
  } else if action.authority_envelope_id != self.scope.authority_envelope_id {
    Some("authority-envelope-mismatch")
  } else if self.scope.capability_digest == "" {
    Some("session-capability-missing")
  } else if action.value_redacted != "" && action.value_redacted != "[redacted]" {
    Some("secret-value-not-redacted")
  } else if !self.scope.permitted_effects.contains(action.required_effect) {
    Some("effect-not-authorized")
  } else {
    None
  }
}

///|
fn BrowserWorker::actor_issue(
  self : BrowserWorker,
  action : BrowserAction,
) -> String? {
  match action.actor {
    User if self.status is UserControl => None
    Agent if self.status is AgentOperating => None
    Replay if self.status is AgentOperating => None
    User => Some("user-does-not-control-session")
    Agent => Some("agent-is-not-operating")
    Replay => Some("replay-is-not-operating")
  }
}

///|
fn BrowserWorker::record(
  self : BrowserWorker,
  action : BrowserAction,
  outcome : BrowserActionOutcome,
  observations? : Array[String] = [],
  before_state_digest? : String = "",
  after_state_digest? : String = "",
  evidence_refs? : Array[String] = [],
  host_receipt_id? : String = "",
  completed_at? : String = "",
) -> BrowserActionReceipt {
  let receipt : BrowserActionReceipt = {
    action_id: action.action_id,
    session_id: action.session_id,
    actor: action.actor,
    actor_id: action.actor_id,
    operation: action.operation,
    semantic_target: action.target,
    redacted_arguments: action.value_redacted,
    expected_observation: action.expected_observation,
    outcome,
    observations,
    before_state_digest,
    after_state_digest,
    evidence_refs,
    host_receipt_id,
    authority_envelope_id: action.authority_envelope_id,
    capability_digest: self.scope.capability_digest,
    capability_expires_at: self.scope.capability_expires_at,
    code_revision: action.code_revision,
    completed_at,
  }
  self.receipts.push(receipt)
  receipt
}

///|
pub fn BrowserWorker::prepare(
  self : BrowserWorker,
  action : BrowserAction,
  expected_before_digest? : String = "",
) -> BrowserDispatch {
  match self.receipt_for_action(action.action_id) {
    Some(receipt) => return Duplicate(receipt)
    None => ()
  }
  if self.status is Stopped {
    return Rejected(self.record(action, Blocked("session-stopped")))
  }
  match self.scope_issue(action) {
    Some(issue) => return Rejected(self.record(action, Blocked(issue)))
    None => ()
  }
  match self.actor_issue(action) {
    Some(issue) => return Rejected(self.record(action, Blocked(issue)))
    None => ()
  }
  if self.remaining_actions <= 0 {
    return Rejected(self.record(action, Blocked("action-budget-exhausted")))
  }
  Ready({
    request_id: "host-" + action.action_id,
    session_id: action.session_id,
    action_id: action.action_id,
    actor: action.actor,
    actor_id: action.actor_id,
    operation: action.operation,
    effect_class: action.required_effect,
    semantic_target: action.target,
    redacted_arguments: action.value_redacted,
    expected_observation: action.expected_observation,
    expected_before_digest,
    code_revision: action.code_revision,
    authority_envelope_id: action.authority_envelope_id,
    capability_digest: self.scope.capability_digest,
    capability_expires_at: self.scope.capability_expires_at,
  })
}

///|
fn host_identity_issue(
  command : BrowserHostCommand,
  result : BrowserHostResult,
) -> String? {
  if result.request_id != command.request_id {
    Some("host-request-mismatch")
  } else if result.session_id != command.session_id {
    Some("host-session-mismatch")
  } else if result.action_id != command.action_id {
    Some("host-action-mismatch")
  } else if result.code_revision != command.code_revision {
    Some("host-revision-mismatch")
  } else if result.authority_envelope_id != command.authority_envelope_id {
    Some("host-authority-mismatch")
  } else if result.capability_digest != command.capability_digest {
    Some("host-capability-mismatch")
  } else if result.host_receipt_id == "" {
    Some("host-receipt-missing")
  } else {
    None
  }
}

///|
pub fn BrowserWorker::complete(
  self : BrowserWorker,
  action : BrowserAction,
  command : BrowserHostCommand,
  result : BrowserHostResult,
) -> BrowserActionReceipt {
  match self.receipt_for_action(action.action_id) {
    Some(receipt) => return receipt
    None => ()
  }
  match host_identity_issue(command, result) {
    Some(issue) => return self.record(action, Blocked(issue))
    None => ()
  }
  if self.status is Stopped {
    return self.record(action, Cancelled("session-stopped-before-result"))
  }
  if (action.actor is Agent || action.actor is Replay) &&
    !(self.status is AgentOperating) {
    return self.record(action, Cancelled("agent-control-revoked"))
  }
  match result.status {
    CancelledByHost(reason) => return self.record(action, Cancelled(reason))
    RejectedByHost(reason) => return self.record(action, Blocked(reason))
    Crashed(reason) => return self.record(action, Blocked("host-crashed:" + reason))
    Completed => ()
  }
  if !result.target_resolved {
    return self.record(action, Diverged("semantic-target-changed"))
  }
  if result.before_state_digest == "" || result.after_state_digest == "" {
    return self.record(action, Blocked("host-state-digest-missing"))
  }
  if command.expected_before_digest != "" &&
    result.before_state_digest != command.expected_before_digest {
    return self.record(action, Diverged("before-state-digest-mismatch"))
  }
  self.remaining_actions = self.remaining_actions - 1
  let evidence_refs : Array[String] = []
  if result.screenshot_before_ref != "" {
    evidence_refs.push(result.screenshot_before_ref)
  }
  if result.screenshot_after_ref != "" {
    evidence_refs.push(result.screenshot_after_ref)
  }
  self.record(
    action,
    Accepted,
    observations=result.observations,
    before_state_digest=result.before_state_digest,
    after_state_digest=result.after_state_digest,
    evidence_refs~,
    host_receipt_id=result.host_receipt_id,
    completed_at=result.completed_at,
  )
}

///|
pub fn BrowserWorker::complete_transport_error(
  self : BrowserWorker,
  action : BrowserAction,
  command : BrowserHostCommand,
  message : String,
) -> BrowserActionReceipt {
  match self.receipt_for_action(action.action_id) {
    Some(receipt) => receipt
    None =>
      if command.action_id != action.action_id ||
        command.session_id != action.session_id ||
        command.code_revision != action.code_revision ||
        command.authority_envelope_id != action.authority_envelope_id {
        self.record(action, Blocked("transport-command-mismatch"))
      } else if self.status is Stopped || self.status is Paused ||
        self.status is UserControl {
        self.record(action, Cancelled("host-transport-cancelled:" + message))
      } else {
        self.record(action, Blocked("host-transport-failed:" + message))
      }
  }
}

///|
pub fn BrowserWorker::prepare_replay(
  self : BrowserWorker,
  source : BrowserActionReceipt,
  action : BrowserAction,
) -> BrowserDispatch {
  if !source.accepted() {
    return Rejected(self.record(action, Blocked("source-receipt-not-accepted")))
  }
  if source.session_id != action.session_id ||
    source.code_revision != action.code_revision ||
    source.operation != action.operation {
    return Rejected(self.record(action, Diverged("replay-lineage-mismatch")))
  }
  self.prepare(action, expected_before_digest=source.before_state_digest)
}
