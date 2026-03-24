///|
pub(all) enum TriggerSource {
  Manual
  Scheduled
  Webhook
  Recovery
  Custom(String)
} derive(ToJson, FromJson, Show)

///|
pub(all) enum RunStatus {
  Pending
  Running
  Succeeded
  Failed
  Cancelled
} derive(ToJson, FromJson, Show)

///|
pub(all) struct RetryPolicy {
  max_attempts : Int
  backoff_ms : Int?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct SchedulePolicy {
  kind : String
  interval_minutes : Int?
  timezone : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct WorkflowStepDefinition {
  id : String
  kind : String
  config : Json
  retry_policy : RetryPolicy?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct WorkflowDefinition {
  id : String
  kind : String
  steps : Array[WorkflowStepDefinition]
  output_bindings : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobDefinition {
  id : String
  kind : String
  enabled : Bool
  config : Json
  schedule : SchedulePolicy?
  retry_policy : RetryPolicy?
  workflow_id : String?
  created_at : Int
  updated_at : Int
  tags : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobRun {
  id : String
  job_id : String
  trigger : TriggerSource
  parent_run_id : String?
  parent_step_id : String?
  depth : Int
  workspace_dir : String?
  status : RunStatus
  attempt : Int
  retry_of : String?
  started_at : Int?
  completed_at : Int?
  summary : String?
  error : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobStepRun {
  id : String
  run_id : String
  step_id : String
  status : RunStatus
  started_at : Int?
  completed_at : Int?
  metrics : Json
  logs : Array[String]
  retry_count : Int
  summary : String?
  output : Json?
  error : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) enum ArtifactStatus {
  Active
  Archived
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) struct ArtifactRecord {
  id : String
  run_id : String
  job_id : String
  artifact_type : String
  logical_key : String?
  version : Int
  status : ArtifactStatus
  path : String
  content_type : String
  metadata : Json
  created_at : Int
  archived_at : Int?
  scope : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ArtifactQuery {
  job_id : String?
  run_id : String?
  artifact_type : String?
  logical_key : String?
  scope : String?
  status : ArtifactStatus?
} derive(ToJson, FromJson, Show)

///|
pub fn ArtifactQuery::new(
  job_id? : String? = None,
  run_id? : String? = None,
  artifact_type? : String? = None,
  logical_key? : String? = None,
  scope? : String? = None,
  status? : ArtifactStatus? = None,
) -> ArtifactQuery {
  ArtifactQuery::{ job_id, run_id, artifact_type, logical_key, scope, status }
}

///|
pub(all) struct ArtifactWriteRequest {
  run_id : String
  job_id : String
  artifact_type : String
  logical_key : String?
  content_type : String
  file_name : String?
  metadata : Json
  scope : Array[String]
  content : String
  append_only : Bool
} derive(ToJson, FromJson, Show)

///|
pub fn ArtifactWriteRequest::new(
  run_id~ : String,
  job_id~ : String,
  artifact_type~ : String,
  content~ : String,
  logical_key? : String? = None,
  content_type? : String = "text/plain",
  file_name? : String? = None,
  metadata? : Json = {},
  scope? : Array[String] = [],
  append_only? : Bool = true,
) -> ArtifactWriteRequest {
  ArtifactWriteRequest::{
    run_id,
    job_id,
    artifact_type,
    logical_key,
    content_type,
    file_name,
    metadata,
    scope,
    content,
    append_only,
  }
}

///|
pub(all) struct ArtifactRetentionPolicy {
  artifact_type : String?
  scope : String?
  keep_latest : Int?
  max_age_ms : Int?
  archive_before_delete : Bool
} derive(ToJson, FromJson, Show)

///|
pub fn ArtifactRetentionPolicy::new(
  artifact_type? : String? = None,
  scope? : String? = None,
  keep_latest? : Int? = None,
  max_age_ms? : Int? = None,
  archive_before_delete? : Bool = true,
) -> ArtifactRetentionPolicy {
  ArtifactRetentionPolicy::{
    artifact_type,
    scope,
    keep_latest,
    max_age_ms,
    archive_before_delete,
  }
}

///|
pub(all) struct ArtifactCleanupReport {
  archived_ids : Array[String]
  deleted_ids : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub(all) enum MemoryStatus {
  Active
  Archived
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) struct MemoryRecord {
  id : String
  kind : String
  title : String?
  content : String
  metadata : Json
  tags : Array[String]
  scope : Array[String]
  workspace : String?
  agent_id : String?
  channel_id : String?
  account_id : String?
  recipient : String?
  thread_id : String?
  source_artifact_id : String?
  status : MemoryStatus
  created_at : Int
  updated_at : Int
  archived_at : Int?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct MemoryWriteRequest {
  kind : String
  title : String?
  content : String
  metadata : Json
  tags : Array[String]
  scope : Array[String]
  workspace : String?
  agent_id : String?
  channel_id : String?
  account_id : String?
  recipient : String?
  thread_id : String?
  source_artifact_id : String?
} derive(ToJson, FromJson, Show)

///|
pub fn MemoryWriteRequest::new(
  kind~ : String,
  content~ : String,
  title? : String? = None,
  metadata? : Json = {},
  tags? : Array[String] = [],
  scope? : Array[String] = [],
  workspace? : String? = None,
  agent_id? : String? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  source_artifact_id? : String? = None,
) -> MemoryWriteRequest {
  MemoryWriteRequest::{
    kind,
    title,
    content,
    metadata,
    tags,
    scope,
    workspace,
    agent_id,
    channel_id,
    account_id,
    recipient,
    thread_id,
    source_artifact_id,
  }
}

///|
pub(all) struct MemoryQuery {
  kind : String?
  tag : String?
  scope : String?
  workspace : String?
  agent_id : String?
  channel_id : String?
  account_id : String?
  recipient : String?
  thread_id : String?
  source_artifact_id : String?
  status : MemoryStatus?
} derive(ToJson, FromJson, Show)

///|
pub fn MemoryQuery::new(
  kind? : String? = None,
  tag? : String? = None,
  scope? : String? = None,
  workspace? : String? = None,
  agent_id? : String? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  source_artifact_id? : String? = None,
  status? : MemoryStatus? = None,
) -> MemoryQuery {
  MemoryQuery::{
    kind,
    tag,
    scope,
    workspace,
    agent_id,
    channel_id,
    account_id,
    recipient,
    thread_id,
    source_artifact_id,
    status,
  }
}

///|
pub(all) struct MemorySearchHit {
  memory_id : String
  kind : String
  title : String?
  score : Int
  snippet : String
  tags : Array[String]
  scope : Array[String]
  workspace : String?
  channel_id : String?
  account_id : String?
  recipient : String?
  thread_id : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ChatBinding {
  id : String
  title : String?
  artifact_query : ArtifactQuery
  scope : Array[String]
  created_at : Int
  updated_at : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct RetrievalHit {
  artifact_id : String
  artifact_type : String
  logical_key : String?
  score : Int
  snippet : String
  path : String
  scope : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ChatCitation {
  artifact_id : String
  artifact_type : String
  logical_key : String?
  snippet : String
  path : String
  scope : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ChatAnswer {
  binding_id : String?
  question : String
  answer : String
  citations : Array[ChatCitation]
  hits : Array[RetrievalHit]
  memory_hits : Array[MemorySearchHit]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobAskParams {
  question : String
  binding_id : String?
  artifact_query : ArtifactQuery?
  max_hits : Int?
} derive(ToJson, FromJson, Show)

///|
pub(all) enum NotificationVerbosity {
  Off
  Normal
  Verbose
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) struct JobNotificationPreference {
  id : String
  channel_id : String
  account_id : String
  recipient : String
  thread_id : String?
  verbosity : NotificationVerbosity
  heartbeat_interval_ms : Int?
  warn_after_ms : Int?
  created_at : Int
  updated_at : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) enum JobProposalStatus {
  Draft
  Confirmed
  Rejected
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobProposalStep {
  id : String
  title : String
  prompt : String
  kind : String
  metadata : Json
  child_profile : String?
  execution_mode : String?
  execution_target : String?
  include_parent_outputs : Bool?
  max_depth : Int?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobProposal {
  id : String
  title : String
  request_text : String
  summary : String
  revision_history : Array[String]
  suggested_family : String?
  profile_id : String?
  profile_role : String?
  profile_metadata : Json
  status : JobProposalStatus
  steps : Array[JobProposalStep]
  tags : Array[String]
  channel_id : String?
  account_id : String?
  recipient : String?
  thread_id : String?
  presented_message_id : String?
  job_id : String?
  workflow_id : String?
  last_run_id : String?
  created_at : Int
  updated_at : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobControllerState {
  controller_job_id : String
  controller_run_id : String
  family : String
  profile_id : String?
  objective : String
  active_iteration_ids : Array[String]
  accepted_iteration_ids : Array[String]
  rejected_iteration_ids : Array[String]
  best_iteration_id : String?
  frontier : Array[String]
  metadata : Json
  created_at : Int
  updated_at : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobControllerIteration {
  id : String
  controller_job_id : String
  controller_run_id : String
  parent_iteration_id : String?
  title : String
  hypothesis : String
  status : String
  decision : String?
  child_job_ids : Array[String]
  child_run_ids : Array[String]
  metadata : Json
  created_at : Int
  updated_at : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobControllerLineageEdge {
  id : String
  controller_job_id : String
  from_iteration_id : String
  to_iteration_id : String
  edge_kind : String
  metadata : Json
  created_at : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobControllerDecision {
  id : String
  controller_job_id : String
  controller_run_id : String
  iteration_id : String
  step_id : String
  verdict : String
  reason : String?
  next_action : String?
  metadata : Json
  created_at : Int
  updated_at : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct JobRunEvent {
  run_id : String
  job_id : String
  event_type : String
  timestamp : Int
  step_id : String?
  status : RunStatus?
  message : String
  data : Json
} derive(ToJson, FromJson, Show)
