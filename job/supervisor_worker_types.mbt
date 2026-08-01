///|
/// Human-authored metadata for one generic MoonClaw worker. `cwd` and
/// `web_search` are explicit so the runtime never silently broadens the
/// worker's filesystem or network posture.
pub(all) struct SupervisorWorkerTaskV1 {
  task_id : String
  conversation_id : String
  title : String
  cwd : String
  model : String?
  web_search : Bool
  metadata : Json
} derive(ToJson, FromJson, Debug, Eq)

///|
/// All metered dimensions are required and finite at the HTTP boundary.
pub(all) struct SupervisorWorkerBudgetV1 {
  max_cost_micro_usd : Int64
  max_runtime_ms : Int64
  max_tokens : Int64
  max_artifacts : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Explicit authority attenuation for a delegated worker.
pub(all) struct SupervisorWorkerScopeV1 {
  claim_ceiling : String
  budget : SupervisorWorkerBudgetV1
  artifact_prefixes : Array[String]
  expires_at : String
} derive(ToJson, FromJson, Debug, Eq)

///|
/// High-level delegation surface. Worker identity, delegation references, and
/// provider details are deliberately runtime-owned.
pub(all) struct SupervisorDelegateIntentRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  instruction : String
  task : SupervisorWorkerTaskV1
  scope : SupervisorWorkerScopeV1
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Internal daemon binding returned after the intent has created or restored
/// its one durable child run.
pub(all) struct SupervisorDelegateIntentPreparedV1 {
  receipt : SupervisorCommandReceiptV1
  worker_run_id : String
  worker_job_id : String
  execution_status : String
  delegation : Json
} derive(ToJson, Debug, Eq)

///|
pub(all) struct SupervisorWorkerSteerRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  worker_run_id : String
  instruction : String
  metadata : Json
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorWorkerStopRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  worker_run_id : String
  reason : String
  force : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorWorkerRetryRequestV1 {
  envelope : SupervisorCommandEnvelopeV1
  supervisor_id : String
  worker_run_id : String
  reason : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SupervisorWorkerStatusV1 {
  contract_id : String
  supervisor_id : String
  parent_run_id : String
  parent_step_id : String
  worker_run_id : String
  worker_job_id : String
  provider_task_id : String
  run_status : RunStatus
  execution_status : String
  attempt : Int
  accounting_mode : String
  started_at : Int?
  finished_at : Int?
  delegation : Json
  authorization : Json
  summary : String?
  error : String?
  result_evidence : Json?
  artifact_refs : Array[String]
  artifact_evidence : Array[Json]
  outcome_evidence_status : String
  outcome_source_event_id : String?
  outcome_evidence_candidate : SupervisorBookkeeperOutcomeEvidenceV1?
} derive(ToJson, FromJson, Debug)

///|
pub fn supervisor_delegate_intent_payload_v1(
  supervisor_id : String,
  instruction : String,
  task : SupervisorWorkerTaskV1,
  scope : SupervisorWorkerScopeV1,
) -> Json {
  {
    "supervisor_id": supervisor_id,
    "instruction": instruction,
    "task": task,
    "scope": scope,
  }
}

///|
pub fn supervisor_worker_steer_payload_v1(
  supervisor_id : String,
  worker_run_id : String,
  instruction : String,
  metadata : Json,
) -> Json {
  {
    "supervisor_id": supervisor_id,
    "worker_run_id": worker_run_id,
    "instruction": instruction,
    "metadata": metadata,
  }
}

///|
pub fn supervisor_worker_stop_payload_v1(
  supervisor_id : String,
  worker_run_id : String,
  reason : String,
  force : Bool,
) -> Json {
  {
    "supervisor_id": supervisor_id,
    "worker_run_id": worker_run_id,
    "reason": reason,
    "force": force,
  }
}

///|
pub fn supervisor_worker_retry_payload_v1(
  supervisor_id : String,
  worker_run_id : String,
  reason : String,
) -> Json {
  {
    "supervisor_id": supervisor_id,
    "worker_run_id": worker_run_id,
    "reason": reason,
  }
}
