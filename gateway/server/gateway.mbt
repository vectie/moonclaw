///|
priv suberror HttpError {
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
  acp_runtime : @acp.AcpRuntime
  acp_process_manager : @spawn.Manager
  active_acp_runs : Map[String, @spawn.Process]
  cancelled_acp_runs : Map[String, Bool]
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
  _password : String?
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
  Tick
  Shutdown
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

///|
pub fn Gateway::acp_runtime(self : Gateway) -> @acp.AcpRuntime {
  self.acp_runtime
}

///|
fn Gateway::register_active_acp_run(
  self : Gateway,
  run_id : String,
  process : @spawn.Process,
) -> Unit {
  self.active_acp_runs[run_id] = process
}

///|
fn Gateway::clear_active_acp_run(self : Gateway, run_id : String) -> Unit {
  self.active_acp_runs.remove(run_id) |> ignore()
}

///|
fn Gateway::mark_acp_run_cancel_requested(
  self : Gateway,
  run_id : String,
) -> Unit {
  self.cancelled_acp_runs[run_id] = true
}

///|
fn Gateway::consume_acp_run_cancel_requested(
  self : Gateway,
  run_id : String,
) -> Bool {
  let cancelled = self.cancelled_acp_runs.contains(run_id)
  if cancelled {
    self.cancelled_acp_runs.remove(run_id) |> ignore()
  }
  cancelled
}

///|
fn Gateway::cancel_active_acp_run(
  self : Gateway,
  run_id : String,
) -> Result[Bool, String] {
  match self.active_acp_runs.get(run_id) {
    Some(process) => {
      self.mark_acp_run_cancel_requested(run_id)
      process.kill(@signal.sigterm) catch {
        error => return Err("Failed to cancel ACP run \{run_id}: \{error}")
      }
      Ok(true)
    }
    None => Ok(false)
  }
}

///|
fn Gateway::active_acp_run_for_session(
  self : Gateway,
  session_id : String,
) -> @acp.AcpRun? {
  for run in self.acp_runtime().list_runs_for_session(session_id) {
    if self.active_acp_runs.contains(run.id) &&
      (run.status == "running" || run.status == "cancelling") {
      return Some(run)
    }
  }
  None
}
