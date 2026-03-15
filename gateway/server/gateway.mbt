///|
suberror HttpError {
  HttpError(code~ : Int, reason~ : String, body~ : String)
}

///|
fn json_error(code : Int, reason : String, body : Json) -> HttpError {
  HttpError(code~, reason~, body=body.stringify())
}

///|
pub struct Gateway {
  clock : &@clock.Clock
  uuid : @uuid.Generator
  httpx : @httpx.Server
  port : Int
  events : @broadcast.Broadcast[GatewayEvent]
  auth : AuthConfig
  sessions : SessionManager
  dedupe : DedupeCache
  logger : @pino.Logger
  home : String
  cwd : String
  models : @model.Loader
  mut started_at : Int
  mut pending_requests : Int
  agent_runs : Map[String, AgentRun]
  active_channel_sessions : Map[String, @event.ExternalEventQueue]
  shutdown_requested : Bool
  agent_events : @broadcast.Broadcast[@protocol.AgentEventPayload]
  channel_manager : ChannelManager
  extension_registry : @channel.ExtensionRegistry
  extension_websocket_runtime_manager : @channel.WebSocketClientRuntimeManager
  extension_websocket_runtime : @channel.WebSocketClientRuntime
  mailbox_manager : MailboxManager
  coordinator : Coordinator
  pipeline_manager : PipelineManager
  channel_state : ChannelStateStore
  job_app : @job.GatewayJobApp
  security_runtime : @security.SecurityRuntime
  workspace_runtime : @workspace.WorkspaceRuntime
  plugin_runtime : @plugin.PluginRuntime
}

///|
struct AgentRun {
  run_id : String
  session_key : String
  status : String
  created_at : Int
  completed_at : Int?
  result : Json?
  error : @protocol.ErrorShape?
} derive(ToJson, FromJson, Show)

///|
struct AuthConfig {
  token : String?
  password : String?
}

///|
struct SessionManager {
  sessions : Map[String, SessionEntry]
  session_dir : String
}

///|
struct SessionEntry {
  session_id : String
  updated_at : Int
  channel : String?
  model_override : String?
  provider_override : String?
  cwd : String?
} derive(ToJson, FromJson, Show)

///|
struct DedupeCache {
  entries : Map[String, DedupeEntry]
  ttl_ms : Int
}

///|
struct DedupeEntry {
  ts : Int
  ok : Bool
  payload : Json?
  error : @protocol.ErrorShape?
}

///|
struct PersistedChannelAccount {
  account_id : String
  config : Json
  auto_start : Bool
} derive(ToJson, FromJson, Show)

///|
struct PersistedChannelState {
  channel_id : String
  config : @channel.ChannelConfig
  accounts : Array[PersistedChannelAccount]
} derive(ToJson, FromJson, Show)

///|
struct ChannelStateStore {
  path : String
  states : Map[String, PersistedChannelState]
}

///|
enum GatewayEvent {
  Tick(Int)
  Shutdown
  SessionChanged(String)
  AgentStarted(String)
  AgentCompleted(String)
}

///|
pub fn Gateway::request_shutdown(self : Gateway) -> Unit {
  self.events.put(GatewayEvent::Shutdown)
}

///|
pub async fn Gateway::schedule_due_jobs(self : Gateway) -> Array[@job.JobRun] {
  let runs = self
    .job_runtime()
    .trigger_due_definitions(current_time_ms(), fn() {
      self.uuid.v4().to_string()
    })
  for run in runs {
    self.logger.info("Scheduled job run created: \{run.job_id} -> \{run.id}")
    self.launch_job_run(run.id)
  }
  runs
}

///|
fn Gateway::active_job_runs(self : Gateway) -> Array[@job.JobRun] {
  self
  .job_runtime()
  .store()
  .list_runs()
  .filter(fn(run) {
    run.status is @job.RunStatus::Running ||
    run.status is @job.RunStatus::Pending
  })
}

///|
fn Gateway::job_runtime(self : Gateway) -> @job.RuntimeManager {
  self.job_app.runtime()
}

///|
pub fn Gateway::workspace_runtime(
  self : Gateway,
) -> @workspace.WorkspaceRuntime {
  self.workspace_runtime
}

///|
pub fn Gateway::security_runtime(self : Gateway) -> @security.SecurityRuntime {
  self.security_runtime
}

///|
pub fn Gateway::plugin_runtime(self : Gateway) -> @plugin.PluginRuntime {
  self.plugin_runtime
}
