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
  error : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ArtifactRecord {
  id : String
  run_id : String
  job_id : String
  artifact_type : String
  path : String
  metadata : Json
  created_at : Int
  scope : Array[String]
} derive(ToJson, FromJson, Show)
