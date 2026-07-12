///|
pub struct BrowserWorker {
  scope : BrowserSessionScope
  mut status : BrowserSessionStatus
  mut remaining_actions : Int
  receipts : Array[BrowserActionReceipt]
}

///|
pub fn BrowserWorker::new(
  scope : BrowserSessionScope,
  action_budget? : Int = 100,
) -> BrowserWorker {
  {
    scope,
    status: Ready,
    remaining_actions: if action_budget < 0 {
      0
    } else {
      action_budget
    },
    receipts: [],
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
pub fn BrowserWorker::receipts(
  self : BrowserWorker,
) -> Array[BrowserActionReceipt] {
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
  observations : Array[String],
  completed_at : String,
) -> BrowserActionReceipt {
  let receipt : BrowserActionReceipt = {
    action_id: action.action_id,
    session_id: action.session_id,
    actor: action.actor,
    operation: action.operation,
    outcome,
    observations,
    authority_envelope_id: action.authority_envelope_id,
    code_revision: action.code_revision,
    completed_at,
  }
  self.receipts.push(receipt)
  receipt
}

///|
pub fn BrowserWorker::execute(
  self : BrowserWorker,
  action : BrowserAction,
  target_stable~ : Bool,
  observations? : Array[String] = [],
  completed_at? : String = "",
) -> BrowserActionReceipt {
  if self.status is Stopped {
    return self.record(action, Blocked("session-stopped"), [], completed_at)
  }
  match self.scope_issue(action) {
    Some(issue) => return self.record(action, Blocked(issue), [], completed_at)
    None => ()
  }
  match self.actor_issue(action) {
    Some(issue) => return self.record(action, Blocked(issue), [], completed_at)
    None => ()
  }
  if !target_stable {
    return self.record(
      action,
      Diverged("semantic-target-changed"),
      observations,
      completed_at,
    )
  }
  if self.remaining_actions <= 0 {
    return self.record(
      action,
      Blocked("action-budget-exhausted"),
      [],
      completed_at,
    )
  }
  self.remaining_actions = self.remaining_actions - 1
  self.record(action, Accepted, observations, completed_at)
}

///|
pub fn BrowserWorker::replay(
  self : BrowserWorker,
  accepted : BrowserActionReceipt,
  action : BrowserAction,
  target_stable~ : Bool,
  completed_at? : String = "",
) -> BrowserActionReceipt {
  if !accepted.accepted() {
    return self.record(
      action,
      Blocked("source-receipt-not-accepted"),
      [],
      completed_at,
    )
  }
  if accepted.session_id != action.session_id ||
    accepted.code_revision != action.code_revision ||
    accepted.operation != action.operation {
    return self.record(
      action,
      Diverged("replay-lineage-mismatch"),
      [],
      completed_at,
    )
  }
  self.execute(action, target_stable~, completed_at~)
}
