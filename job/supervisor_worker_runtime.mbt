///|
fn supervisor_worker_execution_status(status : RunStatus) -> String {
  match status {
    Pending => "pending_provider"
    Running => "running"
    WaitingForInput => "waiting_for_input"
    Succeeded => "succeeded"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
fn validate_supervisor_worker_intent(
  request : SupervisorDelegateIntentRequestV1,
  accounting_mode : String,
) -> Result[Unit, String] {
  let budget = request.scope.budget
  guard !request.supervisor_id.trim().is_blank() &&
    !request.instruction.trim().is_blank() &&
    !request.task.task_id.trim().is_blank() &&
    !request.task.conversation_id.trim().is_blank() &&
    !request.task.title.trim().is_blank() &&
    !request.task.cwd.trim().is_blank() &&
    request.task.metadata is Object(_) &&
    request.scope.artifact_prefixes.length() > 0 &&
    request.scope.artifact_prefixes.length() <= budget.max_artifacts &&
    budget.max_cost_micro_usd >= 0L &&
    budget.max_runtime_ms > 0L &&
    budget.max_runtime_ms <= 86400000L &&
    budget.max_tokens > 0L &&
    budget.max_artifacts > 0 &&
    @capability.wire_timestamp_is_canonical(request.scope.expires_at) &&
    request.envelope.evaluated_at < request.scope.expires_at else {
    return Err("invalid or unbounded supervisor worker intent")
  }
  ignore(delegation_claim_ceiling_from_id(request.scope.claim_ceiling)) catch {
    _ => return Err("unsupported supervisor worker claim ceiling")
  }
  if !request.scope.artifact_prefixes.all(fn(prefix) {
      @capability.evidence_artifact_ref_is_canonical(prefix) &&
      !prefix.contains("*")
    }) {
    return Err("supervisor worker artifact scope is not exact")
  }
  match accounting_mode {
    "local-unmetered" => ()
    "metered-external" =>
      return Err("provider_metering_unavailable: cost_micro_usd")
    _ => return Err("unknown provider accounting mode")
  }
  Ok(())
}

///|
fn SupervisorRuntime::worker_edge(
  self : SupervisorRuntime,
  supervisor_id : String,
  worker_run_id : String,
) -> Result[SupervisorWorkerLineageV1, String] {
  for edge in self.lineage {
    if edge.supervisor_id == supervisor_id &&
      edge.worker_run_id == worker_run_id {
      return Ok(edge)
    }
  }
  Err("target worker is not persisted supervisor lineage")
}

///|
fn SupervisorRuntime::validate_worker_capacity(
  self : SupervisorRuntime,
  state : SupervisorStateV1,
) -> Result[Unit, String] {
  let max_active_workers = match state.profile.runtime_binding {
    { "max_active_workers": Number(value, ..), .. } => value.to_int()
    _ =>
      return Err(
        "immutable supervisor runtime binding must declare max_active_workers",
      )
  }
  guard max_active_workers > 0 && max_active_workers <= 128 else {
    return Err("invalid immutable max_active_workers binding")
  }
  let mut active = 0
  for edge in self.lineage {
    if edge.supervisor_id != state.supervisor_id {
      continue
    }
    match self.runtime.store().get_run(edge.worker_run_id) {
      Some(run) if run.status is Pending ||
        run.status is Running ||
        run.status is WaitingForInput => active = active + 1
      _ => ()
    }
  }
  if active >= max_active_workers {
    Err(
      "supervisor max_active_workers reached: \{active}/\{max_active_workers}",
    )
  } else {
    Ok(())
  }
}

///|
fn SupervisorRuntime::prepared_worker(
  self : SupervisorRuntime,
  receipt : SupervisorCommandReceiptV1,
) -> Result[SupervisorDelegateIntentPreparedV1, String] {
  guard receipt.response
    is {
      "worker_run_id": String(worker_run_id),
      "worker_job_id": String(worker_job_id),
      "delegation": delegation,
      ..
    } else {
    return Err("durable delegation receipt is incomplete")
  }
  let run = match self.runtime.store().get_run(worker_run_id) {
    Some(value) => value
    None => return Err("durable delegated worker run is missing")
  }
  Ok({
    receipt,
    worker_run_id,
    worker_job_id,
    execution_status: supervisor_worker_execution_status(run.status),
    delegation,
  })
}

///|
pub async fn SupervisorRuntime::verify_delegate_intent(
  self : SupervisorRuntime,
  request : SupervisorDelegateIntentRequestV1,
  accounting_mode : String,
) -> Result[SupervisorDelegateIntentPreparedV1?, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.delegate@0.1.5",
        supervisor_delegate_intent_payload_v1(
          request.supervisor_id,
          request.instruction,
          request.task,
          request.scope,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) =>
        match self.prepared_worker(receipt) {
          Ok(value) => return Ok(Some(value))
          Err(error) => return Err(error)
        }
      Ok(None) => ()
    }
    match validate_supervisor_worker_intent(request, accounting_mode) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let state = self.state_for(request.supervisor_id)
    guard (state.lifecycle is Running || state.lifecycle is Dormant) &&
      state.active_run_id is Some(_) else {
      return Err("delegation requires an active or wakeable supervisor")
    }
    match self.validate_worker_capacity(state) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    Ok(None)
  })
}

///|
pub async fn SupervisorRuntime::delegate_intent(
  self : SupervisorRuntime,
  request : SupervisorDelegateIntentRequestV1,
  worker_run_id : String,
  accounting_mode : String,
) -> Result[SupervisorDelegateIntentPreparedV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match
      self.validate_envelope(
        request.envelope,
        "moonclaw/supervisor.delegate@0.1.5",
        supervisor_delegate_intent_payload_v1(
          request.supervisor_id,
          request.instruction,
          request.task,
          request.scope,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    match self.preflight(request.envelope, request.supervisor_id, true) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) =>
        return self.prepared_worker(duplicate_receipt(receipt))
      Ok(None) => ()
    }
    match validate_supervisor_worker_intent(request, accounting_mode) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    let previous = self.state_for(request.supervisor_id)
    match self.validate_worker_capacity(previous) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    let parent_run_id = match previous.active_run_id {
      Some(value) if previous.lifecycle is Running => value
      Some(value) if previous.lifecycle is Dormant =>
        match
          self.resume_bound_run(
            request.supervisor_id,
            Some(value),
            supervisor_native_runtime_timestamp(),
          ) {
          Ok(Some(resumed)) => resumed
          Ok(None) => return Err("failed to wake canonical supervisor run")
          Err(error) => return Err(error)
        }
      _ => return Err("delegation requires an active or wakeable supervisor")
    }
    let parent = match self.runtime.store().get_run(parent_run_id) {
      Some(value) => value
      None => return Err("canonical supervisor run is missing")
    }
    let definition = match self.runtime.store().get_definition(parent.job_id) {
      Some(value) => value
      None => return Err("canonical supervisor job definition is missing")
    }
    let workflow = match
      definition.workflow_id.bind(fn(id) {
        self.runtime.store().get_workflow(id)
      }) {
      Some(value) => value
      None => return Err("canonical supervisor workflow is missing")
    }
    guard workflow.steps.any(fn(step) {
      step.id == "delegate" && step.kind == "job.delegate"
    }) else {
      return Err("supervisor workflow has no job.delegate step")
    }
    guard !worker_run_id.trim().is_blank() else {
      return Err("provider did not supply a real worker task identity")
    }
    let suffix = request.envelope.request_digest[7:31].to_owned()
    let worker_job_id = "moonclaw.supervisor-worker.\{suffix}"
    let child_principal = @capability.principal_ref_v1(
      "supervisor-worker-\{suffix}",
      @capability.Agent,
      "moonclaw",
      worker_run_id,
    )
    let authority = @capability.authority_decision_ref_v1(
      "worker-authority-\{suffix}",
      child_principal,
      request.envelope.request_digest,
      request.envelope.evaluated_at,
      request.scope.expires_at,
    )
    let operation = @capability.operation_ref(
      "moonclaw", "job.delegate", "0.1.5",
    )
    let budget = @capability.handover_budget_ceilings_v1(
      max_cost_micro_usd=request.scope.budget.max_cost_micro_usd,
      max_runtime_ms=request.scope.budget.max_runtime_ms,
      max_tokens=request.scope.budget.max_tokens,
      max_artifacts=request.scope.budget.max_artifacts,
    )
    let delegation = issue_child_delegation_v1(
      "worker-delegation-\{suffix}",
      parent_run_id,
      worker_run_id,
      self.receiver,
      child_principal,
      [operation],
      request.scope.artifact_prefixes,
      delegation_claim_ceiling_from_id(request.scope.claim_ceiling),
      budget,
      authority,
      request.envelope.evaluated_at,
      request.scope.expires_at,
    ) catch {
      error => return Err("failed to issue bounded child delegation: \{error}")
    }
    let encoded_delegation = encode_child_delegation_v1(delegation)
    let restored = decode_child_delegation_v1(encoded_delegation) catch {
      error =>
        return Err("failed to validate bounded child delegation: \{error}")
    }
    guard restored == delegation else {
      return Err("bounded child delegation did not round-trip exactly")
    }
    let metering_evidence = @capability.content_addressed_evidence_ref(
      "supervisor-workers/\{suffix}/delegation-use.json",
      request.envelope.request_digest,
    ) catch {
      error =>
        return Err("invalid delegation metering evidence: \{to_repr(error)}")
    }
    let consumption = child_delegation_consumption_v1(
      accumulated_cost_micro_usd=0L,
      requested_cost_micro_usd=0L,
      accumulated_runtime_ms=0L,
      requested_runtime_ms=request.scope.budget.max_runtime_ms,
      accumulated_tokens=0L,
      requested_tokens=request.scope.budget.max_tokens,
      accumulated_artifacts=0,
      requested_artifacts=request.scope.artifact_prefixes.length(),
      metering_evidence,
    ) catch {
      error => return Err("invalid delegation consumption: \{error}")
    }
    let authorization = match
      authorize_child_delegation_use_v1(
        delegation,
        child_principal,
        worker_run_id,
        operation,
        request.scope.artifact_prefixes,
        delegation_claim_ceiling_from_id(request.scope.claim_ceiling),
        consumption,
        request.envelope.evaluated_at,
      ) {
      Ok(value) => value
      Err(error) =>
        return Err("child provider authorization failed closed: \{error}")
    }
    let authorization_evidence = encode_child_delegation_use_receipt_v1(
      authorization,
    )
    let runtime_timestamp = supervisor_native_runtime_timestamp()
    let timestamp_correlation : Json = {
      "issued_at_ms": request.envelope.issued_at,
      "runtime_timestamp": runtime_timestamp,
    }
    if self.runtime.store().get_definition(worker_job_id) is None {
      self.runtime.register_definition({
        id: worker_job_id,
        kind: "job.supervisor-worker",
        enabled: true,
        config: {
          "supervisor_id": request.supervisor_id,
          "intent": supervisor_delegate_intent_payload_v1(
            request.supervisor_id,
            request.instruction,
            request.task,
            request.scope,
          ),
          "delegation": encoded_delegation,
          "provider_task_id": worker_run_id,
          "authorization": authorization_evidence,
          "accounting_mode": accounting_mode,
          "timestamp_correlation": timestamp_correlation,
          "provider_metering": {
            "accounting_mode": accounting_mode,
            "cost_micro_usd": "zero_billable_cost",
            "requested_cost_micro_usd": 0,
            "runtime_ms": "enforced_by_daemon_deadline",
            "tokens": "verified_from_provider_result",
            "artifacts": "verified_from_provider_result",
          },
        },
        schedule: None,
        retry_policy: Some({ max_attempts: 3, backoff_ms: Some(1000) }),
        workflow_id: None,
        created_at: runtime_timestamp,
        updated_at: runtime_timestamp,
        tags: ["supervisor-worker", "delegated", "moonclaw-task"],
      })
    }
    let child = match self.runtime.store().get_run(worker_run_id) {
      Some(value) => value
      None =>
        match
          self.runtime.trigger_definition(
            worker_run_id,
            worker_job_id,
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
    guard child.job_id == worker_job_id &&
      child.parent_run_id == Some(parent_run_id) &&
      child.parent_step_id == Some("delegate") &&
      child.depth == parent.depth + 1 else {
      return Err("delegated worker durable lineage is inconsistent")
    }
    let edge = SupervisorWorkerLineageV1::{
      supervisor_id: request.supervisor_id,
      parent_run_id,
      parent_step_id: "delegate",
      worker_run_id,
      worker_job_id,
      depth: child.depth,
      delegation_ref: encoded_delegation,
      recorded_at: request.envelope.issued_at,
    }
    let state = {
      ..previous,
      lifecycle: SupervisorLifecycleV1::Running,
      cursor: previous.cursor + 1,
      updated_at: request.envelope.issued_at,
    }
    let receipt = self.commit_unlocked(
      request.envelope,
      state,
      "worker.delegated",
      {
        "worker_run_id": worker_run_id,
        "worker_job_id": worker_job_id,
        "provider_task_id": worker_run_id,
        "execution_status": "pending_provider",
        "run_status": child.status,
        "lineage": edge,
        "delegation": encoded_delegation,
        "authorization": authorization_evidence,
        "accounting_mode": accounting_mode,
        "timestamp_correlation": timestamp_correlation,
      },
      payload={
        "intent": supervisor_delegate_intent_payload_v1(
          request.supervisor_id,
          request.instruction,
          request.task,
          request.scope,
        ),
        "provider_task_id": worker_run_id,
        "authorization": authorization_evidence,
        "accounting_mode": accounting_mode,
        "scheduler": "job.delegate",
        "timestamp_correlation": timestamp_correlation,
      },
      conversation_id=Some(request.task.conversation_id),
      task_id=Some(request.task.task_id),
      parent_run_id=Some(parent_run_id),
      worker_run_id=Some(worker_run_id),
      lineage=Some(edge),
    )
    Ok({
      receipt,
      worker_run_id,
      worker_job_id,
      execution_status: "pending_provider",
      delegation: encoded_delegation,
    })
  })
}

///|
fn SupervisorRuntime::worker_source_event(
  self : SupervisorRuntime,
  supervisor_id : String,
  worker_run_id : String,
) -> Result[SupervisorJournalEventV1, String] {
  for event in self.events {
    if event.supervisor_id == supervisor_id &&
      event.event_type == "worker.delegated" &&
      event.worker_run_id == Some(worker_run_id) {
      return Ok(event)
    }
  }
  Err("worker lifecycle has no governed delegation event")
}

///|
fn SupervisorRuntime::worker_accounting_mode(
  self : SupervisorRuntime,
  supervisor_id : String,
  worker_run_id : String,
) -> Result[String, String] {
  let source = match self.worker_source_event(supervisor_id, worker_run_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match source.receipt.response {
    { "accounting_mode": String(value), .. } => Ok(value)
    _ => Err("delegated worker has no runtime-owned accounting resolution")
  }
}

///|
async fn SupervisorRuntime::commit_worker_derived(
  self : SupervisorRuntime,
  source : SupervisorJournalEventV1,
  command_id : String,
  event_type : String,
  response : Json,
  payload : Json,
  timestamp : SupervisorEpochMsV1,
) -> SupervisorCommandReceiptV1 {
  self.verified_commands.set(command_id, source.authority_verification)
  let envelope = SupervisorCommandEnvelopeV1::{
    contract_id: "moonclaw.supervisor-command.v1",
    command_id,
    request_digest: source.command_digest,
    issued_at: timestamp,
    evaluated_at: source.authority_verification.verified_at,
    expected_cursor: None,
    authority: {},
  }
  let previous = self.state_for(source.supervisor_id)
  let state = { ..previous, cursor: previous.cursor + 1, updated_at: timestamp }
  self.commit_unlocked(
    envelope,
    state,
    event_type,
    response,
    payload~,
    parent_run_id=source.parent_run_id,
    worker_run_id=source.worker_run_id,
  )
}

///|
pub async fn SupervisorRuntime::record_worker_provider_acceptance(
  self : SupervisorRuntime,
  supervisor_id : String,
  worker_run_id : String,
  provider_evidence : Json,
  accepted_at : SupervisorEpochMsV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    let edge = match self.worker_edge(supervisor_id, worker_run_id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let source = match self.worker_source_event(supervisor_id, worker_run_id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let run = match self.runtime.store().get_run(worker_run_id) {
      Some(value) => value
      None => return Err("delegated worker run is missing")
    }
    let accounting_mode = match
      self.worker_accounting_mode(supervisor_id, worker_run_id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let command_id = "provider.accepted.\{worker_run_id}.\{run.attempt}"
    match self.receipts.get(command_id) {
      Some(receipt) => return Ok(duplicate_receipt(receipt))
      None => ()
    }
    guard run.status is Pending else {
      return Err("provider acceptance is stale for worker state")
    }
    let runtime_timestamp = supervisor_native_runtime_timestamp()
    let timestamp_correlation : Json = {
      "issued_at_ms": accepted_at,
      "runtime_timestamp": runtime_timestamp,
    }
    let started = match
      self.runtime.mark_run_started(worker_run_id, runtime_timestamp) {
      Some(value) => value
      None => return Err("failed to start accepted worker run")
    }
    Ok(
      self.commit_worker_derived(
        source,
        command_id,
        "worker.provider.accepted",
        {
          "worker_run_id": edge.worker_run_id,
          "worker_job_id": edge.worker_job_id,
          "provider_task_id": worker_run_id,
          "execution_status": "running",
          "run_status": started.status,
          "provider_evidence": provider_evidence,
          "accounting_mode": accounting_mode,
          "timestamp_correlation": timestamp_correlation,
        },
        {
          "provider_evidence": provider_evidence,
          "accounting_mode": accounting_mode,
          "timestamp_correlation": timestamp_correlation,
        },
        accepted_at,
      ),
    )
  })
}

///|
fn supervisor_worker_total_tokens(provider_evidence : Json) -> Int64? {
  match provider_evidence {
    { "total_tokens": Number(value, ..), .. } => Some(value.to_int64())
    {
      "assistant_event": {
        "desc": { "usage": { "total_tokens": Number(value, ..), .. }, .. },
        ..
      },
      ..
    } => Some(value.to_int64())
    _ => None
  }
}

///|
fn supervisor_worker_artifact_evidence(
  result : String,
) -> Result[(Array[String], Array[Json]), String] {
  let parsed = @json.parse(result) catch {
    _ =>
      return Err(
        "provider_metering_unavailable: artifact_evidence must be explicit JSON",
      )
  }
  guard parsed is { "artifact_evidence": Array(items), .. } else {
    return Err(
      "provider_metering_unavailable: artifact_evidence must be explicit JSON",
    )
  }
  let refs : Array[String] = []
  let evidence : Array[Json] = []
  for item in items {
    guard item is Object(fields) else {
      return Err(
        "provider artifact evidence requires artifact_ref/path and digest",
      )
    }
    let reference = match fields.get("artifact_ref") {
      Some(String(value)) => value
      _ =>
        match fields.get("path") {
          Some(String(value)) => value
          _ =>
            return Err(
              "provider artifact evidence requires artifact_ref/path and digest",
            )
        }
    }
    let raw_digest = match fields.get("digest") {
      Some(String(value)) => value
      _ =>
        match fields.get("sha256") {
          Some(String(value)) => value
          _ =>
            return Err(
              "provider artifact evidence requires artifact_ref/path and digest",
            )
        }
    }
    let digest = if raw_digest.has_prefix("sha256:") {
      raw_digest
    } else {
      "sha256:\{raw_digest}"
    }
    if !@capability.evidence_artifact_ref_is_canonical(reference) ||
      !supervisor_digest_valid(digest) ||
      refs.contains(reference) {
      return Err(
        "provider artifact evidence is not content-addressed and exact",
      )
    }
    refs.push(reference)
    fields["digest"] = Json::string(digest)
    evidence.push(Json::object(fields))
  }
  Ok((refs, evidence))
}

///|
/// A worker may prepare review evidence, but cannot review or submit it. Every
/// candidate evidence reference must resolve to the exact verified artifact
/// reference and digest returned by the provider result.
fn supervisor_worker_outcome_candidate(
  result : String,
  artifact_evidence : Array[Json],
) -> Result[SupervisorBookkeeperOutcomeEvidenceV1?, String] {
  let parsed = @json.parse(result) catch { _ => return Ok(None) }
  let candidate_json = match parsed {
    { "outcome_evidence_candidate": value, .. } => value
    _ => return Ok(None)
  }
  if candidate_json is Null {
    return Ok(None)
  }
  let candidate : SupervisorBookkeeperOutcomeEvidenceV1 = @json.from_json(
    candidate_json,
  ) catch {
    _ => return Err("worker outcome evidence candidate has an invalid shape")
  }
  match validate_outcome_evidence(candidate) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  for reference in candidate.evidence_refs {
    let bound = artifact_evidence.any(fn(artifact) {
      match artifact {
        { "artifact_ref": String(artifact_ref), "digest": String(digest), .. } =>
          artifact_ref == reference.reference_id && digest == reference.digest
        { "path": String(path), "digest": String(digest), .. } =>
          path == reference.reference_id && digest == reference.digest
        _ => false
      }
    })
    if !bound {
      return Err(
        "worker outcome evidence candidate is not bound to verified artifact evidence",
      )
    }
  }
  Ok(Some(candidate))
}

///|
pub async fn SupervisorRuntime::record_worker_provider_terminal(
  self : SupervisorRuntime,
  supervisor_id : String,
  worker_run_id : String,
  succeeded : Bool,
  result : String,
  provider_evidence : Json,
  finished_at : SupervisorEpochMsV1,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    self.reload_unlocked()
    match self.worker_edge(supervisor_id, worker_run_id) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    let source = match self.worker_source_event(supervisor_id, worker_run_id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let run = match self.runtime.store().get_run(worker_run_id) {
      Some(value) => value
      None => return Err("delegated worker run is missing")
    }
    let intent = match self.worker_intent(supervisor_id, worker_run_id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let accounting_mode = match
      self.worker_accounting_mode(supervisor_id, worker_run_id) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let mut effective_success = succeeded
    let mut effective_result = result
    let artifact_refs : Array[String] = []
    let artifact_evidence : Array[Json] = []
    let mut total_tokens : Int64? = None
    let mut token_budget_assurance = "verified"
    let mut outcome_evidence_candidate : SupervisorBookkeeperOutcomeEvidenceV1? = None
    let mut outcome_evidence_error : String? = None
    let runtime_timestamp = supervisor_native_runtime_timestamp()
    let runtime_ms = runtime_timestamp -
      run.started_at.unwrap_or(runtime_timestamp)
    if succeeded {
      if runtime_ms < 0 ||
        runtime_ms.to_int64() > intent.scope.budget.max_runtime_ms {
        effective_success = false
        effective_result = "provider runtime budget exceeded: \{runtime_ms}"
      }
      match supervisor_worker_total_tokens(provider_evidence) {
        Some(value) if value >= 0L && value <= intent.scope.budget.max_tokens =>
          total_tokens = Some(value)
        Some(value) => {
          effective_success = false
          effective_result = "provider token budget exceeded: \{value}"
        }
        None =>
          // The local daemon provider does not guarantee usage telemetry on
          // every backend. Runtime and artifact ceilings remain enforced; the
          // missing token dimension is durable and visible instead of turning
          // every otherwise-valid local result into a false provider failure.
          token_budget_assurance = "degraded_tokens_unavailable"
      }
      match supervisor_worker_artifact_evidence(result) {
        Ok((refs, evidence)) =>
          if refs.length() > intent.scope.budget.max_artifacts ||
            !refs.all(fn(reference) {
              intent.scope.artifact_prefixes.any(fn(prefix) {
                child_prefix_is_within(reference, prefix)
              })
            }) {
            effective_success = false
            effective_result = "provider artifact budget or scope exceeded"
          } else {
            artifact_refs.append(refs)
            artifact_evidence.append(evidence)
          }
        Err(error) => {
          effective_success = false
          effective_result = error
        }
      }
      if effective_success {
        match supervisor_worker_outcome_candidate(result, artifact_evidence) {
          Ok(candidate) => outcome_evidence_candidate = candidate
          Err(error) => outcome_evidence_error = Some(error)
        }
      }
    }
    let terminal = if effective_success { "succeeded" } else { "failed" }
    let command_id = "provider.\{terminal}.\{worker_run_id}.\{run.attempt}"
    match self.receipts.get(command_id) {
      Some(receipt) => return Ok(duplicate_receipt(receipt))
      None => ()
    }
    guard run.status is Running else {
      return Err("provider terminal result is stale for worker state")
    }
    let updated = if effective_success {
      self.runtime.mark_run_succeeded(
        worker_run_id,
        runtime_timestamp,
        summary=Some(effective_result),
      )
    } else {
      self.runtime.mark_run_failed(
        worker_run_id,
        runtime_timestamp,
        effective_result,
        summary=Some("MoonClaw worker provider failed"),
      )
    }
    let updated = match updated {
      Some(value) => value
      None => return Err("failed to persist provider terminal result")
    }
    let result_evidence : Json = {
      "contract_id": "moonclaw.supervisor-worker-result-evidence.v1",
      "worker_run_id": worker_run_id,
      "attempt": run.attempt,
      "content_digest": @capability.sha256_digest_ref_v1(
        @encoding/utf8.encode(result),
      ).text(),
      "total_tokens": total_tokens,
      "artifact_evidence": artifact_evidence,
      "outcome_evidence_candidate": outcome_evidence_candidate,
      "outcome_evidence_error": outcome_evidence_error,
      "timestamp_correlation": {
        "issued_at_ms": finished_at,
        "runtime_timestamp": runtime_timestamp,
      },
      "metering": {
        "accounting_mode": accounting_mode,
        "cost_micro_usd": "zero_billable_cost",
        "charged_cost_micro_usd": 0,
        "runtime_ms": runtime_ms,
        "tokens": token_budget_assurance,
        "artifacts": "verified",
      },
      "provider_evidence": provider_evidence,
    }
    Ok(
      self.commit_worker_derived(
        source,
        command_id,
        "worker.provider.\{terminal}",
        {
          "worker_run_id": worker_run_id,
          "provider_task_id": worker_run_id,
          "execution_status": terminal,
          "run_status": updated.status,
          "result": effective_result,
          "result_evidence": result_evidence,
          "outcome_evidence_status": if effective_success {
            if outcome_evidence_candidate is Some(_) {
              "review_ready"
            } else {
              "outcome_evidence_required"
            }
          } else {
            "not_applicable"
          },
          "outcome_evidence_candidate": outcome_evidence_candidate,
          "outcome_evidence_error": outcome_evidence_error,
          "provider_evidence": provider_evidence,
          "accounting_mode": accounting_mode,
          "timestamp_correlation": {
            "issued_at_ms": finished_at,
            "runtime_timestamp": runtime_timestamp,
          },
        },
        {
          "result": effective_result,
          "result_evidence": result_evidence,
          "artifact_refs": artifact_refs,
          "artifact_evidence": artifact_evidence,
          "outcome_evidence_status": if effective_success {
            if outcome_evidence_candidate is Some(_) {
              "review_ready"
            } else {
              "outcome_evidence_required"
            }
          } else {
            "not_applicable"
          },
          "outcome_evidence_candidate": outcome_evidence_candidate,
          "outcome_evidence_error": outcome_evidence_error,
          "provider_evidence": provider_evidence,
          "accounting_mode": accounting_mode,
          "timestamp_correlation": {
            "issued_at_ms": finished_at,
            "runtime_timestamp": runtime_timestamp,
          },
        },
        finished_at,
      ),
    )
  })
}

///|
pub fn SupervisorRuntime::worker_status(
  self : SupervisorRuntime,
  supervisor_id : String,
  worker_run_id : String,
) -> Result[SupervisorWorkerStatusV1, String] {
  let edge = match self.worker_edge(supervisor_id, worker_run_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let run = match self.runtime.store().get_run(worker_run_id) {
    Some(value) => value
    None => return Err("delegated worker run is missing")
  }
  let mut result_evidence : Json? = None
  let mut authorization : Json = {}
  let mut accounting_mode = "unresolved"
  let artifact_refs : Array[String] = []
  let artifact_evidence : Array[Json] = []
  let mut outcome_source_event_id : String? = None
  let mut outcome_evidence_status = if run.status is Succeeded {
    "outcome_evidence_required"
  } else {
    "not_ready"
  }
  let mut outcome_evidence_candidate : SupervisorBookkeeperOutcomeEvidenceV1? = None
  for event in self.events {
    if event.supervisor_id == supervisor_id &&
      event.worker_run_id == Some(worker_run_id) &&
      event.event_type == "worker.delegated" {
      match event.receipt.response {
        {
          "authorization": value,
          "accounting_mode": String(resolved_accounting_mode),
          ..
        } => {
          authorization = value
          accounting_mode = resolved_accounting_mode
        }
        _ => ()
      }
    }
    if event.supervisor_id == supervisor_id &&
      event.worker_run_id == Some(worker_run_id) &&
      event.event_type == "worker.provider.succeeded" {
      match event.payload {
        {
          "outcome_evidence_status": String(status),
          "outcome_evidence_candidate": candidate_json,
          ..
        } if status == "review_ready" => {
          let candidate : SupervisorBookkeeperOutcomeEvidenceV1 = @json.from_json(
            candidate_json,
          ) catch {
            _ => continue
          }
          outcome_evidence_status = "review_ready"
          outcome_evidence_candidate = Some(candidate)
        }
        _ => ()
      }
      match event.payload {
        {
          "result_evidence": evidence,
          "artifact_refs": Array(refs),
          "artifact_evidence": Array(artifacts),
          ..
        } => {
          result_evidence = Some(evidence)
          artifact_refs.clear()
          for reference in refs {
            match reference {
              String(value) => artifact_refs.push(value)
              _ => ()
            }
          }
          artifact_evidence.clear()
          for artifact in artifacts {
            artifact_evidence.push(artifact)
          }
          outcome_source_event_id = Some(event.event_id)
        }
        { "result_evidence": evidence, .. } => {
          result_evidence = Some(evidence)
          outcome_source_event_id = Some(event.event_id)
        }
        _ => ()
      }
    }
  }
  Ok({
    contract_id: "moonclaw.supervisor-worker-status.v1",
    supervisor_id,
    parent_run_id: edge.parent_run_id,
    parent_step_id: edge.parent_step_id,
    worker_run_id,
    worker_job_id: edge.worker_job_id,
    provider_task_id: worker_run_id,
    run_status: run.status,
    execution_status: supervisor_worker_execution_status(run.status),
    attempt: run.attempt,
    accounting_mode,
    started_at: run.started_at,
    finished_at: run.finished_at,
    delegation: edge.delegation_ref,
    authorization,
    summary: run.summary,
    error: run.error,
    result_evidence,
    artifact_refs,
    artifact_evidence,
    outcome_evidence_status,
    outcome_source_event_id,
    outcome_evidence_candidate,
  })
}

///|
pub fn SupervisorRuntime::worker_intent(
  self : SupervisorRuntime,
  supervisor_id : String,
  worker_run_id : String,
) -> Result[SupervisorDelegateIntentRequestV1, String] {
  match self.worker_edge(supervisor_id, worker_run_id) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  for event in self.events {
    if event.supervisor_id == supervisor_id &&
      event.worker_run_id == Some(worker_run_id) {
      match event.payload {
        { "intent": intent, .. } => {
          guard intent
            is {
              "supervisor_id": String(intent_supervisor_id),
              "instruction": String(instruction),
              "task": task_json,
              "scope": scope_json,
              ..
            } else {
            return Err("durable worker intent is invalid")
          }
          let task : SupervisorWorkerTaskV1 = @json.from_json(task_json) catch {
            _ => return Err("durable worker task metadata is invalid")
          }
          let scope : SupervisorWorkerScopeV1 = @json.from_json(scope_json) catch {
            _ => return Err("durable worker scope is invalid")
          }
          return Ok({
            envelope: {
              contract_id: "moonclaw.supervisor-command.v1",
              command_id: event.command_id,
              request_digest: event.command_digest,
              issued_at: event.timestamp,
              evaluated_at: event.authority_verification.verified_at,
              expected_cursor: None,
              authority: {},
            },
            supervisor_id: intent_supervisor_id,
            instruction,
            task,
            scope,
          })
        }
        _ => ()
      }
    }
  }
  Err("durable worker intent is missing")
}

///|
async fn SupervisorRuntime::verify_worker_command(
  self : SupervisorRuntime,
  envelope : SupervisorCommandEnvelopeV1,
  supervisor_id : String,
  worker_run_id : String,
  operation : String,
  payload : Json,
) -> Result[SupervisorCommandReceiptV1?, String] {
  self.reload_unlocked()
  match self.validate_envelope(envelope, operation, payload) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.preflight(envelope, supervisor_id, true) {
    Err(error) => return Err(error)
    Ok(Some(receipt)) => return Ok(Some(receipt))
    Ok(None) => ()
  }
  match self.worker_edge(supervisor_id, worker_run_id) {
    Ok(_) => Ok(None)
    Err(error) => Err(error)
  }
}

///|
pub async fn SupervisorRuntime::verify_worker_steer(
  self : SupervisorRuntime,
  request : SupervisorWorkerSteerRequestV1,
) -> Result[SupervisorCommandReceiptV1?, String] {
  self.with_lock(async fn() {
    if request.instruction.trim().is_blank() || !(request.metadata is Object(_)) {
      return Err("invalid worker steer instruction")
    }
    match
      self.verify_worker_command(
        request.envelope,
        request.supervisor_id,
        request.worker_run_id,
        "moonclaw/supervisor.worker.steer@0.1.5",
        supervisor_worker_steer_payload_v1(
          request.supervisor_id,
          request.worker_run_id,
          request.instruction,
          request.metadata,
        ),
      ) {
      Ok(None) =>
        match self.runtime.store().get_run(request.worker_run_id) {
          Some(run) if run.status is Running => Ok(None)
          _ => Err("worker steer requires a running provider")
        }
      other => other
    }
  })
}

///|
pub async fn SupervisorRuntime::worker_steer(
  self : SupervisorRuntime,
  request : SupervisorWorkerSteerRequestV1,
  provider_evidence : Json,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    match
      self.verify_worker_command(
        request.envelope,
        request.supervisor_id,
        request.worker_run_id,
        "moonclaw/supervisor.worker.steer@0.1.5",
        supervisor_worker_steer_payload_v1(
          request.supervisor_id,
          request.worker_run_id,
          request.instruction,
          request.metadata,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    let run = match self.runtime.store().get_run(request.worker_run_id) {
      Some(value) => value
      None => return Err("delegated worker run is missing")
    }
    guard run.status is Running else {
      return Err("worker steer requires a running provider")
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
        "worker.steered",
        {
          "worker_run_id": request.worker_run_id,
          "execution_status": "running",
          "provider_evidence": provider_evidence,
        },
        payload={
          "instruction": request.instruction,
          "metadata": request.metadata,
          "provider_evidence": provider_evidence,
        },
        worker_run_id=Some(request.worker_run_id),
      ),
    )
  })
}

///|
pub async fn SupervisorRuntime::verify_worker_stop(
  self : SupervisorRuntime,
  request : SupervisorWorkerStopRequestV1,
) -> Result[SupervisorCommandReceiptV1?, String] {
  self.with_lock(async fn() {
    if request.reason.trim().is_blank() {
      return Err("worker stop reason must not be blank")
    }
    match
      self.verify_worker_command(
        request.envelope,
        request.supervisor_id,
        request.worker_run_id,
        "moonclaw/supervisor.worker.stop@0.1.5",
        supervisor_worker_stop_payload_v1(
          request.supervisor_id,
          request.worker_run_id,
          request.reason,
          request.force,
        ),
      ) {
      Ok(None) =>
        match self.runtime.store().get_run(request.worker_run_id) {
          Some(run) if run.status is Pending ||
            run.status is Running ||
            run.status is WaitingForInput => Ok(None)
          _ => Err("worker stop requires a nonterminal provider")
        }
      other => other
    }
  })
}

///|
pub async fn SupervisorRuntime::worker_stop(
  self : SupervisorRuntime,
  request : SupervisorWorkerStopRequestV1,
  provider_evidence : Json,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    match
      self.verify_worker_command(
        request.envelope,
        request.supervisor_id,
        request.worker_run_id,
        "moonclaw/supervisor.worker.stop@0.1.5",
        supervisor_worker_stop_payload_v1(
          request.supervisor_id,
          request.worker_run_id,
          request.reason,
          request.force,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    let stopped = match
      self.runtime.cancel_run(
        request.worker_run_id,
        supervisor_native_runtime_timestamp(),
        summary=Some(request.reason),
      ) {
      Some(value) => value
      None => return Err("delegated worker run is missing")
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
        "worker.stopped",
        {
          "worker_run_id": request.worker_run_id,
          "execution_status": "cancelled",
          "run_status": stopped.status,
          "provider_evidence": provider_evidence,
        },
        payload={
          "reason": request.reason,
          "force": request.force,
          "provider_evidence": provider_evidence,
        },
        worker_run_id=Some(request.worker_run_id),
      ),
    )
  })
}

///|
pub async fn SupervisorRuntime::verify_worker_retry(
  self : SupervisorRuntime,
  request : SupervisorWorkerRetryRequestV1,
) -> Result[SupervisorCommandReceiptV1?, String] {
  self.with_lock(async fn() {
    if request.reason.trim().is_blank() {
      return Err("worker retry reason must not be blank")
    }
    match
      self.verify_worker_command(
        request.envelope,
        request.supervisor_id,
        request.worker_run_id,
        "moonclaw/supervisor.worker.retry-resume@0.1.5",
        supervisor_worker_retry_payload_v1(
          request.supervisor_id,
          request.worker_run_id,
          request.reason,
        ),
      ) {
      Ok(None) =>
        match self.runtime.store().get_run(request.worker_run_id) {
          Some(run) if run.status is Failed || run.status is Cancelled =>
            Ok(None)
          _ =>
            Err("worker retry requires a failed or cancelled provider result")
        }
      other => other
    }
  })
}

///|
pub async fn SupervisorRuntime::worker_retry(
  self : SupervisorRuntime,
  request : SupervisorWorkerRetryRequestV1,
  provider_evidence : Json,
) -> Result[SupervisorCommandReceiptV1, String] {
  self.with_lock(async fn() {
    match
      self.verify_worker_command(
        request.envelope,
        request.supervisor_id,
        request.worker_run_id,
        "moonclaw/supervisor.worker.retry-resume@0.1.5",
        supervisor_worker_retry_payload_v1(
          request.supervisor_id,
          request.worker_run_id,
          request.reason,
        ),
      ) {
      Err(error) => return Err(error)
      Ok(Some(receipt)) => return Ok(receipt)
      Ok(None) => ()
    }
    let run = match self.runtime.store().get_run(request.worker_run_id) {
      Some(value) => value
      None => return Err("delegated worker run is missing")
    }
    guard run.status is Failed || run.status is Cancelled else {
      return Err("worker retry requires a failed or cancelled provider result")
    }
    let resumed = JobRun::{
      ..run,
      status: Running,
      attempt: run.attempt + 1,
      started_at: Some(supervisor_native_runtime_timestamp()),
      finished_at: None,
      summary: None,
      error: None,
    }
    self.runtime.store().save_run(resumed)
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
        "worker.retried",
        {
          "worker_run_id": request.worker_run_id,
          "provider_task_id": request.worker_run_id,
          "execution_status": "running",
          "run_status": resumed.status,
          "attempt": resumed.attempt,
          "provider_evidence": provider_evidence,
        },
        payload={
          "reason": request.reason,
          "provider_evidence": provider_evidence,
        },
        worker_run_id=Some(request.worker_run_id),
      ),
    )
  })
}
