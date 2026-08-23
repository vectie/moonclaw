///|
pub struct SupervisorRuntime {
  runtime : RuntimeManager
  receiver : @capability.PrincipalRefV1
  verifier : SupervisorAuthorityVerifierV1
  states : Map[String, SupervisorStateV1]
  receipts : Map[String, SupervisorCommandReceiptV1]
  events : Array[SupervisorJournalEventV1]
  lineage : Array[SupervisorWorkerLineageV1]
  outcome_evidence : Array[SupervisorBookkeeperOutcomeEvidenceV1]
  verified_commands : Map[String, SupervisorAuthorityVerificationV1]
}

///|
pub fn SupervisorRuntime::new(
  runtime~ : RuntimeManager,
  receiver~ : @capability.PrincipalRefV1,
  verifier~ : SupervisorAuthorityVerifierV1,
) -> SupervisorRuntime {
  {
    runtime,
    receiver,
    verifier,
    states: {},
    receipts: {},
    events: [],
    lineage: [],
    outcome_evidence: [],
    verified_commands: {},
  }
}

///|
/// Safe process-local timestamp for legacy JobRun APIs. It is deliberately
/// generated independently and never converted from an external epoch value.
fn supervisor_native_runtime_timestamp() -> Int {
  @async.now().to_int()
}

///|
fn SupervisorRuntime::root(self : SupervisorRuntime) -> String {
  self.runtime.store().root_dir() |> @pathx.join("supervisors")
}

///|
fn SupervisorRuntime::journal_file(self : SupervisorRuntime) -> String {
  self.root() |> @pathx.join("journal.v1.jsonl")
}

///|
fn SupervisorRuntime::lock_file(self : SupervisorRuntime) -> String {
  self.root() |> @pathx.join(".lock")
}

///|
async fn[T] SupervisorRuntime::with_lock(
  self : SupervisorRuntime,
  f : async () -> T,
) -> T {
  @fsx.make_directory(self.root(), recursive=true, exists_ok=true) catch {
    _ => ()
  }
  let file = @fs.open(
    self.lock_file(),
    mode=WriteOnly,
    create_mode=OpenOrCreate,
    permission=0o644,
  )
  defer file.close()
  @fsx.lock_file(file)
  f()
}

///|
fn supervisor_digest_valid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  value[7:].all(fn(c) { (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') })
}

///|
fn supervisor_source_product_valid(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 128 &&
  value
  .iter()
  .all(fn(c) {
    (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.'
  })
}

///|
async fn SupervisorRuntime::validate_envelope(
  self : SupervisorRuntime,
  envelope : SupervisorCommandEnvelopeV1,
  expected_operation : String,
  payload : Json,
) -> Result[Unit, String] {
  guard envelope.contract_id == "moonclaw.supervisor-command.v1" else {
    return Err("unsupported supervisor command contract")
  }
  guard !envelope.command_id.trim().is_blank() &&
    supervisor_digest_valid(envelope.request_digest) else {
    return Err("supervisor command identity is invalid")
  }
  let authority = @capability.decode_authority_decision_ref_v1(
    envelope.authority,
  ) catch {
    _ => return Err("supervisor command authority reference is invalid")
  }
  if !authority.is_fresh_for(self.receiver, envelope.evaluated_at) {
    return Err(
      "supervisor command authority is missing, stale, or receiver-mismatched",
    )
  }
  if authority.digest().text() != envelope.request_digest {
    return Err(
      "supervisor command authority is not bound to the request digest",
    )
  }
  let recomputed = supervisor_command_digest_v1(envelope, payload)
  if recomputed != envelope.request_digest {
    return Err("supervisor command request digest mismatch")
  }
  match (self.verifier.verify)(envelope, expected_operation) {
    Ok(verification) => {
      if verification.operation_ref != expected_operation ||
        !supervisor_digest_valid(verification.operation_digest) {
        return Err("MoonGate operation verification is not exact")
      }
      self.verified_commands.set(envelope.command_id, verification)
    }
    Err(error) =>
      return Err("MoonGate capability verification failed: \{error}")
  }
  Ok(())
}

///|
pub fn supervisor_command_digest_v1(
  _envelope : SupervisorCommandEnvelopeV1,
  payload : Json,
) -> String {
  supervisor_payload_digest_v1(payload)
}

///|
fn SupervisorRuntime::apply_event(
  self : SupervisorRuntime,
  event : SupervisorJournalEventV1,
) -> Unit raise {
  let previous = self.states.get(event.supervisor_id)
  let expected = previous.map(fn(state) { state.cursor + 1 }).unwrap_or(1)
  if event.contract_id != "moonclaw.supervisor-journal-event.v1" ||
    event.cursor != expected ||
    event.event_id != "\{event.supervisor_id}:\{event.cursor}" ||
    event.state_after.cursor != event.cursor {
    fail("invalid or non-contiguous supervisor journal event \{event.event_id}")
  }
  match self.receipts.get(event.command_id) {
    Some(existing) if existing.request_digest != event.command_digest =>
      fail("divergent duplicate supervisor command \{event.command_id}")
    Some(_) =>
      fail(
        "duplicate supervisor command in durable journal \{event.command_id}",
      )
    None => ()
  }
  self.states.set(event.supervisor_id, event.state_after)
  self.receipts.set(event.command_id, event.receipt)
  self.events.push(event)
  match event.lineage {
    Some(edge) => self.lineage.push(edge)
    None => ()
  }
  match event.outcome_evidence {
    Some(value) => self.outcome_evidence.push(value)
    None => ()
  }
}

///|
async fn SupervisorRuntime::reload_unlocked(self : SupervisorRuntime) -> Unit {
  clear_map(self.states)
  clear_map(self.receipts)
  self.events.clear()
  self.lineage.clear()
  self.outcome_evidence.clear()
  clear_map(self.verified_commands)
  let path = self.journal_file()
  guard @fsx.exists(path) else { return }
  let lines : Array[String] = []
  for raw in @fsx.read_file(path).split("\n") {
    let line = raw.to_owned().trim().to_owned()
    if !line.is_blank() {
      lines.push(line)
    }
  }
  let mut recovered_tail = false
  for i in 0..<lines.length() {
    let event : SupervisorJournalEventV1 = @json.from_json(
      @json.parse(lines[i]),
    ) catch {
      error => {
        if i == lines.length() - 1 {
          recovered_tail = true
          break
        }
        fail("Failed to replay supervisor journal at entry \{i}: \{error}")
      }
    }
    self.apply_event(event)
  }
  if recovered_tail {
    let valid = self.events
      .map(fn(event) { event.to_json().stringify() })
      .join("\n")
    @fsx.write_to_file(path, valid)
  }
}

///|
pub async fn SupervisorRuntime::load(self : SupervisorRuntime) -> Unit {
  self.runtime.load()
  self.with_lock(async fn() { self.reload_unlocked() })
}

///|
fn duplicate_receipt(
  receipt : SupervisorCommandReceiptV1,
) -> SupervisorCommandReceiptV1 {
  { ..receipt, duplicate: true }
}

///|
fn SupervisorRuntime::preflight(
  self : SupervisorRuntime,
  envelope : SupervisorCommandEnvelopeV1,
  supervisor_id : String,
  require_existing : Bool,
) -> Result[SupervisorCommandReceiptV1?, String] {
  match self.receipts.get(envelope.command_id) {
    Some(receipt) =>
      if receipt.supervisor_id == supervisor_id &&
        receipt.request_digest == envelope.request_digest {
        return Ok(Some(duplicate_receipt(receipt)))
      } else {
        return Err("divergent duplicate supervisor command")
      }
    None => ()
  }
  let state = self.states.get(supervisor_id)
  if require_existing && state is None {
    return Err("unknown supervisor: \{supervisor_id}")
  }
  let cursor = state.map(fn(value) { value.cursor }).unwrap_or(0)
  match envelope.expected_cursor {
    Some(expected) if expected != cursor =>
      return Err(
        "stale supervisor cursor: expected \{expected}, current \{cursor}",
      )
    _ => ()
  }
  Ok(None)
}

///|
async fn SupervisorRuntime::commit_unlocked(
  self : SupervisorRuntime,
  envelope : SupervisorCommandEnvelopeV1,
  state : SupervisorStateV1,
  event_type : String,
  response : Json,
  payload? : Json = {},
  conversation_id? : String? = None,
  task_id? : String? = None,
  parent_run_id? : String? = None,
  worker_run_id? : String? = None,
  lineage? : SupervisorWorkerLineageV1? = None,
  outcome_evidence? : SupervisorBookkeeperOutcomeEvidenceV1? = None,
) -> SupervisorCommandReceiptV1 {
  let cursor = state.cursor
  let event_id = "\{state.supervisor_id}:\{cursor}"
  let receipt = SupervisorCommandReceiptV1::{
    contract_id: "moonclaw.supervisor-command-receipt.v1",
    command_id: envelope.command_id,
    request_digest: envelope.request_digest,
    supervisor_id: state.supervisor_id,
    cursor,
    event_id,
    status: "accepted",
    duplicate: false,
    response,
  }
  let authority_verification = match
    self.verified_commands.get(envelope.command_id) {
    Some(value) => value
    None =>
      fail("supervisor command is missing MoonGate authority verification")
  }
  let event = SupervisorJournalEventV1::{
    contract_id: "moonclaw.supervisor-journal-event.v1",
    event_id,
    supervisor_id: state.supervisor_id,
    cursor,
    command_id: envelope.command_id,
    command_digest: envelope.request_digest,
    event_type,
    timestamp: envelope.issued_at,
    conversation_id,
    task_id,
    parent_run_id,
    worker_run_id,
    payload,
    state_after: state,
    receipt,
    lineage,
    outcome_evidence,
    authority_verification,
  }
  let content = self.events.map(fn(item) { item.to_json().stringify() })
  content.push(event.to_json().stringify())
  @fsx.write_to_file(self.journal_file(), content.join("\n"))
  self.apply_event(event)
  receipt
}

///|
pub async fn SupervisorRuntime::activate_profile(
  self : SupervisorRuntime,
  request : SupervisorActivateRequestV1,
  executor_run_id : String,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let profile = request.profile
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.activate@0.1.5",
        supervisor_activate_payload_v1(profile),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, profile.supervisor_id, false) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    guard profile.contract_id == "moonsuite.supervisor-profile-activation.v1" &&
      supervisor_source_product_valid(profile.source_product) &&
      profile.profile_version > 0 &&
      supervisor_digest_valid(profile.profile_digest) &&
      !profile.supervisor_id.trim().is_blank() &&
      !profile.profile_id.trim().is_blank() &&
      profile.runtime_profile is Object(_) &&
      profile.runtime_binding is Object(_) else {
      return Err("invalid external supervisor profile activation")
    }
    let runtime_profile_digest = @capability.sha256_digest_ref_v1(
      @encoding/utf8.encode(profile.runtime_profile.stringify()),
    ).text()
    if runtime_profile_digest != profile.profile_digest {
      return Err("external supervisor runtime profile digest mismatch")
    }
    match self.states.get(profile.supervisor_id) {
      Some(existing) if profile.profile_version <=
        existing.profile.profile_version =>
        return Err("stale supervisor profile version")
      Some(existing) =>
        match existing.active_run_id {
          Some(old_run_id) =>
            ignore(
              self.runtime.cancel_run(
                old_run_id,
                supervisor_native_runtime_timestamp(),
                summary=Some("superseded by supervisor profile activation"),
              ),
            )
          None => ()
        }
      _ => ()
    }
    let job_id = "moonclaw.supervisor.\{profile.supervisor_id}"
    let workflow_id = "\{job_id}.mailbox"
    let run_id = executor_run_id
    let runtime_timestamp = supervisor_native_runtime_timestamp()
    if run_id.trim().is_blank() {
      return Err("supervisor activation requires a canonical executor run id")
    }
    self.runtime.register_workflow({
      id: workflow_id,
      kind: "supervisor.mailbox",
      steps: [
        {
          id: "mailbox",
          kind: "supervisor.mailbox",
          config: {
            "supervisor_id": profile.supervisor_id,
            "profile_id": profile.profile_id,
            "profile_version": profile.profile_version,
          },
          retry_policy: None,
        },
        {
          id: "delegate",
          kind: "job.delegate",
          config: { "supervisor_id": profile.supervisor_id },
          retry_policy: Some({ max_attempts: 3, backoff_ms: Some(1000) }),
        },
      ],
      output_bindings: ["mailbox"],
    })
    self.runtime.register_definition({
      id: job_id,
      kind: "job.supervisor",
      enabled: true,
      config: {
        "supervisor_id": profile.supervisor_id,
        "external_profile": profile.to_json(),
      },
      schedule: None,
      retry_policy: Some({ max_attempts: 3, backoff_ms: Some(1000) }),
      workflow_id: Some(workflow_id),
      created_at: runtime_timestamp,
      updated_at: runtime_timestamp,
      tags: ["supervisor", "external-profile"],
    })
    match self.runtime.store().get_run(run_id) {
      Some(existing) => {
        guard existing.job_id == job_id && existing.parent_run_id is None else {
          return Err("canonical executor run is bound to a different job")
        }
        match self.runtime.mark_run_resumed(run_id, runtime_timestamp) {
          Some(_) => ()
          None => return Err("failed to resume canonical executor run")
        }
      }
      None =>
        match
          self.runtime.trigger_definition(
            run_id,
            job_id,
            Custom("supervisor-activation"),
            runtime_timestamp,
          ) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
    }
    let cursor = self.states
      .get(profile.supervisor_id)
      .map(fn(s) { s.cursor + 1 })
      .unwrap_or(1)
    let state = SupervisorStateV1::{
      contract_id: "moonclaw.supervisor-state.v1",
      supervisor_id: profile.supervisor_id,
      profile,
      lifecycle: Dormant,
      active_run_id: Some(run_id),
      cursor,
      updated_at: request.envelope.issued_at,
      last_error: None,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "profile.activated",
        state.to_json(),
        payload=profile.to_json(),
      ),
    )
  })
}

///|
/// Pre-dispatch gate used by the daemon before it starts or resumes the sole
/// executor task. Activation performs the same check again under journal lock.
pub async fn SupervisorRuntime::verify_activation(
  self : SupervisorRuntime,
  request : SupervisorActivateRequestV1,
) -> Result[SupervisorCommandReceiptV1?, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let profile = request.profile
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.activate@0.1.5",
        supervisor_activate_payload_v1(profile),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, profile.supervisor_id, false) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(Some(receipt))
      Ok(None) => ()
    }
    guard profile.contract_id == "moonsuite.supervisor-profile-activation.v1" &&
      supervisor_source_product_valid(profile.source_product) &&
      profile.profile_version > 0 &&
      supervisor_digest_valid(profile.profile_digest) &&
      !profile.supervisor_id.trim().is_blank() &&
      !profile.profile_id.trim().is_blank() &&
      profile.runtime_profile is Object(_) &&
      profile.runtime_binding is Object(_) else {
      return Err("invalid external supervisor profile activation")
    }
    let digest = @capability.sha256_digest_ref_v1(
      @encoding/utf8.encode(profile.runtime_profile.stringify()),
    ).text()
    if digest != profile.profile_digest {
      return Err("external supervisor runtime profile digest mismatch")
    }
    match self.states.get(profile.supervisor_id) {
      Some(existing) if profile.profile_version <=
        existing.profile.profile_version =>
        Err("stale supervisor profile version")
      _ => Ok(None)
    }
  })
}

///|
fn SupervisorRuntime::state_for(
  self : SupervisorRuntime,
  id : String,
) -> SupervisorStateV1 raise {
  match self.states.get(id) {
    Some(state) => state
    None => fail("unknown supervisor: \{id}")
  }
}

///|
async fn SupervisorRuntime::resume_bound_run(
  self : SupervisorRuntime,
  supervisor_id : String,
  run_id : String?,
  now_ms : Int,
) -> Result[String?, String] {
  let target = match run_id {
    Some(id) => Some(id)
    None => self.state_for(supervisor_id).active_run_id
  }
  match target {
    None => Ok(None)
    Some(id) => {
      let run = match self.runtime.store().get_run(id) {
        Some(run) => run
        None => return Err("unknown supervisor run: \{id}")
      }
      if run.parent_run_id is Some(_) {
        return Err("a worker run cannot be bound as a supervisor")
      }
      match run.status {
        Succeeded => Err("a succeeded supervisor run cannot be resumed")
        Running => Ok(Some(id))
        Pending =>
          match self.runtime.mark_run_started(id, now_ms) {
            Some(_) => Ok(Some(id))
            None => Err("failed to start supervisor run")
          }
        WaitingForInput | Failed | Cancelled =>
          match self.runtime.mark_run_resumed(id, now_ms) {
            Some(_) => Ok(Some(id))
            None => Err("failed to resume supervisor run")
          }
      }
    }
  }
}

///|
pub async fn SupervisorRuntime::wake_resume(
  self : SupervisorRuntime,
  request : SupervisorWakeRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.wake@0.1.5",
        supervisor_wake_payload_v1(request.supervisor_id, request.run_id),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    let bound = match
      self.resume_bound_run(
        request.supervisor_id,
        request.run_id,
        supervisor_native_runtime_timestamp(),
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let previous = self.state_for(request.supervisor_id)
    let state = {
      ..previous,
      lifecycle: Running,
      active_run_id: bound,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
      last_error: None,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "supervisor.woken",
        state.to_json(),
        payload={ "run_id": bound },
      ),
    )
  })
}

///|
fn validate_message(message : SupervisorMessageV1) -> Result[Unit, String] {
  if message.message_id.trim().is_blank() ||
    message.conversation_id.trim().is_blank() ||
    message.sender_ref.trim().is_blank() ||
    message.content.trim().is_blank() ||
    message.content_type.trim().is_blank() {
    Err("invalid supervisor message")
  } else {
    Ok(())
  }
}

///|
pub async fn SupervisorRuntime::send_message(
  self : SupervisorRuntime,
  request : SupervisorSendMessageRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.message.send@0.1.5",
        supervisor_message_payload_v1(request.supervisor_id, request.message),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    match validate_message(request.message) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if self.events.any(fn(event) {
        match event.payload {
          { "message": { "message_id": String(id), .. }, .. } =>
            id == request.message.message_id
          _ => false
        }
      }) {
      return Err("duplicate message_id with a different command")
    }
    let previous = self.state_for(request.supervisor_id)
    let bound = match
      self.resume_bound_run(
        request.supervisor_id,
        previous.active_run_id,
        supervisor_native_runtime_timestamp(),
      ) {
      Ok(Some(run_id)) => run_id
      Ok(None) => return Err("supervisor message has no runnable binding")
      Err(error) => return Err(error)
    }
    let state = {
      ..previous,
      lifecycle: Running,
      active_run_id: Some(bound),
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "message.sent",
        { "message_id": request.message.message_id },
        payload={ "message": request.message },
        conversation_id=Some(request.message.conversation_id),
        task_id=request.message.task_id,
      ),
    )
  })
}

///|
pub async fn SupervisorRuntime::steer(
  self : SupervisorRuntime,
  request : SupervisorSteerRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.steer@0.1.5",
        supervisor_steer_payload_v1(
          request.supervisor_id,
          request.message,
          request.target_run_id,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    match validate_message(request.message) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let previous = self.state_for(request.supervisor_id)
    guard previous.lifecycle is Running &&
      previous.active_run_id == Some(request.target_run_id) else {
      return Err("steer target is stale or not active")
    }
    self.runtime
    .store()
    .append_run_event({
      run_id: request.target_run_id,
      job_id: self.runtime
      .store()
      .get_run(request.target_run_id)
      .map(fn(r) { r.job_id })
      .unwrap_or(""),
      event_type: "supervisor.steer",
      timestamp: supervisor_native_runtime_timestamp(),
      step_id: None,
      status: Some(Running),
      message: request.message.content,
      data: request.message.to_json(),
    })
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "supervisor.steered",
        { "target_run_id": request.target_run_id },
        payload={ "message": request.message },
        conversation_id=Some(request.message.conversation_id),
        task_id=request.message.task_id,
        parent_run_id=Some(request.target_run_id),
      ),
    )
  })
}

///|
fn SupervisorRuntime::mailbox_messages(
  self : SupervisorRuntime,
  supervisor_id : String,
  now_ms : SupervisorEpochMsV1,
  claimable_only? : Bool = false,
) -> Array[SupervisorMessageV1] {
  let messages : Map[String, SupervisorMessageV1] = Map([])
  let acknowledged : Map[String, Bool] = Map([])
  let claimed_until : Map[String, SupervisorEpochMsV1] = Map([])
  for event in self.events {
    if event.supervisor_id != supervisor_id {
      continue
    }
    match event.event_type {
      "message.sent" | "supervisor.steered" =>
        match event.payload {
          { "message": message, .. } => {
            let decoded : SupervisorMessageV1 = @json.from_json(message) catch {
              _ => continue
            }
            messages.set(decoded.message_id, decoded)
          }
          _ => ()
        }
      "mailbox.claimed" =>
        match event.payload {
          { "message_ids": Array(ids), "lease_expires_at": until_json, .. } => {
            let until : SupervisorEpochMsV1 = @json.from_json(until_json) catch {
              _ => continue
            }
            for value in ids {
              match value {
                String(id) => claimed_until.set(id, until)
                _ => ()
              }
            }
          }
          _ => ()
        }
      "mailbox.acknowledged" =>
        match event.payload {
          { "message_ids": Array(ids), .. } =>
            for value in ids {
              match value {
                String(id) => acknowledged.set(id, true)
                _ => ()
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
  messages
  .values()
  .to_array()
  .filter(fn(message) {
    !acknowledged.contains(message.message_id) &&
    (
      !claimable_only ||
      claimed_until
      .get(message.message_id)
      .map(fn(until) { until <= now_ms })
      .unwrap_or(true)
    )
  })
}

///|
pub async fn SupervisorRuntime::claim_mailbox(
  self : SupervisorRuntime,
  request : SupervisorMailboxClaimRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let payload : Json = {
      "supervisor_id": request.supervisor_id,
      "claim_id": request.claim_id,
      "max_messages": request.max_messages,
      "lease_expires_at": request.lease_expires_at,
    }
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.mailbox.claim@0.1.5",
        payload,
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    guard !request.claim_id.trim().is_blank() &&
      request.max_messages > 0 &&
      request.max_messages <= 100 &&
      request.lease_expires_at > request.envelope.issued_at else {
      return Err("invalid mailbox claim")
    }
    let available = self.mailbox_messages(
      request.supervisor_id,
      request.envelope.issued_at,
      claimable_only=true,
    )
    let claimed = available[:available.length().min(request.max_messages)].to_owned()
    let previous = self.state_for(request.supervisor_id)
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "mailbox.claimed",
        { "claim_id": request.claim_id, "messages": claimed },
        payload={
          "claim_id": request.claim_id,
          "lease_expires_at": request.lease_expires_at,
          "message_ids": claimed.map(fn(message) { message.message_id }),
        },
      ),
    )
  })
}

///|
pub async fn SupervisorRuntime::ack_mailbox(
  self : SupervisorRuntime,
  request : SupervisorMailboxAckRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let payload : Json = {
      "supervisor_id": request.supervisor_id,
      "claim_id": request.claim_id,
      "message_ids": request.message_ids,
    }
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.mailbox.ack@0.1.5",
        payload,
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    let unconsumed = self.mailbox_messages(
      request.supervisor_id,
      request.envelope.issued_at,
    )
    guard !request.claim_id.trim().is_blank() &&
      !request.message_ids.is_empty() &&
      request.message_ids.all(fn(id) {
        unconsumed.any(fn(message) { message.message_id == id })
      }) else {
      return Err(
        "mailbox acknowledgement contains unknown or consumed messages",
      )
    }
    let previous = self.state_for(request.supervisor_id)
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "mailbox.acknowledged",
        payload,
        payload~,
      ),
    )
  })
}

///|
pub async fn SupervisorRuntime::stop_cancel(
  self : SupervisorRuntime,
  request : SupervisorStopRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.stop@0.1.5",
        supervisor_stop_payload_v1(
          request.supervisor_id,
          request.reason,
          request.force,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    if request.reason.trim().is_blank() {
      return Err("stop reason must not be blank")
    }
    let previous = self.state_for(request.supervisor_id)
    match previous.active_run_id {
      Some(id) =>
        match self.runtime.store().get_run(id) {
          Some(run) if run.status is Pending ||
            run.status is Running ||
            run.status is WaitingForInput =>
            ignore(
              self.runtime.cancel_run(
                id,
                supervisor_native_runtime_timestamp(),
                summary=Some(request.reason),
              ),
            )
          _ => ()
        }
      None => ()
    }
    // Stopping suspends the one canonical executor; it does not replace its
    // identity. Wake/retry must resume this same daemon task and JobRun.
    let state = {
      ..previous,
      lifecycle: Stopped,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "supervisor.stopped",
        state.to_json(),
        payload={ "reason": request.reason, "force": request.force },
        parent_run_id=previous.active_run_id,
      ),
    )
  })
}

///|
pub async fn SupervisorRuntime::retry_resume(
  self : SupervisorRuntime,
  request : SupervisorRetryResumeRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.retry-resume@0.1.5",
        supervisor_retry_resume_payload_v1(
          request.supervisor_id,
          request.action,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    let previous = self.state_for(request.supervisor_id)
    let run_id = match request.action {
      Resume =>
        match
          self.resume_bound_run(
            request.supervisor_id,
            None,
            supervisor_native_runtime_timestamp(),
          ) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
      Retry(new_run_id~) => {
        let old = match previous.active_run_id {
          Some(id) => id
          None => return Err("retry requires a bound failed run")
        }
        guard new_run_id == old else {
          return Err("retry cannot replace the canonical supervisor executor")
        }
        match
          self.resume_bound_run(
            request.supervisor_id,
            Some(old),
            supervisor_native_runtime_timestamp(),
          ) {
          Ok(run_id) => run_id
          Err(error) => return Err(error)
        }
      }
    }
    let state = {
      ..previous,
      lifecycle: Running,
      active_run_id: run_id,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
      last_error: None,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "supervisor.recovered",
        state.to_json(),
        payload={ "action": request.action },
      ),
    )
  })
}

///|
pub async fn SupervisorRuntime::delegate(
  self : SupervisorRuntime,
  request : SupervisorDelegateRequestV1,
) -> Result[SupervisorDelegateResponseV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.delegate@0.1.5",
        {
          "supervisor_id": request.supervisor_id,
          "parent_run_id": request.request.parent_context.run.id,
          "parent_step_id": request.request.parent_context.step.id,
          "worker_run_id": request.request.child_run.id,
          "delegation": encode_child_delegation_v1(request.delegation),
        },
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let governed = match
      bind_child_run_execution_request_v1(
        request.request,
        request.delegation,
        request.child_principal,
        request.operation,
        request.artifact_refs,
        request.requested_claim,
        request.consumption,
        request.envelope.evaluated_at,
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match self.receipts.get(request.envelope.command_id) {
      Some(receipt) =>
        return Ok({ receipt: duplicate_receipt(receipt), governed })
      None => ()
    }
    let previous = self.state_for(request.supervisor_id)
    guard previous.lifecycle is Running &&
      previous.active_run_id == Some(request.request.parent_context.run.id) else {
      return Err("delegate parent is not the active supervisor run")
    }
    guard request.request.parent_context.step.kind == "job.delegate" else {
      return Err("supervisor workers must use the existing job.delegate step")
    }
    let edge = SupervisorWorkerLineageV1::{
      supervisor_id: request.supervisor_id,
      parent_run_id: request.request.parent_context.run.id,
      parent_step_id: request.request.parent_context.step.id,
      worker_run_id: request.request.child_run.id,
      worker_job_id: request.request.child_run.job_id,
      depth: request.request.child_run.depth,
      delegation_ref: encode_child_delegation_v1(request.delegation),
      recorded_at: request.envelope.issued_at,
    }
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    let receipt = self.commit_unlocked(
      request.envelope,
      state,
      "worker.delegated",
      edge.to_json(),
      payload={
        "governance_contract": "moonclaw.child-delegation.v1",
        "scheduler": "job.delegate",
      },
      parent_run_id=Some(edge.parent_run_id),
      worker_run_id=Some(edge.worker_run_id),
      lineage=Some(edge),
    )
    Ok({ receipt, governed })
  })
}

///|
/// Binds an HTTP supervisor delegation command to a child run that the
/// existing `job.delegate` scheduler has already created. No caller-supplied
/// worker identity is accepted unless it matches durable runtime lineage.
pub async fn SupervisorRuntime::delegate_existing(
  self : SupervisorRuntime,
  request : SupervisorDelegateExistingRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.delegate@0.1.5",
        supervisor_delegate_existing_payload_v1(
          request.supervisor_id,
          request.worker_run_id,
          request.worker_job_id,
          request.delegation,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    let previous = self.state_for(request.supervisor_id)
    let parent_run_id = match previous.active_run_id {
      Some(value) => value
      None => return Err("supervisor has no canonical parent run")
    }
    let parent = match self.runtime.store().get_run(parent_run_id) {
      Some(value) => value
      None => return Err("canonical supervisor run is missing")
    }
    let definition = match self.runtime.store().get_definition(parent.job_id) {
      Some(value) => value
      None => return Err("canonical supervisor job definition is missing")
    }
    let workflow_id = match definition.workflow_id {
      Some(value) => value
      None => return Err("canonical supervisor has no workflow")
    }
    let workflow = match self.runtime.store().get_workflow(workflow_id) {
      Some(value) => value
      None => return Err("canonical supervisor workflow is missing")
    }
    guard workflow.steps.any(fn(step) {
      step.id == "delegate" && step.kind == "job.delegate"
    }) else {
      return Err("supervisor workflow has no job.delegate step")
    }
    let delegation : ChildDelegationV1 = decode_child_delegation_v1(
      request.delegation,
    ) catch {
      _ => return Err("invalid child delegation contract")
    }
    guard request.delegation
      is {
        "payload": {
          "parent_run_id": String(delegated_parent),
          "child_run_id": String(delegated_child),
          "issued_at": String(delegation_issued_at),
          "expires_at": String(delegation_expires_at),
          ..
        },
        ..
      } &&
      delegated_parent == parent_run_id &&
      delegated_child == request.worker_run_id &&
      delegation_issued_at <= request.envelope.evaluated_at &&
      request.envelope.evaluated_at < delegation_expires_at else {
      return Err("child delegation does not match durable runtime lineage")
    }
    guard !request.worker_run_id.trim().is_blank() &&
      !request.worker_job_id.trim().is_blank() else {
      return Err("delegated worker identity is invalid")
    }
    let child = match self.runtime.store().get_run(request.worker_run_id) {
      Some(value) => value
      None => {
        let runtime_timestamp = supervisor_native_runtime_timestamp()
        if self.runtime.store().get_definition(request.worker_job_id) is None {
          self.runtime.register_definition({
            id: request.worker_job_id,
            kind: "job.supervisor-worker",
            enabled: true,
            config: {
              "supervisor_id": request.supervisor_id,
              "delegation": encode_child_delegation_v1(delegation),
            },
            schedule: None,
            retry_policy: Some({ max_attempts: 3, backoff_ms: Some(1000) }),
            workflow_id: None,
            created_at: runtime_timestamp,
            updated_at: runtime_timestamp,
            tags: ["supervisor-worker", "delegated"],
          })
        }
        match
          self.runtime.trigger_definition(
            request.worker_run_id,
            request.worker_job_id,
            Custom("supervisor-delegation"),
            runtime_timestamp,
            parent_run_id=Some(parent_run_id),
            parent_step_id=Some("delegate"),
            depth=parent.depth + 1,
          ) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
      }
    }
    guard child.job_id == request.worker_job_id &&
      child.parent_run_id == Some(parent_run_id) &&
      child.parent_step_id == Some("delegate") &&
      child.depth == parent.depth + 1 else {
      return Err("delegated worker durable lineage is inconsistent")
    }
    let edge = SupervisorWorkerLineageV1::{
      supervisor_id: request.supervisor_id,
      parent_run_id,
      parent_step_id: "delegate",
      worker_run_id: child.id,
      worker_job_id: child.job_id,
      depth: child.depth,
      delegation_ref: encode_child_delegation_v1(delegation),
      recorded_at: request.envelope.issued_at,
    }
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "worker.delegated",
        {
          "lineage": edge,
          "execution_status": "pending_provider",
          "required_provider": "moonclaw-child-run-executor",
        },
        payload={
          "governance_contract": "moonclaw.child-delegation.v1",
          "scheduler": "job.delegate",
          "worker_status": child.status,
        },
        parent_run_id=Some(edge.parent_run_id),
        worker_run_id=Some(edge.worker_run_id),
        lineage=Some(edge),
      ),
    )
  })
}

///|
fn validate_gap(gap : SupervisorGapStatementV1, ids : Array[String]) -> Bool {
  if gap.summary.trim().is_blank() ||
    gap.evidence_refs.is_empty() ||
    (gap.present && (gap.severity < 1 || gap.severity > 5)) ||
    (!gap.present && gap.severity != 0) {
    return false
  }
  let seen : Array[String] = []
  for id in gap.evidence_refs {
    if id.trim().is_blank() || seen.contains(id) || !ids.contains(id) {
      return false
    }
    seen.push(id)
  }
  true
}

///|
fn validate_outcome_evidence(
  value : SupervisorBookkeeperOutcomeEvidenceV1,
) -> Result[Unit, String] {
  let ids : Array[String] = []
  for evidence in value.evidence_refs {
    if evidence.reference_id.trim().is_blank() ||
      evidence.reference_version.trim().is_blank() ||
      !supervisor_digest_valid(evidence.digest) ||
      evidence.provenance_ref.trim().is_blank() ||
      ids.contains(evidence.reference_id) {
      return Err("invalid MoonBook outcome evidence projection")
    }
    ids.push(evidence.reference_id)
  }
  guard value.contract_version ==
    "moonbook.bookkeeper.product_outcome_submission.v1" &&
    value.source_product == "moonclaw" &&
    !value.submission.record_id.trim().is_blank() &&
    !value.submission.record_version.trim().is_blank() &&
    !value.deliverable_title.trim().is_blank() &&
    !value.deliverable_summary.trim().is_blank() &&
    !value.outcome_summary.trim().is_blank() &&
    !value.owner_route.trim().is_blank() &&
    !value.evidence_refs.is_empty() &&
    !value.decision_evidence_id.trim().is_blank() &&
    ids.contains(value.decision_evidence_id) &&
    value.observed_at >= 0 &&
    value.recorded_at >= value.observed_at &&
    supervisor_digest_valid(value.submission.record_digest) &&
    !value.capability_id.trim().is_blank() &&
    !value.capability_version.trim().is_blank() &&
    supervisor_digest_valid(value.capability_change_digest) &&
    !value.capability_summary.trim().is_blank() &&
    validate_gap(value.information_gap, ids) &&
    validate_gap(value.recognition_gap, ids) &&
    validate_gap(value.decisiveness_gap, ids) else {
    return Err("invalid MoonBook outcome evidence projection")
  }
  Ok(())
}

///|
pub async fn SupervisorRuntime::emit_outcome_evidence(
  self : SupervisorRuntime,
  request : SupervisorOutcomeEvidenceRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.outcome-evidence.propose@0.1.5",
        supervisor_outcome_evidence_payload_v1(
          request.supervisor_id,
          request.source_event_ids,
          request.projection,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    match validate_outcome_evidence(request.projection) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    if request.source_event_ids.is_empty() {
      return Err("outcome evidence must cite durable supervisor events")
    }
    for id in request.source_event_ids {
      if !self.events.any(fn(event) {
          event.supervisor_id == request.supervisor_id && event.event_id == id
        }) {
        return Err("outcome evidence must cite durable supervisor events")
      }
    }
    let previous = self.state_for(request.supervisor_id)
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "outcome.evidence.proposed",
        request.projection.to_json(),
        payload={
          "source_event_ids": request.source_event_ids,
          "target_operation": "moonbook/bookkeeper.outcome.submit@0.1.0",
          "input_schema": "moonbook/bookkeeper-product-outcome-submission@1.0.0",
          "final_acceptance": false,
        },
        outcome_evidence=Some(request.projection),
      ),
    )
  })
}

///|
fn SupervisorRuntime::outbox_unacknowledged(
  self : SupervisorRuntime,
  supervisor_id : String,
  now_ms : SupervisorEpochMsV1,
  claimable_only? : Bool = false,
) -> Array[SupervisorBookkeeperOutcomeEvidenceV1] {
  let items : Map[String, SupervisorBookkeeperOutcomeEvidenceV1] = Map([])
  let acknowledged : Map[String, Bool] = Map([])
  let claimed_until : Map[String, SupervisorEpochMsV1] = Map([])
  for event in self.events {
    if event.supervisor_id != supervisor_id {
      continue
    }
    match event.outcome_evidence {
      Some(item) => items.set(item.submission.record_id, item)
      None => ()
    }
    match event.event_type {
      "outcome.outbox.claimed" =>
        match event.payload {
          { "submission_ids": Array(ids), "lease_expires_at": until_json, .. } => {
            let until : SupervisorEpochMsV1 = @json.from_json(until_json) catch {
              _ => continue
            }
            for value in ids {
              match value {
                String(id) => claimed_until.set(id, until)
                _ => ()
              }
            }
          }
          _ => ()
        }
      "outcome.outbox.acknowledged" =>
        match event.payload {
          { "submission_ids": Array(ids), .. } =>
            for value in ids {
              match value {
                String(id) => acknowledged.set(id, true)
                _ => ()
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
  items
  .values()
  .to_array()
  .filter(fn(item) {
    let id = item.submission.record_id
    !acknowledged.contains(id) &&
    (
      !claimable_only ||
      claimed_until.get(id).map(fn(until) { until <= now_ms }).unwrap_or(true)
    )
  })
}

///|
pub async fn SupervisorRuntime::claim_outcome_outbox(
  self : SupervisorRuntime,
  request : SupervisorOutcomeOutboxClaimRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let payload : Json = {
      "supervisor_id": request.supervisor_id,
      "claim_id": request.claim_id,
      "max_items": request.max_items,
      "lease_expires_at": request.lease_expires_at,
    }
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.outcome-outbox.claim@0.1.5",
        payload,
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    guard !request.claim_id.trim().is_blank() &&
      request.max_items > 0 &&
      request.max_items <= 100 &&
      request.lease_expires_at > request.envelope.issued_at else {
      return Err("invalid outcome outbox claim")
    }
    let available = self.outbox_unacknowledged(
      request.supervisor_id,
      request.envelope.issued_at,
      claimable_only=true,
    )
    let claimed = available[:available.length().min(request.max_items)].to_owned()
    let ids = claimed.map(fn(item) { item.submission.record_id })
    let previous = self.state_for(request.supervisor_id)
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "outcome.outbox.claimed",
        { "claim_id": request.claim_id, "items": claimed },
        payload={
          "claim_id": request.claim_id,
          "lease_expires_at": request.lease_expires_at,
          "submission_ids": ids,
          "target_operation": "moonbook/bookkeeper.outcome.submit@0.1.0",
        },
      ),
    )
  })
}

///|
pub async fn SupervisorRuntime::ack_outcome_outbox(
  self : SupervisorRuntime,
  request : SupervisorOutcomeOutboxAckRequestV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let payload : Json = {
      "supervisor_id": request.supervisor_id,
      "claim_id": request.claim_id,
      "submission_ids": request.submission_ids,
      "bookkeeper_receipts": request.bookkeeper_receipts,
    }
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.outcome-outbox.ack@0.1.5",
        payload,
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    let available = self.outbox_unacknowledged(
      request.supervisor_id,
      request.envelope.issued_at,
    )
    guard !request.claim_id.trim().is_blank() &&
      !request.submission_ids.is_empty() &&
      request.bookkeeper_receipts.length() == request.submission_ids.length() &&
      request.submission_ids.all(fn(id) {
        available.any(fn(item) { item.submission.record_id == id })
      }) else {
      return Err("outcome outbox acknowledgement is incomplete or stale")
    }
    let previous = self.state_for(request.supervisor_id)
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    Ok(
      self.commit_unlocked(
        request.envelope,
        state,
        "outcome.outbox.acknowledged",
        payload,
        payload~,
      ),
    )
  })
}

///|
pub fn SupervisorRuntime::status(
  self : SupervisorRuntime,
  supervisor_id : String,
) -> Result[SupervisorStatusProjectionV1, String] {
  let state = match self.states.get(supervisor_id) {
    Some(state) => state
    None => return Err("unknown supervisor: \{supervisor_id}")
  }
  let events = self.events.filter(fn(event) {
    event.supervisor_id == supervisor_id
  })
  let latest = if events.is_empty() {
    None
  } else {
    events.get(events.length() - 1)
  }
  let worker_lineage = self.lineage.filter(fn(edge) {
    edge.supervisor_id == supervisor_id
  })
  let workers : Array[SupervisorWorkerStatusV1] = []
  for edge in worker_lineage {
    match self.worker_status(supervisor_id, edge.worker_run_id) {
      Ok(value) => workers.push(value)
      Err(_) => ()
    }
  }
  Ok({
    contract_id: "moonclaw.supervisor-status.v1",
    state,
    pending_message_count: self
    .mailbox_messages(supervisor_id, state.updated_at)
    .length(),
    worker_lineage,
    workers,
    latest_event: latest,
  })
}

///|
pub fn SupervisorRuntime::list_status(
  self : SupervisorRuntime,
) -> Array[SupervisorStatusProjectionV1] {
  let result : Array[SupervisorStatusProjectionV1] = []
  for state in self.states.values() {
    match self.status(state.supervisor_id) {
      Ok(value) => result.push(value)
      Err(_) => ()
    }
  }
  result
}

///|
pub fn SupervisorRuntime::pending_mailbox(
  self : SupervisorRuntime,
  supervisor_id : String,
  now_ms : SupervisorEpochMsV1,
) -> Array[SupervisorMessageV1] {
  self.mailbox_messages(supervisor_id, now_ms)
}

///|
/// Records successful delivery by the retained daemon executor. This derived
/// journal mutation inherits the already-verified source command and cannot be
/// called for a message without exact durable authority evidence.
pub async fn SupervisorRuntime::record_message_delivery(
  self : SupervisorRuntime,
  supervisor_id : String,
  message_id : String,
  executor_run_id : String,
  delivered_at : SupervisorEpochMsV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let mut source : SupervisorJournalEventV1? = None
    for event in self.events {
      if event.supervisor_id != supervisor_id ||
        !(event.event_type == "message.sent" ||
        event.event_type == "supervisor.steered") {
        continue
      }
      match event.payload {
        { "message": Object(message), .. } =>
          match message.get("message_id") {
            Some(String(id)) if id == message_id => source = Some(event)
            _ => ()
          }
        _ => ()
      }
    }
    let source = match source {
      Some(value) => value
      None => return Err("message delivery has no governed source event")
    }
    if self
      .mailbox_messages(supervisor_id, delivered_at)
      .all(fn(message) { message.message_id != message_id }) {
      return Err("message is already consumed or unknown")
    }
    let command_id = "delivery.\{source.command_id}.\{message_id}"
    match self.receipts.get(command_id) {
      Some(receipt) => return Ok(duplicate_receipt(receipt))
      None => ()
    }
    self.verified_commands.set(command_id, source.authority_verification)
    let envelope = SupervisorCommandEnvelopeV1::{
      contract_id: "moonclaw.supervisor-command.v1",
      command_id,
      request_digest: source.command_digest,
      issued_at: delivered_at,
      evaluated_at: source.authority_verification.verified_at,
      expected_cursor: None,
      authority: {},
    }
    let previous = self.state_for(supervisor_id)
    guard previous.active_run_id == Some(executor_run_id) else {
      return Err(
        "message executor identity does not match active supervisor run",
      )
    }
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: delivered_at,
    }
    self.commit_unlocked(
      envelope,
      state,
      "mailbox.acknowledged",
      { "message_id": message_id, "executor_run_id": executor_run_id },
      payload={
        "claim_id": "daemon-executor",
        "message_ids": [message_id],
        "executor_run_id": executor_run_id,
        "source_event_id": source.event_id,
      },
    )
    |> Ok
  })
}

///|
/// Persists one real provider reply for the earliest delivered supervisor
/// message that has not yet received a reply. The reply inherits the exact
/// authority verification of that source message and grants no new authority.
pub async fn SupervisorRuntime::record_assistant_response(
  self : SupervisorRuntime,
  supervisor_id : String,
  executor_run_id : String,
  content : String,
  provider_evidence : Json,
  responded_at : SupervisorEpochMsV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    guard !content.trim().is_blank() else {
      return Err("supervisor assistant response is blank")
    }
    let previous = self.state_for(supervisor_id)
    guard previous.active_run_id == Some(executor_run_id) else {
      return Err(
        "assistant response executor identity does not match active supervisor run",
      )
    }
    let responded_sources : Map[String, Bool] = Map([])
    for event in self.events {
      if event.supervisor_id == supervisor_id &&
        event.event_type == "supervisor.assistant.responded" {
        match event.payload {
          {
            "assistant_response": {
              "source_event_id": String(source_event_id),
              ..
            },
            ..
          } => responded_sources.set(source_event_id, true)
          _ => ()
        }
      }
    }
    let mut delivery : SupervisorJournalEventV1? = None
    let mut source_event_id : String? = None
    for event in self.events {
      if delivery is Some(_) ||
        event.supervisor_id != supervisor_id ||
        event.event_type != "mailbox.acknowledged" {
        continue
      }
      match event.payload {
        {
          "executor_run_id": String(delivered_by),
          "source_event_id": String(source_id),
          ..
        } if delivered_by == executor_run_id &&
          !responded_sources.contains(source_id) => {
          delivery = Some(event)
          source_event_id = Some(source_id)
        }
        _ => ()
      }
    }
    let delivery = match delivery {
      Some(value) => value
      None =>
        return Err(
          "assistant response has no delivered, unresponded supervisor message",
        )
    }
    let source_event_id = source_event_id.unwrap()
    let mut source : SupervisorJournalEventV1? = None
    for event in self.events {
      if event.supervisor_id == supervisor_id &&
        event.event_id == source_event_id &&
        (
          event.event_type == "message.sent" ||
          event.event_type == "supervisor.steered"
        ) {
        source = Some(event)
      }
    }
    let source = match source {
      Some(value) => value
      None => return Err("assistant response source message is missing")
    }
    let command_id = "assistant-response.\{source.event_id}"
    match self.receipts.get(command_id) {
      Some(receipt) => return Ok(duplicate_receipt(receipt))
      None => ()
    }
    self.verified_commands.set(command_id, source.authority_verification)
    let envelope = SupervisorCommandEnvelopeV1::{
      contract_id: "moonclaw.supervisor-command.v1",
      command_id,
      request_digest: source.command_digest,
      issued_at: responded_at,
      evaluated_at: source.authority_verification.verified_at,
      expected_cursor: None,
      authority: {},
    }
    let response_id = "assistant-response:\{source.event_id}"
    let assistant_response : Json = {
      "contract_id": "moonclaw.supervisor-assistant-response.v1",
      "response_id": response_id,
      "content": content,
      "content_type": "text/plain",
      "conversation_id": source.conversation_id,
      "task_id": source.task_id,
      "source_event_id": source.event_id,
      "delivery_event_id": delivery.event_id,
      "executor_run_id": executor_run_id,
      "responded_at": responded_at,
      "provider_evidence": provider_evidence,
    }
    let state = {
      ..previous,
      cursor: previous.cursor + 1,
      updated_at: responded_at,
    }
    Ok(
      self.commit_unlocked(
        envelope,
        state,
        "supervisor.assistant.responded",
        assistant_response,
        payload={ "assistant_response": assistant_response },
        conversation_id=source.conversation_id,
        task_id=source.task_id,
        parent_run_id=Some(executor_run_id),
      ),
    )
  })
}

///|
pub fn SupervisorRuntime::replay(
  self : SupervisorRuntime,
  supervisor_id : String,
  after_cursor? : Int = 0,
  limit? : Int = 100,
) -> Result[SupervisorReplayResponseV1, String] {
  if self.states.get(supervisor_id) is None {
    return Err("unknown supervisor: \{supervisor_id}")
  }
  if after_cursor < 0 || limit < 1 || limit > 1000 {
    return Err("invalid supervisor replay cursor or limit")
  }
  let all = self.events.filter(fn(event) {
    event.supervisor_id == supervisor_id && event.cursor > after_cursor
  })
  let page = all[:all.length().min(limit)].to_owned()
  let next = if page.is_empty() {
    after_cursor
  } else {
    page[page.length() - 1].cursor
  }
  Ok({
    contract_id: "moonclaw.supervisor-replay.v1",
    supervisor_id,
    after_cursor,
    next_cursor: next,
    has_more: all.length() > page.length(),
    events: page,
  })
}
