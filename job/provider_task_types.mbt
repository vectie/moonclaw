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
  priority : Int
  requires_review : Bool
  target_pages : Array[String]
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ProviderTaskBatch {
  goal_id : String
  goal : String
  summary : String
  tasks : Array[ProviderTaskSpec]
} derive(Show, ToJson, FromJson)

///|
/// Provider-owned context schema. Some field names remain wiki-shaped for
/// compatibility with existing extensions, but MoonClaw treats this as generic
/// extension task context.
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
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ProviderTaskMemoryCandidate {
  kind : String
  title : String
  detail : String
  durable : Bool
  target_page : String?
} derive(Show, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderTaskResult {
  task_id : String
  summary : String
  artifacts : Array[String]
  memory_candidates : Array[ProviderTaskMemoryCandidate]
  requires_review : Bool
  notify_town : Bool
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ProviderTaskPersistOutcome {
  log_path : String
  updated_pages : Array[String]
  review_queued : Bool
  notify_town : Bool
  evidence_id : String
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ProviderTaskCommand {
  provider : @resource_providers.RegisteredResourceProvider
  command : String
  args : Array[String]
  cwd : String?
  workspace_root : String
} derive(Show)
