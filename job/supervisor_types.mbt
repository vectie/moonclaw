///|
/// Exact epoch milliseconds. The wire form is a canonical non-negative decimal
/// string so JavaScript and cross-product transports cannot round it.
pub struct SupervisorEpochMsV1(Int64) derive(Eq, Compare, Debug)

///|
pub fn supervisor_epoch_ms_v1(value : Int64) -> SupervisorEpochMsV1 raise {
  guard value >= 0L else { fail("supervisor epoch milliseconds are negative") }
  SupervisorEpochMsV1(value)
}

///|
pub fn SupervisorEpochMsV1::value(self : SupervisorEpochMsV1) -> Int64 {
  let SupervisorEpochMsV1(value) = self
  value
}

///|
pub impl ToJson for SupervisorEpochMsV1 with fn to_json(
  self : SupervisorEpochMsV1,
) -> Json {
  self.value().to_string().to_json()
}

///|
pub impl @json.FromJson for SupervisorEpochMsV1 with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SupervisorEpochMsV1 raise @json.JsonDecodeError {
  guard json is String(text) &&
    !text.is_blank() &&
    (text == "0" || !text.has_prefix("0")) &&
    text.iter().all(fn(c) { c >= '0' && c <= '9' }) else {
    raise JsonDecodeError(
      (path, "expected canonical epoch-millisecond decimal string"),
    )
  }
  let value = @string.parse_int64(text) catch {
    _ => raise JsonDecodeError((path, "epoch-millisecond string exceeds Int64"))
  }
  supervisor_epoch_ms_v1(value) catch {
    _ => raise JsonDecodeError((path, "invalid epoch milliseconds"))
  }
}

///|
/// Opaque, externally-owned activation input. The source product owns profile
/// authoring; MoonClaw only binds its exact version and digest to execution.
pub(all) struct SupervisorProfileActivationV1 {
  contract_id : String
  supervisor_id : String
  profile_id : String
  profile_version : Int
  profile_digest : String
  source_product : String
  runtime_profile : Json
  runtime_binding : Json
  activated_at : SupervisorEpochMsV1
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Common idempotency, cursor, and authority envelope for every mutation.
/// `authority` is the MoonLib `moonsuite.authority-decision-ref.v1` wire form.
pub(all) struct SupervisorCommandEnvelopeV1 {
  contract_id : String
  command_id : String
  request_digest : String
  issued_at : SupervisorEpochMsV1
  evaluated_at : String
  expected_cursor : Int?
  authority : Json
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorAuthorityVerificationV1 {
  operation_ref : String
  operation_digest : String
  capability_resolution : Json
  verified_at : String
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Host verification port. The daemon implementation resolves the exact live
/// operation through MoonGate; tests may supply a deterministic verifier.
pub(all) struct SupervisorAuthorityVerifierV1 {
  verify : async (SupervisorCommandEnvelopeV1, String) -> Result[
    SupervisorAuthorityVerificationV1,
    String,
  ]
}

///|
pub fn SupervisorAuthorityVerifierV1::new(
  verify~ : async (SupervisorCommandEnvelopeV1, String) -> Result[
    SupervisorAuthorityVerificationV1,
    String,
  ],
) -> SupervisorAuthorityVerifierV1 {
  { verify, }
}

///|
pub(all) enum SupervisorLifecycleV1 {
  Dormant
  Running
  Stopped
  Failed
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorStateV1 {
  contract_id : String
  supervisor_id : String
  profile : SupervisorProfileActivationV1
  lifecycle : SupervisorLifecycleV1
  active_run_id : String?
  cursor : Int
  updated_at : SupervisorEpochMsV1
  last_error : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorCommandReceiptV1 {
  contract_id : String
  command_id : String
  request_digest : String
  supervisor_id : String
  cursor : Int
  event_id : String
  status : String
  duplicate : Bool
  response : Json
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorActivateRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  profile : SupervisorProfileActivationV1
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorWakeRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  run_id : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorMessageV1 {
  message_id : String
  conversation_id : String
  task_id : String?
  sender_ref : String
  content : String
  content_type : String
  reply_to_message_id : String?
  created_at : SupervisorEpochMsV1
  metadata : Json
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorSendMessageRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  message : SupervisorMessageV1
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorSteerRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  message : SupervisorMessageV1
  target_run_id : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorMailboxClaimRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  claim_id : String
  max_messages : Int
  lease_expires_at : SupervisorEpochMsV1
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorMailboxAckRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  claim_id : String
  message_ids : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorStopRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  reason : String
  force : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) enum SupervisorRecoveryActionV1 {
  Resume
  Retry(new_run_id~ : String)
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorRetryResumeRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  action : SupervisorRecoveryActionV1
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorWorkerLineageV1 {
  supervisor_id : String
  parent_run_id : String
  parent_step_id : String
  worker_run_id : String
  worker_job_id : String
  depth : Int
  delegation_ref : Json
  recorded_at : SupervisorEpochMsV1
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Internal executor port for the existing `job.delegate` path. It cannot be
/// decoded from the daemon HTTP surface.
#warnings("-struct_never_constructed")
pub struct SupervisorDelegateRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  request : ChildRunExecutionRequest
  delegation : ChildDelegationV1
  child_principal : @capability.PrincipalRefV1
  operation : @capability.OperationRef
  artifact_refs : Array[String]
  requested_claim : DelegationClaimCeilingV1
  consumption : ChildDelegationConsumptionV1
}

///|
pub struct SupervisorDelegateResponseV1 {
  receipt : SupervisorCommandReceiptV1
  governed : GovernedChildRunExecutionRequestV1
}

///|
/// HTTP adapter for a real child already created by MoonClaw's established
/// `job.delegate` scheduler. The runtime verifies that run before journaling.
pub(all) struct SupervisorDelegateExistingRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  worker_run_id : String
  worker_job_id : String
  delegation : Json
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorVersionedRecordRefV1 {
  record_id : String
  record_version : String
  record_digest : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorEvidenceRefV1 {
  reference_id : String
  reference_version : String
  digest : String
  provenance_ref : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorGapStatementV1 {
  present : Bool
  severity : Int
  summary : String
  evidence_refs : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Exact, lossless projection into MoonBook's existing ProductOutcomeSubmission.
/// It is evidence only and can never represent review, acceptance, or closure.
pub(all) struct SupervisorBookkeeperOutcomeEvidenceV1 {
  contract_version : String
  submission : SupervisorVersionedRecordRefV1
  source_product : String
  deliverable_title : String
  deliverable_summary : String
  outcome_summary : String
  owner_route : String
  evidence_refs : Array[SupervisorEvidenceRefV1]
  decision_evidence_id : String
  // MoonBook owns this wire shape and currently requires JSON integers.
  observed_at : Int
  recorded_at : Int
  information_gap : SupervisorGapStatementV1
  recognition_gap : SupervisorGapStatementV1
  decisiveness_gap : SupervisorGapStatementV1
  capability_id : String
  capability_version : String
  capability_change_digest : String
  capability_summary : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorOutcomeEvidenceRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  source_event_ids : Array[String]
  projection : SupervisorBookkeeperOutcomeEvidenceV1
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorOutcomeOutboxClaimRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  claim_id : String
  max_items : Int
  lease_expires_at : SupervisorEpochMsV1
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorOutcomeOutboxAckRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  claim_id : String
  submission_ids : Array[String]
  bookkeeper_receipts : Array[Json]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorJournalEventV1 {
  contract_id : String
  event_id : String
  supervisor_id : String
  cursor : Int
  command_id : String
  command_digest : String
  event_type : String
  timestamp : SupervisorEpochMsV1
  conversation_id : String?
  task_id : String?
  parent_run_id : String?
  worker_run_id : String?
  payload : Json
  state_after : SupervisorStateV1
  receipt : SupervisorCommandReceiptV1
  lineage : SupervisorWorkerLineageV1?
  outcome_evidence : SupervisorBookkeeperOutcomeEvidenceV1?
  authority_verification : SupervisorAuthorityVerificationV1
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorStatusProjectionV1 {
  contract_id : String
  state : SupervisorStateV1
  pending_message_count : Int
  worker_lineage : Array[SupervisorWorkerLineageV1]
  workers : Array[SupervisorWorkerStatusV1]
  latest_event : SupervisorJournalEventV1?
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct SupervisorReplayResponseV1 {
  contract_id : String
  supervisor_id : String
  after_cursor : Int
  next_cursor : Int
  has_more : Bool
  events : Array[SupervisorJournalEventV1]
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Canonical operation payloads. Callers hash exactly the returned JSON; the
/// envelope and authority proof are deliberately outside that digest.
pub fn supervisor_activate_payload_v1(
  profile : SupervisorProfileActivationV1,
) -> Json {
  profile.to_json()
}

///|
pub fn supervisor_wake_payload_v1(
  supervisor_id : String,
  run_id : String?,
) -> Json {
  { "supervisor_id": supervisor_id, "run_id": run_id }
}

///|
pub fn supervisor_message_payload_v1(
  supervisor_id : String,
  message : SupervisorMessageV1,
) -> Json {
  { "supervisor_id": supervisor_id, "message": message }
}

///|
pub fn supervisor_steer_payload_v1(
  supervisor_id : String,
  message : SupervisorMessageV1,
  target_run_id : String,
) -> Json {
  {
    "supervisor_id": supervisor_id,
    "message": message,
    "target_run_id": target_run_id,
  }
}

///|
pub fn supervisor_stop_payload_v1(
  supervisor_id : String,
  reason : String,
  force : Bool,
) -> Json {
  { "supervisor_id": supervisor_id, "reason": reason, "force": force }
}

///|
pub fn supervisor_retry_resume_payload_v1(
  supervisor_id : String,
  action : SupervisorRecoveryActionV1,
) -> Json {
  { "supervisor_id": supervisor_id, "action": action }
}

///|
pub fn supervisor_outcome_evidence_payload_v1(
  supervisor_id : String,
  source_event_ids : Array[String],
  projection : SupervisorBookkeeperOutcomeEvidenceV1,
) -> Json {
  {
    "supervisor_id": supervisor_id,
    "source_event_ids": source_event_ids,
    "projection": projection,
  }
}

///|
pub fn supervisor_delegate_existing_payload_v1(
  supervisor_id : String,
  worker_run_id : String,
  worker_job_id : String,
  delegation : Json,
) -> Json {
  {
    "supervisor_id": supervisor_id,
    "worker_run_id": worker_run_id,
    "worker_job_id": worker_job_id,
    "delegation": delegation,
  }
}

///|
pub fn supervisor_payload_digest_v1(payload : Json) -> String {
  @capability.sha256_digest_ref_v1(@encoding/utf8.encode(payload.stringify())).text()
}
