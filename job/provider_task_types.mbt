///|
/// Provider-backed extension task contracts.
///
/// These structs form the boundary between MoonClaw's generic execution runtime
/// and workspace-local extension providers. Keep them small and transport-safe:
/// domain semantics belong in provider-owned skills and packets, not in the
/// MoonClaw harness.
pub(all) struct ProviderTaskSpec {
  id : String
  title : String
  kind : String
  prompt : String
  priority : Int32
  requires_review : Bool
  target_pages : Array[String]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProviderTaskBatch {
  goal_id : String
  goal : String
  summary : String
  tasks : Array[ProviderTaskSpec]
} derive(Debug, ToJson, FromJson)

///|
/// Provider-owned context schema for generic extension task execution.
/// Field names describe durable book/runtime concerns, not MoonClaw domain
/// semantics.
pub(all) struct ProviderTaskWorkerContext {
  book_id : String
  workspace_root : String
  task_id : String
  prompt : String
  policy : Array[String]
  routines : Array[String]
  skill_paths : Array[String]
  context_pages : Array[String]
  active_memory : Array[String]
  user_memory : Array[String]
  working_memory : Array[String]
  memory_summary : String
  output_contract : Array[String]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProviderTaskMemoryCandidate {
  kind : String
  title : String
  detail : String
  durable : Bool
  target_page : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderTaskResult {
  task_id : String
  summary : String
  artifacts : Array[String]
  memory_candidates : Array[ProviderTaskMemoryCandidate]
  requires_review : Bool
  notify_town : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProviderTaskPersistOutcome {
  log_path : String
  updated_pages : Array[String]
  review_queued : Bool
  notify_town : Bool
  evidence_id : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ProviderTaskCommand {
  provider : @resource_providers.RegisteredResourceProvider
  command : String
  args : Array[String]
  cwd : String?
  workspace_root : String
} derive(Debug)

///|
pub extend ProviderTaskSpec with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProviderTaskSpec with ToJson::{to_json}

///|
pub extend ProviderTaskSpec with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ProviderTaskBatch with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProviderTaskBatch with ToJson::{to_json}

///|
pub extend ProviderTaskBatch with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ProviderTaskWorkerContext with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend ProviderTaskWorkerContext with ToJson::{to_json}

///|
pub extend ProviderTaskWorkerContext with @moonbitlang/core/json.FromJson::{
  from_json,
}

///|
pub extend ProviderTaskMemoryCandidate with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend ProviderTaskMemoryCandidate with Eq::{not_equal, equal}

///|
pub extend ProviderTaskMemoryCandidate with ToJson::{to_json}

///|
pub extend ProviderTaskMemoryCandidate with @moonbitlang/core/json.FromJson::{
  from_json,
}

///|
pub extend ProviderTaskResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProviderTaskResult with ToJson::{to_json}

///|
pub extend ProviderTaskResult with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ProviderTaskPersistOutcome with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend ProviderTaskPersistOutcome with ToJson::{to_json}

///|
pub extend ProviderTaskPersistOutcome with @moonbitlang/core/json.FromJson::{
  from_json,
}

///|
pub extend ProviderTaskCommand with @moonbitlang/core/debug.Debug::{to_repr}
